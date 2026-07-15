from __future__ import annotations

from collections.abc import Callable, Mapping
from contextlib import contextmanager
import os
from pathlib import Path
import re
import subprocess

from scripts.blueprint_harness_utils import (
    ensure_embedded_asset_owner_outputs,
    lean_low_priority_command,
    rebuild_embedded_asset_owners,
    run,
    run_with_heartbeat,
    timed_step,
)


OFFICIAL_BLUEPRINT_REPOSITORY = "leanprover/verso-blueprint"
OFFICIAL_BLUEPRINT_URL_PATTERNS = (
    rf"https://github\.com/{OFFICIAL_BLUEPRINT_REPOSITORY}(?:\.git)?",
    rf"git@github\.com:{OFFICIAL_BLUEPRINT_REPOSITORY}\.git",
    rf"ssh://git@github\.com/{OFFICIAL_BLUEPRINT_REPOSITORY}\.git",
)
OFFICIAL_BLUEPRINT_SOURCE_DESCRIPTION = f"`{OFFICIAL_BLUEPRINT_REPOSITORY}`"
OFFICIAL_BLUEPRINT_REQUIRE_PATTERN = re.compile(
    r'^(?P<indent>[ \t]*)require\s+VersoBlueprint\s+from\s+git\s+"(?P<url>[^"]+)"(?:\s*@\s*"(?P<ref>[^"]+)")?[ \t]*$',
    re.MULTILINE,
)
RELATIVE_BLUEPRINT_REQUIRE_PATTERN = re.compile(
    r'^(?P<indent>\s*)require\s+VersoBlueprint\s+from\s+"(?P<path>(?:(?:\.\.?)/)+verso-blueprint/?)"\s*$',
    re.MULTILINE,
)
MATHLIB_STANDARD_LINTER_OPTION_PATTERN = re.compile(
    r"^(?P<indent>\s*)⟨`weak\.linter\.mathlibStandardSet,\s*true⟩",
    re.MULTILINE,
)


def _blueprint_lakefile_text(project_dir: Path) -> tuple[Path, str]:
    lakefile = project_dir / "lakefile.lean"
    if not lakefile.exists():
        raise SystemExit(f"[blueprint-harness] missing lakefile for cloned project: {lakefile}")
    return lakefile, lakefile.read_text(encoding="utf-8")


def _official_blueprint_git_dependency_match(text: str) -> re.Match[str] | None:
    return next(
        (
            candidate
            for candidate in OFFICIAL_BLUEPRINT_REQUIRE_PATTERN.finditer(text)
            if any(re.fullmatch(pattern, candidate.group("url")) for pattern in OFFICIAL_BLUEPRINT_URL_PATTERNS)
        ),
        None,
    )


def _require_official_blueprint_git_dependency(project_dir: Path, *, action: str) -> tuple[Path, str, re.Match[str]]:
    lakefile, text = _blueprint_lakefile_text(project_dir)
    match = _official_blueprint_git_dependency_match(text)
    if match is None:
        raise SystemExit(
            "[blueprint-harness] expected the cloned project to declare `VersoBlueprint` in "
            "`lakefile.lean` from an approved `VersoBlueprint` Git source "
            f"({OFFICIAL_BLUEPRINT_SOURCE_DESCRIPTION}); cannot {action}."
        )
    return lakefile, text, match


def _require_approved_local_blueprint_dependency(project_dir: Path) -> tuple[Path, str, re.Match[str]]:
    lakefile, text = _blueprint_lakefile_text(project_dir)
    match = _official_blueprint_git_dependency_match(text)
    if match is None:
        match = RELATIVE_BLUEPRINT_REQUIRE_PATTERN.search(text)
    if match is None:
        raise SystemExit(
            "[blueprint-harness] expected the cloned project to declare `VersoBlueprint` in "
            "`lakefile.lean` from an approved `VersoBlueprint` Git source "
            f"({OFFICIAL_BLUEPRINT_SOURCE_DESCRIPTION}) or a relative `verso-blueprint` checkout; "
            "cannot inject the local path override automatically."
        )
    return lakefile, text, match


def rewrite_local_blueprint_dependency(
    project_dir: Path,
    package_root: Path,
    *,
    relative: bool = False,
) -> Path:
    lakefile, text, match = _require_approved_local_blueprint_dependency(project_dir)
    local_path = (
        Path(os.path.relpath(package_root.resolve(), project_dir.resolve())).as_posix()
        if relative
        else str(package_root.resolve())
    )
    replacement = f'{match.group("indent")}require VersoBlueprint from "{local_path}"'
    rewritten = text[: match.start()] + replacement + text[match.end() :]
    rewritten = disable_header_linter_for_mathlib_blueprint_lakefile(rewritten)
    lakefile.write_text(rewritten, encoding="utf-8")
    return lakefile


def disable_header_linter_for_mathlib_blueprint_lakefile(text: str) -> str:
    # The Mathlib header linter parses the leading file text as Lean commands.
    # Top-level Verso documents contain non-command markup, so keep the rest of
    # the Mathlib linter set while disabling only that header check.
    if "`weak.linter.style.header" in text:
        return text

    match = MATHLIB_STANDARD_LINTER_OPTION_PATTERN.search(text)
    if match is None:
        return text

    indent = match.group("indent")
    replacement = f"{indent}⟨`weak.linter.style.header, false⟩,\n{match.group(0)}"
    return text[: match.start()] + replacement + text[match.end() :]


def rewrite_pinned_blueprint_dependency(project_dir: Path, ref: str) -> tuple[Path, str | None]:
    if not ref or any(char in ref for char in ('"', "\n", "\r")):
        raise SystemExit("[blueprint-harness] expected a non-empty `VersoBlueprint` ref without quotes or newlines")

    lakefile, text, match = _require_official_blueprint_git_dependency(
        project_dir,
        action="rewrite the pinned `VersoBlueprint` ref automatically",
    )
    replacement = f'{match.group("indent")}require VersoBlueprint from git "{match.group("url")}"@"{ref}"'
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


def project_lake_update_command(package_root: Path, project_dir: Path) -> list[str]:
    manifest = tracked_project_manifest_path(project_dir)
    if manifest is not None:
        print(
            "[blueprint-harness] committed lake-manifest.json detected; "
            "running full `lake update` from committed pins"
        )
    else:
        print(
            "[blueprint-harness] no committed lake-manifest.json detected; "
            "falling back to full `lake update`"
        )
    return lean_low_priority_command(package_root, "lake", "update")


def run_project_lake_update(package_root: Path, project_dir: Path) -> list[str]:
    command = project_lake_update_command(package_root, project_dir)
    run(command, cwd=project_dir)
    return command


def maybe_rewrite_in_repo_blueprint_dependency(
    project_dir: Path,
    package_root: Path,
    *,
    relative: bool = False,
) -> tuple[Path | None, str | None]:
    lakefile = project_dir / "lakefile.lean"
    if not lakefile.exists():
        return None, None

    text = lakefile.read_text(encoding="utf-8")
    if 'require VersoBlueprint from "' in text:
        return None, None
    if "require VersoBlueprint from git" not in text:
        return None, None

    rewrite_local_blueprint_dependency(project_dir, package_root, relative=relative)
    return lakefile, text


@contextmanager
def maybe_in_repo_blueprint_dependency_override(
    project_dir: Path,
    package_root: Path,
    *,
    log: bool = False,
    relative: bool = False,
):
    rewritten_lakefile, original_lakefile_text = maybe_rewrite_in_repo_blueprint_dependency(
        project_dir,
        package_root,
        relative=relative,
    )
    if rewritten_lakefile is not None and log:
        print(f"[blueprint-harness] local package override: rewrote {rewritten_lakefile}")
    try:
        yield rewritten_lakefile
    finally:
        if rewritten_lakefile is not None and original_lakefile_text is not None:
            rewritten_lakefile.write_text(original_lakefile_text, encoding="utf-8")


@contextmanager
def local_blueprint_dependency_override(
    package_root: Path,
    project_dir: Path,
    *,
    restore_lakefile: bool,
    log: bool = False,
):
    lakefile = project_dir / "lakefile.lean"
    original_text = lakefile.read_text(encoding="utf-8") if restore_lakefile else None
    rewritten_lakefile = rewrite_local_blueprint_dependency(project_dir, package_root)
    if log:
        print(f"[blueprint-harness] local package override: rewrote {rewritten_lakefile}")
    try:
        yield rewritten_lakefile
    finally:
        if original_text is not None:
            lakefile.write_text(original_text, encoding="utf-8")


def rebuild_and_log_embedded_asset_owners(package_root: Path) -> list[str]:
    rebuilt = rebuild_embedded_asset_owners(package_root)
    for target in rebuilt:
        print(f"[blueprint-harness] rebuilt embedded-asset owner target: {target}")
    return rebuilt


def ensure_and_log_embedded_asset_owner_outputs(package_root: Path) -> list[str]:
    materialized = ensure_embedded_asset_owner_outputs(package_root)
    for target in materialized:
        print(f"[blueprint-harness] materialized embedded-asset owner output: {target}")
    return materialized


def format_project_command(command: tuple[str, ...], placeholders: Mapping[str, object]) -> list[str]:
    values = {key: str(value) for key, value in placeholders.items()}
    return [part.format(**values) for part in command]


def run_project_update_build_generate(
    package_root: Path,
    project_dir: Path,
    *,
    update_project: Callable[[], object],
    build_command: tuple[str, ...] | None,
    generate_command: tuple[str, ...],
    format_command: Callable[[tuple[str, ...]], list[str]],
    skip_build: bool,
    project_id: str | None = None,
) -> None:
    label_prefix = f"{project_id}: " if project_id is not None else ""
    with timed_step(f"{label_prefix}update project"):
        update_project()
    if not skip_build and build_command is not None:
        run_with_heartbeat(
            lean_low_priority_command(package_root, *format_command(build_command)),
            cwd=project_dir,
            label=f"{label_prefix}build project",
        )
    with timed_step(f"{label_prefix}embedded asset owner outputs"):
        ensure_and_log_embedded_asset_owner_outputs(package_root)
    run_with_heartbeat(
        lean_low_priority_command(package_root, *format_command(generate_command)),
        cwd=project_dir,
        label=f"{label_prefix}generate project",
    )
