from __future__ import annotations

from dataclasses import dataclass, replace
import json
import re
import shutil
import subprocess
from pathlib import Path
import tomllib

from scripts.blueprint_harness_releases import (
    lean_release_order_key,
    lean_toolchain_spec,
    normalize_lean_release_ref,
    release_branch_from_lean_ref,
    rewrite_lean_toolchain,
)
from scripts.blueprint_harness_projects import HarnessProject, reference_dependency_cache_key
from scripts.blueprint_harness_project_commands import (
    discard_untracked_project_manifest,
    format_project_command,
    local_blueprint_dependency_override,
    maybe_in_repo_blueprint_dependency_override,
    project_lake_update_command,
    rebuild_and_log_embedded_asset_owners,
    restore_tracked_project_manifest,
    rewrite_pinned_blueprint_dependency,
    run_project_update_build_generate,
    snapshot_tracked_project_manifest,
)
from scripts.blueprint_harness_utils import format_command, lean_low_priority_command, run, run_with_heartbeat


COMMIT_HASH_PATTERN = re.compile(r"^[0-9a-f]{40}$", re.IGNORECASE)
REFERENCE_PACKAGE_MODE_COPY = "copy"
REFERENCE_PACKAGE_MODE_MOVE = "move"
REFERENCE_PACKAGE_MODES = (REFERENCE_PACKAGE_MODE_COPY, REFERENCE_PACKAGE_MODE_MOVE)
GITHUB_SUBMODULE_URL_REWRITE_ARGS = (
    "-c",
    "url.https://github.com/.insteadOf=git@github.com:",
    "-c",
    "url.https://github.com/.insteadOf=ssh://git@github.com/",
)
REFERENCE_HARNESS_CONFIG = "verso-harness.toml"


def command_with_verbose(command: tuple[str, ...]) -> tuple[str, ...]:
    if "--verbose" in command:
        return command
    return (*command, "--verbose")


def reference_generation_command(
    command: tuple[str, ...],
    *,
    verbose: bool,
) -> tuple[str, ...]:
    if verbose:
        command = command_with_verbose(command)
    return command


@dataclass(frozen=True)
class ReferenceProjectBumpResult:
    edit_dir: Path
    branch: str
    base_ref: str
    previous_ref: str | None
    changed: bool
    committed: bool
    pushed: bool
    output_dir: Path | None


@dataclass(frozen=True)
class ReferenceToolchainCandidate:
    path: Path
    lean_ref: str
    release_branch: str
    order_key: tuple[int, int, int, int]


@dataclass(frozen=True)
class ReferenceToolchainReconciliationResult:
    selected_ref: str | None
    release_branch: str | None
    changed_paths: tuple[Path, ...]

    @property
    def changed(self) -> bool:
        return bool(self.changed_paths)


@dataclass(frozen=True)
class ReferenceLakeUpdateResult:
    command: list[str]
    reconciliation: ReferenceToolchainReconciliationResult


def output_dir_for(project: HarnessProject, output_root: Path) -> Path:
    return output_root / project.project_id


def site_dir_for(project: HarnessProject, output_root: Path) -> Path:
    return output_dir_for(project, output_root) / project.site_subdir


def reference_source_cache_checkout_dir(layout, project: HarnessProject) -> Path:
    return layout.reference_source_cache_root / reference_dependency_cache_key(project)


def reference_dependency_cache_dir(layout, project: HarnessProject) -> Path:
    return layout.reference_dependency_cache_root / reference_dependency_cache_key(project)


def reference_dependency_packages_dir(layout, project: HarnessProject) -> Path:
    return reference_dependency_cache_dir(layout, project) / "packages"


def reference_dependency_path_builds_dir(layout, project: HarnessProject) -> Path:
    return reference_dependency_cache_dir(layout, project) / "path-builds"


def reference_local_checkout_dir(layout, project: HarnessProject) -> Path:
    return layout.reference_project_checkout_root / reference_dependency_cache_key(project)


def reference_edit_checkout_dir(layout, project: HarnessProject) -> Path:
    return layout.reference_project_edit_root / project.project_id


def reference_dependency_cache_keys(projects: tuple[HarnessProject, ...] | list[HarnessProject]) -> set[str]:
    keys: set[str] = set()
    for project in projects:
        if not project.git_checkout:
            continue
        if project.ref is not None:
            keys.add(reference_dependency_cache_key(project))
        for target in project.targets:
            if target.ref is None:
                continue
            keys.add(
                reference_dependency_cache_key(
                    replace(project, ref=target.ref, selected_release=target.release)
                )
            )
    return keys


def lake_packages_dir(project_dir: Path) -> Path:
    return project_dir / ".lake" / "packages"


def lake_build_dir(project_dir: Path) -> Path:
    return project_dir / ".lake" / "build"


def read_reference_toolchain_candidate(path: Path) -> ReferenceToolchainCandidate | None:
    if not path.exists():
        return None
    try:
        lean_ref = normalize_lean_release_ref(path.read_text(encoding="utf-8"))
    except SystemExit:
        return None

    order_key = lean_release_order_key(lean_ref)
    if order_key is None:
        return None
    return ReferenceToolchainCandidate(
        path=path,
        lean_ref=lean_ref,
        release_branch=release_branch_from_lean_ref(lean_ref),
        order_key=order_key,
    )


def reference_dependency_toolchain_paths(project_dir: Path) -> list[Path]:
    packages = lake_packages_dir(project_dir)
    if not packages.exists():
        return []
    return sorted(path / "lean-toolchain" for path in packages.iterdir() if (path / "lean-toolchain").exists())


def reconcile_reference_toolchains(package_root: Path, project_dir: Path) -> ReferenceToolchainReconciliationResult:
    package_candidate = read_reference_toolchain_candidate(package_root / "lean-toolchain")
    project_candidate = read_reference_toolchain_candidate(project_dir / "lean-toolchain")
    if package_candidate is None or project_candidate is None:
        return ReferenceToolchainReconciliationResult(
            selected_ref=None,
            release_branch=None,
            changed_paths=(),
        )
    if package_candidate.release_branch != project_candidate.release_branch:
        return ReferenceToolchainReconciliationResult(
            selected_ref=None,
            release_branch=None,
            changed_paths=(),
        )

    common_branch = package_candidate.release_branch
    candidates = [package_candidate, project_candidate]
    for path in reference_dependency_toolchain_paths(project_dir):
        candidate = read_reference_toolchain_candidate(path)
        if candidate is not None and candidate.release_branch == common_branch:
            candidates.append(candidate)

    selected = max(candidates, key=lambda candidate: candidate.order_key)
    package_toolchain_path = package_candidate.path.resolve()
    changed_paths: list[Path] = []
    for candidate in candidates:
        # The package checkout is the source for the run; reconcile only the
        # disposable reference checkout files.
        if candidate.path.resolve() == package_toolchain_path:
            continue
        if candidate.lean_ref == selected.lean_ref:
            continue
        rewrite_lean_toolchain(candidate.path, selected.lean_ref)
        changed_paths.append(candidate.path)

    if changed_paths:
        print(
            "[blueprint-harness] reconciled reference Lean toolchain to "
            f"{lean_toolchain_spec(selected.lean_ref)} for {len(changed_paths)} file(s) sharing {common_branch}"
        )
    return ReferenceToolchainReconciliationResult(
        selected_ref=selected.lean_ref,
        release_branch=common_branch,
        changed_paths=tuple(changed_paths),
    )


def validate_reference_package_mode(mode: str) -> str:
    if mode not in REFERENCE_PACKAGE_MODES:
        expected = ", ".join(REFERENCE_PACKAGE_MODES)
        raise ValueError(f"unknown reference package mode `{mode}`; expected one of: {expected}")
    return mode


def seed_lake_packages_from_dependency_cache(
    layout,
    project: HarnessProject,
    project_dir: Path,
    *,
    package_mode: str = REFERENCE_PACKAGE_MODE_COPY,
) -> Path | None:
    package_mode = validate_reference_package_mode(package_mode)
    source_packages = reference_dependency_packages_dir(layout, project)
    if not source_packages.exists():
        return None
    destination_packages = lake_packages_dir(project_dir)
    if package_mode == REFERENCE_PACKAGE_MODE_MOVE:
        discard_lake_packages(project_dir)
        destination_packages.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(source_packages), str(destination_packages))
        print(
            "[blueprint-harness] moved reference dependency packages into "
            f"{destination_packages}"
        )
        return source_packages
    destination_packages.mkdir(parents=True, exist_ok=True)
    run(["rsync", "-a", f"{source_packages}/", f"{destination_packages}/"], cwd=layout.package_root)
    return source_packages


def store_lake_packages_in_dependency_cache(
    layout,
    project: HarnessProject,
    project_dir: Path,
    *,
    package_mode: str = REFERENCE_PACKAGE_MODE_COPY,
) -> Path | None:
    package_mode = validate_reference_package_mode(package_mode)
    source_packages = lake_packages_dir(project_dir)
    if not source_packages.exists():
        return None
    destination_packages = reference_dependency_packages_dir(layout, project)
    if package_mode == REFERENCE_PACKAGE_MODE_MOVE:
        if destination_packages.exists() or destination_packages.is_symlink():
            if destination_packages.is_symlink() or destination_packages.is_file():
                destination_packages.unlink()
            else:
                shutil.rmtree(destination_packages)
        destination_packages.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(source_packages), str(destination_packages))
        print(
            "[blueprint-harness] restored reference dependency packages to "
            f"{destination_packages}"
        )
        return destination_packages
    destination_packages.mkdir(parents=True, exist_ok=True)
    run(["rsync", "-a", "--delete", f"{source_packages}/", f"{destination_packages}/"], cwd=layout.package_root)
    return destination_packages

def discard_lake_packages(project_dir: Path) -> Path | None:
    packages = lake_packages_dir(project_dir)
    if not packages.exists() and not packages.is_symlink():
        return None
    if packages.is_symlink() or packages.is_file():
        packages.unlink()
    else:
        shutil.rmtree(packages)
    return packages


def _relative_path_dependency_dirs(project_dir: Path, package_root: Path) -> list[Path]:
    manifest_path = project_dir / "lake-manifest.json"
    if not manifest_path.exists():
        return []
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return []
    packages = manifest.get("packages")
    if not isinstance(packages, list):
        return []

    package_root = package_root.resolve()
    project_dir = project_dir.resolve()
    paths: list[Path] = []
    seen: set[str] = set()
    for package in packages:
        if not isinstance(package, dict) or package.get("type") != "path":
            continue
        raw_dir = package.get("dir")
        if not isinstance(raw_dir, str) or not raw_dir:
            continue
        dependency_dir = (project_dir / raw_dir).resolve()
        if dependency_dir == package_root:
            continue
        try:
            relative_dir = dependency_dir.relative_to(project_dir)
        except ValueError:
            continue
        if str(relative_dir) == ".":
            continue
        relative_text = relative_dir.as_posix()
        if relative_text in seen:
            continue
        seen.add(relative_text)
        paths.append(relative_dir)
    return paths


def seed_lake_path_builds_from_dependency_cache(layout, project: HarnessProject, project_dir: Path) -> Path | None:
    source_root = reference_dependency_path_builds_dir(layout, project)
    if not source_root.exists():
        return None
    copied = False
    for relative_dir in _relative_path_dependency_dirs(project_dir, layout.package_root):
        source_build = source_root / relative_dir / ".lake" / "build"
        if not source_build.exists():
            continue
        destination_build = lake_build_dir(project_dir / relative_dir)
        destination_build.mkdir(parents=True, exist_ok=True)
        run(["rsync", "-a", f"{source_build}/", f"{destination_build}/"], cwd=layout.package_root)
        copied = True
    return source_root if copied else None


def store_lake_path_builds_in_dependency_cache(layout, project: HarnessProject, project_dir: Path) -> Path | None:
    destination_root = reference_dependency_path_builds_dir(layout, project)
    copied = False
    for relative_dir in _relative_path_dependency_dirs(project_dir, layout.package_root):
        source_build = lake_build_dir(project_dir / relative_dir)
        if not source_build.exists():
            continue
        destination_build = destination_root / relative_dir / ".lake" / "build"
        destination_build.mkdir(parents=True, exist_ok=True)
        run(["rsync", "-a", "--delete", f"{source_build}/", f"{destination_build}/"], cwd=layout.package_root)
        copied = True
    return destination_root if copied else None


def short_git_ref(ref: str) -> str:
    return ref[:12] if COMMIT_HASH_PATTERN.fullmatch(ref) is not None else ref


def default_reference_bump_branch(ref: str) -> str:
    slug = re.sub(r"[^A-Za-z0-9]+", "-", short_git_ref(ref)).strip("-").lower()
    if not slug:
        slug = "pin"
    return f"chore/bump-verso-blueprint-{slug}"


def reference_command_placeholders(
    project: HarnessProject,
    *,
    package_root: Path,
    checkout_root: Path,
    project_dir: Path,
    output_dir: Path,
) -> dict[str, object]:
    return {
        "checkout_root": checkout_root,
        "package_root": package_root,
        "project_dir": project_dir,
        "output_dir": output_dir,
        "project_id": project.project_id,
        "site_dir": site_dir_for(project, output_dir.parent),
    }


def reference_submodule_update_command() -> list[str]:
    return [
        "git",
        *GITHUB_SUBMODULE_URL_REWRITE_ARGS,
        "submodule",
        "update",
        "--init",
        "--depth",
        "1",
        "--recursive",
    ]


def require_reference_harness_layout(project_dir: Path) -> None:
    config_path = project_dir / REFERENCE_HARNESS_CONFIG
    if not config_path.exists():
        raise SystemExit(
            "[blueprint-harness] expected the external reference checkout to be a "
            f"`leanblueprint-to-verso` consumer; missing {config_path}"
        )

    try:
        config = tomllib.loads(config_path.read_text(encoding="utf-8"))
    except tomllib.TOMLDecodeError as exc:
        raise SystemExit(f"[blueprint-harness] invalid {config_path}: {exc}") from exc

    formalization_path = config.get("formalization_path")
    if not isinstance(formalization_path, str) or not formalization_path:
        raise SystemExit(f"[blueprint-harness] expected {config_path} to declare `formalization_path`")
    if Path(formalization_path).is_absolute():
        raise SystemExit(f"[blueprint-harness] expected `formalization_path` in {config_path} to be relative")

    helper_root = project_dir / "tools" / "verso-harness"
    helper_check = helper_root / "scripts" / "check_harness.py"
    if not helper_root.is_dir():
        raise SystemExit(
            "[blueprint-harness] expected the external reference checkout to vendor "
            f"`tools/verso-harness`; missing {helper_root}"
        )
    if not helper_check.is_file():
        raise SystemExit(
            "[blueprint-harness] expected the external reference checkout to include the "
            f"`leanblueprint-to-verso` helper checker; missing {helper_check}"
        )

    formalization_root = project_dir / formalization_path
    if not formalization_root.exists():
        raise SystemExit(
            "[blueprint-harness] expected the external reference checkout to contain the "
            f"configured formalization path `{formalization_path}` from {config_path}"
        )


def bootstrap_reference_checkout(*, project_dir: Path) -> None:
    if not (project_dir / ".gitmodules").exists():
        return
    # All external reference blueprints are managed as leanblueprint-to-verso
    # consumers, so the common bootstrap step is simply to initialize the
    # helper and formalization submodules declared by the repo itself.
    run(reference_submodule_update_command(), cwd=project_dir)
    require_reference_harness_layout(project_dir)


def ref_is_commit_hash(ref: str | None) -> bool:
    return ref is not None and COMMIT_HASH_PATTERN.fullmatch(ref) is not None


def clone_git_project(
    project: HarnessProject,
    destination: Path,
    *,
    cwd: Path,
    source: str | None = None,
    shallow: bool = True,
) -> Path:
    checkout_commit_after_clone = source is None and ref_is_commit_hash(project.ref)
    command = ["git", "clone"]
    if source is None and shallow:
        command.extend(["--depth", "1"])
    if project.ref and source is None and not checkout_commit_after_clone:
        command.extend(["--branch", project.ref])
    command.extend([source or project.repository or "", str(destination)])
    run(command, cwd=cwd)
    if checkout_commit_after_clone:
        update_git_checkout(project, destination)
    return destination


def fetch_git_project(project: HarnessProject, checkout_root: Path) -> None:
    if project.ref is None:
        run(["git", "fetch", "origin"], cwd=checkout_root)
        return
    if ref_is_commit_hash(project.ref):
        run(["git", "fetch", "origin", project.ref], cwd=checkout_root)
        return
    run(["git", "fetch", "origin", project.ref], cwd=checkout_root)


def update_git_checkout(project: HarnessProject, checkout_root: Path) -> None:
    if project.ref is None:
        return
    run(["git", "fetch", "--depth", "1", "origin", project.ref], cwd=checkout_root)
    discard_untracked_project_manifest(checkout_root / project.project_root)
    # Harness-managed clones are disposable, so force the ref switch even if a
    # previous run left tracked edits or conflicting untracked files behind.
    run(["git", "checkout", "--detach", "--force", "FETCH_HEAD"], cwd=checkout_root)
    run(["git", "reset", "--hard", "FETCH_HEAD"], cwd=checkout_root)


def git_checkout_is_clean(checkout_root: Path) -> bool:
    status = subprocess.run(
        ["git", "status", "--short"],
        cwd=checkout_root,
        check=True,
        text=True,
        capture_output=True,
    ).stdout.strip()
    return not status


def current_git_branch(checkout_root: Path) -> str | None:
    branch = subprocess.run(
        ["git", "branch", "--show-current"],
        cwd=checkout_root,
        check=True,
        text=True,
        capture_output=True,
    ).stdout.strip()
    return branch or None


def local_branch_exists(checkout_root: Path, branch: str) -> bool:
    return (
        subprocess.run(
            ["git", "rev-parse", "--verify", "--quiet", f"refs/heads/{branch}"],
            cwd=checkout_root,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        ).returncode
        == 0
    )


def default_reference_edit_branch(project: HarnessProject) -> str:
    return f"wip/{project.project_id}"


def default_reference_edit_base(project: HarnessProject) -> str:
    ref = project.ref or "main"
    if ref_is_commit_hash(ref):
        return ref
    return f"origin/{ref}"


def prepare_reference_edit_checkout(
    layout,
    project: HarnessProject,
    *,
    branch: str | None,
    base_ref: str | None,
) -> tuple[Path, str, str]:
    if not project.git_checkout or project.repository is None:
        raise SystemExit(f"[blueprint-harness] project `{project.project_id}` is not an external git checkout project")

    edit_dir = reference_edit_checkout_dir(layout, project)
    edit_dir.parent.mkdir(parents=True, exist_ok=True)
    if not edit_dir.exists():
        clone_git_project(project, edit_dir, cwd=layout.package_root, shallow=False)
    else:
        fetch_git_project(project, edit_dir)

    target_branch = branch or default_reference_edit_branch(project)
    target_base_ref = base_ref or default_reference_edit_base(project)
    current_branch = current_git_branch(edit_dir)

    if local_branch_exists(edit_dir, target_branch):
        if current_branch != target_branch and not git_checkout_is_clean(edit_dir):
            raise SystemExit(
                f"[blueprint-harness] editable checkout `{edit_dir}` has local modifications; "
                f"cannot switch to branch `{target_branch}` safely."
            )
        if current_branch != target_branch:
            run(["git", "checkout", target_branch], cwd=edit_dir)
    else:
        if current_branch != target_branch and not git_checkout_is_clean(edit_dir):
            raise SystemExit(
                f"[blueprint-harness] editable checkout `{edit_dir}` has local modifications; "
                f"cannot create branch `{target_branch}` safely."
            )
        run(["git", "checkout", "-b", target_branch, target_base_ref], cwd=edit_dir)

    bootstrap_reference_checkout(project_dir=edit_dir / project.project_root)
    return edit_dir, target_branch, target_base_ref


def run_reference_lake_update(
    package_root: Path,
    project_dir: Path,
    *,
    reconcile_toolchains: bool = True,
) -> ReferenceLakeUpdateResult:
    reconciliation = (
        reconcile_reference_toolchains(package_root, project_dir)
        if reconcile_toolchains
        else ReferenceToolchainReconciliationResult(
            selected_ref=None,
            release_branch=None,
            changed_paths=(),
        )
    )
    command = project_lake_update_command(package_root, project_dir)
    run(command, cwd=project_dir)
    return ReferenceLakeUpdateResult(command=command, reconciliation=reconciliation)


def project_checkout_pathspec(checkout_root: Path, project_dir: Path) -> str:
    relative = project_dir.relative_to(checkout_root)
    return "." if str(relative) == "." else relative.as_posix()


def git_has_tracked_changes(checkout_root: Path, pathspec: str) -> bool:
    status = subprocess.run(
        ["git", "status", "--short", "--untracked-files=no", "--", pathspec],
        cwd=checkout_root,
        check=True,
        text=True,
        capture_output=True,
    ).stdout.strip()
    return bool(status)


def git_has_staged_changes(checkout_root: Path) -> bool:
    return (
        subprocess.run(
            ["git", "diff", "--cached", "--quiet"],
            cwd=checkout_root,
            check=False,
        ).returncode
        == 1
    )


def commit_project_tracked_changes(checkout_root: Path, pathspec: str, message: str) -> bool:
    run(["git", "add", "-u", "--", pathspec], cwd=checkout_root)
    if not git_has_staged_changes(checkout_root):
        return False
    run(["git", "commit", "-m", message], cwd=checkout_root)
    return True


def push_reference_edit_branch(checkout_root: Path, branch: str) -> None:
    run(["git", "push", "--set-upstream", "origin", branch], cwd=checkout_root)


def seed_reference_edit_checkout_lake(layout, project: HarnessProject, edit_dir: Path) -> Path | None:
    if shutil.which("rsync") is None:
        return None

    local_lake = reference_local_checkout_dir(layout, project) / project.project_root / ".lake"
    if local_lake.exists():
        run(
            ["rsync", "-a", "--delete", f"{local_lake}/", f"{edit_dir / project.project_root / '.lake'}/"],
            cwd=layout.package_root,
        )
        return local_lake

    dependency_packages = reference_dependency_packages_dir(layout, project)
    if dependency_packages.exists():
        edit_packages = edit_dir / project.project_root / ".lake" / "packages"
        edit_packages.mkdir(parents=True, exist_ok=True)
        run(
            [
                "rsync",
                "-a",
                "--delete",
                f"{dependency_packages}/",
                f"{edit_packages}/",
            ],
            cwd=layout.package_root,
        )
        return dependency_packages

    for source_dir in (
        reference_source_cache_checkout_dir(layout, project),
    ):
        source_lake = source_dir / project.project_root / ".lake"
        if source_lake.exists():
            run(
                ["rsync", "-a", "--delete", f"{source_lake}/", f"{edit_dir / project.project_root / '.lake'}/"],
                cwd=layout.package_root,
            )
            return source_lake
    return None


def bump_reference_project(
    layout,
    project: HarnessProject,
    *,
    ref: str,
    branch: str | None,
    base_ref: str | None,
    build_project: bool,
    generate_site: bool,
    output_root: Path | None,
    commit: bool,
    push: bool,
    commit_message: str | None,
) -> ReferenceProjectBumpResult:
    target_branch = branch or default_reference_bump_branch(ref)
    edit_dir, target_branch, target_base_ref = prepare_reference_edit_checkout(
        layout,
        project,
        branch=target_branch,
        base_ref=base_ref,
    )
    if not git_checkout_is_clean(edit_dir):
        raise SystemExit(
            f"[blueprint-harness] editable checkout `{edit_dir}` has local modifications; "
            "commit or discard them before bumping `VersoBlueprint`."
        )

    seeded_from = seed_reference_edit_checkout_lake(layout, project, edit_dir)
    if seeded_from is not None:
        print(f"[blueprint-harness] seeded editable checkout `.lake/` from {seeded_from}")

    project_dir = edit_dir / project.project_root
    _lakefile, previous_ref = rewrite_pinned_blueprint_dependency(project_dir, ref)
    run_reference_lake_update(layout.package_root, project_dir)

    generated_output: Path | None = None
    command_output_root = output_root or (layout.artifact_root / "reference-blueprints-edit")

    if build_project and project.build_command is not None:
        run_with_heartbeat(
            lean_low_priority_command(
                layout.package_root,
                *format_project_command(
                    project.build_command,
                    reference_command_placeholders(
                        project,
                        package_root=layout.package_root,
                        checkout_root=edit_dir,
                        project_dir=project_dir,
                        output_dir=output_dir_for(project, command_output_root),
                    ),
                ),
            ),
            cwd=project_dir,
            label=f"{project.project_id}: edit build project",
        )

    if generate_site:
        generated_output = output_dir_for(project, command_output_root)
        generated_output.mkdir(parents=True, exist_ok=True)
        run_with_heartbeat(
            lean_low_priority_command(
                layout.package_root,
                *format_project_command(
                    project.generate_command or (),
                    reference_command_placeholders(
                        project,
                        package_root=layout.package_root,
                        checkout_root=edit_dir,
                        project_dir=project_dir,
                        output_dir=generated_output,
                    ),
                ),
            ),
            cwd=project_dir,
            label=f"{project.project_id}: edit generate project",
        )

    pathspec = project_checkout_pathspec(edit_dir, project_dir)
    changed = git_has_tracked_changes(edit_dir, pathspec)
    committed = False
    pushed = False

    if commit or push:
        message = commit_message or f"chore: bump VersoBlueprint to {short_git_ref(ref)}"
        committed = commit_project_tracked_changes(edit_dir, pathspec, message)
        if push and committed:
            push_reference_edit_branch(edit_dir, target_branch)
            pushed = True

    return ReferenceProjectBumpResult(
        edit_dir=edit_dir,
        branch=target_branch,
        base_ref=target_base_ref,
        previous_ref=previous_ref,
        changed=changed,
        committed=committed,
        pushed=pushed,
        output_dir=generated_output,
    )


def reference_cache_warm_build_failure_message(
    layout,
    project: HarnessProject,
    command: list[str],
    err: subprocess.CalledProcessError,
) -> str:
    cache_key = reference_dependency_cache_key(project)
    source_cache = reference_source_cache_checkout_dir(layout, project)
    dependency_cache = reference_dependency_packages_dir(layout, project)
    return "\n".join(
        [
            (
                f"[blueprint-harness] failed to warm reference cache for `{project.project_id}` "
                f"({cache_key}); command exited with code {err.returncode}: {format_command(command)}"
            ),
            f"[blueprint-harness] source cache: {source_cache}",
            f"[blueprint-harness] dependency package cache: {dependency_cache}",
            (
                "[blueprint-harness] stale or cross-toolchain Lake build artifacts in the shared "
                "reference cache can cause incompatible `.olean` header errors."
            ),
            (
                "[blueprint-harness] for docs/Python-only work, create the checkout with "
                "`python3 -m scripts.blueprint_harness create-worktree <name> --lightweight`."
            ),
            (
                "[blueprint-harness] to inspect or remove stale reference caches, run "
                "`python3 -m scripts.blueprint_reference_harness prune --dry-run`, then "
                "`python3 -m scripts.blueprint_reference_harness prune` if the listed paths are disposable."
            ),
        ]
    )


def sync_reference_cache_checkout(
    layout,
    project: HarnessProject,
    *,
    warm_build: bool,
    package_mode: str = REFERENCE_PACKAGE_MODE_COPY,
) -> Path:
    package_mode = validate_reference_package_mode(package_mode)
    cache_dir = reference_source_cache_checkout_dir(layout, project)
    cache_dir.parent.mkdir(parents=True, exist_ok=True)
    if not cache_dir.exists():
        clone_git_project(project, cache_dir, cwd=layout.package_root)
    elif not (cache_dir / ".git").exists():
        shutil.rmtree(cache_dir)
        clone_git_project(project, cache_dir, cwd=layout.package_root)
    else:
        update_git_checkout(project, cache_dir)
    project_dir = cache_dir / project.project_root
    discard_untracked_project_manifest(project_dir)
    bootstrap_reference_checkout(project_dir=project_dir)
    borrowed_packages = (
        seed_lake_packages_from_dependency_cache(layout, project, project_dir, package_mode=package_mode) is not None
        and package_mode == REFERENCE_PACKAGE_MODE_MOVE
    )
    seed_lake_path_builds_from_dependency_cache(layout, project, project_dir)
    try:
        with local_blueprint_dependency_override(layout.package_root, project_dir, restore_lakefile=True):
            run_reference_lake_update(layout.package_root, project_dir)
            seed_lake_path_builds_from_dependency_cache(layout, project, project_dir)
            if warm_build and project.build_command is not None:
                command = lean_low_priority_command(layout.package_root, *project.build_command)
                try:
                    run_with_heartbeat(command, cwd=project_dir, label=f"{project.project_id}: warm cache build")
                except subprocess.CalledProcessError as err:
                    raise SystemExit(reference_cache_warm_build_failure_message(layout, project, command, err)) from err
            store_lake_path_builds_in_dependency_cache(layout, project, project_dir)
            if store_lake_packages_in_dependency_cache(layout, project, project_dir, package_mode=package_mode) is not None:
                # The dependency cache is now the source of truth. Drop the warmed
                # cache checkout copy so large external projects do not keep two
                # Mathlib package trees before the local checkout is prepared.
                discard_lake_packages(project_dir)
            borrowed_packages = False
    finally:
        if borrowed_packages:
            store_lake_packages_in_dependency_cache(layout, project, project_dir, package_mode=package_mode)
    return cache_dir


def sync_reference_local_checkout(
    layout,
    project: HarnessProject,
    cache_dir: Path,
    *,
    package_mode: str = REFERENCE_PACKAGE_MODE_COPY,
) -> Path:
    package_mode = validate_reference_package_mode(package_mode)
    local_dir = reference_local_checkout_dir(layout, project)
    local_dir.parent.mkdir(parents=True, exist_ok=True)
    if not local_dir.exists():
        clone_git_project(project, local_dir, cwd=layout.package_root, source=str(cache_dir))
    else:
        update_git_checkout(project, local_dir)
    bootstrap_reference_checkout(project_dir=local_dir / project.project_root)

    dependency_packages = reference_dependency_packages_dir(layout, project)
    if dependency_packages.exists():
        local_packages = local_dir / project.project_root / ".lake" / "packages"
        if package_mode == REFERENCE_PACKAGE_MODE_MOVE:
            discard_lake_packages(local_dir / project.project_root)
            local_packages.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(dependency_packages), str(local_packages))
            print(
                "[blueprint-harness] moved reference dependency packages into "
                f"{local_packages}"
            )
        else:
            local_packages.mkdir(parents=True, exist_ok=True)
            run(
                [
                    "rsync",
                    "-a",
                    f"{dependency_packages}/",
                    f"{local_packages}/",
                ],
                cwd=layout.package_root,
            )
    else:
        cache_lake = cache_dir / project.project_root / ".lake"
        if not cache_lake.exists():
            return local_dir
        # Fallback for caches produced before the dedicated dependency-package
        # cache existed: seed dependency state from the shared checkout, but
        # preserve the worktree-local project's own build products. Those
        # artifacts are produced after rewriting the reference project to depend
        # on the local VersoBlueprint checkout, so deleting them defeats the
        # local cache.
        run(
            ["rsync", "-a", "--exclude", "/build/", f"{cache_lake}/", f"{local_dir / project.project_root / '.lake'}/"],
            cwd=layout.package_root,
        )
    seed_lake_path_builds_from_dependency_cache(layout, project, local_dir / project.project_root)
    return local_dir


def generate_in_repo_command_project(
    layout,
    output_root: Path,
    project: HarnessProject,
    *,
    skip_build: bool,
    verbose: bool = False,
) -> None:
    project_dir = layout.package_root / project.project_root
    if not project_dir.exists():
        raise SystemExit(f"[blueprint-harness] missing in-repo project root for `{project.project_id}`: {project_dir}")

    output_dir = output_dir_for(project, output_root)
    output_dir.mkdir(parents=True, exist_ok=True)
    rebuild_and_log_embedded_asset_owners(layout.package_root)
    discard_untracked_project_manifest(project_dir)
    original_manifest = snapshot_tracked_project_manifest(project_dir)
    try:
        with maybe_in_repo_blueprint_dependency_override(project_dir, layout.package_root, log=True):
            generate_command = reference_generation_command(project.generate_command or (), verbose=verbose)
            run_project_update_build_generate(
                layout.package_root,
                project_dir,
                update_project=lambda: run_reference_lake_update(
                    layout.package_root,
                    project_dir,
                    reconcile_toolchains=False,
                ),
                build_command=project.build_command,
                generate_command=generate_command,
                format_command=lambda command: format_project_command(
                    command,
                    reference_command_placeholders(
                        project,
                        package_root=layout.package_root,
                        checkout_root=project_dir,
                        project_dir=project_dir,
                        output_dir=output_dir,
                    ),
                ),
                skip_build=skip_build,
                project_id=project.project_id,
            )
    finally:
        restore_tracked_project_manifest(original_manifest)


def generate_git_project(
    layout,
    output_root: Path,
    project: HarnessProject,
    *,
    skip_build: bool,
    package_mode: str = REFERENCE_PACKAGE_MODE_COPY,
    verbose: bool = False,
) -> None:
    package_mode = validate_reference_package_mode(package_mode)
    rebuild_and_log_embedded_asset_owners(layout.package_root)
    cache_dir = sync_reference_cache_checkout(layout, project, warm_build=False, package_mode=package_mode)
    checkout_root = sync_reference_local_checkout(layout, project, cache_dir, package_mode=package_mode)
    project_dir = checkout_root / project.project_root
    borrowed_packages = package_mode == REFERENCE_PACKAGE_MODE_MOVE and lake_packages_dir(project_dir).exists()
    try:
        discard_untracked_project_manifest(project_dir)
        output_dir = output_dir_for(project, output_root)
        output_dir.mkdir(parents=True, exist_ok=True)
        bootstrap_reference_checkout(project_dir=project_dir)
        def update_reference_project() -> None:
            run_reference_lake_update(
                layout.package_root,
                project_dir,
                reconcile_toolchains=True,
            )
            seed_lake_path_builds_from_dependency_cache(layout, project, project_dir)

        with local_blueprint_dependency_override(layout.package_root, project_dir, restore_lakefile=False, log=True):
            generate_command = reference_generation_command(project.generate_command or (), verbose=verbose)
            run_project_update_build_generate(
                layout.package_root,
                project_dir,
                update_project=update_reference_project,
                build_command=project.build_command,
                generate_command=generate_command,
                format_command=lambda command: format_project_command(
                    command,
                    reference_command_placeholders(
                        project,
                        package_root=layout.package_root,
                        checkout_root=checkout_root,
                        project_dir=project_dir,
                        output_dir=output_dir,
                    ),
                ),
                skip_build=skip_build,
                project_id=project.project_id,
            )
            store_lake_path_builds_in_dependency_cache(layout, project, project_dir)
    finally:
        if borrowed_packages:
            store_lake_packages_in_dependency_cache(layout, project, project_dir, package_mode=package_mode)


def sync_reference_blueprints(
    layout,
    projects: list[HarnessProject],
    *,
    warm_build: bool,
    prepare_local_checkout: bool,
    package_mode: str = REFERENCE_PACKAGE_MODE_COPY,
) -> None:
    package_mode = validate_reference_package_mode(package_mode)
    git_projects = [project for project in projects if project.git_checkout]
    if not git_projects:
        return
    if shutil.which("rsync") is None:
        raise SystemExit("[blueprint-harness] `rsync` is required for reference dependency cache sync.")
    for project in git_projects:
        cache_dir = sync_reference_cache_checkout(layout, project, warm_build=warm_build, package_mode=package_mode)
        if prepare_local_checkout:
            local_dir = sync_reference_local_checkout(layout, project, cache_dir, package_mode=package_mode)
            print(f"[blueprint-harness] prepared local reference checkout: {local_dir}")


def reference_prune_plan(
    active_worktree_names: set[str],
    active_cache_keys: set[str],
    cache_root: Path,
    checkout_root: Path,
    dependency_cache_root: Path | None = None,
) -> list[Path]:
    removals: list[Path] = []
    if cache_root.exists():
        for path in sorted(child for child in cache_root.iterdir() if child.is_dir()):
            if path.name not in active_cache_keys:
                removals.append(path)
    if dependency_cache_root is not None and dependency_cache_root.exists():
        for path in sorted(child for child in dependency_cache_root.iterdir() if child.is_dir()):
            if path.name not in active_cache_keys:
                removals.append(path)
    if checkout_root.exists():
        for namespace_dir in sorted(child for child in checkout_root.iterdir() if child.is_dir()):
            if namespace_dir.name not in active_worktree_names:
                removals.append(namespace_dir)
                continue
            for project_dir in sorted(child for child in namespace_dir.iterdir() if child.is_dir()):
                if project_dir.name not in active_cache_keys:
                    removals.append(project_dir)
    return removals
