from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

from scripts.blueprint_harness_branches import (
    BranchPolicyReleaseTarget,
    CHECKOUT_ROLE_CHOICES,
    RefSyncStatus,
    active_release_branch,
    branch_policy_path,
    checkout_branch_role,
    default_dev_branch,
    checkout_is_backport_only,
    current_branch_name,
    is_ancestor,
    load_branch_policy,
    local_release_ref,
    release_sync_status,
    preferred_release_ref,
    require_checkout_role,
    ref_oid,
    ref_sync_status,
    resolve_git_ref,
    root_checkout_namespace,
    write_branch_policy,
)
from scripts.blueprint_harness_releases import (
    normalize_lean_release_ref,
    release_branch_from_lean_ref,
    release_candidate_name_or_none,
)
from scripts.blueprint_harness_cli import add_optional_worktree_name_argument
from scripts.blueprint_harness_manifest import load_json_object
from scripts.blueprint_harness_paths import (
    canonical_reference_project_site_dir,
    canonical_test_blueprint_site_dir,
    detect_harness_layout,
)
from scripts.blueprint_harness_projects import (
    load_project_catalog as load_project_catalog_manifest,
    resolve_manifest_path,
    resolve_projects_for_release,
    resolve_release_projects,
    resolve_release_target,
)
from scripts.blueprint_harness_references import (
    reference_dependency_cache_keys,
    reference_prune_plan,
    sync_reference_blueprints,
)
from scripts.blueprint_harness_toolchains import bump_toolchain_checkout
from scripts.blueprint_harness_utils import run
from scripts.blueprint_harness_worktrees import (
    GitWorktree,
    git_worktree_map,
    git_worktrees,
    normalize_priority,
    resolve_worktree_name,
    sync_worktree_registry,
    update_worktree_record,
    worktree_is_clean,
    worktree_record_map,
)

PUBLIC_REPOSITORY = "leanprover/verso-blueprint"
PUBLIC_PR_TITLE_TYPES = ("feat", "fix", "doc", "style", "refactor", "test", "chore", "perf")
PUBLIC_PR_TITLE_RE = re.compile(
    r"^(" + "|".join(re.escape(title_type) for title_type in PUBLIC_PR_TITLE_TYPES) + r"): \S.*$"
)
PUBLIC_PR_SCOPED_TITLE_RE = re.compile(
    r"^(" + "|".join(re.escape(title_type) for title_type in PUBLIC_PR_TITLE_TYPES) + r")\([^)]*\):"
)


def sync_root_worktree_lake(layout) -> None:
    if not layout.in_linked_worktree:
        return

    source_lake = layout.repo_root / ".lake"
    source_bin_dir = source_lake / "build" / "bin"
    if not source_bin_dir.exists():
        raise SystemExit(
            "[blueprint-harness] root worktree has no prepared `.lake/build/bin` to sync. "
            "Build from the root checkout first; linked worktrees should not bootstrap the dependency graph locally."
        )

    if shutil.which("rsync") is None:
        raise SystemExit("[blueprint-harness] `rsync` is required for root-worktree sync.")

    destination_lake = layout.package_root / ".lake"
    destination_lake.mkdir(parents=True, exist_ok=True)
    run(
        [
            "rsync",
            "-a",
            "--delete",
            f"{source_lake}/",
            f"{destination_lake}/",
        ],
        cwd=layout.package_root,
    )


def worktree_path(repo_root: Path, worktree_name: str) -> Path:
    return repo_root / ".worktrees" / worktree_name


def normalize_worktree_name(raw_name: str) -> str:
    name = raw_name.strip()
    if not name:
        raise SystemExit("[blueprint-harness] worktree name must not be empty")
    if Path(name).name != name or name in {".", ".."}:
        raise SystemExit(
            "[blueprint-harness] worktree name must be a single path segment; "
            "the helper always creates linked worktrees under `.worktrees/<name>`."
        )
    return name


def default_branch_name(worktree_name: str) -> str:
    return f"feat/{worktree_name}"


def create_worktree_sync_policy(args: argparse.Namespace) -> tuple[bool, bool]:
    return (args.skip_sync or args.lightweight, args.skip_reference_sync or args.lightweight)


def branch_exists(repo_root: Path, branch: str) -> bool:
    return (
        subprocess.run(
            ["git", "rev-parse", "--verify", "--quiet", f"refs/heads/{branch}"],
            cwd=repo_root,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        ).returncode
        == 0
    )


def current_commit_subject(repo_root: Path) -> str:
    subject = subprocess.run(
        ["git", "log", "-1", "--format=%s"],
        cwd=repo_root,
        check=True,
        text=True,
        capture_output=True,
    ).stdout.strip()
    if not subject:
        raise SystemExit("[blueprint-harness] unable to derive a PR title from the current commit subject")
    return subject


def github_pr_title(repo_root: Path, pr_number: int) -> str | None:
    result = subprocess.run(
        ["gh", "pr", "view", str(pr_number), "--repo", PUBLIC_REPOSITORY, "--json", "title"],
        cwd=repo_root,
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        return None
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        return None
    title = payload.get("title") if isinstance(payload, dict) else None
    return title if isinstance(title, str) and title.strip() else None


def resolve_main_pr_title(repo_root: Path, args: argparse.Namespace) -> str:
    if args.main_title is not None:
        return validate_public_pr_title(args.main_title)
    title = github_pr_title(repo_root, args.main_pr)
    if title is None:
        raise SystemExit(
            "[blueprint-harness] unable to read the default-development PR title from GitHub; "
            "pass `--main-title '<type>: <subject>'` explicitly."
        )
    return validate_public_pr_title(title)


def validate_public_pr_title(title: str) -> str:
    normalized = title.strip()
    if normalized != title or not normalized:
        raise SystemExit("[blueprint-harness] public PR title must not be empty or padded with whitespace")
    if PUBLIC_PR_SCOPED_TITLE_RE.match(normalized):
        raise SystemExit(
            "[blueprint-harness] invalid public PR title: follow Lean upstream style "
            "`<type>: <subject>` without type scopes such as `feat(entry): ...`; "
            "put the affected area in the subject instead."
        )
    if not PUBLIC_PR_TITLE_RE.match(normalized):
        allowed = ", ".join(PUBLIC_PR_TITLE_TYPES)
        raise SystemExit(
            "[blueprint-harness] invalid public PR title: expected Lean upstream style "
            f"`<type>: <subject>` with one of: {allowed}."
        )
    return normalized


def source_commit_series(repo_root: Path, source_branch: str) -> list[str]:
    result = subprocess.run(
        ["git", "rev-list", "--reverse", f"{preferred_release_ref(repo_root)}..{source_branch}"],
        cwd=repo_root,
        check=True,
        text=True,
        capture_output=True,
    )
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def resolve_create_worktree_base(layout, requested_base: str | None) -> str:
    release_branch = active_release_branch(layout.repo_root)
    preferred_base = preferred_release_ref(layout.repo_root)
    if requested_base is None:
        default_branch = default_dev_branch(layout.repo_root)
        remote_default_branch = f"origin/{default_branch}"
        if ref_oid(layout.repo_root, remote_default_branch) is not None:
            requested_base = remote_default_branch
        elif ref_oid(layout.repo_root, default_branch) is not None:
            requested_base = default_branch
        else:
            requested_base = remote_default_branch

    if requested_base == release_branch and preferred_base != release_branch:
        status = release_sync_status(layout.repo_root)
        if status.relationship != "in_sync":
            raise SystemExit(
                f"[blueprint-harness] local `{release_branch}` is {status.relationship} relative to `{status.upstream_ref}`; "
                f"refusing to use local `{release_branch}` as the worktree base. Rebase local `{release_branch}` first or pass "
                f"`--base {status.upstream_ref}` explicitly."
            )
    return requested_base


def preferred_worktree_base_ref(path: Path) -> str:
    return preferred_release_ref(path)


def ref_merged_into_worktree_base(repo_root: Path, ref: str, worktree_path: Path) -> bool:
    base_ref = preferred_worktree_base_ref(worktree_path)
    if ref_oid(repo_root, ref) is None or ref_oid(repo_root, base_ref) is None:
        return False
    return is_ancestor(repo_root, ref, base_ref)


def merged_clean_worktree_candidates(repo_root: Path, current_path: Path) -> list[tuple[str, Path, str]]:
    candidates: list[tuple[str, Path, str]] = []
    records, _registry = worktree_record_map(repo_root)
    release_branch = local_release_ref(repo_root)
    for record in records.values():
        path = Path(record.path)
        if record.root_checkout or path.resolve() == current_path.resolve():
            continue
        if record.locked:
            continue
        if record.branch is None or record.branch == release_branch:
            continue
        if not record.merged_into_main or record.dirty:
            continue
        candidates.append((record.name, path, record.branch))
    return candidates


def local_branch_ref(repo_root: Path, branch: str) -> str | None:
    ref = f"refs/heads/{branch}"
    if ref_oid(repo_root, ref) is None:
        return None
    return branch


def origin_branch_exists(repo_root: Path, branch: str) -> bool:
    return (
        subprocess.run(
            ["git", "ls-remote", "--exit-code", "--heads", "origin", branch],
            cwd=repo_root,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        ).returncode
        == 0
    )


def branch_worktrees(repo_root: Path, branch: str) -> list[GitWorktree]:
    return [worktree for worktree in git_worktrees(repo_root) if worktree.branch == branch]


def text_or_blank(value: object | None) -> str:
    return "" if value is None else str(value)


def bool_or_blank(value: bool | None) -> str:
    return "" if value is None else str(value).lower()


def lock_or_blank(locked: bool) -> str:
    return "locked" if locked else ""


def print_worktree_dashboard(records, registry: Path) -> None:
    print(f"worktree_registry={registry}")
    for record in records:
        scope = ",".join(record.write_scope) if record.write_scope else ""
        print(
            f"{record.name}\tlock={lock_or_blank(record.locked)}\tpriority={record.priority or ''}\tstatus={record.status}\t"
            f"owner={record.owner or ''}\tbranch={record.branch or ''}\tdirty={bool_or_blank(record.dirty)}\t"
            f"base_ahead={text_or_blank(record.main_ahead)}\tbase_behind={text_or_blank(record.main_behind)}\t"
            f"scope={scope}\tsummary={record.summary or ''}"
        )


def command_sync_root_lake(_: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    if not layout.in_linked_worktree:
        print("[blueprint-harness] root checkout detected; no worktree sync needed")
        return 0

    sync_root_worktree_lake(layout)
    print("[blueprint-harness] synced `.lake/` from root worktree")
    return 0


def command_bump_toolchain(args: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    require_checkout_role(layout.package_root, required_role="default_dev", operation="bump-toolchain")
    result = bump_toolchain_checkout(
        layout.package_root,
        args.toolchain,
        verso_ref=args.verso_ref,
        validate=not args.skip_validation,
    )
    print(f"package_root={layout.package_root}")
    print(f"toolchain_ref={result.lean_ref}")
    print(f"toolchain_spec={result.toolchain_spec}")
    print(f"verso_ref={result.verso_ref}")
    print(f"verso_tag_oid={result.verso_tag_oid}")
    print(f"validated={str(not args.skip_validation).lower()}")
    return 0


def dedupe_release_branches(branches: list[str] | tuple[str, ...]) -> tuple[str, ...]:
    result: list[str] = []
    seen: set[str] = set()
    for branch in branches:
        normalized = release_branch_from_lean_ref(branch)
        if normalized not in seen:
            result.append(normalized)
            seen.add(normalized)
    return tuple(result)


def write_json(path: Path, data: object) -> None:
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def update_release_line_project_manifest(
    manifest_path: Path,
    *,
    release_id: str,
) -> None:
    try:
        raw = load_json_object(manifest_path)
    except ValueError as err:
        raise SystemExit(f"[blueprint-harness] invalid project manifest: {err}") from err

    projects = raw.get("projects")
    if not isinstance(projects, list):
        raise SystemExit(f"[blueprint-harness] invalid project manifest `{manifest_path}`: expected `projects` list")

    for project in projects:
        if not isinstance(project, dict):
            continue
        source = project.get("source")
        if not isinstance(source, dict) or source.get("kind") != "in_repo_project":
            continue
        targets = project.get("targets")
        if not isinstance(targets, list):
            raise SystemExit(
                f"[blueprint-harness] invalid project manifest `{manifest_path}`: "
                f"in-repo project `{project.get('id', '<unknown>')}` has no `targets` list"
            )
        if not any(
            isinstance(target, dict) and release_branch_from_lean_ref(str(target.get("release", ""))) == release_id
            for target in targets
        ):
            targets.append({"release": release_id})

    write_json(manifest_path, raw)


def upsert_release_target(
    targets: tuple[BranchPolicyReleaseTarget, ...],
    target: BranchPolicyReleaseTarget,
) -> tuple[BranchPolicyReleaseTarget, ...]:
    updated = list(targets)
    for index, candidate in enumerate(updated):
        if candidate.release_id == target.release_id:
            updated[index] = target
            return tuple(updated)
    updated.append(target)
    return tuple(updated)


def command_start_release_line(args: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    release_id = release_branch_from_lean_ref(args.toolchain)
    current_branch = current_branch_name(layout.package_root)
    if current_branch != release_id:
        raise SystemExit(
            f"[blueprint-harness] start-release-line must run from local branch `{release_id}`; "
            f"current branch is `{current_branch or '<detached>'}`"
        )

    old_policy = load_branch_policy(layout.package_root)
    inherited_backports = dedupe_release_branches(
        [old_policy.default_dev_branch, *old_policy.required_backport_branches]
    )
    required_backports = tuple(branch for branch in inherited_backports if branch != release_id)

    result = bump_toolchain_checkout(
        layout.package_root,
        args.toolchain,
        verso_ref=args.verso_ref,
        validate=not args.skip_validation,
    )
    release_toolchain = release_branch_from_lean_ref(result.lean_ref)
    release_verso_ref = release_branch_from_lean_ref(result.verso_ref)
    rc = release_candidate_name_or_none(result.lean_ref)
    if rc is not None and release_verso_ref != release_id:
        raise SystemExit(
            f"[blueprint-harness] release candidate `{result.lean_ref}` expects a matching `verso` release line; "
            f"got `{result.verso_ref}`"
        )

    release_targets = upsert_release_target(
        old_policy.release_targets,
        BranchPolicyReleaseTarget(
            release_id=release_id,
            release_toolchain=release_toolchain,
            release_verso_ref=release_verso_ref,
            branch=release_id,
            deploy_pages=args.deploy_pages,
        ),
    )
    new_policy = write_branch_policy(
        layout.package_root,
        default_dev_branch=release_id,
        required_backport_branches=required_backports,
        release_targets=release_targets,
        version=max(old_policy.version, 2),
    )
    manifest_path = resolve_manifest_path(None, layout.package_root)
    update_release_line_project_manifest(
        manifest_path,
        release_id=release_id,
    )

    print(f"package_root={layout.package_root}")
    print(f"release_branch={release_id}")
    print(f"toolchain_ref={result.lean_ref}")
    print(f"verso_ref={result.verso_ref}")
    print(f"rc={rc or ''}")
    print(f"branch_policy={new_policy.source_path}")
    print(f"default_dev_branch={new_policy.default_dev_branch}")
    print(f"required_backports={','.join(new_policy.required_backport_branches)}")
    print(f"project_manifest={manifest_path}")
    print(f"deploy_pages={str(args.deploy_pages).lower()}")
    print("[blueprint-harness] next: commit this branch-start change, then update older branches with:")
    print(f"python3 -m scripts.blueprint_harness set-default-dev-branch {release_id}")
    return 0


def command_set_default_dev_branch(args: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    old_policy = load_branch_policy(layout.package_root)
    new_policy = write_branch_policy(
        layout.package_root,
        default_dev_branch=args.branch,
        required_backport_branches=old_policy.required_backport_branches,
        release_targets=old_policy.release_targets,
        version=old_policy.version,
    )
    print(f"branch_policy={new_policy.source_path}")
    print(f"default_dev_branch={new_policy.default_dev_branch}")
    print(f"required_backports={','.join(new_policy.required_backport_branches)}")
    print(f"active_release_branch={active_release_branch(layout.package_root)}")
    print(f"checkout_role={checkout_branch_role(layout.package_root)}")
    return 0


def print_branch_policy_status(layout) -> RefSyncStatus:
    release_branch = active_release_branch(layout.package_root)
    status = release_sync_status(layout.package_root)
    print(f"current_branch={current_branch_name(layout.package_root) or ''}")
    print(f"branch_policy={branch_policy_path(layout.package_root)}")
    print(f"default_dev_branch={default_dev_branch(layout.package_root)}")
    print(f"active_release_branch={release_branch}")
    print(f"checkout_role={checkout_branch_role(layout.package_root)}")
    print(f"backport_only={bool_or_blank(checkout_is_backport_only(layout.package_root))}")
    print(f"release_tracking_ref={status.local_ref}")
    print(f"preferred_release_ref={status.upstream_ref}")
    print(f"release_oid={status.local_oid or ''}")
    print(f"{status.upstream_ref}_oid={status.upstream_oid or ''}")
    print(f"relationship={status.relationship}")
    return status


def command_create_worktree(args: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    worktree_name = normalize_worktree_name(args.name)
    destination = worktree_path(layout.repo_root, worktree_name)
    branch = args.branch or default_branch_name(worktree_name)
    base_ref = resolve_create_worktree_base(layout, args.base)
    skip_sync, skip_reference_sync = create_worktree_sync_policy(args)

    if destination.exists():
        raise SystemExit(f"[blueprint-harness] worktree path already exists: {destination}")

    destination.parent.mkdir(parents=True, exist_ok=True)
    if branch_exists(layout.repo_root, branch):
        command = ["git", "worktree", "add", str(destination), branch]
    else:
        command = ["git", "worktree", "add", "-b", branch, str(destination), base_ref]
    run(command, cwd=layout.repo_root)

    new_layout = detect_harness_layout(destination)
    if not skip_sync:
        sync_root_worktree_lake(new_layout)
    if not skip_reference_sync:
        manifest_path = resolve_manifest_path(None, new_layout.package_root)
        try:
            catalog = load_project_catalog_manifest(manifest_path)
            _release_target, projects = resolve_release_projects(catalog, None, new_layout.package_root, None)
        except (FileNotFoundError, ValueError) as err:
            raise SystemExit(f"[blueprint-harness] {err}") from err
        sync_reference_blueprints(new_layout, projects, warm_build=False, prepare_local_checkout=True)
    if any(value is not None for value in (args.owner, args.priority, args.summary, args.status, args.scope)) or args.lock:
        update_worktree_record(
            layout.repo_root,
            worktree_name,
            owner=args.owner,
            locked=True if args.lock else None,
            priority=normalize_priority(args.priority),
            summary=args.summary,
            status=args.status,
            write_scope=args.scope,
        )

    print(f"[blueprint-harness] worktree path: {destination}")
    print(f"[blueprint-harness] branch: {branch}")
    print(f"[blueprint-harness] base ref: {base_ref}")
    print(f"[blueprint-harness] artifact root: {new_layout.artifact_root}")
    return 0


def command_release_status(args: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    release_branch = active_release_branch(layout.package_root)
    status = print_branch_policy_status(layout)
    if args.require_sync and status.relationship != "in_sync":
        print(
            f"[blueprint-harness] local `{release_branch}` is {status.relationship} relative to `{status.upstream_ref}`",
            file=sys.stderr,
        )
        return 1
    return 0


def parse_prepare_backports_exemptions(values: list[str] | None) -> dict[str, str]:
    exemptions: dict[str, str] = {}
    for value in values or []:
        branch, separator, reason = value.partition("=")
        branch = branch.strip()
        reason = reason.strip()
        if not separator or not branch or not reason:
            raise SystemExit(
                "[blueprint-harness] expected `--exempt <branch>=<reason>` with both a branch and a reason"
            )
        exemptions[branch] = reason
    return exemptions


def backport_plan_lines(required_backports: tuple[str, ...], exemptions: dict[str, str]) -> list[str]:
    lines: list[str] = []
    for branch in required_backports:
        if branch in exemptions:
            lines.append(f"Backport {branch}: exempt: {exemptions[branch]}")
        else:
            lines.append(f"Backport {branch}: pending")
    return lines


def print_public_pr_message_scaffold(
    *,
    default_dev: str,
    source_branch: str,
    title: str,
    backport_lines: list[str],
    summary: str | None,
    changes: list[str] | None,
) -> None:
    paired_backports_required = any(": exempt:" not in line for line in backport_lines)
    print(f"repository={PUBLIC_REPOSITORY}")
    print(f"base={default_dev}")
    print(f"head={source_branch}")
    print("draft=true")
    if paired_backports_required:
        print("recommended_merge_method=merge")
    else:
        print("recommended_merge_method=squash")
    print(f"pr_title={title}")
    print()
    print("## Submission")
    print(f"- Push `{source_branch}` to a branch visible to `{PUBLIC_REPOSITORY}`.")
    print(f"- Open a draft PR against `{PUBLIC_REPOSITORY}:{default_dev}` using the title and body below.")
    if paired_backports_required:
        print("- Use a merge commit when landing so paired backports can cherry-pick commits that remain in default-dev history.")
    print("- Keep local worktree and write-scope notes out of the public body unless they materially help review.")
    print()
    print("## PR Submission Guardrails")
    print("- Use the PR title and body below as the public PR metadata; do not hand-roll a replacement from local notes.")
    print("- Follow Lean upstream title style: `<type>: <subject>`, without type scopes such as `feat(entry): ...`.")
    print("- Do not add generator or tool prefixes such as `[codex]` to the public PR title.")
    print("- Do not add routine validation transcripts to the PR body; CI is the default validation record.")
    print()
    print("## PR Title")
    print(title)
    print()
    print("## PR Body")
    print(
        summary
        or "This PR <short summary of the problem solved and useful outcome>."
    )
    if changes:
        print()
        for item in changes:
            print(f"- {item}")
    if backport_lines:
        print()
        for line in backport_lines:
            print(line)


def release_marker(release_ref: str) -> str:
    normalized = normalize_lean_release_ref(release_ref)
    match = re.match(r"^v(\d+)\.(\d+)", normalized)
    if match is not None:
        return f"v{match.group(1)}{match.group(2)}"
    return "v" + re.sub(r"[^A-Za-z0-9]+", "", normalized.removeprefix("v"))


def backport_label_for_release(release_ref: str) -> str:
    normalized = normalize_lean_release_ref(release_ref)
    label_fragment = re.sub(r"[^A-Za-z0-9._-]+", "-", normalized).strip("-").lower()
    return f"backport-{label_fragment or 'release'}"


def slugify_backport_fragment(text: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", text.strip())
    cleaned = re.sub(r"-{2,}", "-", cleaned).strip("-")
    return cleaned or "change"


def default_backport_branch_name(source_branch: str, release_ref: str) -> str:
    marker = release_marker(release_ref)
    if "/" in source_branch:
        prefix, slug = source_branch.split("/", 1)
        return f"{prefix}/backport-{marker}-{slugify_backport_fragment(slug)}"
    return f"backport-{marker}-{slugify_backport_fragment(source_branch)}"


def default_backport_worktree_name(source_branch: str, release_ref: str) -> str:
    branch_name = default_backport_branch_name(source_branch, release_ref)
    return branch_name.split("/", 1)[1] if "/" in branch_name else branch_name


def prepare_backport_targets(layout, args: argparse.Namespace) -> tuple[str, ...]:
    policy = load_branch_policy(layout.package_root)
    if args.all_required:
        if args.release is not None:
            raise SystemExit("[blueprint-harness] pass either one <release> or `--all-required`, not both")
        return policy.required_backport_branches
    if args.release is None:
        raise SystemExit("[blueprint-harness] expected one <release> or `--all-required`")
    return (normalize_lean_release_ref(args.release),)


def print_prepare_backport_pr_scaffold(
    *,
    default_dev: str,
    backport_release: str,
    source_branch: str,
    main_pr: int,
    main_title: str,
    source_commits: list[str],
) -> None:
    paired_branch = default_backport_branch_name(source_branch, backport_release)
    paired_worktree = default_backport_worktree_name(source_branch, backport_release)
    paired_title = f"[backport {backport_release}] {main_title}"
    paired_label = backport_label_for_release(backport_release)

    print("## Local Backport Plan")
    print()
    print(f"repository={PUBLIC_REPOSITORY}")
    print(f"default_dev_branch={default_dev}")
    print(f"backport_release={backport_release}")
    print(f"source_branch={source_branch}")
    print(f"paired_worktree={paired_worktree}")
    print(f"paired_branch={paired_branch}")
    print(f"paired_title={paired_title}")
    print(f"paired_label={paired_label}")
    print(f"source_commits={','.join(source_commits)}")
    print(f"base_ref=origin/{backport_release}")
    print()
    print("### Batch Apply")
    print(
        f"- Create the linked worktree on `origin/{backport_release}` and attach it to `{paired_branch}`."
    )
    if source_commits:
        print(f"- Cherry-pick the default-development series with `git cherry-pick -x {' '.join(source_commits)}`.")
    else:
        print("- No source commits were detected beyond the default-development base.")
    print("- Let the agent resolve any cherry-pick conflicts in the backport worktree.")
    print("- Run validation on the backport branch before opening the paired PR.")
    print()
    print("## PR Submission Guardrails")
    print("- Use the PR title and body below as the public backport PR metadata.")
    print("- Keep the title after the backport prefix in Lean upstream style: `<type>: <subject>`, without type scopes.")
    print(f"- Apply the release label `{paired_label}` to the paired backport PR.")
    print("- Keep review-facing discussion on the default-development PR unless this backport diverges.")
    print("- Do not add routine validation transcripts to the backport PR body; CI is the default validation record.")
    print()
    print("## PR Title")
    print(paired_title)
    print()
    print("## PR Body")
    print("## Summary")
    print(f"Backport #{main_pr} to `{backport_release}`.")
    print()
    print("## Primary Review")
    print(f"- Primary review: #{main_pr}")
    print(f"- Keep review comments on #{main_pr} unless this backport diverges materially.")
    print()
    print("## Scope")
    print(f"- Backport the already-reviewed default-development change onto `{backport_release}`.")
    print("- Keep this PR limited to release-line-specific conflict resolution.")
    print("- Preserve one-to-one commit provenance with `cherry-pick -x`.")
    print()
    print("## Backport Delta")
    print("- No intentional release-specific changes.")
    print("- If conflict resolution requires deviations from the default-development PR, describe them here.")


def command_prepare_backports(args: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    policy = load_branch_policy(layout.package_root)
    exemptions = parse_prepare_backports_exemptions(args.exempt)
    unknown = sorted(branch for branch in exemptions if branch not in policy.required_backport_branches)
    if unknown:
        raise SystemExit(
            "[blueprint-harness] unknown required backport branch(es): "
            + ", ".join(unknown)
            + ". Update `branch-policy.json` or remove the extra `--exempt` entries."
        )

    print(f"default_dev_branch={policy.default_dev_branch}")
    print(f"required_backports={','.join(policy.required_backport_branches)}")
    if not policy.required_backport_branches:
        print("[blueprint-harness] no required backports are configured for this checkout")
        return 0

    print()
    for line in backport_plan_lines(policy.required_backport_branches, exemptions):
        print(line)
    print()
    print("[blueprint-harness] paste these lines into the default-dev PR body while it is draft")
    print("[blueprint-harness] replace each `pending` entry with `#<pr>` or `exempt: <reason>` before ready for review")
    return 0


def command_prepare_pr(args: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    require_checkout_role(layout.package_root, required_role="default_dev", operation="prepare-pr")
    policy = load_branch_policy(layout.package_root)
    exemptions = parse_prepare_backports_exemptions(args.exempt)
    unknown = sorted(branch for branch in exemptions if branch not in policy.required_backport_branches)
    if unknown:
        raise SystemExit(
            "[blueprint-harness] unknown required backport branch(es): "
            + ", ".join(unknown)
            + ". Update `branch-policy.json` or remove the extra `--exempt` entries."
        )

    source_branch = args.source_branch or current_branch_name(layout.package_root)
    if not source_branch:
        raise SystemExit("[blueprint-harness] unable to determine a source branch; pass `--source-branch` explicitly")

    title = validate_public_pr_title(args.title or current_commit_subject(layout.package_root))
    print_public_pr_message_scaffold(
        default_dev=policy.default_dev_branch,
        source_branch=source_branch,
        title=title,
        backport_lines=backport_plan_lines(policy.required_backport_branches, exemptions),
        summary=args.summary,
        changes=args.change,
    )
    return 0


def command_prepare_backport_pr(args: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    require_checkout_role(layout.package_root, required_role="default_dev", operation="prepare-backport-pr")
    targets = prepare_backport_targets(layout, args)
    source_branch = args.source_branch or current_branch_name(layout.package_root)
    if not source_branch:
        raise SystemExit("[blueprint-harness] unable to determine a source branch; pass `--source-branch` explicitly")

    main_title = resolve_main_pr_title(layout.package_root, args)
    source_commits = source_commit_series(layout.package_root, source_branch)
    default_dev = default_dev_branch(layout.package_root)

    for index, backport_release in enumerate(targets):
        if index:
            print("\n---\n")
        print_prepare_backport_pr_scaffold(
            default_dev=default_dev,
            backport_release=backport_release,
            source_branch=source_branch,
            main_pr=args.main_pr,
            main_title=main_title,
            source_commits=source_commits,
        )
    return 0


def command_require_branch_role(args: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    print_branch_policy_status(layout)
    actual_role = checkout_branch_role(layout.package_root)
    if actual_role == args.role:
        return 0

    active_branch = active_release_branch(layout.package_root)
    default_branch = default_dev_branch(layout.package_root)
    if args.role == "default_dev":
        print(
            f"[blueprint-harness] checkout `{active_branch}` is backport-only; "
            f"default development branch is `{default_branch}`",
            file=sys.stderr,
        )
    else:
        print(
            f"[blueprint-harness] checkout `{active_branch}` is the default development branch; "
            "a backport-only branch is required for this operation",
            file=sys.stderr,
        )
    return 1


def cleanup_source_branch(layout, branch: str, *, delete_remote: bool) -> None:
    worktrees = [worktree for worktree in branch_worktrees(layout.repo_root, branch) if not worktree.root_checkout]
    if len(worktrees) > 1:
        names = ", ".join(sorted(worktree.name for worktree in worktrees))
        raise SystemExit(
            f"[blueprint-harness] branch `{branch}` is checked out in multiple linked worktrees: {names}; "
            "clean them up manually."
        )
    if worktrees:
        worktree = worktrees[0]
        if not worktree_is_clean(worktree.path):
            raise SystemExit(
                f"[blueprint-harness] linked worktree `{worktree.name}` for branch `{branch}` has local modifications"
            )
        run(["git", "worktree", "remove", str(worktree.path)], cwd=layout.repo_root)
        print(f"[blueprint-harness] removed worktree `{worktree.name}`")

    if local_branch_ref(layout.repo_root, branch) is not None:
        run(["git", "branch", "-d", branch], cwd=layout.repo_root)
        print(f"[blueprint-harness] deleted local branch `{branch}`")

    if delete_remote and origin_branch_exists(layout.repo_root, branch):
        run(["git", "push", "origin", "--delete", branch], cwd=layout.repo_root)
        print(f"[blueprint-harness] deleted remote branch `{branch}`")


def command_land_release(args: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    release_branch = active_release_branch(layout.package_root)
    if layout.in_linked_worktree:
        raise SystemExit("[blueprint-harness] run `land-release` from the root checkout, not from a linked worktree")
    status = release_sync_status(layout.repo_root)
    tracking_ref = status.local_ref
    if current_branch_name(layout.repo_root) != tracking_ref:
        raise SystemExit(f"[blueprint-harness] root checkout must be on `{tracking_ref}` before landing changes")
    if not worktree_is_clean(layout.package_root):
        raise SystemExit("[blueprint-harness] root checkout has local modifications; commit or stash them first")

    if status.relationship != "in_sync":
        raise SystemExit(
            f"[blueprint-harness] local `{tracking_ref}` is {status.relationship} relative to `{status.upstream_ref}`; "
            f"sync `{tracking_ref}` before landing additional changes"
        )

    source_ref = args.source
    if ref_oid(layout.repo_root, source_ref) is None:
        raise SystemExit(f"[blueprint-harness] unknown source ref `{source_ref}`")
    if source_ref in {tracking_ref, status.upstream_ref}:
        raise SystemExit(f"[blueprint-harness] source ref must not be `{tracking_ref}` itself")
    if not is_ancestor(layout.repo_root, tracking_ref, source_ref):
        raise SystemExit(
            f"[blueprint-harness] source ref `{source_ref}` is not a fast-forward descendant of local `{tracking_ref}`; "
            "rebase or merge it first"
        )

    run(["git", "merge", "--ff-only", source_ref], cwd=layout.repo_root)
    print(f"[blueprint-harness] landed `{source_ref}` onto local `{tracking_ref}`")

    if preferred_release_ref(layout.repo_root) == f"origin/{tracking_ref}" and not args.no_push:
        run(["git", "push", "origin", tracking_ref], cwd=layout.repo_root)
        print(f"[blueprint-harness] pushed `{tracking_ref}` to origin")

    if args.cleanup:
        cleanup_branch = None
        if local_branch_ref(layout.repo_root, source_ref) is not None:
            cleanup_branch = source_ref
        elif source_ref.startswith("origin/"):
            cleanup_branch = source_ref.removeprefix("origin/")

        if cleanup_branch is None:
            print(
                "[blueprint-harness] cleanup skipped: source ref is not a branch name tracked locally or under origin"
            )
        elif cleanup_branch == tracking_ref:
            print(f"[blueprint-harness] cleanup skipped: refusing to clean up `{tracking_ref}`")
        else:
            cleanup_source_branch(layout, cleanup_branch, delete_remote=not args.keep_remote)

    return 0


def command_paths(args: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    manifest_path = resolve_manifest_path(None, layout.package_root)
    catalog = load_project_catalog_manifest(manifest_path)
    release_target = resolve_release_target(catalog, None, layout.package_root)
    if args.all_projects:
        projects = list(catalog.projects)
    else:
        projects = resolve_projects_for_release(catalog, release_target.release_id, None)
    release_branch = active_release_branch(layout.package_root)
    print(f"package_root={layout.package_root}")
    print(f"repo_root={layout.repo_root}")
    print(f"worktree_name={layout.worktree_name or ''}")
    print(f"artifact_root={layout.artifact_root}")
    print(f"project_manifest={manifest_path}")
    print(f"selected_release_target={release_target.release_id}")
    print(f"project_path_scope={'all' if args.all_projects else 'selected_release'}")
    print("local_override_strategy=ephemeral_lakefile_rewrite")
    print(f"active_release_branch={release_branch}")
    print(f"preferred_release_ref={preferred_release_ref(layout.package_root)}")
    print(f"root_lake={layout.repo_root / '.lake'}")
    print(f"reference_output_root={layout.reference_output_root}")
    print(f"test_blueprint_output_root={layout.test_blueprint_output_root}")
    print(f"preview_runtime_showcase_test_site={canonical_test_blueprint_site_dir('preview_runtime_showcase', Path(__file__))}")
    print(f"reference_source_cache_root={layout.reference_source_cache_root}")
    print(f"reference_dependency_cache_root={layout.reference_dependency_cache_root}")
    print(f"reference_checkout_root={layout.reference_project_checkout_root}")
    print(f"reference_edit_root={layout.reference_project_edit_root}")
    for project in projects:
        canonical_site = canonical_reference_project_site_dir(project.project_id, Path(__file__))
        print(f"{project.project_id}_site={canonical_site}")
    return 0


def command_worktree_prune_candidates(_: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    candidates = merged_clean_worktree_candidates(layout.repo_root, layout.package_root)
    if not candidates:
        print("[blueprint-harness] worktree prune candidates: none")
        return 0
    for name, path, branch in candidates:
        print(f"{name}\tbranch={branch}\tpath={path}")
    return 0


def command_worktree_retire(args: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    release_branch = local_release_ref(layout.repo_root)
    name = resolve_worktree_name(layout.worktree_name, args.name)
    records, _registry = worktree_record_map(layout.repo_root)
    if name not in records:
        raise SystemExit(f"[blueprint-harness] unknown worktree `{name}`")
    record = records[name]
    worktrees = git_worktree_map(layout.repo_root)
    if name not in worktrees:
        raise SystemExit(f"[blueprint-harness] unknown worktree `{name}`")
    worktree = worktrees[name]
    path = worktree.path
    branch = worktree.branch
    if record.locked:
        raise SystemExit(f"[blueprint-harness] worktree `{name}` is locked; unlock it before retiring")
    if worktree.root_checkout:
        raise SystemExit("[blueprint-harness] cannot retire the root checkout")
    if path.resolve() == layout.package_root.resolve():
        raise SystemExit("[blueprint-harness] cannot retire the current active worktree from inside itself")
    if branch == release_branch:
        raise SystemExit(f"[blueprint-harness] cannot retire a linked worktree attached to `{release_branch}`")
    merge_subject = branch or worktree.head
    base_ref = preferred_worktree_base_ref(path)
    if not ref_merged_into_worktree_base(layout.repo_root, merge_subject, path):
        if branch is None:
            raise SystemExit(
                f"[blueprint-harness] detached worktree `{name}` is at `{worktree.head}` "
                f"which is not merged into `{base_ref}`"
            )
        raise SystemExit(f"[blueprint-harness] branch `{branch}` is not merged into `{base_ref}`")
    if not worktree_is_clean(path):
        raise SystemExit(f"[blueprint-harness] worktree `{name}` has local modifications")

    print(f"name={name}")
    print(f"path={path}")
    print(f"branch={branch or ''}")
    print(f"head={worktree.head}")
    if args.dry_run:
        return 0

    run(["git", "worktree", "remove", str(path)], cwd=layout.repo_root)
    if branch is not None:
        run(["git", "branch", "-d", branch], cwd=layout.repo_root)

    manifest_path = resolve_manifest_path(None, layout.package_root)
    try:
        projects = load_project_catalog_manifest(manifest_path).projects
    except (FileNotFoundError, ValueError) as err:
        raise SystemExit(f"[blueprint-harness] {err}") from err
    active_names = {
        root_checkout_namespace(layout.repo_root) if worktree.root_checkout else worktree.name
        for worktree in git_worktrees(layout.repo_root)
    }
    cache_keys = reference_dependency_cache_keys(projects)
    removals = reference_prune_plan(
        active_names,
        cache_keys,
        layout.reference_source_cache_root,
        layout.reference_project_root / "by-worktree",
        layout.reference_dependency_cache_root,
    )
    for stale_path in removals:
        shutil.rmtree(stale_path)
    print(f"[blueprint-harness] retired worktree `{name}`")
    if removals:
        print(f"[blueprint-harness] removed {len(removals)} stale reference path(s)")
    return 0


def command_worktree_list(_: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    records, registry = sync_worktree_registry(layout.repo_root)
    print_worktree_dashboard(records, registry)
    return 0


def command_worktree_status(args: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    name = resolve_worktree_name(layout.worktree_name, args.name)
    records, registry = worktree_record_map(layout.repo_root)
    if name not in records:
        raise SystemExit(f"[blueprint-harness] unknown worktree `{name}`")
    record = records[name]
    print(f"worktree_registry={registry}")
    print(f"name={record.name}")
    print(f"path={record.path}")
    print(f"branch={record.branch or ''}")
    print(f"status={record.status}")
    print(f"owner={record.owner or ''}")
    print(f"locked={bool_or_blank(record.locked)}")
    print(f"priority={record.priority or ''}")
    print(f"summary={record.summary or ''}")
    print(f"write_scope={','.join(record.write_scope)}")
    print(f"created_at={record.created_at or ''}")
    print(f"updated_at={record.updated_at or ''}")
    print(f"dirty={bool_or_blank(record.dirty)}")
    print(f"tracked_changes={text_or_blank(record.tracked_changes)}")
    print(f"untracked_changes={text_or_blank(record.untracked_changes)}")
    print(f"base_ref={record.base_ref or ''}")
    print(f"merged_into_base={bool_or_blank(record.merged_into_main)}")
    print(f"base_ahead={text_or_blank(record.main_ahead)}")
    print(f"base_behind={text_or_blank(record.main_behind)}")
    print(f"upstream={record.upstream or ''}")
    print(f"upstream_ahead={text_or_blank(record.upstream_ahead)}")
    print(f"upstream_behind={text_or_blank(record.upstream_behind)}")
    print(f"last_commit={record.last_commit or ''}")
    print(f"last_commit_at={record.last_commit_at or ''}")
    print(f"last_commit_subject={record.last_commit_subject or ''}")
    return 0


def command_worktree_claim(args: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    name = resolve_worktree_name(layout.worktree_name, args.name)
    record, record_path, registry = update_worktree_record(
        layout.repo_root,
        name,
        owner=args.owner,
        locked=True if args.lock else (False if args.unlock else None),
        priority=normalize_priority(args.priority),
        summary=args.summary,
        status=args.status,
        write_scope=args.scope,
    )
    print(f"worktree_registry={registry}")
    print(f"worktree_record={record_path}")
    print(f"name={record.name}")
    print(f"status={record.status}")
    print(f"owner={record.owner or ''}")
    print(f"locked={bool_or_blank(record.locked)}")
    print(f"priority={record.priority or ''}")
    print(f"summary={record.summary or ''}")
    print(f"write_scope={','.join(record.write_scope)}")
    return 0


def command_worktree_release(args: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    name = resolve_worktree_name(layout.worktree_name, args.name)
    record, record_path, registry = update_worktree_record(
        layout.repo_root,
        name,
        status=args.status,
        locked=False,
        summary=args.summary,
        write_scope=[],
    )
    print(f"worktree_registry={registry}")
    print(f"worktree_record={record_path}")
    print(f"name={record.name}")
    print(f"status={record.status}")
    return 0


def add_release_management_commands(subparsers) -> None:
    sync_root_lake = subparsers.add_parser(
        "sync-root-lake",
        help="Sync `.lake/` from the root checkout into the current linked worktree.",
    )
    sync_root_lake.set_defaults(func=command_sync_root_lake)

    bump_toolchain = subparsers.add_parser(
        "bump-toolchain",
        help="Bump the managed Lean toolchain pins, select the matching `verso` release, and refresh tracked manifests.",
    )
    bump_toolchain.add_argument(
        "toolchain",
        help="Lean toolchain ref such as `v4.29.0`, `4.29.0`, `4.30-rc2`, or `leanprover/lean4:v4.30.0-rc2`.",
    )
    bump_toolchain.add_argument(
        "--verso-ref",
        default=None,
        help="Override the `verso` release tag. Defaults to the normalized Lean toolchain ref.",
    )
    bump_toolchain.add_argument(
        "--skip-validation",
        action="store_true",
        help="Refresh the pins and manifests but skip the follow-up build/test validation.",
    )
    bump_toolchain.set_defaults(func=command_bump_toolchain)

    start_release_line = subparsers.add_parser(
        "start-release-line",
        help="Prepare the current branch as a new default-development Lean release line.",
    )
    start_release_line.add_argument(
        "toolchain",
        help="Lean toolchain ref for the new line, such as `v4.30.0` or official RC name `4.30-rc2`.",
    )
    start_release_line.add_argument(
        "--verso-ref",
        default=None,
        help="Override the `verso` release tag. Defaults to the normalized Lean toolchain ref.",
    )
    start_release_line.add_argument(
        "--deploy-pages",
        action="store_true",
        help="Enable Pages deployment for the new release target immediately. RC lines usually leave this unset.",
    )
    start_release_line.add_argument(
        "--skip-validation",
        action="store_true",
        help="Refresh release-line files but skip the follow-up build/test validation.",
    )
    start_release_line.set_defaults(func=command_start_release_line)

    set_default_dev_branch = subparsers.add_parser(
        "set-default-dev-branch",
        help="Update only `branch-policy.json.default_dev_branch` in the current checkout.",
    )
    set_default_dev_branch.add_argument(
        "branch",
        help="New default development branch, such as `v4.30.0`.",
    )
    set_default_dev_branch.set_defaults(func=command_set_default_dev_branch)

    release_status = subparsers.add_parser(
        "release-status",
        help="Show whether the active local release branch is in sync with its preferred upstream ref.",
    )
    release_status.add_argument(
        "--require-sync",
        action="store_true",
        help="Exit nonzero when the active local release branch is not in sync with its preferred upstream ref.",
    )
    release_status.set_defaults(func=command_release_status)


def add_pr_preparation_commands(subparsers) -> None:
    prepare_backports = subparsers.add_parser(
        "prepare-backports",
        help="Print PR-body lines for the required backport plan on the current default-dev release line.",
    )
    prepare_backports.add_argument(
        "--exempt",
        action="append",
        default=None,
        help="Pre-fill one required branch as `exempt: <reason>` using `--exempt <branch>=<reason>`. Repeat as needed.",
    )
    prepare_backports.set_defaults(func=command_prepare_backports)

    prepare_pr = subparsers.add_parser(
        "prepare-pr",
        help="Print a public draft PR title and body scaffold for the current default-dev branch.",
    )
    prepare_pr.add_argument(
        "--title",
        default=None,
        help="Override the PR title. Defaults to the current commit subject.",
    )
    prepare_pr.add_argument(
        "--summary",
        default=None,
        help="Pre-fill the opening PR body paragraph. It should usually start with `This PR`.",
    )
    prepare_pr.add_argument(
        "--change",
        action="append",
        default=None,
        help="Add one Changes bullet. Repeat as needed.",
    )
    prepare_pr.add_argument(
        "--source-branch",
        default=None,
        help="Override the PR head branch. Defaults to the current branch.",
    )
    prepare_pr.add_argument(
        "--exempt",
        action="append",
        default=None,
        help="Pre-fill one required backport branch as `exempt: <reason>`. Repeat as needed.",
    )
    prepare_pr.set_defaults(func=command_prepare_pr)

    prepare_backport_pr = subparsers.add_parser(
        "prepare-backport-pr",
        help="Print a standardized paired backport branch name, PR title, and PR body scaffold.",
    )
    prepare_backport_pr.add_argument(
        "release",
        nargs="?",
        help="Backport release branch such as `v4.28.0`. Omit with `--all-required`.",
    )
    prepare_backport_pr.add_argument(
        "--all-required",
        action="store_true",
        help="Print one scaffold block for every required backport release in `branch-policy.json`.",
    )
    prepare_backport_pr.add_argument(
        "--main-pr",
        type=int,
        required=True,
        help="Default-development PR number that remains the primary review surface.",
    )
    prepare_backport_pr.add_argument(
        "--main-title",
        default=None,
        help="Override the default-development PR title. Defaults to the title of `--main-pr` from GitHub.",
    )
    prepare_backport_pr.add_argument(
        "--source-branch",
        default=None,
        help="Override the default-development branch name. Defaults to the current branch.",
    )
    prepare_backport_pr.set_defaults(func=command_prepare_backport_pr)


def add_landing_commands(subparsers) -> None:
    require_role = subparsers.add_parser(
        "require-branch-role",
        help="Exit nonzero unless the current checkout matches the requested branch-policy role.",
    )
    require_role.add_argument(
        "role",
        choices=CHECKOUT_ROLE_CHOICES,
        help="Required checkout role: `default_dev` for the main development line, or `backport` for maintenance-only release lines.",
    )
    require_role.set_defaults(func=command_require_branch_role)

    land_release = subparsers.add_parser(
        "land-release",
        help="Fast-forward land one reviewed source ref onto the active root release branch, optionally push, and clean up the source branch.",
    )
    land_release.add_argument(
        "source",
        help="Source ref to land onto the active release branch. This must be a fast-forward descendant of that local release branch.",
    )
    land_release.add_argument(
        "--no-push",
        action="store_true",
        help="Update the local release branch but do not push the matching `origin/<release>` branch afterward.",
    )
    land_release.add_argument(
        "--cleanup",
        action="store_true",
        help="After landing, remove the source worktree and delete the source branch when it can be identified safely.",
    )
    land_release.add_argument(
        "--keep-remote",
        action="store_true",
        help="With `--cleanup`, keep the remote source branch instead of deleting it.",
    )
    land_release.set_defaults(func=command_land_release)


def add_worktree_commands(subparsers) -> None:
    add_create_worktree_command(subparsers)
    add_worktree_lifecycle_commands(subparsers)


def add_create_worktree_command(subparsers) -> None:
    create_worktree = subparsers.add_parser(
        "create-worktree",
        help=(
            "Create a linked worktree under `.worktrees/<name>`, then by default "
            "sync the root `.lake/` and prepare the reference blueprint clones."
        ),
    )
    create_worktree.add_argument("name", help="Worktree directory name under `.worktrees/`.")
    create_worktree.add_argument(
        "--branch",
        default=None,
        help="Branch to attach to the new worktree. Defaults to `feat/<name>`.",
    )
    create_worktree.add_argument(
        "--base",
        default=None,
        help="Base ref used when creating a new branch. Defaults to the preferred active release ref.",
    )
    create_worktree.add_argument(
        "--skip-sync",
        action="store_true",
        help="Do not sync `.lake/` from the root checkout after creating the worktree.",
    )
    create_worktree.add_argument(
        "--skip-reference-sync",
        action="store_true",
        help="Do not prepare the shared and per-worktree reference blueprint clones after creating the worktree.",
    )
    create_worktree.add_argument(
        "--lightweight",
        action="store_true",
        help="Create only the git worktree and skip both `.lake/` sync and reference-checkout preparation.",
    )
    create_worktree.add_argument("--owner", default=None, help="Owner or agent responsible for the worktree.")
    create_worktree.add_argument("--lock", action="store_true", help="Mark the worktree as locked for active exclusive work.")
    create_worktree.add_argument("--priority", default=None, help="Optional local priority label such as P0, P1, or P2.")
    create_worktree.add_argument("--summary", default=None, help="Short summary of the worktree purpose.")
    create_worktree.add_argument("--status", default=None, help="Initial status label such as active, blocked, review, done, or wip.")
    create_worktree.add_argument("--scope", action="append", default=None, help="Writable scope path. Repeat for multiple scopes.")
    create_worktree.set_defaults(func=command_create_worktree)


def add_worktree_lifecycle_commands(subparsers) -> None:
    worktree_prune_candidates = subparsers.add_parser(
        "worktree-prune-candidates",
        help="List merged clean linked worktrees that are good prune candidates.",
    )
    worktree_prune_candidates.set_defaults(func=command_worktree_prune_candidates)

    worktree_retire = subparsers.add_parser(
        "worktree-retire",
        help="Retire one merged clean linked worktree and prune its stale reference clones.",
    )
    add_optional_worktree_name_argument(worktree_retire)
    worktree_retire.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the target worktree without deleting it.",
    )
    worktree_retire.set_defaults(func=command_worktree_retire)

    worktree_list = subparsers.add_parser(
        "worktree-list",
        help="Refresh and print the local worktree dashboard.",
    )
    worktree_list.set_defaults(func=command_worktree_list)

    worktree_status = subparsers.add_parser(
        "worktree-status",
        help="Show local coordination metadata for one worktree.",
    )
    add_optional_worktree_name_argument(worktree_status)
    worktree_status.set_defaults(func=command_worktree_status)

    worktree_claim = subparsers.add_parser(
        "worktree-claim",
        help="Set or update local coordination metadata for one worktree.",
    )
    add_optional_worktree_name_argument(worktree_claim)
    worktree_claim.add_argument("--owner", default=None, help="Owner or agent responsible for the worktree.")
    lock_group = worktree_claim.add_mutually_exclusive_group()
    lock_group.add_argument("--lock", action="store_true", help="Mark the worktree as locked for active exclusive work.")
    lock_group.add_argument("--unlock", action="store_true", help="Clear the worktree lock.")
    worktree_claim.add_argument("--priority", default=None, help="Optional local priority label such as P0, P1, or P2.")
    worktree_claim.add_argument("--summary", default=None, help="Short summary of the worktree purpose.")
    worktree_claim.add_argument("--status", default=None, help="Status label such as active, blocked, review, done, or wip.")
    worktree_claim.add_argument("--scope", action="append", default=None, help="Writable scope path. Repeat for multiple scopes.")
    worktree_claim.set_defaults(func=command_worktree_claim)

    worktree_release = subparsers.add_parser(
        "worktree-release",
        help="Mark a worktree as done or otherwise retired in local coordination metadata.",
    )
    add_optional_worktree_name_argument(worktree_release)
    worktree_release.add_argument("--status", default="done", help="Final status label.")
    worktree_release.add_argument("--summary", default=None, help="Optional final summary.")
    worktree_release.set_defaults(func=command_worktree_release)


def add_path_commands(subparsers) -> None:
    paths = subparsers.add_parser(
        "paths",
        help="Print canonical and resolved worktree-aware harness paths.",
    )
    paths.add_argument(
        "--all-projects",
        action="store_true",
        help="Print site paths for every manifest project instead of only the current release selection.",
    )
    paths.set_defaults(func=command_paths)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python3 -m scripts.blueprint_harness",
        description="Worktree, landing, and local coordination CLI for this repository.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    add_release_management_commands(subparsers)
    add_pr_preparation_commands(subparsers)
    add_landing_commands(subparsers)
    add_worktree_commands(subparsers)
    add_path_commands(subparsers)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
