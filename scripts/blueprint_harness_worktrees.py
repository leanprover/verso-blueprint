from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess

from scripts.blueprint_harness_branches import ROOT_WORKTREE_NAME, preferred_release_ref


ROOT_METADATA_FILENAME = "_root.json"
REGISTRY_FILENAME = "registry.json"
METADATA_DIRNAME = "_meta"


@dataclass(frozen=True)
class GitWorktree:
    name: str
    path: Path
    head: str
    branch: str | None
    root_checkout: bool


@dataclass
class WorktreeMetadata:
    version: int
    name: str
    status: str
    owner: str | None = None
    locked: bool = False
    priority: str | None = None
    summary: str | None = None
    write_scope: list[str] = field(default_factory=list)
    created_at: str | None = None
    updated_at: str | None = None


@dataclass
class WorktreeRecord:
    version: int
    name: str
    path: str
    branch: str | None
    root_checkout: bool
    status: str
    owner: str | None = None
    locked: bool = False
    priority: str | None = None
    summary: str | None = None
    write_scope: list[str] = field(default_factory=list)
    created_at: str | None = None
    updated_at: str | None = None
    dirty: bool | None = None
    tracked_changes: int | None = None
    untracked_changes: int | None = None
    base_ref: str | None = None
    merged_into_main: bool | None = None
    main_ahead: int | None = None
    main_behind: int | None = None
    upstream: str | None = None
    upstream_ahead: int | None = None
    upstream_behind: int | None = None
    last_commit: str | None = None
    last_commit_at: str | None = None
    last_commit_subject: str | None = None


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def worktree_name(repo_root: Path, path: Path) -> str:
    return ROOT_WORKTREE_NAME if path.resolve() == repo_root.resolve() else path.name


def metadata_path(repo_root: Path, name: str) -> Path:
    if name == ROOT_WORKTREE_NAME:
        return repo_root / ".worktrees" / METADATA_DIRNAME / ROOT_METADATA_FILENAME
    return repo_root / ".worktrees" / METADATA_DIRNAME / f"{name}.json"

def registry_path(repo_root: Path) -> Path:
    return repo_root / ".worktrees" / REGISTRY_FILENAME


def default_status(branch: str | None, root_checkout: bool) -> str:
    if root_checkout:
        return "base"
    if branch is None:
        return "active"
    if branch.startswith("wip/"):
        return "wip"
    return "active"


def default_summary(name: str) -> str:
    return name.replace("-", " ")


def normalize_priority(priority: str | None) -> str | None:
    if priority is None:
        return None
    normalized = priority.strip()
    if not normalized:
        return None
    if normalized.lower() in {"p0", "p1", "p2"}:
        return normalized.upper()
    return normalized


def metadata_from_dict(data: dict[str, object]) -> WorktreeMetadata:
    raw_scope = data.get("write_scope") or []
    write_scope = [str(entry) for entry in raw_scope] if isinstance(raw_scope, list) else []
    return WorktreeMetadata(
        version=int(data.get("version", 1)),
        name=str(data["name"]),
        status=str(data.get("status") or "active"),
        owner=str(data["owner"]) if data.get("owner") is not None else None,
        locked=bool(data.get("locked", False)),
        priority=normalize_priority(str(data["priority"])) if data.get("priority") is not None else None,
        summary=str(data["summary"]) if data.get("summary") is not None else None,
        write_scope=write_scope,
        created_at=str(data["created_at"]) if data.get("created_at") is not None else None,
        updated_at=str(data["updated_at"]) if data.get("updated_at") is not None else None,
    )


def metadata_from_record(record: WorktreeRecord) -> WorktreeMetadata:
    return WorktreeMetadata(
        version=record.version,
        name=record.name,
        status=record.status,
        owner=record.owner,
        locked=record.locked,
        priority=normalize_priority(record.priority),
        summary=record.summary,
        write_scope=record.write_scope[:],
        created_at=record.created_at,
        updated_at=record.updated_at,
    )


def parse_git_worktree_porcelain(text: str, repo_root: Path) -> list[GitWorktree]:
    blocks = [block for block in text.strip().split("\n\n") if block.strip()]
    worktrees: list[GitWorktree] = []
    for block in blocks:
        path: Path | None = None
        head: str | None = None
        branch: str | None = None
        for line in block.splitlines():
            if line.startswith("worktree "):
                path = Path(line.removeprefix("worktree ").strip())
            elif line.startswith("HEAD "):
                head = line.removeprefix("HEAD ").strip()
            elif line.startswith("branch "):
                branch_ref = line.removeprefix("branch ").strip()
                branch = branch_ref.removeprefix("refs/heads/")
        if path is None or head is None:
            continue
        worktrees.append(
            GitWorktree(
                name=worktree_name(repo_root, path),
                path=path,
                head=head,
                branch=branch,
                root_checkout=path.resolve() == repo_root.resolve(),
            )
        )
    return worktrees


def git_worktrees(repo_root: Path) -> list[GitWorktree]:
    result = subprocess.run(
        ["git", "worktree", "list", "--porcelain"],
        cwd=repo_root,
        check=True,
        text=True,
        capture_output=True,
    )
    return parse_git_worktree_porcelain(result.stdout, repo_root)


def load_record(path: Path) -> WorktreeMetadata | None:
    if not path.exists():
        return None
    data = json.loads(path.read_text(encoding="utf-8"))
    return metadata_from_dict(data)


def save_record(path: Path, record: WorktreeMetadata) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(asdict(record), indent=2) + "\n", encoding="utf-8")


def prune_stale_metadata(repo_root: Path, active_names: set[str]) -> None:
    meta_dir = repo_root / ".worktrees" / METADATA_DIRNAME
    if not meta_dir.exists():
        return
    for path in meta_dir.glob("*.json"):
        if path.name == ROOT_METADATA_FILENAME:
            keep = ROOT_WORKTREE_NAME in active_names
        else:
            keep = path.stem in active_names
        if not keep:
            path.unlink(missing_ok=True)


def save_registry(repo_root: Path, records: list[WorktreeRecord]) -> Path:
    path = registry_path(repo_root)
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "version": 1,
        "generated_at": utc_now(),
        "worktrees": [asdict(record) for record in records],
    }
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return path


def ref_oid(repo_root: Path, ref: str) -> str | None:
    result = subprocess.run(
        ["git", "rev-parse", "--verify", "--quiet", ref],
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
            ["git", "merge-base", "--is-ancestor", ancestor, descendant],
            cwd=repo_root,
            check=False,
        ).returncode
        == 0
    )


def ref_merged_into_base(repo_root: Path, ref: str, base_ref: str) -> bool:
    if ref_oid(repo_root, ref) is None or ref_oid(repo_root, base_ref) is None:
        return False
    return is_ancestor(repo_root, ref, base_ref)


def rev_list_counts(repo_root: Path, ref: str, base_ref: str) -> tuple[int | None, int | None]:
    if ref_oid(repo_root, ref) is None or ref_oid(repo_root, base_ref) is None:
        return None, None
    result = subprocess.run(
        ["git", "rev-list", "--left-right", "--count", f"{base_ref}...{ref}"],
        cwd=repo_root,
        check=True,
        text=True,
        capture_output=True,
    )
    behind_text, ahead_text = result.stdout.strip().split()
    return int(ahead_text), int(behind_text)


def branch_upstream(repo_root: Path, branch: str) -> str | None:
    result = subprocess.run(
        ["git", "for-each-ref", "--format=%(upstream:short)", f"refs/heads/{branch}"],
        cwd=repo_root,
        check=True,
        text=True,
        capture_output=True,
    )
    upstream = result.stdout.strip()
    return upstream or None


def worktree_status_counts(path: Path) -> tuple[bool, int, int]:
    result = subprocess.run(
        ["git", "status", "--short"],
        cwd=path,
        check=True,
        text=True,
        capture_output=True,
    )
    lines = [line for line in result.stdout.splitlines() if line.strip()]
    tracked_changes = sum(1 for line in lines if not line.startswith("??"))
    untracked_changes = sum(1 for line in lines if line.startswith("??"))
    return bool(lines), tracked_changes, untracked_changes


def worktree_last_commit(path: Path) -> tuple[str | None, str | None, str | None]:
    result = subprocess.run(
        ["git", "log", "-1", "--format=%h%n%cI%n%s"],
        cwd=path,
        check=True,
        text=True,
        capture_output=True,
    )
    parts = result.stdout.splitlines()
    if len(parts) != 3:
        return None, None, None
    return parts[0] or None, parts[1] or None, parts[2] or None


def collect_worktree_facts(repo_root: Path, git_wt: GitWorktree) -> dict[str, object]:
    ref = git_wt.branch or git_wt.head
    dirty, tracked_changes, untracked_changes = worktree_status_counts(git_wt.path)
    base_ref = preferred_release_ref(git_wt.path)
    main_ahead, main_behind = rev_list_counts(repo_root, ref, base_ref)
    upstream = branch_upstream(repo_root, git_wt.branch) if git_wt.branch is not None else None
    upstream_ahead, upstream_behind = (
        rev_list_counts(repo_root, ref, upstream) if upstream is not None else (None, None)
    )
    last_commit, last_commit_at, last_commit_subject = worktree_last_commit(git_wt.path)
    return {
        "dirty": dirty,
        "tracked_changes": tracked_changes,
        "untracked_changes": untracked_changes,
        "base_ref": base_ref,
        "merged_into_main": ref_merged_into_base(repo_root, ref, base_ref),
        "main_ahead": main_ahead,
        "main_behind": main_behind,
        "upstream": upstream,
        "upstream_ahead": upstream_ahead,
        "upstream_behind": upstream_behind,
        "last_commit": last_commit,
        "last_commit_at": last_commit_at,
        "last_commit_subject": last_commit_subject,
    }


def sync_worktree_registry(repo_root: Path) -> tuple[list[WorktreeRecord], Path]:
    now = utc_now()
    records: list[WorktreeRecord] = []
    git_wt_list = git_worktrees(repo_root)
    active_names = {git_wt.name for git_wt in git_wt_list}
    for git_wt in git_wt_list:
        path = metadata_path(repo_root, git_wt.name)
        existing = load_record(path)
        facts = collect_worktree_facts(repo_root, git_wt)
        metadata = WorktreeMetadata(
            version=1,
            name=git_wt.name,
            status=existing.status if existing and existing.status else default_status(git_wt.branch, git_wt.root_checkout),
            owner=existing.owner if existing else None,
            locked=existing.locked if existing else False,
            priority=normalize_priority(existing.priority) if existing else None,
            summary=existing.summary if existing and existing.summary is not None else default_summary(git_wt.name),
            write_scope=existing.write_scope[:] if existing else [],
            created_at=existing.created_at if existing and existing.created_at else now,
            updated_at=existing.updated_at if existing and existing.updated_at else now,
        )
        record = WorktreeRecord(
            version=1,
            name=git_wt.name,
            path=str(git_wt.path),
            branch=git_wt.branch,
            root_checkout=git_wt.root_checkout,
            status=metadata.status,
            owner=metadata.owner,
            locked=metadata.locked,
            priority=metadata.priority,
            summary=metadata.summary,
            write_scope=metadata.write_scope[:],
            created_at=metadata.created_at,
            updated_at=metadata.updated_at,
            dirty=facts["dirty"],
            tracked_changes=facts["tracked_changes"],
            untracked_changes=facts["untracked_changes"],
            base_ref=facts["base_ref"],
            merged_into_main=facts["merged_into_main"],
            main_ahead=facts["main_ahead"],
            main_behind=facts["main_behind"],
            upstream=facts["upstream"],
            upstream_ahead=facts["upstream_ahead"],
            upstream_behind=facts["upstream_behind"],
            last_commit=facts["last_commit"],
            last_commit_at=facts["last_commit_at"],
            last_commit_subject=facts["last_commit_subject"],
        )
        save_record(path, metadata)
        records.append(record)
    prune_stale_metadata(repo_root, active_names)
    records.sort(key=lambda record: (not record.root_checkout, record.name))
    return records, save_registry(repo_root, records)


def resolve_worktree_name(current_name: str | None, requested_name: str | None) -> str:
    if requested_name:
        return requested_name
    return current_name or ROOT_WORKTREE_NAME


def worktree_record_map(repo_root: Path) -> tuple[dict[str, WorktreeRecord], Path]:
    records, registry = sync_worktree_registry(repo_root)
    return {record.name: record for record in records}, registry


def update_worktree_record(
    repo_root: Path,
    name: str,
    *,
    owner: str | None = None,
    locked: bool | None = None,
    priority: str | None = None,
    summary: str | None = None,
    status: str | None = None,
    write_scope: list[str] | None = None,
) -> tuple[WorktreeRecord, Path, Path]:
    record_map, registry = worktree_record_map(repo_root)
    if name not in record_map:
        raise KeyError(name)
    record = record_map[name]
    if owner is not None:
        record.owner = owner
    if locked is not None:
        record.locked = locked
    if priority is not None:
        record.priority = normalize_priority(priority)
    if summary is not None:
        record.summary = summary
    if status is not None:
        record.status = status
    if write_scope is not None:
        record.write_scope = write_scope
    now = utc_now()
    record.updated_at = now
    record_path = metadata_path(repo_root, name)
    save_record(record_path, metadata_from_record(record))
    save_registry(repo_root, sorted(record_map.values(), key=lambda rec: (not rec.root_checkout, rec.name)))
    return record, record_path, registry
