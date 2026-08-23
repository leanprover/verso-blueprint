from __future__ import annotations

from dataclasses import dataclass, replace
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
import tomllib

from scripts.blueprint_harness_releases import (
    lean_release_family,
    lean_release_subversion,
    normalize_lean_release_ref,
)
from scripts.blueprint_harness_projects import (
    HarnessProject,
    command_with_pdf,
    reference_source_identity,
    selected_project_toolchain,
    short_git_ref,
)
from scripts.blueprint_harness_project_commands import (
    discard_untracked_project_manifest,
    format_project_command,
    local_blueprint_dependency_override,
    maybe_in_repo_blueprint_dependency_override,
    project_lake_update_command,
    restore_tracked_project_manifest,
    rewrite_pinned_blueprint_dependency,
    run_project_update_build_generate,
    snapshot_tracked_project_manifest,
)
from scripts.blueprint_harness_utils import format_command, lean_low_priority_command, run, run_with_heartbeat


COMMIT_HASH_PATTERN = re.compile(r"^[0-9a-f]{40}$", re.IGNORECASE)
GITHUB_SUBMODULE_URL_REWRITE_ARGS = (
    "-c",
    "url.https://github.com/.insteadOf=git@github.com:",
    "-c",
    "url.https://github.com/.insteadOf=ssh://git@github.com/",
)
REFERENCE_HARNESS_CONFIG = "verso-harness.toml"
REFERENCE_BUILD_METRICS_FILENAME = "build-metrics.json"


def command_with_verbose(command: tuple[str, ...]) -> tuple[str, ...]:
    if "--verbose" in command:
        return command
    return (*command, "--verbose")


def reference_generation_command(
    command: tuple[str, ...],
    *,
    pdf: bool,
    verbose: bool,
) -> tuple[str, ...]:
    if pdf:
        command = command_with_pdf(command)
    if verbose:
        command = command_with_verbose(command)
    return command


def reference_build_metrics_command(
    package_root: Path,
    project: HarnessProject,
    output_dir: Path,
    command: tuple[str, ...],
) -> tuple[str, ...]:
    if project.selected_release is None:
        raise ValueError(f"project `{project.project_id}` is missing selected release metadata")
    return (
        sys.executable,
        str(package_root / "scripts" / "reference_build_metrics.py"),
        "record",
        "--output",
        str(output_dir / REFERENCE_BUILD_METRICS_FILENAME),
        "--project-id",
        project.project_id,
        "--release-id",
        project.selected_release,
        "--source-ref",
        project.ref or "",
        "--toolchain",
        selected_project_toolchain(project),
        "--",
        *command,
    )


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
class ReferenceToolchain:
    lean_ref: str
    release_family: tuple[int, int]
    subversion: tuple[int, int, int]


@dataclass(frozen=True)
class ReferenceSourcePaths:
    identity: str
    source_checkout: Path
    dependency_packages: Path
    dependency_path_builds: Path
    local_checkout: Path


def output_dir_for(project: HarnessProject, output_root: Path) -> Path:
    return output_root / project.project_id


def site_dir_for(project: HarnessProject, output_root: Path) -> Path:
    return output_dir_for(project, output_root) / project.site_subdir


def reference_source_paths(layout, project: HarnessProject) -> ReferenceSourcePaths:
    identity = reference_source_identity(project)
    dependency_cache = layout.reference_dependency_cache_root / identity
    return ReferenceSourcePaths(
        identity=identity,
        source_checkout=layout.reference_source_cache_root / identity,
        dependency_packages=dependency_cache / "packages",
        dependency_path_builds=dependency_cache / "path-builds",
        local_checkout=layout.reference_project_checkout_root / identity,
    )


def reference_edit_checkout_dir(layout, project: HarnessProject) -> Path:
    return layout.reference_project_edit_root / project.project_id


def reference_source_identities(projects: tuple[HarnessProject, ...] | list[HarnessProject]) -> set[str]:
    identities: set[str] = set()
    for project in projects:
        if not project.git_checkout:
            continue
        if project.ref is not None:
            identities.add(reference_source_identity(project))
        for target in project.targets:
            if target.ref is None:
                continue
            identities.add(
                reference_source_identity(
                    replace(project, ref=target.ref, selected_release=target.release)
                )
            )
    return identities


def lake_packages_dir(project_dir: Path) -> Path:
    return project_dir / ".lake" / "packages"


def lake_build_dir(project_dir: Path) -> Path:
    return project_dir / ".lake" / "build"


def read_reference_toolchain(path: Path) -> ReferenceToolchain | None:
    if not path.exists():
        return None
    try:
        lean_ref = normalize_lean_release_ref(path.read_text(encoding="utf-8"))
    except SystemExit:
        return None

    return ReferenceToolchain(
        lean_ref=lean_ref,
        release_family=lean_release_family(lean_ref),
        subversion=lean_release_subversion(lean_ref),
    )


def validate_external_reference_toolchain(
    package_root: Path,
    project_dir: Path,
    *,
    expected_project_toolchain: str,
) -> str:
    """Reject cross-release checks without changing any checkout toolchain.

    The external project owns the compiler used for its build. In particular,
    an RC-pinned catalog project remains on that RC even when the selected
    Verso Blueprint checkout has advanced to the final release. Dependency
    toolchains are immutable inputs and are never inspected or rewritten.
    """
    package_toolchain = read_reference_toolchain(package_root / "lean-toolchain")
    project_toolchain = read_reference_toolchain(project_dir / "lean-toolchain")
    if package_toolchain is None:
        raise SystemExit(
            "[blueprint-harness] selected Verso Blueprint checkout has no valid `lean-toolchain`: "
            f"{package_root / 'lean-toolchain'}"
        )
    if project_toolchain is None:
        raise SystemExit(
            "[blueprint-harness] external reference project has no valid `lean-toolchain`: "
            f"{project_dir / 'lean-toolchain'}"
        )
    if package_toolchain.release_family != project_toolchain.release_family:
        raise SystemExit(
            "[blueprint-harness] reference Blueprint release mismatch: "
            f"project `{project_dir}` uses Lean `{project_toolchain.lean_ref}` "
            f"(family {project_toolchain.release_family}), but the selected Verso Blueprint checkout "
            f"uses Lean `{package_toolchain.lean_ref}` (family {package_toolchain.release_family}). "
            "Catalog each external Blueprint only under its current matching release."
        )
    if package_toolchain.subversion < project_toolchain.subversion:
        raise SystemExit(
            "[blueprint-harness] Verso Blueprint is older than the reference Blueprint: "
            f"VBP uses Lean `{package_toolchain.lean_ref}`, while project `{project_dir}` uses "
            f"Lean `{project_toolchain.lean_ref}`. Ask the VBP maintainers to bump VBP before "
            "building this reference."
        )
    expected_ref = normalize_lean_release_ref(expected_project_toolchain)
    if project_toolchain.lean_ref != expected_ref:
        raise SystemExit(
            "[blueprint-harness] reference Blueprint toolchain mismatch: "
            f"catalog target expects Lean `{expected_ref}`, but project `{project_dir}` "
            f"uses Lean `{project_toolchain.lean_ref}`. Update the external project ref "
            "or its `reference_toolchain` metadata."
        )
    return project_toolchain.lean_ref


def require_reference_rsync() -> None:
    if shutil.which("rsync") is None:
        raise SystemExit("[blueprint-harness] `rsync` is required for external reference cache copies.")


def seed_lake_packages_from_dependency_cache(
    layout,
    project: HarnessProject,
    project_dir: Path,
) -> Path | None:
    source_packages = reference_source_paths(layout, project).dependency_packages
    if not source_packages.exists():
        return None
    destination_packages = lake_packages_dir(project_dir)
    destination_packages.mkdir(parents=True, exist_ok=True)
    run(["rsync", "-a", f"{source_packages}/", f"{destination_packages}/"], cwd=layout.package_root)
    return source_packages


def store_lake_packages_in_dependency_cache(
    layout,
    project: HarnessProject,
    project_dir: Path,
) -> Path | None:
    source_packages = lake_packages_dir(project_dir)
    if not source_packages.exists():
        return None
    destination_packages = reference_source_paths(layout, project).dependency_packages
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
    source_root = reference_source_paths(layout, project).dependency_path_builds
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
    destination_root = reference_source_paths(layout, project).dependency_path_builds
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
    # Reference generation does not need large source-data objects stored in
    # external projects' Git LFS. Leave their pointers intact so an upstream
    # quota outage cannot prevent the formalization submodule from checking out.
    return [
        "env",
        "GIT_LFS_SKIP_SMUDGE=1",
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
) -> list[str]:
    command = project_lake_update_command(package_root, project_dir)
    run(command, cwd=project_dir)
    return command


def run_external_reference_lake_update(
    package_root: Path,
    project_dir: Path,
    *,
    expected_project_toolchain: str,
) -> list[str]:
    validate_external_reference_toolchain(
        package_root,
        project_dir,
        expected_project_toolchain=expected_project_toolchain,
    )
    return run_reference_lake_update(package_root, project_dir)


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

    paths = reference_source_paths(layout, project)
    local_lake = paths.local_checkout / project.project_root / ".lake"
    if local_lake.exists():
        run(
            ["rsync", "-a", "--delete", f"{local_lake}/", f"{edit_dir / project.project_root / '.lake'}/"],
            cwd=layout.package_root,
        )
        return local_lake

    dependency_packages = paths.dependency_packages
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

    source_lake = paths.source_checkout / project.project_root / ".lake"
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
    run_external_reference_lake_update(
        layout.package_root,
        project_dir,
        expected_project_toolchain=selected_project_toolchain(project),
    )

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
    paths = reference_source_paths(layout, project)
    return "\n".join(
        [
            (
                f"[blueprint-harness] failed to warm reference cache for `{project.project_id}` "
                f"({paths.identity}); command exited with code {err.returncode}: {format_command(command)}"
            ),
            f"[blueprint-harness] source cache: {paths.source_checkout}",
            f"[blueprint-harness] dependency package cache: {paths.dependency_packages}",
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
) -> Path:
    cache_dir = reference_source_paths(layout, project).source_checkout
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
    seed_lake_packages_from_dependency_cache(layout, project, project_dir)
    seed_lake_path_builds_from_dependency_cache(layout, project, project_dir)
    with local_blueprint_dependency_override(layout.package_root, project_dir, restore_lakefile=True):
        run_external_reference_lake_update(
            layout.package_root,
            project_dir,
            expected_project_toolchain=selected_project_toolchain(project),
        )
        seed_lake_path_builds_from_dependency_cache(layout, project, project_dir)
        if warm_build and project.build_command is not None:
            command = lean_low_priority_command(layout.package_root, *project.build_command)
            try:
                run_with_heartbeat(command, cwd=project_dir, label=f"{project.project_id}: warm cache build")
            except subprocess.CalledProcessError as err:
                raise SystemExit(reference_cache_warm_build_failure_message(layout, project, command, err)) from err
        store_lake_path_builds_in_dependency_cache(layout, project, project_dir)
        if store_lake_packages_in_dependency_cache(layout, project, project_dir) is not None:
            # The dependency cache is now the source of truth. Drop the warmed
            # source-checkout copy so large external projects do not keep two
            # Mathlib package trees before the local checkout is prepared.
            discard_lake_packages(project_dir)
    return cache_dir


def sync_reference_local_checkout(
    layout,
    project: HarnessProject,
    cache_dir: Path,
) -> Path:
    paths = reference_source_paths(layout, project)
    local_dir = paths.local_checkout
    local_dir.parent.mkdir(parents=True, exist_ok=True)
    if not local_dir.exists():
        clone_git_project(project, local_dir, cwd=layout.package_root, source=str(cache_dir))
    else:
        update_git_checkout(project, local_dir)
    bootstrap_reference_checkout(project_dir=local_dir / project.project_root)

    project_dir = local_dir / project.project_root
    seed_lake_packages_from_dependency_cache(layout, project, project_dir)
    seed_lake_path_builds_from_dependency_cache(layout, project, project_dir)
    return local_dir


def generate_in_repo_command_project(
    layout,
    output_root: Path,
    project: HarnessProject,
    *,
    skip_build: bool,
    pdf: bool = False,
    verbose: bool = False,
    record_build_metrics: bool = False,
) -> None:
    project_dir = layout.package_root / project.project_root
    if not project_dir.exists():
        raise SystemExit(f"[blueprint-harness] missing in-repo project root for `{project.project_id}`: {project_dir}")

    output_dir = output_dir_for(project, output_root)
    output_dir.mkdir(parents=True, exist_ok=True)
    discard_untracked_project_manifest(project_dir)
    original_manifest = snapshot_tracked_project_manifest(project_dir)
    try:
        with maybe_in_repo_blueprint_dependency_override(project_dir, layout.package_root, log=True):
            generate_command = reference_generation_command(
                project.generate_command or (),
                pdf=pdf,
                verbose=verbose or record_build_metrics,
            )
            if record_build_metrics:
                generate_command = reference_build_metrics_command(
                    layout.package_root,
                    project,
                    output_dir,
                    generate_command,
                )
            run_project_update_build_generate(
                layout.package_root,
                project_dir,
                update_project=lambda: run_reference_lake_update(
                    layout.package_root,
                    project_dir,
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
    pdf: bool = False,
    verbose: bool = False,
    record_build_metrics: bool = False,
) -> None:
    cache_dir = sync_reference_cache_checkout(layout, project, warm_build=False)
    checkout_root = sync_reference_local_checkout(layout, project, cache_dir)
    project_dir = checkout_root / project.project_root
    discard_untracked_project_manifest(project_dir)
    output_dir = output_dir_for(project, output_root)
    output_dir.mkdir(parents=True, exist_ok=True)

    def update_reference_project() -> None:
        run_external_reference_lake_update(
            layout.package_root,
            project_dir,
            expected_project_toolchain=selected_project_toolchain(project),
        )
        seed_lake_path_builds_from_dependency_cache(layout, project, project_dir)

    with local_blueprint_dependency_override(layout.package_root, project_dir, restore_lakefile=False, log=True):
        generate_command = reference_generation_command(
            project.generate_command or (),
            pdf=pdf,
            verbose=verbose or record_build_metrics,
        )
        if record_build_metrics:
            generate_command = reference_build_metrics_command(
                layout.package_root,
                project,
                output_dir,
                generate_command,
            )
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


def sync_reference_blueprints(
    layout,
    projects: list[HarnessProject],
    *,
    warm_build: bool,
    prepare_local_checkout: bool,
) -> None:
    git_projects = [project for project in projects if project.git_checkout]
    if not git_projects:
        return
    require_reference_rsync()
    for project in git_projects:
        cache_dir = sync_reference_cache_checkout(layout, project, warm_build=warm_build)
        if prepare_local_checkout:
            local_dir = sync_reference_local_checkout(layout, project, cache_dir)
            print(f"[blueprint-harness] prepared local reference checkout: {local_dir}")


def reference_prune_plan(
    active_worktree_names: set[str],
    active_source_identities: set[str],
    cache_root: Path,
    checkout_root: Path,
    dependency_cache_root: Path | None = None,
) -> list[Path]:
    removals: list[Path] = []
    if cache_root.exists():
        for path in sorted(child for child in cache_root.iterdir() if child.is_dir()):
            if path.name not in active_source_identities:
                removals.append(path)
    if dependency_cache_root is not None and dependency_cache_root.exists():
        for path in sorted(child for child in dependency_cache_root.iterdir() if child.is_dir()):
            if path.name not in active_source_identities:
                removals.append(path)
    if checkout_root.exists():
        for namespace_dir in sorted(child for child in checkout_root.iterdir() if child.is_dir()):
            if namespace_dir.name not in active_worktree_names:
                removals.append(namespace_dir)
                continue
            for project_dir in sorted(child for child in namespace_dir.iterdir() if child.is_dir()):
                if project_dir.name not in active_source_identities:
                    removals.append(project_dir)
    return removals
