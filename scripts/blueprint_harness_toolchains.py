from __future__ import annotations

from dataclasses import dataclass
import re
import subprocess
from pathlib import Path

from scripts.blueprint_harness_releases import (
    lean_toolchain_spec,
    normalize_lean_release_ref,
    release_branch_from_lean_ref,
    rewrite_lean_toolchain,
)
from scripts.blueprint_harness_project_commands import (
    maybe_in_repo_blueprint_dependency_override,
    rewrite_pinned_blueprint_dependency,
)
from scripts.blueprint_harness_utils import lean_low_priority_command, run


VERSO_REPOSITORY_URL = "https://github.com/leanprover/verso"
VERSO_SLIDES_REPOSITORY_URL = "https://github.com/leanprover/verso-slides"
OFFICIAL_VERSO_URL_PATTERNS = (
    r"https://github\.com/leanprover/verso(?:\.git)?",
    r"git@github\.com:leanprover/verso\.git",
    r"ssh://git@github\.com/leanprover/verso\.git",
)
OFFICIAL_VERSO_SLIDES_URL_PATTERNS = (
    r"https://github\.com/leanprover/verso-slides(?:\.git)?",
    r"git@github\.com:leanprover/verso-slides\.git",
    r"ssh://git@github\.com/leanprover/verso-slides\.git",
)
VERSO_REQUIRE_PATTERN = re.compile(
    r'^(?P<indent>\s*)require\s+verso\s+from\s+git\s+"(?P<url>[^"]+)"(?:\s*@\s*"(?P<ref>[^"]+)")?\s*$',
    re.MULTILINE,
)
VERSO_SLIDES_REQUIRE_PATTERN = re.compile(
    r'^(?P<indent>\s*)require\s+«verso-slides»\s+from\s+git\s+"(?P<url>[^"]+)"(?:\s*@\s*"(?P<ref>[^"]+)")?\s*$',
    re.MULTILINE,
)


@dataclass(frozen=True)
class ManagedReleaseDependency:
    package_name: str
    require_name: str
    repository_url: str
    official_url_patterns: tuple[str, ...]
    require_pattern: re.Pattern[str]


VERSO_DEPENDENCY = ManagedReleaseDependency(
    package_name="verso",
    require_name="verso",
    repository_url=VERSO_REPOSITORY_URL,
    official_url_patterns=OFFICIAL_VERSO_URL_PATTERNS,
    require_pattern=VERSO_REQUIRE_PATTERN,
)
VERSO_SLIDES_DEPENDENCY = ManagedReleaseDependency(
    package_name="verso-slides",
    require_name="«verso-slides»",
    repository_url=VERSO_SLIDES_REPOSITORY_URL,
    official_url_patterns=OFFICIAL_VERSO_SLIDES_URL_PATTERNS,
    require_pattern=VERSO_SLIDES_REQUIRE_PATTERN,
)


@dataclass(frozen=True)
class ToolchainBumpResult:
    lean_ref: str
    toolchain_spec: str
    verso_ref: str
    verso_tag_oid: str
    verso_slides_ref: str
    verso_slides_tag_oid: str


def standalone_test_blueprint_dirs(package_root: Path) -> tuple[Path, ...]:
    """Every standalone test Blueprint package; each owns a toolchain and manifest."""
    return tuple(sorted(lakefile.parent for lakefile in (package_root / "tests" / "test_blueprints").glob("*/lakefile.lean")))


def managed_toolchain_project_dirs(package_root: Path) -> tuple[Path, ...]:
    return (
        package_root,
        package_root / "project_template",
        *standalone_test_blueprint_dirs(package_root),
    )


def _matches_any(patterns: tuple[str, ...], value: str) -> bool:
    return any(re.fullmatch(pattern, value) for pattern in patterns)


def _require_managed_git_dependency(
    project_dir: Path,
    dependency: ManagedReleaseDependency,
    *,
    action: str,
) -> tuple[Path, str, re.Match[str]]:
    lakefile = project_dir / "lakefile.lean"
    if not lakefile.exists():
        raise SystemExit(f"[blueprint-harness] missing lakefile: {lakefile}")

    text = lakefile.read_text(encoding="utf-8")
    match = next(
        (
            candidate
            for candidate in dependency.require_pattern.finditer(text)
            if _matches_any(dependency.official_url_patterns, candidate.group("url"))
        ),
        None,
    )
    if match is None:
        raise SystemExit(
            f"[blueprint-harness] expected the managed project to declare `{dependency.package_name}` in "
            f"`lakefile.lean` from the official `{dependency.repository_url}` Git source; cannot {action}."
        )
    return lakefile, text, match


def rewrite_pinned_release_dependency(
    project_dir: Path,
    dependency: ManagedReleaseDependency,
    ref: str,
) -> tuple[Path, str | None]:
    if not ref or any(char.isspace() for char in ref) or any(char in ref for char in {'"', "\n", "\r"}):
        raise SystemExit(
            f"[blueprint-harness] expected a non-empty `{dependency.package_name}` ref without whitespace, "
            "quotes, or newlines"
        )

    lakefile, text, match = _require_managed_git_dependency(
        project_dir,
        dependency,
        action=f"rewrite the pinned `{dependency.package_name}` ref automatically",
    )
    replacement = (
        f'{match.group("indent")}require {dependency.require_name} from git "{dependency.repository_url}"@"{ref}"'
    )
    rewritten = text[: match.start()] + replacement + text[match.end() :]
    lakefile.write_text(rewritten, encoding="utf-8")
    return lakefile, match.group("ref")


def rewrite_pinned_verso_dependency(project_dir: Path, ref: str) -> tuple[Path, str | None]:
    return rewrite_pinned_release_dependency(project_dir, VERSO_DEPENDENCY, ref)


def rewrite_pinned_verso_slides_dependency(project_dir: Path, ref: str) -> tuple[Path, str | None]:
    return rewrite_pinned_release_dependency(project_dir, VERSO_SLIDES_DEPENDENCY, ref)


def resolve_remote_tag_oid(
    package_root: Path,
    dependency: ManagedReleaseDependency,
    ref: str,
) -> str | None:
    result = subprocess.run(
        ["git", "ls-remote", "--exit-code", "--refs", "--tags", dependency.repository_url, f"refs/tags/{ref}"],
        cwd=package_root,
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode == 2:
        return None
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or f"exit code {result.returncode}"
        raise SystemExit(f"[blueprint-harness] failed to query `{dependency.package_name}` tag `{ref}`: {detail}")
    line = result.stdout.strip().splitlines()[0]
    oid = line.split()[0]
    return oid


def resolve_remote_verso_tag_oid(package_root: Path, ref: str) -> str | None:
    return resolve_remote_tag_oid(package_root, VERSO_DEPENDENCY, ref)


def resolve_remote_verso_slides_tag_oid(package_root: Path, ref: str) -> str | None:
    return resolve_remote_tag_oid(package_root, VERSO_SLIDES_DEPENDENCY, ref)


def refresh_managed_manifest(package_root: Path, project_dir: Path) -> None:
    with maybe_in_repo_blueprint_dependency_override(project_dir, package_root, relative=True):
        run(lean_low_priority_command(package_root, "lake", "update"), cwd=project_dir)


def validate_bumped_toolchain(package_root: Path) -> None:
    run(lean_low_priority_command(package_root, "lake", "build"), cwd=package_root)
    run(lean_low_priority_command(package_root, "lake", "test"), cwd=package_root)
    run(lean_low_priority_command(package_root, "lake", "build"), cwd=package_root / "project_template")
    for project_dir in standalone_test_blueprint_dirs(package_root):
        run(lean_low_priority_command(package_root, "lake", "build"), cwd=project_dir)


def bump_toolchain_checkout(
    package_root: Path,
    requested_toolchain: str,
    *,
    verso_ref: str | None = None,
    verso_slides_ref: str | None = None,
    validate: bool = True,
) -> ToolchainBumpResult:
    lean_ref = normalize_lean_release_ref(requested_toolchain)
    selected_verso_ref = normalize_lean_release_ref(verso_ref) if verso_ref is not None else lean_ref
    selected_verso_slides_ref = (
        normalize_lean_release_ref(verso_slides_ref) if verso_slides_ref is not None else lean_ref
    )
    verso_tag_oid = resolve_remote_verso_tag_oid(package_root, selected_verso_ref)
    if verso_tag_oid is None:
        raise SystemExit(
            f"[blueprint-harness] no matching `verso` tag `{selected_verso_ref}` found in `{VERSO_REPOSITORY_URL}`. "
            "Pass `--verso-ref` explicitly if the Lean toolchain and `verso` release names differ."
        )
    verso_slides_tag_oid = resolve_remote_verso_slides_tag_oid(package_root, selected_verso_slides_ref)
    if verso_slides_tag_oid is None:
        raise SystemExit(
            f"[blueprint-harness] no matching `verso-slides` tag `{selected_verso_slides_ref}` found in "
            f"`{VERSO_SLIDES_REPOSITORY_URL}`. Pass `--verso-slides-ref` explicitly if the Lean toolchain and "
            "`verso-slides` release names differ."
        )

    for project_dir in managed_toolchain_project_dirs(package_root):
        rewrite_lean_toolchain(project_dir / "lean-toolchain", lean_ref)

    rewrite_pinned_verso_dependency(package_root, selected_verso_ref)
    rewrite_pinned_verso_slides_dependency(package_root, selected_verso_slides_ref)
    rewrite_pinned_blueprint_dependency(
        package_root / "project_template",
        release_branch_from_lean_ref(lean_ref),
    )

    for project_dir in managed_toolchain_project_dirs(package_root):
        refresh_managed_manifest(package_root, project_dir)

    if validate:
        validate_bumped_toolchain(package_root)

    return ToolchainBumpResult(
        lean_ref=lean_ref,
        toolchain_spec=lean_toolchain_spec(lean_ref),
        verso_ref=selected_verso_ref,
        verso_tag_oid=verso_tag_oid,
        verso_slides_ref=selected_verso_slides_ref,
        verso_slides_tag_oid=verso_slides_tag_oid,
    )
