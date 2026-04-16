from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
import os
from pathlib import Path
import re
import sys
from typing import Any
from urllib.error import HTTPError
from urllib.request import Request, urlopen

if str(Path(__file__).resolve().parents[1]) not in sys.path:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts.blueprint_harness_branches import load_branch_policy


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
API_BASE = "https://api.github.com"
API_VERSION = "2022-11-28"
BACKPORT_LINE_RE = re.compile(r"(?mi)^Backport\s+([^\s:]+)\s*:\s*(.+)\s*$")
BACKPORT_PR_RE = re.compile(r"(?:#|/pull/)(\d+)\b")


@dataclass(frozen=True)
class BackportEntry:
    branch: str
    pr_number: int | None = None
    exempt_reason: str | None = None


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

    def check_runs(self, sha: str) -> dict[str, Any]:
        data = self.get_json(f"/repos/{self.repo_full_name}/commits/{sha}/check-runs")
        if not isinstance(data, dict):
            raise BackportCheckError(f"Unexpected check run payload for {sha}")
        return data

    def combined_status(self, sha: str) -> dict[str, Any]:
        data = self.get_json(f"/repos/{self.repo_full_name}/commits/{sha}/status")
        if not isinstance(data, dict):
            raise BackportCheckError(f"Unexpected combined status payload for {sha}")
        return data


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Enforce paired backport PR metadata for ready non-draft default-dev PRs."
    )
    parser.add_argument(
        "--event-path",
        default=os.environ.get("GITHUB_EVENT_PATH"),
        help="Path to the GitHub event JSON. Defaults to GITHUB_EVENT_PATH.",
    )
    parser.add_argument(
        "--token",
        default=os.environ.get("GITHUB_TOKEN"),
        help="GitHub token with read access to pull requests and checks. Defaults to GITHUB_TOKEN.",
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

        pr_match = BACKPORT_PR_RE.search(value)
        if pr_match is None:
            raise BackportCheckError(
                f"Backport {branch}: expected `#<pr>` or `exempt: <reason>`, got `{value}`"
            )
        entries[branch] = BackportEntry(branch=branch, pr_number=int(pr_match.group(1)))
    return entries


def check_runs_state(check_runs: dict[str, Any], combined_status: dict[str, Any]) -> None:
    failures: list[str] = []
    pending: list[str] = []
    seen_run = False

    for run in check_runs.get("check_runs", []):
        if not isinstance(run, dict):
            continue
        seen_run = True
        name = str(run.get("name") or "<unnamed check>")
        status = str(run.get("status") or "")
        conclusion = run.get("conclusion")
        if status != "completed":
            pending.append(name)
            continue
        if conclusion in {"success", "neutral", "skipped"}:
            continue
        failures.append(f"{name} ({conclusion or 'unknown'})")

    state = str(combined_status.get("state") or "")
    if state in {"failure", "error"}:
        failures.append(f"combined status ({state})")
    elif state == "pending":
        pending.append("combined status")

    if failures:
        raise BackportCheckError("paired backport PR checks are failing: " + ", ".join(failures))
    if pending:
        raise BackportCheckError("paired backport PR checks are still pending: " + ", ".join(pending))
    if not seen_run and state not in {"success", ""}:
        raise BackportCheckError(f"paired backport PR has unexpected combined status `{state}`")
    if not seen_run and state == "":
        raise BackportCheckError("paired backport PR does not report any check runs yet")


def verify_backport_pr(
    api: GitHubApi,
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

    if bool(pr.get("merged")):
        return

    sha = str(pr.get("head", {}).get("sha") or "")
    if not sha:
        raise BackportCheckError(f"paired backport PR #{entry.pr_number} is missing a head SHA")

    check_runs_state(api.check_runs(sha), api.combined_status(sha))


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
    if bool(pull_request.get("draft")):
        print("[backport-check] draft PR; skipping paired backport gate until ready for review")
        return False
    return True


def run(event_path: str | None, token: str | None) -> int:
    event = load_event(event_path)
    pull_request = event_pull_request(event)
    policy = load_branch_policy(PACKAGE_ROOT)

    if not should_enforce(pull_request, policy.default_dev_branch, policy.required_backport_branches):
        return 0

    if not token:
        raise BackportCheckError("missing GitHub token; pass --token or set GITHUB_TOKEN")

    body = str(pull_request.get("body") or "")
    entries = parse_backport_entries(body)
    missing = [branch for branch in policy.required_backport_branches if branch not in entries]
    if missing:
        raise BackportCheckError(
            "missing paired backport metadata for "
            + ", ".join(missing)
            + ". Add lines like `Backport v4.28.0: #123` or `Backport v4.28.0: exempt: <reason>`"
        )

    repository = event.get("repository")
    if not isinstance(repository, dict) or not isinstance(repository.get("full_name"), str):
        raise BackportCheckError("event payload is missing repository.full_name")
    api = GitHubApi(repository["full_name"], token)

    for branch in policy.required_backport_branches:
        entry = entries[branch]
        if entry.exempt_reason is not None:
            print(f"[backport-check] {branch}: exempt ({entry.exempt_reason})")
            continue
        verify_backport_pr(api, branch, entry)
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
