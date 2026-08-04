from __future__ import annotations

import argparse
import base64
import json
from dataclasses import dataclass
import os
from pathlib import Path
import re
import sys
from typing import Any
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen

if str(Path(__file__).resolve().parents[1]) not in sys.path:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts.blueprint_harness_branches import (
    BranchPolicy,
    dedupe_release_branches,
    load_branch_policy,
    load_branch_policy_text,
)
from scripts.blueprint_harness_backports import (
    RELEASE_LINE_BOOTSTRAP_STATUS,
    RELEASE_LINE_RETIREMENT_STATUS,
    backport_exemption_violations,
)
from scripts.blueprint_harness_releases import release_branch_from_lean_ref, release_branch_version


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
API_BASE = "https://api.github.com"
API_VERSION = "2022-11-28"
BACKPORT_LINE_RE = re.compile(r"(?mi)^Backport\s+([^\s:]+)\s*:\s*(.+)\s*$")
BACKPORT_PR_RE = re.compile(r"(?:#|/pull/)(\d+)\b")
CHERRY_PICK_SOURCE_RE = re.compile(r"(?mi)^\(cherry picked from commit ([0-9a-f]{40})\)\s*$")


@dataclass(frozen=True)
class BackportEntry:
    branch: str
    pr_number: int | None = None
    exempt_reason: str | None = None
    pending: bool = False
    pending_note: str | None = None
    release_line_bootstrap: bool = False
    release_line_retirement: bool = False


@dataclass(frozen=True)
class PullRequestCommit:
    sha: str
    message: str


class BackportCheckError(RuntimeError):
    pass


class GitHubApi:
    def __init__(self, repo_full_name: str, token: str):
        self.repo_full_name = repo_full_name
        self.token = token

    def get_json(self, path: str) -> Any:
        request = Request(
            f"{API_BASE}{path}",
            headers={
                "Accept": "application/vnd.github+json",
                "Authorization": f"Bearer {self.token}",
                "X-GitHub-Api-Version": API_VERSION,
            },
        )
        try:
            with urlopen(request) as response:
                return json.load(response)
        except HTTPError as err:
            detail = err.read().decode("utf-8", errors="replace").strip()
            raise BackportCheckError(f"GitHub API request failed for {path}: {err.code} {detail}") from err

    def pull_request(self, number: int) -> dict[str, Any]:
        data = self.get_json(f"/repos/{self.repo_full_name}/pulls/{number}")
        if not isinstance(data, dict):
            raise BackportCheckError(f"Unexpected pull request payload for #{number}")
        return data

    def pull_request_commits(self, number: int) -> list[PullRequestCommit]:
        commits: list[PullRequestCommit] = []
        page = 1
        while True:
            data = self.get_json(f"/repos/{self.repo_full_name}/pulls/{number}/commits?per_page=100&page={page}")
            if not isinstance(data, list):
                raise BackportCheckError(f"Unexpected commit payload for PR #{number}")
            if not data:
                return commits
            for item in data:
                if not isinstance(item, dict):
                    continue
                sha = str(item.get("sha") or "")
                message = str(item.get("commit", {}).get("message") or "")
                if not sha or not message:
                    raise BackportCheckError(f"Unexpected commit payload shape for PR #{number}")
                commits.append(PullRequestCommit(sha=sha, message=message))
            if len(data) < 100:
                return commits
            page += 1

    def pull_request_files(self, number: int) -> list[str]:
        files: list[str] = []
        page = 1
        while True:
            data = self.get_json(f"/repos/{self.repo_full_name}/pulls/{number}/files?per_page=100&page={page}")
            if not isinstance(data, list):
                raise BackportCheckError(f"Unexpected file payload for PR #{number}")
            if not data:
                return files
            for item in data:
                filename = item.get("filename") if isinstance(item, dict) else None
                if not isinstance(filename, str) or not filename:
                    raise BackportCheckError(f"Unexpected file payload shape for PR #{number}")
                files.append(filename)
            if len(data) < 100:
                return files
            page += 1

    def file_text(self, path: str, ref: str) -> str:
        encoded_path = quote(path, safe="/")
        encoded_ref = quote(ref, safe="")
        data = self.get_json(f"/repos/{self.repo_full_name}/contents/{encoded_path}?ref={encoded_ref}")
        if not isinstance(data, dict) or data.get("encoding") != "base64" or not isinstance(data.get("content"), str):
            raise BackportCheckError(f"Unexpected repository file payload for `{path}` at `{ref}`")
        try:
            return base64.b64decode(data["content"], validate=False).decode("utf-8")
        except (ValueError, UnicodeDecodeError) as err:
            raise BackportCheckError(f"Unable to decode repository file `{path}` at `{ref}`") from err


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Enforce paired backport planning for draft default-dev PRs and paired backport readiness for ready PRs."
    )
    parser.add_argument(
        "--event-path",
        default=os.environ.get("GITHUB_EVENT_PATH"),
        help="Path to the GitHub event JSON. Defaults to GITHUB_EVENT_PATH.",
    )
    parser.add_argument(
        "--token",
        default=os.environ.get("GITHUB_TOKEN"),
        help="GitHub token with read access to pull requests. Defaults to GITHUB_TOKEN.",
    )
    return parser.parse_args()


def load_event(event_path: str | None) -> dict[str, Any]:
    if not event_path:
        raise BackportCheckError("missing event path; pass --event-path or set GITHUB_EVENT_PATH")
    path = Path(event_path)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as err:
        raise BackportCheckError(f"missing event payload: {path}") from err
    except json.JSONDecodeError as err:
        raise BackportCheckError(f"invalid event payload `{path}`: {err}") from err
    if not isinstance(data, dict):
        raise BackportCheckError(f"invalid event payload `{path}`: expected JSON object")
    return data


def parse_backport_entries(body: str) -> dict[str, BackportEntry]:
    entries: dict[str, BackportEntry] = {}
    for branch, raw_value in BACKPORT_LINE_RE.findall(body):
        value = raw_value.strip()
        lower = value.lower()
        if lower.startswith("exempt"):
            reason = value[len("exempt") :].lstrip(" :-()")
            if not reason:
                raise BackportCheckError(f"Backport {branch}: exemption must include a reason")
            entries[branch] = BackportEntry(branch=branch, exempt_reason=reason)
            continue
        if lower.startswith("pending"):
            note = value[len("pending") :].lstrip(" :-()")
            entries[branch] = BackportEntry(branch=branch, pending=True, pending_note=note or None)
            continue
        if lower == RELEASE_LINE_BOOTSTRAP_STATUS:
            entries[branch] = BackportEntry(branch=branch, release_line_bootstrap=True)
            continue
        if lower == RELEASE_LINE_RETIREMENT_STATUS:
            entries[branch] = BackportEntry(branch=branch, release_line_retirement=True)
            continue

        pr_match = BACKPORT_PR_RE.search(value)
        if pr_match is None:
            raise BackportCheckError(
                f"Backport {branch}: expected `#<pr>`, `pending`, `exempt: <reason>`, or "
                f"`{RELEASE_LINE_BOOTSTRAP_STATUS}`/`{RELEASE_LINE_RETIREMENT_STATUS}`, got `{value}`"
            )
        entries[branch] = BackportEntry(branch=branch, pr_number=int(pr_match.group(1)))
    return entries


def validate_backport_entries(
    body: str,
    required_backports: tuple[str, ...],
    *,
    allow_pending: bool,
) -> dict[str, BackportEntry]:
    entries = parse_backport_entries(body)
    missing = [branch for branch in required_backports if branch not in entries]
    if missing:
        example_branch = missing[0]
        if allow_pending:
            example = f"`Backport {example_branch}: pending`"
        else:
            example = f"`Backport {example_branch}: #123`"
        raise BackportCheckError(
            "missing paired backport metadata for "
            + ", ".join(missing)
            + f". Add lines like {example}, `Backport {example_branch}: exempt: <reason>`, or "
            + f"`Backport {example_branch}: {RELEASE_LINE_BOOTSTRAP_STATUS}`/"
            + f"`Backport {example_branch}: {RELEASE_LINE_RETIREMENT_STATUS}`"
        )

    if allow_pending:
        return entries

    pending = [branch for branch in required_backports if entries[branch].pending]
    if pending:
        raise BackportCheckError(
            "pending backport entries are not allowed once the default-dev PR is ready for review: "
            + ", ".join(pending)
            + f". Replace each `pending` entry with `#<pr>`, `exempt: <reason>`, or "
            + f"`{RELEASE_LINE_BOOTSTRAP_STATUS}`/`{RELEASE_LINE_RETIREMENT_STATUS}` "
            + "for a machine-checked release-policy transition"
        )
    return entries


def load_release_transition_head_policy(
    api: GitHubApi,
    pull_request: dict[str, Any],
    base_policy: BranchPolicy,
    *,
    transition_name: str,
) -> BranchPolicy:
    base = pull_request.get("base")
    base_sha = str(base.get("sha") or "") if isinstance(base, dict) else ""
    head = pull_request.get("head")
    head_sha = str(head.get("sha") or "") if isinstance(head, dict) else ""
    if not base_sha:
        raise BackportCheckError(f"{transition_name} validation requires pull_request.base.sha")
    if not head_sha:
        raise BackportCheckError(f"{transition_name} validation requires pull_request.head.sha")

    try:
        head_policy = load_branch_policy_text(
            api.file_text("branch-policy.json", head_sha),
            source_path=Path(f"github-head-{head_sha[:12]}-branch-policy.json"),
        )
        base_toolchain_release = release_branch_from_lean_ref(api.file_text("lean-toolchain", base_sha).strip())
        head_toolchain_release = release_branch_from_lean_ref(api.file_text("lean-toolchain", head_sha).strip())
    except SystemExit as err:
        raise BackportCheckError(str(err)) from err

    if base_toolchain_release != base_policy.default_dev_branch:
        raise BackportCheckError(
            f"{transition_name} base is internally inconsistent: "
            "its Lean toolchain does not match its default branch"
        )
    if head_toolchain_release != head_policy.default_dev_branch:
        raise BackportCheckError(
            f"{transition_name} head is internally inconsistent: "
            "its Lean toolchain does not match its default branch"
        )
    return head_policy


def verify_release_line_bootstrap(
    api: GitHubApi,
    source_pr_number: int,
    pull_request: dict[str, Any],
    base_policy: BranchPolicy,
) -> BranchPolicy:
    head_policy = load_release_transition_head_policy(
        api,
        pull_request,
        base_policy,
        transition_name="release-line bootstrap",
    )
    try:
        base_version = release_branch_version(base_policy.default_dev_branch)
        head_version = release_branch_version(head_policy.default_dev_branch)
    except SystemExit as err:
        raise BackportCheckError(str(err)) from err
    if head_version <= base_version:
        raise BackportCheckError(
            "release-line bootstrap status requires a newer default development release line"
        )

    inherited_backports = dedupe_release_branches(
        (base_policy.default_dev_branch, *base_policy.required_backport_branches)
    )
    retained_count = len(head_policy.required_backport_branches)
    if (
        retained_count == 0
        or retained_count > len(inherited_backports)
        or inherited_backports[:retained_count] != head_policy.required_backport_branches
    ):
        raise BackportCheckError(
            "release-line bootstrap must retain the previous default branch followed by an ordered prefix of "
            "the previous backport sequence; only the oldest contiguous suffix may retire"
        )
    retired_branches = inherited_backports[retained_count:]

    if base_policy.release_targets or head_policy.release_targets:
        retired_set = set(retired_branches)
        retained_targets = tuple(
            target for target in base_policy.release_targets if target.release_id not in retired_set
        )
        new_targets = tuple(
            target
            for target in head_policy.release_targets
            if target.release_id == head_policy.default_dev_branch
        )
        if len(new_targets) != 1 or head_policy.release_targets != (*retained_targets, new_targets[0]):
            raise BackportCheckError(
                "release-line bootstrap must preserve retained release targets, remove only retired targets, "
                "and append exactly one target for the new default line"
            )
        new_target = new_targets[0]
        if (
            release_branch_from_lean_ref(new_target.release_toolchain) != head_policy.default_dev_branch
            or release_branch_from_lean_ref(new_target.release_verso_ref) != head_policy.default_dev_branch
            or new_target.branch != head_policy.default_dev_branch
        ):
            raise BackportCheckError(
                "release-line bootstrap target must use the new default release line for its toolchain, "
                "Verso ref, and branch"
            )

    changed_files = set(api.pull_request_files(source_pr_number))
    missing_files = sorted({"branch-policy.json", "lean-toolchain"} - changed_files)
    if missing_files:
        raise BackportCheckError(
            "release-line bootstrap must change both release identity files; missing " + ", ".join(missing_files)
        )
    return head_policy


def verify_release_line_retirement(
    api: GitHubApi,
    source_pr_number: int,
    pull_request: dict[str, Any],
    base_policy: BranchPolicy,
) -> tuple[BranchPolicy, tuple[str, ...]]:
    head_policy = load_release_transition_head_policy(
        api,
        pull_request,
        base_policy,
        transition_name="release-line retirement",
    )

    if head_policy.default_dev_branch != base_policy.default_dev_branch:
        raise BackportCheckError("release-line retirement must preserve the default development release line")

    retained_count = len(head_policy.required_backport_branches)
    if retained_count >= len(base_policy.required_backport_branches):
        raise BackportCheckError("release-line retirement status requires removing at least one backport branch")
    if base_policy.required_backport_branches[:retained_count] != head_policy.required_backport_branches:
        raise BackportCheckError(
            "release-line retirement may remove only the oldest contiguous suffix of required backport branches"
        )
    retired_branches = base_policy.required_backport_branches[retained_count:]

    retired_set = set(retired_branches)
    expected_targets = tuple(
        target for target in base_policy.release_targets if target.release_id not in retired_set
    )
    if head_policy.release_targets != expected_targets:
        raise BackportCheckError(
            "release-line retirement must remove exactly the retired release targets and preserve every remaining target"
        )

    changed_files = set(api.pull_request_files(source_pr_number))
    if "branch-policy.json" not in changed_files:
        raise BackportCheckError("release-line retirement must change branch-policy.json")
    return head_policy, retired_branches


def parse_cherry_pick_source(message: str) -> str | None:
    match = CHERRY_PICK_SOURCE_RE.search(message)
    if match is None:
        return None
    return match.group(1)


def verify_backport_commit_series(api: GitHubApi, source_pr_number: int, backport_pr_number: int) -> None:
    source_commits = api.pull_request_commits(source_pr_number)
    backport_commits = api.pull_request_commits(backport_pr_number)
    if len(backport_commits) != len(source_commits):
        raise BackportCheckError(
            f"paired backport PR #{backport_pr_number} has {len(backport_commits)} commits, "
            f"expected {len(source_commits)} from PR #{source_pr_number}"
        )

    source_shas = [commit.sha for commit in source_commits]
    mapped_shas: list[str] = []
    for commit in backport_commits:
        source_sha = parse_cherry_pick_source(commit.message)
        if source_sha is None:
            raise BackportCheckError(
                f"paired backport PR #{backport_pr_number} commit `{commit.sha}` is missing "
                "`(cherry picked from commit <sha>)` provenance"
            )
        mapped_shas.append(source_sha)

    unexpected = [sha for sha in mapped_shas if sha not in source_shas]
    if unexpected:
        raise BackportCheckError(
            f"paired backport PR #{backport_pr_number} references source commit(s) not present in PR #{source_pr_number}: "
            + ", ".join(unexpected)
        )

    if len(set(mapped_shas)) != len(mapped_shas):
        raise BackportCheckError(f"paired backport PR #{backport_pr_number} repeats at least one source commit")

    if mapped_shas != source_shas:
        raise BackportCheckError(
            f"paired backport PR #{backport_pr_number} does not preserve the commit order from PR #{source_pr_number}"
        )

    # Release-line conflict resolution routinely changes the exact patch while
    # preserving the reviewed source-series provenance. Keep this guard focused
    # on the one-to-one cherry-pick contract instead of patch identity.


def verify_backport_pr(
    api: GitHubApi,
    source_pr_number: int,
    branch: str,
    entry: BackportEntry,
) -> None:
    if entry.pr_number is None:
        return
    pr = api.pull_request(entry.pr_number)
    base_ref = str(pr.get("base", {}).get("ref") or "")
    if base_ref != branch:
        raise BackportCheckError(
            f"paired backport PR #{entry.pr_number} targets `{base_ref}`, expected `{branch}`"
        )

    if bool(pr.get("draft")):
        raise BackportCheckError(f"paired backport PR #{entry.pr_number} is still draft")

    state = str(pr.get("state") or "")
    if state == "closed" and not bool(pr.get("merged")):
        raise BackportCheckError(f"paired backport PR #{entry.pr_number} is closed without merge")

    verify_backport_commit_series(api, source_pr_number, entry.pr_number)


def verify_backport_exemptions(
    api: GitHubApi,
    source_pr_number: int,
    entries: dict[str, BackportEntry],
) -> None:
    exempt_branches = [entry.branch for entry in entries.values() if entry.exempt_reason is not None]
    if not exempt_branches:
        return
    violations = backport_exemption_violations(api.pull_request_files(source_pr_number))
    if violations:
        raise BackportCheckError(
            "backport exemptions are limited to documentation and repository metadata changes; "
            "paired backports are required for " + ", ".join(violations)
        )


def event_pull_request(event: dict[str, Any]) -> dict[str, Any]:
    pull_request = event.get("pull_request")
    if not isinstance(pull_request, dict):
        raise BackportCheckError("event payload does not contain a pull_request object")
    return pull_request


def should_enforce(
    pull_request: dict[str, Any],
    default_dev_branch: str,
    required_backports: tuple[str, ...],
    *,
    release_line_bootstrap: bool = False,
    release_line_retirement: bool = False,
) -> bool:
    if release_line_bootstrap:
        print("[backport-check] release-line bootstrap plan declared; validating the base-to-head policy transition")
        return True
    if release_line_retirement:
        print("[backport-check] release-line retirement plan declared; validating the base-to-head policy transition")
        return True
    if not required_backports:
        print("[backport-check] no required backport branches configured; skipping")
        return False
    if str(pull_request.get("base", {}).get("ref") or "") != default_dev_branch:
        print(
            "[backport-check] PR targets "
            f"`{pull_request.get('base', {}).get('ref', '')}`, not default dev `{default_dev_branch}`; skipping"
        )
        return False
    return True


def run(event_path: str | None, token: str | None) -> int:
    event = load_event(event_path)
    pull_request = event_pull_request(event)
    base_policy = load_branch_policy(PACKAGE_ROOT)
    body = str(pull_request.get("body") or "")
    release_line_bootstrap = any(
        value.strip().lower() == RELEASE_LINE_BOOTSTRAP_STATUS for _, value in BACKPORT_LINE_RE.findall(body)
    )
    release_line_retirement = any(
        value.strip().lower() == RELEASE_LINE_RETIREMENT_STATUS for _, value in BACKPORT_LINE_RE.findall(body)
    )
    if release_line_bootstrap and release_line_retirement:
        raise BackportCheckError("release-line bootstrap and retirement plans cannot be mixed")

    if not should_enforce(
        pull_request,
        base_policy.default_dev_branch,
        base_policy.required_backport_branches,
        release_line_bootstrap=release_line_bootstrap,
        release_line_retirement=release_line_retirement,
    ):
        return 0

    draft = bool(pull_request.get("draft"))
    repository = event.get("repository")
    source_pr_number_raw = pull_request.get("number", event.get("number"))
    try:
        source_pr_number = int(source_pr_number_raw)
    except (TypeError, ValueError) as err:
        raise BackportCheckError("event payload is missing the default-development PR number") from err

    api = None
    if release_line_bootstrap or release_line_retirement:
        if not isinstance(repository, dict) or not isinstance(repository.get("full_name"), str):
            raise BackportCheckError("event payload is missing repository.full_name")
        if not token:
            raise BackportCheckError("missing GitHub token; pass --token or set GITHUB_TOKEN")
        api = GitHubApi(repository["full_name"], token)
        if release_line_bootstrap:
            policy = verify_release_line_bootstrap(api, source_pr_number, pull_request, base_policy)
            plan_branches = policy.required_backport_branches
        else:
            policy, plan_branches = verify_release_line_retirement(
                api, source_pr_number, pull_request, base_policy
            )
    else:
        policy = base_policy
        plan_branches = policy.required_backport_branches

    entries = validate_backport_entries(body, plan_branches, allow_pending=draft)
    if release_line_bootstrap:
        non_bootstrap = [
            branch for branch in policy.required_backport_branches if not entries[branch].release_line_bootstrap
        ]
        if non_bootstrap:
            raise BackportCheckError(
                "release-line bootstrap status must be used for every required backport branch; mixed plans are invalid"
            )
    if release_line_retirement:
        retirement_branches = {
            branch for branch, entry in entries.items() if entry.release_line_retirement
        }
        if retirement_branches != set(plan_branches):
            raise BackportCheckError(
                "release-line retirement status must name exactly the retired backport branches"
            )
    entries_to_verify = [entries[branch] for branch in plan_branches if entries[branch].pr_number is not None]
    exemptions_to_verify = [entries[branch] for branch in plan_branches if entries[branch].exempt_reason is not None]
    bootstraps_to_verify = [
        entries[branch] for branch in plan_branches if entries[branch].release_line_bootstrap
    ]
    retirements_to_verify = [entries[branch] for branch in plan_branches if entries[branch].release_line_retirement]
    needs_api = bool(
        exemptions_to_verify or bootstraps_to_verify or retirements_to_verify or (not draft and entries_to_verify)
    )
    if needs_api and api is None:
        if not isinstance(repository, dict) or not isinstance(repository.get("full_name"), str):
            raise BackportCheckError("event payload is missing repository.full_name")
        if not token:
            raise BackportCheckError("missing GitHub token; pass --token or set GITHUB_TOKEN")
        api = GitHubApi(repository["full_name"], token)
    if api is not None:
        verify_backport_exemptions(api, source_pr_number, entries)
    if draft:
        print("[backport-check] draft PR; enforcing declared backport plan only")
        for branch in plan_branches:
            entry = entries[branch]
            if entry.exempt_reason is not None:
                print(f"[backport-check] {branch}: exempt ({entry.exempt_reason})")
            elif entry.release_line_bootstrap:
                print(f"[backport-check] {branch}: release-line bootstrap verified")
            elif entry.release_line_retirement:
                print(f"[backport-check] {branch}: release-line retirement verified")
            elif entry.pending:
                note_suffix = f" ({entry.pending_note})" if entry.pending_note else ""
                print(f"[backport-check] {branch}: pending{note_suffix}")
            else:
                print(
                    f"[backport-check] {branch}: paired PR #{entry.pr_number} recorded; "
                    "paired PR structure will be verified after ready for review"
                )
        return 0

    for branch in plan_branches:
        entry = entries[branch]
        if entry.exempt_reason is not None:
            print(f"[backport-check] {branch}: exempt ({entry.exempt_reason})")
            continue
        if entry.release_line_bootstrap:
            print(f"[backport-check] {branch}: release-line bootstrap verified")
            continue
        if entry.release_line_retirement:
            print(f"[backport-check] {branch}: release-line retirement verified")
            continue
        if api is None:
            raise BackportCheckError(f"Backport {branch}: internal error; paired PR verification is unavailable")
        verify_backport_pr(api, source_pr_number, branch, entry)
        print(f"[backport-check] {branch}: paired PR #{entry.pr_number} is ready")
    return 0


def main() -> int:
    args = parse_args()
    try:
        return run(args.event_path, args.token)
    except BackportCheckError as err:
        print(f"[backport-check] FAIL: {err}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
