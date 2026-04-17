from __future__ import annotations

from dataclasses import dataclass
import os
import re
import shutil
import subprocess
from pathlib import Path
import tomllib

from scripts.blueprint_harness_projects import HarnessProject
from scripts.blueprint_harness_utils import lean_low_priority_command, rebuild_embedded_asset_owners, run


OFFICIAL_BLUEPRINT_REPOSITORY = "leanprover/verso-blueprint"
OFFICIAL_BLUEPRINT_REQUIRE = (
    f'require VersoBlueprint from git "https://github.com/{OFFICIAL_BLUEPRINT_REPOSITORY}"@"main"'
)
OFFICIAL_BLUEPRINT_URL_PATTERNS = (
    rf"https://github\.com/{OFFICIAL_BLUEPRINT_REPOSITORY}(?:\.git)?",
    rf"git@github\.com:{OFFICIAL_BLUEPRINT_REPOSITORY}\.git",
    rf"ssh://git@github\.com/{OFFICIAL_BLUEPRINT_REPOSITORY}\.git",
)
OFFICIAL_BLUEPRINT_SOURCE_DESCRIPTION = f"`{OFFICIAL_BLUEPRINT_REPOSITORY}`"
COMMIT_HASH_PATTERN = re.compile(r"^[0-9a-f]{40}$", re.IGNORECASE)
GITHUB_SUBMODULE_URL_REWRITE_ARGS = (
    "-c",
    "url.https://github.com/.insteadOf=git@github.com:",
    "-c",
    "url.https://github.com/.insteadOf=ssh://git@github.com/",
)
REFERENCE_HARNESS_CONFIG = "verso-harness.toml"
OFFICIAL_BLUEPRINT_REQUIRE_PATTERN = re.compile(
    r'^(?P<indent>\s*)require\s+VersoBlueprint\s+from\s+git\s+"(?P<url>[^"]+)"(?:\s*@\s*"(?P<ref>[^"]+)")?\s*$',
    re.MULTILINE,
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

def output_dir_for(project: HarnessProject, output_root: Path) -> Path:
    return output_root / project.project_id


def site_dir_for(project: HarnessProject, output_root: Path) -> Path:
    return output_dir_for(project, output_root) / project.site_subdir


def reference_cache_checkout_dir(layout, project: HarnessProject) -> Path:
    return layout.reference_project_cache_root / project.project_id


def reference_local_checkout_dir(layout, project: HarnessProject) -> Path:
    return layout.reference_project_checkout_root / project.project_id


def reference_edit_checkout_dir(layout, project: HarnessProject) -> Path:
    return layout.reference_project_edit_root / project.project_id


def use_shared_reference_checkout() -> bool:
    return os.getenv("BP_REFERENCE_CHECKOUT_MODE") == "shared"


def short_git_ref(ref: str) -> str:
    return ref[:12] if COMMIT_HASH_PATTERN.fullmatch(ref) is not None else ref


def default_reference_bump_branch(ref: str) -> str:
    slug = re.sub(r"[^A-Za-z0-9]+", "-", short_git_ref(ref)).strip("-").lower()
    if not slug:
        slug = "pin"
    return f"chore/bump-verso-blueprint-{slug}"


def format_external_command(
    command: tuple[str, ...],
    *,
    project: HarnessProject,
    package_root: Path,
    checkout_root: Path,
    project_dir: Path,
    output_dir: Path,
) -> list[str]:
    site_dir = site_dir_for(project, output_dir.parent)
    placeholders = {
        "checkout_root": str(checkout_root),
        "package_root": str(package_root),
        "project_dir": str(project_dir),
        "output_dir": str(output_dir),
        "project_id": project.project_id,
        "site_dir": str(site_dir),
    }
    return [part.format(**placeholders) for part in command]


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


def _require_official_blueprint_git_dependency(project_dir: Path, *, action: str) -> tuple[Path, str, re.Match[str]]:
    lakefile = project_dir / "lakefile.lean"
    if not lakefile.exists():
        raise SystemExit(f"[blueprint-harness] missing lakefile for cloned project: {lakefile}")

    text = lakefile.read_text(encoding="utf-8")
    match = next(
        (
            candidate
            for candidate in OFFICIAL_BLUEPRINT_REQUIRE_PATTERN.finditer(text)
            if any(re.fullmatch(pattern, candidate.group("url")) for pattern in OFFICIAL_BLUEPRINT_URL_PATTERNS)
        ),
        None,
    )
    if match is None:
        raise SystemExit(
            "[blueprint-harness] expected the cloned project to declare `VersoBlueprint` in "
            "`lakefile.lean` from an approved `VersoBlueprint` Git source "
            f"({OFFICIAL_BLUEPRINT_SOURCE_DESCRIPTION}); cannot {action}."
        )
    return lakefile, text, match


def rewrite_local_blueprint_dependency(project_dir: Path, package_root: Path) -> Path:
    lakefile, text, match = _require_official_blueprint_git_dependency(
        project_dir,
        action="inject the local path override automatically",
    )
    relative_path = os.path.relpath(package_root, start=project_dir)
    replacement = f'{match.group("indent")}require VersoBlueprint from "{relative_path}"'
    rewritten = text[: match.start()] + replacement + text[match.end() :]
    lakefile.write_text(rewritten, encoding="utf-8")
    return lakefile


def rewrite_pinned_blueprint_dependency(project_dir: Path, ref: str) -> tuple[Path, str | None]:
    if not ref or any(char in ref for char in ('"', "\n", "\r")):
        raise SystemExit("[blueprint-harness] expected a non-empty `VersoBlueprint` ref without quotes or newlines")

    lakefile, text, match = _require_official_blueprint_git_dependency(
        project_dir,
        action="rewrite the pinned `VersoBlueprint` ref automatically",
    )
    replacement = (
        f'{match.group("indent")}require VersoBlueprint from git "{match.group("url")}"@"{ref}"'
    )
    rewritten = text[: match.start()] + replacement + text[match.end() :]
    lakefile.write_text(rewritten, encoding="utf-8")
    return lakefile, match.group("ref")


def git_tracks_file(project_dir: Path, relative_path: str) -> bool:
    return (
        subprocess.run(
            ["git", "ls-files", "--error-unmatch", relative_path],
            cwd=project_dir,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        ).returncode
        == 0
    )


def tracked_project_manifest_path(project_dir: Path) -> Path | None:
    manifest = project_dir / "lake-manifest.json"
    if not manifest.exists():
        return None
    if not git_tracks_file(project_dir, manifest.name):
        return None
    return manifest


def discard_untracked_project_manifest(project_dir: Path) -> None:
    manifest = project_dir / "lake-manifest.json"
    if manifest.exists() and tracked_project_manifest_path(project_dir) is None:
        manifest.unlink()


def snapshot_tracked_project_manifest(project_dir: Path) -> tuple[Path, str] | None:
    manifest = tracked_project_manifest_path(project_dir)
    if manifest is None:
        return None
    return manifest, manifest.read_text(encoding="utf-8")


def restore_tracked_project_manifest(snapshot: tuple[Path, str] | None) -> None:
    if snapshot is None:
        return
    manifest, original_text = snapshot
    manifest.write_text(original_text, encoding="utf-8")


def reference_update_command(package_root: Path, project_dir: Path) -> list[str]:
    manifest = tracked_project_manifest_path(project_dir)
    if manifest is not None:
        print(
            "[blueprint-harness] committed lake-manifest.json detected; "
            "updating `VersoBlueprint` only to keep `verso` pinned"
        )
        return lean_low_priority_command(package_root, "lake", "update", "VersoBlueprint")

    print(
        "[blueprint-harness] no committed lake-manifest.json detected; "
        "falling back to full `lake update`"
    )
    return lean_low_priority_command(package_root, "lake", "update")


def maybe_rewrite_in_repo_blueprint_dependency(project_dir: Path, package_root: Path) -> tuple[Path | None, str | None]:
    lakefile = project_dir / "lakefile.lean"
    if not lakefile.exists():
        return None, None

    text = lakefile.read_text(encoding="utf-8")
    if 'require VersoBlueprint from "' in text:
        return None, None
    if "require VersoBlueprint from git" not in text:
        return None, None

    rewrite_local_blueprint_dependency(project_dir, package_root)
    return lakefile, text


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

    for source_dir in (
        reference_local_checkout_dir(layout, project),
        reference_cache_checkout_dir(layout, project),
    ):
        source_lake = source_dir / ".lake"
        if source_lake.exists():
            run(["rsync", "-a", "--delete", f"{source_lake}/", f"{edit_dir / '.lake'}/"], cwd=layout.package_root)
            return source_dir
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
    run(reference_update_command(layout.package_root, project_dir), cwd=project_dir)

    generated_output: Path | None = None
    command_output_root = output_root or (layout.artifact_root / "reference-blueprints-edit")

    if build_project and project.build_command is not None:
        run(
            lean_low_priority_command(
                layout.package_root,
                *format_external_command(
                    project.build_command,
                    project=project,
                    package_root=layout.package_root,
                    checkout_root=edit_dir,
                    project_dir=project_dir,
                    output_dir=output_dir_for(project, command_output_root),
                ),
            ),
            cwd=project_dir,
        )

    if generate_site:
        generated_output = output_dir_for(project, command_output_root)
        generated_output.mkdir(parents=True, exist_ok=True)
        run(
            lean_low_priority_command(
                layout.package_root,
                *format_external_command(
                    project.generate_command or (),
                    project=project,
                    package_root=layout.package_root,
                    checkout_root=edit_dir,
                    project_dir=project_dir,
                    output_dir=generated_output,
                ),
            ),
            cwd=project_dir,
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


def sync_reference_cache_checkout(layout, project: HarnessProject, *, warm_build: bool) -> Path:
    cache_dir = reference_cache_checkout_dir(layout, project)
    cache_dir.parent.mkdir(parents=True, exist_ok=True)
    if not cache_dir.exists():
        clone_git_project(project, cache_dir, cwd=layout.package_root)
    else:
        update_git_checkout(project, cache_dir)
    project_dir = cache_dir / project.project_root
    discard_untracked_project_manifest(project_dir)
    bootstrap_reference_checkout(project_dir=project_dir)
    cache_lakefile = project_dir / "lakefile.lean"
    original_text = cache_lakefile.read_text(encoding="utf-8")
    rewrite_local_blueprint_dependency(project_dir, layout.repo_root)
    try:
        run(reference_update_command(layout.package_root, project_dir), cwd=project_dir)
        if warm_build and project.build_command is not None:
            run(lean_low_priority_command(layout.package_root, *project.build_command), cwd=project_dir)
    finally:
        cache_lakefile.write_text(original_text, encoding="utf-8")
    return cache_dir


def sync_reference_local_checkout(layout, project: HarnessProject, cache_dir: Path) -> Path:
    local_dir = reference_local_checkout_dir(layout, project)
    local_dir.parent.mkdir(parents=True, exist_ok=True)
    if not local_dir.exists():
        clone_git_project(project, local_dir, cwd=layout.package_root, source=str(cache_dir))
    else:
        update_git_checkout(project, local_dir)
    bootstrap_reference_checkout(project_dir=local_dir / project.project_root)

    cache_lake = cache_dir / ".lake"
    if cache_lake.exists():
        # The shared cache checkout is the source of truth for project-specific
        # dependency state, including warmed Mathlib builds when the reference
        # cache has been prepared ahead of time.
        run(["rsync", "-a", "--delete", f"{cache_lake}/", f"{local_dir / '.lake'}/"], cwd=layout.package_root)
    return local_dir


def generate_in_repo_command_project(layout, output_root: Path, project: HarnessProject, *, skip_build: bool) -> None:
    project_dir = layout.package_root / project.project_root
    if not project_dir.exists():
        raise SystemExit(f"[blueprint-harness] missing in-repo project root for `{project.project_id}`: {project_dir}")

    output_dir = output_dir_for(project, output_root)
    output_dir.mkdir(parents=True, exist_ok=True)
    rebuilt = rebuild_embedded_asset_owners(layout.package_root)
    for target in rebuilt:
        print(f"[blueprint-harness] rebuilt embedded-asset owner target: {target}")
    discard_untracked_project_manifest(project_dir)
    original_manifest = snapshot_tracked_project_manifest(project_dir)
    rewritten_lakefile, original_lakefile_text = maybe_rewrite_in_repo_blueprint_dependency(project_dir, layout.package_root)
    if rewritten_lakefile is not None:
        print(f"[blueprint-harness] local package override: rewrote {rewritten_lakefile}")
    try:
        run(reference_update_command(layout.package_root, project_dir), cwd=project_dir)
        if not skip_build and project.build_command is not None:
            run(
                lean_low_priority_command(
                    layout.package_root,
                    *format_external_command(
                        project.build_command,
                        project=project,
                        package_root=layout.package_root,
                        checkout_root=project_dir,
                        project_dir=project_dir,
                        output_dir=output_dir,
                    ),
                ),
                cwd=project_dir,
            )
        run(
            lean_low_priority_command(
                layout.package_root,
                *format_external_command(
                    project.generate_command or (),
                    project=project,
                    package_root=layout.package_root,
                    checkout_root=project_dir,
                    project_dir=project_dir,
                    output_dir=output_dir,
                ),
            ),
            cwd=project_dir,
        )
    finally:
        restore_tracked_project_manifest(original_manifest)
        if rewritten_lakefile is not None and original_lakefile_text is not None:
            rewritten_lakefile.write_text(original_lakefile_text, encoding="utf-8")


def generate_git_project(layout, output_root: Path, project: HarnessProject, *, skip_build: bool) -> None:
    # Shared cache warm builds run against `layout.repo_root` so linked worktree
    # validations must skip them here and build only after rewriting the local
    # checkout dependency to `layout.package_root`.
    cache_warm_build = (not skip_build) and use_shared_reference_checkout()
    rebuilt = rebuild_embedded_asset_owners(layout.package_root)
    for target in rebuilt:
        print(f"[blueprint-harness] rebuilt embedded-asset owner target: {target}")
    cache_dir = sync_reference_cache_checkout(layout, project, warm_build=cache_warm_build)
    checkout_root = cache_dir if use_shared_reference_checkout() else sync_reference_local_checkout(layout, project, cache_dir)
    project_dir = checkout_root / project.project_root
    discard_untracked_project_manifest(project_dir)
    output_dir = output_dir_for(project, output_root)
    output_dir.mkdir(parents=True, exist_ok=True)
    original_text = (project_dir / "lakefile.lean").read_text(encoding="utf-8") if use_shared_reference_checkout() else None
    try:
        bootstrap_reference_checkout(project_dir=project_dir)
        rewritten_lakefile = rewrite_local_blueprint_dependency(project_dir, layout.package_root)
        print(f"[blueprint-harness] local package override: rewrote {rewritten_lakefile}")
        run(reference_update_command(layout.package_root, project_dir), cwd=project_dir)
        if not skip_build and project.build_command is not None:
            run(
                lean_low_priority_command(
                    layout.package_root,
                    *format_external_command(
                        project.build_command,
                        project=project,
                        package_root=layout.package_root,
                        checkout_root=checkout_root,
                        project_dir=project_dir,
                        output_dir=output_dir,
                    ),
                ),
                cwd=project_dir,
            )
        run(
            lean_low_priority_command(
                layout.package_root,
                *format_external_command(
                    project.generate_command or (),
                    project=project,
                    package_root=layout.package_root,
                    checkout_root=checkout_root,
                    project_dir=project_dir,
                    output_dir=output_dir,
                ),
            ),
            cwd=project_dir,
        )
    finally:
        if original_text is not None:
            (project_dir / "lakefile.lean").write_text(original_text, encoding="utf-8")


def sync_reference_blueprints(layout, projects: list[HarnessProject], *, warm_build: bool, prepare_local_checkout: bool) -> None:
    git_projects = [project for project in projects if project.git_checkout]
    if not git_projects:
        return
    if shutil.which("rsync") is None:
        raise SystemExit("[blueprint-harness] `rsync` is required for reference blueprint cache sync.")
    for project in git_projects:
        cache_dir = sync_reference_cache_checkout(layout, project, warm_build=warm_build)
        if prepare_local_checkout:
            local_dir = sync_reference_local_checkout(layout, project, cache_dir)
            print(f"[blueprint-harness] prepared local reference checkout: {local_dir}")


def reference_prune_plan(active_worktree_names: set[str], project_ids: set[str], cache_root: Path, checkout_root: Path) -> list[Path]:
    removals: list[Path] = []
    if cache_root.exists():
        for path in sorted(child for child in cache_root.iterdir() if child.is_dir()):
            if path.name not in project_ids:
                removals.append(path)
    if checkout_root.exists():
        for namespace_dir in sorted(child for child in checkout_root.iterdir() if child.is_dir()):
            if namespace_dir.name not in active_worktree_names:
                removals.append(namespace_dir)
                continue
            for project_dir in sorted(child for child in namespace_dir.iterdir() if child.is_dir()):
                if project_dir.name not in project_ids:
                    removals.append(project_dir)
    return removals
