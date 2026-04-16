from __future__ import annotations

import json
from dataclasses import dataclass
import re
import subprocess
from pathlib import Path


BRANCH_POLICY_FILENAME = "branch-policy.json"
LEAN_TOOLCHAIN_PREFIX = "leanprover/lean4:"
ROOT_WORKTREE_NAME = "root"
CHECKOUT_ROLE_DEFAULT_DEV = "default_dev"
CHECKOUT_ROLE_BACKPORT = "backport"
CHECKOUT_ROLE_CHOICES = (CHECKOUT_ROLE_DEFAULT_DEV, CHECKOUT_ROLE_BACKPORT)
NUMERIC_LEAN_RELEASE_PATTERN = re.compile(r"^v?\d+\.\d+\.\d+(?:[-.A-Za-z0-9]+)?$")


@dataclass(frozen=True)
class BranchPolicy:
    version: int
    default_dev_branch: str
    required_backport_branches: tuple[str, ...]
    source_path: Path


def normalize_lean_release_ref(raw_ref: str) -> str:
    ref = raw_ref.strip()
    if ref.startswith(LEAN_TOOLCHAIN_PREFIX):
        ref = ref[len(LEAN_TOOLCHAIN_PREFIX) :]
    if not ref or any(char.isspace() for char in ref) or any(char in ref for char in {'"', "\n", "\r"}):
        raise SystemExit("[blueprint-harness] expected a Lean release ref without whitespace, quotes, or newlines")
    if NUMERIC_LEAN_RELEASE_PATTERN.fullmatch(ref) is not None and not ref.startswith("v"):
        ref = f"v{ref}"
    return ref


def active_release_branch(repo_root: Path) -> str:
    toolchain_path = repo_root / "lean-toolchain"
    if not toolchain_path.exists():
        raise SystemExit(f"[blueprint-harness] missing lean toolchain file: {toolchain_path}")
    return normalize_lean_release_ref(toolchain_path.read_text(encoding="utf-8"))


def branch_policy_path(checkout_root: Path) -> Path:
    return checkout_root / BRANCH_POLICY_FILENAME


def load_branch_policy(checkout_root: Path) -> BranchPolicy:
    path = branch_policy_path(checkout_root)
    if not path.exists():
        return BranchPolicy(
            version=1,
            default_dev_branch=active_release_branch(checkout_root),
            required_backport_branches=(),
            source_path=path,
        )

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as err:
        raise SystemExit(f"[blueprint-harness] invalid branch policy file `{path}`: {err}") from err

    if not isinstance(data, dict):
        raise SystemExit(f"[blueprint-harness] invalid branch policy file `{path}`: expected a JSON object")

    raw_default = data.get("default_dev_branch")
    if not isinstance(raw_default, str):
        raise SystemExit(f"[blueprint-harness] invalid branch policy file `{path}`: missing string `default_dev_branch`")

    raw_backports = data.get("required_backport_branches", [])
    if not isinstance(raw_backports, list) or not all(isinstance(item, str) for item in raw_backports):
        raise SystemExit(
            f"[blueprint-harness] invalid branch policy file `{path}`: "
            "`required_backport_branches` must be a list of strings"
        )

    raw_version = data.get("version", 1)
    if not isinstance(raw_version, int):
        raise SystemExit(f"[blueprint-harness] invalid branch policy file `{path}`: `version` must be an integer")

    return BranchPolicy(
        version=raw_version,
        default_dev_branch=normalize_lean_release_ref(raw_default),
        required_backport_branches=tuple(normalize_lean_release_ref(item) for item in raw_backports),
        source_path=path,
    )


def default_dev_branch(checkout_root: Path) -> str:
    return load_branch_policy(checkout_root).default_dev_branch


def checkout_branch_role(checkout_root: Path) -> str:
    return (
        CHECKOUT_ROLE_DEFAULT_DEV
        if active_release_branch(checkout_root) == default_dev_branch(checkout_root)
        else CHECKOUT_ROLE_BACKPORT
    )


def checkout_is_backport_only(checkout_root: Path) -> bool:
    return checkout_branch_role(checkout_root) == CHECKOUT_ROLE_BACKPORT


def require_checkout_role(checkout_root: Path, *, required_role: str, operation: str) -> None:
    if required_role not in CHECKOUT_ROLE_CHOICES:
        known = ", ".join(CHECKOUT_ROLE_CHOICES)
        raise SystemExit(f"[blueprint-harness] unknown checkout role `{required_role}`; known roles: {known}")

    actual_role = checkout_branch_role(checkout_root)
    if actual_role == required_role:
        return

    active_branch = active_release_branch(checkout_root)
    default_branch = default_dev_branch(checkout_root)
    if required_role == CHECKOUT_ROLE_DEFAULT_DEV:
        raise SystemExit(
            f"[blueprint-harness] refusing to run `{operation}` from backport-only checkout `{active_branch}`; "
            f"the default development branch is `{default_branch}`"
        )

    raise SystemExit(
        f"[blueprint-harness] refusing to run `{operation}` from default-development checkout `{active_branch}`; "
        f"backport-only work must target a non-default release branch (default: `{default_branch}`)"
    )


def ref_exists(repo_root: Path, ref: str) -> bool:
    return (
        subprocess.run(
            ["git", "rev-parse", "--verify", "--quiet", ref],
            cwd=repo_root,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        ).returncode
        == 0
    )


def preferred_release_ref(repo_root: Path) -> str:
    branch = active_release_branch(repo_root)
    if ref_exists(repo_root, f"refs/remotes/origin/{branch}"):
        return f"origin/{branch}"
    if ref_exists(repo_root, f"refs/heads/{branch}"):
        return branch
    for candidate in ("origin/main", "main", "origin/master", "master"):
        ref = f"refs/remotes/{candidate}" if candidate.startswith("origin/") else f"refs/heads/{candidate}"
        if ref_exists(repo_root, ref):
            return candidate
    return branch


def local_release_ref(repo_root: Path) -> str:
    branch = active_release_branch(repo_root)
    if ref_exists(repo_root, f"refs/heads/{branch}"):
        return branch
    for candidate in ("main", "master"):
        if ref_exists(repo_root, f"refs/heads/{candidate}"):
            return candidate
    return branch


def root_checkout_namespace(repo_root: Path) -> str:
    return local_release_ref(repo_root)
