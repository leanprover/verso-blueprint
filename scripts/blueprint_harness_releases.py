from __future__ import annotations

import re
from pathlib import Path


LEAN_TOOLCHAIN_PREFIX = "leanprover/lean4:"
NUMERIC_LEAN_RELEASE_PATTERN = re.compile(r"^v?\d+\.\d+\.\d+$")
LEAN_RELEASE_CANDIDATE_PATTERN = re.compile(
    r"^v?(?P<major>\d+)\.(?P<minor>\d+)(?:\.(?P<patch>\d+))?-rc(?P<rc>\d+)$"
)


def clean_lean_ref(raw_ref: str) -> str:
    ref = raw_ref.strip()
    if ref.startswith(LEAN_TOOLCHAIN_PREFIX):
        ref = ref[len(LEAN_TOOLCHAIN_PREFIX) :]
    if not ref or any(char.isspace() for char in ref) or any(char in ref for char in {'"', "\n", "\r"}):
        raise SystemExit("[blueprint-harness] expected a Lean release ref without whitespace, quotes, or newlines")
    return ref


def normalize_release_candidate_name(raw_ref: str) -> str:
    ref = clean_lean_ref(raw_ref)
    match = LEAN_RELEASE_CANDIDATE_PATTERN.fullmatch(ref)
    if match is None:
        raise SystemExit("[blueprint-harness] expected an official Lean release candidate name like `4.33-rc1`")

    major = match.group("major")
    minor = match.group("minor")
    patch = match.group("patch")
    rc = match.group("rc")
    if patch is None or patch == "0":
        return f"{major}.{minor}-rc{rc}"
    return f"{major}.{minor}.{patch}-rc{rc}"


def release_candidate_name_or_none(raw_ref: str) -> str | None:
    ref = clean_lean_ref(raw_ref)
    if LEAN_RELEASE_CANDIDATE_PATTERN.fullmatch(ref) is None:
        return None
    return normalize_release_candidate_name(ref)


def release_candidate_ref(raw_ref: str) -> str:
    name = normalize_release_candidate_name(raw_ref)
    match = LEAN_RELEASE_CANDIDATE_PATTERN.fullmatch(name)
    if match is None:
        raise AssertionError(f"normalized release candidate did not parse: {name}")

    patch = match.group("patch") or "0"
    return f"v{match.group('major')}.{match.group('minor')}.{patch}-rc{match.group('rc')}"


def normalize_lean_release_ref(raw_ref: str) -> str:
    ref = clean_lean_ref(raw_ref)
    if LEAN_RELEASE_CANDIDATE_PATTERN.fullmatch(ref) is not None:
        return release_candidate_ref(ref)
    if NUMERIC_LEAN_RELEASE_PATTERN.fullmatch(ref) is not None and not ref.startswith("v"):
        ref = f"v{ref}"
    return ref


def release_branch_from_lean_ref(raw_ref: str) -> str:
    ref = normalize_lean_release_ref(raw_ref)
    match = LEAN_RELEASE_CANDIDATE_PATTERN.fullmatch(ref)
    if match is not None:
        patch = match.group("patch") or "0"
        return f"v{match.group('major')}.{match.group('minor')}.{patch}"
    return ref


def release_branch_version(raw_ref: str) -> tuple[int, int, int]:
    """Return the comparable numeric version of a stable or RC release branch."""
    branch = release_branch_from_lean_ref(raw_ref)
    if NUMERIC_LEAN_RELEASE_PATTERN.fullmatch(branch) is None:
        raise SystemExit(f"[blueprint-harness] expected a numeric Lean release branch, got `{branch}`")
    major, minor, patch = branch.removeprefix("v").split(".")
    return int(major), int(minor), int(patch)


def lean_toolchain_spec(lean_ref: str) -> str:
    return f"{LEAN_TOOLCHAIN_PREFIX}{lean_ref}"


def rewrite_lean_toolchain(path: Path, lean_ref: str) -> None:
    existing = path.read_text(encoding="utf-8")
    suffix = "\n" if existing.endswith("\n") else ""
    path.write_text(f"{lean_toolchain_spec(lean_ref)}{suffix}", encoding="utf-8")
