from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
import os
from pathlib import Path
import re
import subprocess
import sys
from typing import Any
from urllib.error import HTTPError
from urllib.request import Request, urlopen

if str(Path(__file__).resolve().parents[1]) not in sys.path:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts.blueprint_harness_branches import load_branch_policy
from scripts.blueprint_harness_backports import backport_exemption_violations


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

    def get_text(self, path: str, *, accept: str) -> str:
        request = Request(
            f"{API_BASE}{path}",
            headers={
                "Accept": accept,
                "Authorization": f"Bearer {self.token}",
                "X-GitHub-Api-Version": API_VERSION,
            },
        )
        try:
            with urlopen(request) as response:
                return response.read().decode("utf-8", errors="replace")
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

    def commit_diff(self, sha: str) -> str:
        return self.get_text(f"/repos/{self.repo_full_name}/commits/{sha}", accept="application/vnd.github.diff")

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

        pr_match = BACKPORT_PR_RE.search(value)
        if pr_match is None:
            raise BackportCheckError(
                f"Backport {branch}: expected `#<pr>`, `pending`, or `exempt: <reason>`, got `{value}`"
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
            + f". Add lines like {example} or `Backport {example_branch}: exempt: <reason>`"
        )

    if allow_pending:
        return entries

    pending = [branch for branch in required_backports if entries[branch].pending]
    if pending:
        raise BackportCheckError(
            "pending backport entries are not allowed once the default-dev PR is ready for review: "
            + ", ".join(pending)
            + ". Replace each `pending` entry with `#<pr>` or `exempt: <reason>`"
        )
    return entries


def parse_cherry_pick_source(message: str) -> str | None:
    match = CHERRY_PICK_SOURCE_RE.search(message)
    if match is None:
        return None
    return match.group(1)


def git_patch_id(diff_text: str) -> str:
    result = subprocess.run(
        ["git", "patch-id", "--stable"],
        input=diff_text,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise BackportCheckError(f"failed to compute patch-id: {result.stderr.strip() or result.stdout.strip()}")
    line = result.stdout.strip()
    if not line:
        raise BackportCheckError("failed to compute patch-id: commit diff was empty")
    return line.split()[0]


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

    patch_id_cache: dict[str, str] = {}

    def commit_patch_id(sha: str) -> str:
        cached = patch_id_cache.get(sha)
        if cached is not None:
            return cached
        patch_id_cache[sha] = git_patch_id(api.commit_diff(sha))
        return patch_id_cache[sha]

    for source_commit, backport_commit in zip(source_commits, backport_commits):
        if commit_patch_id(source_commit.sha) != commit_patch_id(backport_commit.sha):
            raise BackportCheckError(
                f"paired backport PR #{backport_pr_number} commit `{backport_commit.sha}` does not match "
                f"the patch from source commit `{source_commit.sha}`"
            )


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


def should_enforce(pull_request: dict[str, Any], default_dev_branch: str, required_backports: tuple[str, ...]) -> bool:
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
    policy = load_branch_policy(PACKAGE_ROOT)

    if not should_enforce(pull_request, policy.default_dev_branch, policy.required_backport_branches):
        return 0

    draft = bool(pull_request.get("draft"))
    body = str(pull_request.get("body") or "")
    entries = validate_backport_entries(body, policy.required_backport_branches, allow_pending=draft)
    entries_to_verify = [entries[branch] for branch in policy.required_backport_branches if entries[branch].pr_number is not None]
    exemptions_to_verify = [entries[branch] for branch in policy.required_backport_branches if entries[branch].exempt_reason is not None]
    needs_api = bool(exemptions_to_verify or (not draft and entries_to_verify))
    if needs_api:
        repository = event.get("repository")
        if not isinstance(repository, dict) or not isinstance(repository.get("full_name"), str):
            raise BackportCheckError("event payload is missing repository.full_name")
        source_pr_number_raw = pull_request.get("number", event.get("number"))
        try:
            source_pr_number = int(source_pr_number_raw)
        except (TypeError, ValueError) as err:
            raise BackportCheckError("event payload is missing the default-development PR number") from err
        if not token:
            raise BackportCheckError("missing GitHub token; pass --token or set GITHUB_TOKEN")
        api = GitHubApi(repository["full_name"], token)
        verify_backport_exemptions(api, source_pr_number, entries)
    else:
        source_pr_number = 0
        api = None
    if draft:
        print("[backport-check] draft PR; enforcing declared backport plan only")
        for branch in policy.required_backport_branches:
            entry = entries[branch]
            if entry.exempt_reason is not None:
                print(f"[backport-check] {branch}: exempt ({entry.exempt_reason})")
            elif entry.pending:
                note_suffix = f" ({entry.pending_note})" if entry.pending_note else ""
                print(f"[backport-check] {branch}: pending{note_suffix}")
            else:
                print(
                    f"[backport-check] {branch}: paired PR #{entry.pr_number} recorded; "
                    "paired PR structure will be verified after ready for review"
                )
        return 0

    for branch in policy.required_backport_branches:
        entry = entries[branch]
        if entry.exempt_reason is not None:
            print(f"[backport-check] {branch}: exempt ({entry.exempt_reason})")
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
