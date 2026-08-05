from __future__ import annotations

from collections.abc import Iterable
import json
from dataclasses import dataclass
import subprocess
from pathlib import Path

from scripts.blueprint_harness_releases import (
    normalize_lean_release_ref,
    release_branch_from_lean_ref,
)


BRANCH_POLICY_FILENAME = "branch-policy.json"
ROOT_WORKTREE_NAME = "root"
CHECKOUT_ROLE_DEFAULT_DEV = "default_dev"
CHECKOUT_ROLE_BACKPORT = "backport"
CHECKOUT_ROLE_CHOICES = (CHECKOUT_ROLE_DEFAULT_DEV, CHECKOUT_ROLE_BACKPORT)


def dedupe_release_branches(branches: Iterable[str]) -> tuple[str, ...]:
    """Normalize release branches while preserving their first-seen order."""
    result: list[str] = []
    seen: set[str] = set()
    for branch in branches:
        normalized = release_branch_from_lean_ref(branch)
        if normalized not in seen:
            result.append(normalized)
            seen.add(normalized)
    return tuple(result)


@dataclass(frozen=True)
class BranchPolicyReleaseTarget:
    release_id: str
    release_toolchain: str
    release_verso_ref: str
    branch: str
    deploy_pages: bool

    @property
    def toolchain(self) -> str:
        return self.release_toolchain

    @property
    def verso_ref(self) -> str:
        return self.release_verso_ref


@dataclass(frozen=True)
class BranchPolicy:
    version: int
    default_dev_branch: str
    required_backport_branches: tuple[str, ...]
    release_targets: tuple[BranchPolicyReleaseTarget, ...]
    source_path: Path


@dataclass(frozen=True)
class RefSyncStatus:
    local_ref: str
    upstream_ref: str
    local_oid: str | None
    upstream_oid: str | None
    relationship: str


def active_release_branch(repo_root: Path) -> str:
    toolchain_path = repo_root / "lean-toolchain"
    if not toolchain_path.exists():
        raise SystemExit(f"[blueprint-harness] missing lean toolchain file: {toolchain_path}")
    return release_branch_from_lean_ref(toolchain_path.read_text(encoding="utf-8"))


def branch_policy_path(checkout_root: Path) -> Path:
    return checkout_root / BRANCH_POLICY_FILENAME


def _format_release_target(target: BranchPolicyReleaseTarget) -> dict[str, object]:
    entry: dict[str, object] = {
        "id": target.release_id,
        "toolchain": target.release_toolchain,
        "verso_ref": target.release_verso_ref,
    }
    entry["branch"] = target.branch
    entry["deploy_pages"] = target.deploy_pages
    return entry


def format_branch_policy(
    *,
    default_dev_branch: str,
    required_backport_branches: tuple[str, ...] | list[str],
    release_targets: tuple[BranchPolicyReleaseTarget, ...] | list[BranchPolicyReleaseTarget] = (),
    version: int = 1,
) -> str:
    data: dict[str, object] = {
        "version": version,
        "default_dev_branch": release_branch_from_lean_ref(default_dev_branch),
        "required_backport_branches": [
            release_branch_from_lean_ref(branch) for branch in required_backport_branches
        ],
    }
    if release_targets:
        data["release_targets"] = [_format_release_target(target) for target in release_targets]
    return json.dumps(data, indent=2) + "\n"


def write_branch_policy(
    checkout_root: Path,
    *,
    default_dev_branch: str,
    required_backport_branches: tuple[str, ...] | list[str],
    release_targets: tuple[BranchPolicyReleaseTarget, ...] | list[BranchPolicyReleaseTarget] = (),
    version: int = 1,
) -> BranchPolicy:
    path = branch_policy_path(checkout_root)
    text = format_branch_policy(
        default_dev_branch=default_dev_branch,
        required_backport_branches=required_backport_branches,
        release_targets=release_targets,
        version=version,
    )
    path.write_text(text, encoding="utf-8")
    return load_branch_policy(checkout_root)


def load_branch_policy(checkout_root: Path) -> BranchPolicy:
    path = branch_policy_path(checkout_root)
    if not path.exists():
        return BranchPolicy(
            version=1,
            default_dev_branch=active_release_branch(checkout_root),
            required_backport_branches=(),
            release_targets=(),
            source_path=path,
        )

    return load_branch_policy_text(path.read_text(encoding="utf-8"), source_path=path)


def load_branch_policy_text(text: str, *, source_path: Path) -> BranchPolicy:
    try:
        data = json.loads(text)
    except json.JSONDecodeError as err:
        raise SystemExit(f"[blueprint-harness] invalid branch policy file `{source_path}`: {err}") from err

    if not isinstance(data, dict):
        raise SystemExit(f"[blueprint-harness] invalid branch policy file `{source_path}`: expected a JSON object")

    raw_default = data.get("default_dev_branch")
    if not isinstance(raw_default, str):
        raise SystemExit(
            f"[blueprint-harness] invalid branch policy file `{source_path}`: missing string `default_dev_branch`"
        )

    raw_backports = data.get("required_backport_branches", [])
    if not isinstance(raw_backports, list) or not all(isinstance(item, str) for item in raw_backports):
        raise SystemExit(
            f"[blueprint-harness] invalid branch policy file `{source_path}`: "
            "`required_backport_branches` must be a list of strings"
        )

    raw_version = data.get("version", 1)
    if not isinstance(raw_version, int):
        raise SystemExit(
            f"[blueprint-harness] invalid branch policy file `{source_path}`: `version` must be an integer"
        )

    release_targets = load_branch_policy_release_targets(data, source_path)
    release_ids = {target.release_id for target in release_targets}
    if release_ids and release_branch_from_lean_ref(raw_default) not in release_ids:
        raise SystemExit(
            f"[blueprint-harness] invalid branch policy file `{source_path}`: "
            f"default development branch `{release_branch_from_lean_ref(raw_default)}` is not a release target"
        )
    for branch in raw_backports:
        normalized = release_branch_from_lean_ref(branch)
        if release_ids and normalized not in release_ids:
            raise SystemExit(
                f"[blueprint-harness] invalid branch policy file `{source_path}`: "
                f"required backport branch `{normalized}` is not a release target"
            )

    return BranchPolicy(
        version=raw_version,
        default_dev_branch=release_branch_from_lean_ref(raw_default),
        required_backport_branches=tuple(release_branch_from_lean_ref(item) for item in raw_backports),
        release_targets=release_targets,
        source_path=source_path,
    )


def _require_policy_string(entry: dict, field: str, *, context: str) -> str:
    value = entry.get(field)
    if not isinstance(value, str) or not value:
        raise SystemExit(f"[blueprint-harness] invalid branch policy file `{context}`: missing string `{field}`")
    return value


def load_branch_policy_release_targets(data: dict, path: Path) -> tuple[BranchPolicyReleaseTarget, ...]:
    entries = data.get("release_targets", [])
    if entries is None:
        entries = []
    if not isinstance(entries, list):
        raise SystemExit(f"[blueprint-harness] invalid branch policy file `{path}`: `release_targets` must be a list")

    targets: list[BranchPolicyReleaseTarget] = []
    seen_ids: set[str] = set()
    for index, entry in enumerate(entries, start=1):
        if not isinstance(entry, dict):
            raise SystemExit(
                f"[blueprint-harness] invalid branch policy file `{path}`: release target #{index} must be an object"
            )
        context = f"{path}: release target #{index}"
        release_id = release_branch_from_lean_ref(_require_policy_string(entry, "id", context=context))
        if release_id in seen_ids:
            raise SystemExit(
                f"[blueprint-harness] invalid branch policy file `{path}`: duplicate release target `{release_id}`"
            )
        seen_ids.add(release_id)

        if "rc" in entry:
            raise SystemExit(
                f"[blueprint-harness] invalid branch policy file `{context}`: "
                "`rc` belongs on project targets, not release targets"
            )

        deploy_pages = entry.get("deploy_pages", False)
        if not isinstance(deploy_pages, bool):
            raise SystemExit(
                f"[blueprint-harness] invalid branch policy file `{context}`: expected boolean `deploy_pages`"
            )

        targets.append(
            BranchPolicyReleaseTarget(
                release_id=release_id,
                release_toolchain=normalize_lean_release_ref(
                    _require_policy_string(entry, "toolchain", context=context)
                ),
                release_verso_ref=normalize_lean_release_ref(
                    _require_policy_string(entry, "verso_ref", context=context)
                ),
                branch=release_branch_from_lean_ref(_require_policy_string(entry, "branch", context=context)),
                deploy_pages=deploy_pages,
            )
        )
    return tuple(targets)


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


def resolve_git_ref(repo_root: Path, ref: str) -> str:
    if ref.startswith("refs/"):
        return ref

    candidates: list[str] = []
    if ref.startswith("origin/"):
        candidates.append(f"refs/remotes/{ref}")
    else:
        candidates.append(f"refs/heads/{ref}")
        candidates.append(f"refs/remotes/{ref}")
    candidates.append(ref)

    seen: set[str] = set()
    for candidate in candidates:
        if candidate in seen:
            continue
        seen.add(candidate)
        if ref_exists(repo_root, candidate):
            return candidate
    return ref


def ref_oid(repo_root: Path, ref: str) -> str | None:
    result = subprocess.run(
        ["git", "rev-parse", "--verify", "--quiet", resolve_git_ref(repo_root, ref)],
        cwd=repo_root,
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        return None
    oid = result.stdout.strip()
    return oid or None


def is_ancestor(repo_root: Path, ancestor: str, descendant: str) -> bool:
    return (
        subprocess.run(
            [
                "git",
                "merge-base",
                "--is-ancestor",
                resolve_git_ref(repo_root, ancestor),
                resolve_git_ref(repo_root, descendant),
            ],
            cwd=repo_root,
            check=False,
        ).returncode
        == 0
    )


def current_branch_name(repo_root: Path) -> str | None:
    branch = subprocess.run(
        ["git", "branch", "--show-current"],
        cwd=repo_root,
        check=True,
        text=True,
        capture_output=True,
    ).stdout.strip()
    return branch or None


def ref_sync_status(repo_root: Path, local_ref: str, upstream_ref: str) -> RefSyncStatus:
    local_oid = ref_oid(repo_root, local_ref)
    upstream_oid = ref_oid(repo_root, upstream_ref)
    local_git_ref = resolve_git_ref(repo_root, local_ref)
    upstream_git_ref = resolve_git_ref(repo_root, upstream_ref)

    if local_oid is None:
        relationship = "missing_local"
    elif upstream_oid is None:
        relationship = "missing_upstream"
    elif local_oid == upstream_oid:
        relationship = "in_sync"
    elif is_ancestor(repo_root, local_git_ref, upstream_git_ref):
        relationship = "behind"
    elif is_ancestor(repo_root, upstream_git_ref, local_git_ref):
        relationship = "ahead"
    else:
        relationship = "diverged"

    return RefSyncStatus(
        local_ref=local_ref,
        upstream_ref=upstream_ref,
        local_oid=local_oid,
        upstream_oid=upstream_oid,
        relationship=relationship,
    )


def release_sync_status(repo_root: Path) -> RefSyncStatus:
    upstream_ref = preferred_release_ref(repo_root)
    return ref_sync_status(repo_root, local_release_ref(repo_root), upstream_ref)


def remote_head_ref(repo_root: Path) -> str | None:
    result = subprocess.run(
        ["git", "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"],
        cwd=repo_root,
        check=False,
        text=True,
        capture_output=True,
    )
    ref = result.stdout.strip()
    return ref or None


def preferred_release_ref(repo_root: Path) -> str:
    branch = active_release_branch(repo_root)
    if ref_exists(repo_root, f"refs/remotes/origin/{branch}"):
        return f"origin/{branch}"
    if ref_exists(repo_root, f"refs/heads/{branch}"):
        return branch
    remote_head = remote_head_ref(repo_root)
    if remote_head is not None and ref_exists(repo_root, f"refs/remotes/{remote_head}"):
        return remote_head
    for candidate in ("origin/main", "main", "origin/master", "master"):
        ref = f"refs/remotes/{candidate}" if candidate.startswith("origin/") else f"refs/heads/{candidate}"
        if ref_exists(repo_root, ref):
            return candidate
    return branch


def local_release_ref(repo_root: Path) -> str:
    branch = active_release_branch(repo_root)
    if ref_exists(repo_root, f"refs/heads/{branch}"):
        return branch
    remote_head = remote_head_ref(repo_root)
    if remote_head is not None and remote_head.startswith("origin/"):
        local_head = remote_head[len("origin/") :]
        if ref_exists(repo_root, f"refs/heads/{local_head}"):
            return local_head
    for candidate in ("main", "master"):
        if ref_exists(repo_root, f"refs/heads/{candidate}"):
            return candidate
    return branch


def root_checkout_namespace(repo_root: Path) -> str:
    return local_release_ref(repo_root)
