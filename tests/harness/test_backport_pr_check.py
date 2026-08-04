from __future__ import annotations

import json
import tempfile
import unittest
from dataclasses import replace
from unittest.mock import patch
from pathlib import Path

from scripts.blueprint_harness_branches import load_branch_policy
import scripts.check_backport_pr as backport_mod
from tests.harness.release_fixtures import (
    SAMPLE_DEFAULT_RELEASE,
    SAMPLE_PREVIOUS_RELEASE,
    backport_line,
)


PACKAGE_ROOT = Path(__file__).resolve().parents[2]
BRANCH_POLICY = load_branch_policy(PACKAGE_ROOT)
DEFAULT_DEV_RELEASE = BRANCH_POLICY.default_dev_branch
REQUIRED_BACKPORT_RELEASES = BRANCH_POLICY.required_backport_branches
RUN_REQUIRED_BACKPORT_RELEASES = (SAMPLE_PREVIOUS_RELEASE,)


class FakeGitHubApi:
    def __init__(
        self,
        *,
        pull_requests: dict[int, dict[str, object]] | None = None,
        pull_request_commits: dict[int, list[backport_mod.PullRequestCommit]] | None = None,
        pull_request_files: dict[int, list[str]] | None = None,
    ) -> None:
        self._pull_requests = pull_requests or {}
        self._pull_request_commits = pull_request_commits or {}
        self._pull_request_files = pull_request_files or {}

    def pull_request(self, number: int) -> dict[str, object]:
        return self._pull_requests[number]

    def pull_request_commits(self, number: int) -> list[backport_mod.PullRequestCommit]:
        return self._pull_request_commits[number]

    def pull_request_files(self, number: int) -> list[str]:
        return self._pull_request_files[number]


def write_pull_request_event(path: Path, *, draft: bool, body: str) -> None:
    path.write_text(
        json.dumps(
            {
                "repository": {"full_name": "leanprover/verso-blueprint"},
                "pull_request": {
                    "number": 11,
                    "base": {"ref": DEFAULT_DEV_RELEASE},
                    "draft": draft,
                    "body": body,
                },
            },
            indent=2,
        ),
        encoding="utf-8",
    )


def required_backport_body(status: str) -> str:
    return "".join(f"{backport_line(branch, status)}\n" for branch in RUN_REQUIRED_BACKPORT_RELEASES)


def run_with_required_backport(event_path: Path, *, token: str | None) -> int:
    policy = replace(BRANCH_POLICY, required_backport_branches=RUN_REQUIRED_BACKPORT_RELEASES)
    with patch.object(backport_mod, "load_branch_policy", return_value=policy):
        return backport_mod.run(str(event_path), token=token)


class BackportPrCheckTests(unittest.TestCase):
    def test_pr_template_backport_placeholder_is_safe_for_drafts(self) -> None:
        template = Path(__file__).resolve().parents[2] / ".github" / "PULL_REQUEST_TEMPLATE.md"
        entries = backport_mod.parse_backport_entries(template.read_text(encoding="utf-8"))

        self.assertEqual(set(entries), set(REQUIRED_BACKPORT_RELEASES))
        for branch in REQUIRED_BACKPORT_RELEASES:
            self.assertTrue(entries[branch].pending)

    def test_parse_backport_entries_accepts_pr_pending_and_exemption(self) -> None:
        body = """
Backport v4.28.0: #42
Backport v4.27.0: pending
Backport v4.26.0: exempt: no longer maintained
"""
        entries = backport_mod.parse_backport_entries(body)
        self.assertEqual(entries["v4.28.0"].pr_number, 42)
        self.assertIsNone(entries["v4.28.0"].exempt_reason)
        self.assertTrue(entries["v4.27.0"].pending)
        self.assertEqual(entries["v4.26.0"].exempt_reason, "no longer maintained")

    def test_parse_backport_entries_accepts_pull_request_url(self) -> None:
        body = "Backport v4.28.0: https://github.com/leanprover/verso-blueprint/pull/123\n"
        entries = backport_mod.parse_backport_entries(body)
        self.assertEqual(entries["v4.28.0"].pr_number, 123)

    def test_parse_backport_entries_rejects_missing_exemption_reason(self) -> None:
        with self.assertRaisesRegex(backport_mod.BackportCheckError, "exemption must include a reason"):
            backport_mod.parse_backport_entries("Backport v4.28.0: exempt\n")

    def test_should_enforce_accepts_draft_default_dev_prs(self) -> None:
        pull_request = {"base": {"ref": SAMPLE_DEFAULT_RELEASE}, "draft": True}
        self.assertTrue(backport_mod.should_enforce(pull_request, SAMPLE_DEFAULT_RELEASE, (SAMPLE_PREVIOUS_RELEASE,)))

    def test_should_enforce_skips_non_default_dev_targets(self) -> None:
        pull_request = {"base": {"ref": SAMPLE_PREVIOUS_RELEASE}, "draft": False}
        self.assertFalse(backport_mod.should_enforce(pull_request, SAMPLE_DEFAULT_RELEASE, (SAMPLE_PREVIOUS_RELEASE,)))

    def test_run_requires_metadata_for_draft_default_dev_prs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            event_path = Path(tmp) / "event.json"
            write_pull_request_event(event_path, draft=True, body="")
            with self.assertRaisesRegex(backport_mod.BackportCheckError, "missing paired backport metadata"):
                run_with_required_backport(event_path, token=None)

    def test_run_accepts_pending_entries_for_draft_default_dev_prs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            event_path = Path(tmp) / "event.json"
            write_pull_request_event(
                event_path,
                draft=True,
                body=required_backport_body("pending"),
            )
            self.assertEqual(run_with_required_backport(event_path, token=None), 0)

    def test_verify_backport_commit_series_accepts_matching_cherry_picks(self) -> None:
        api = FakeGitHubApi(
            pull_request_commits={
                11: [
                    backport_mod.PullRequestCommit(sha="a" * 40, message="fix: one"),
                    backport_mod.PullRequestCommit(sha="b" * 40, message="fix: two"),
                ],
                13: [
                    backport_mod.PullRequestCommit(
                        sha="c" * 40,
                        message=f"fix: one\n\n(cherry picked from commit {'a' * 40})",
                    ),
                    backport_mod.PullRequestCommit(
                        sha="d" * 40,
                        message=f"fix: two\n\n(cherry picked from commit {'b' * 40})",
                    ),
                ],
            },
        )
        backport_mod.verify_backport_commit_series(api, 11, 13)

    def test_verify_backport_commit_series_rejects_missing_cherry_pick_provenance(self) -> None:
        api = FakeGitHubApi(
            pull_request_commits={
                11: [backport_mod.PullRequestCommit(sha="a" * 40, message="fix: one")],
                13: [backport_mod.PullRequestCommit(sha="c" * 40, message="fix: one")],
            },
        )
        with self.assertRaisesRegex(backport_mod.BackportCheckError, "missing `\\(cherry picked from commit <sha>\\)` provenance"):
            backport_mod.verify_backport_commit_series(api, 11, 13)

    def test_verify_backport_commit_series_accepts_release_line_adapted_cherry_picks(self) -> None:
        api = FakeGitHubApi(
            pull_request_commits={
                11: [backport_mod.PullRequestCommit(sha="a" * 40, message="fix: one")],
                13: [
                    backport_mod.PullRequestCommit(
                        sha="c" * 40,
                        message=f"fix: one\n\n(cherry picked from commit {'a' * 40})",
                    )
                ],
            },
        )
        backport_mod.verify_backport_commit_series(api, 11, 13)

    def test_verify_backport_pr_accepts_structural_match_without_ci_status(self) -> None:
        api = FakeGitHubApi(
            pull_requests={
                13: {
                    "base": {"ref": "v4.28.0"},
                    "draft": False,
                    "state": "open",
                }
            },
            pull_request_commits={
                11: [backport_mod.PullRequestCommit(sha="a" * 40, message="fix: one")],
                13: [
                    backport_mod.PullRequestCommit(
                        sha="c" * 40,
                        message=f"fix: one\n\n(cherry picked from commit {'a' * 40})",
                    )
                ],
            },
        )
        backport_mod.verify_backport_pr(api, 11, "v4.28.0", backport_mod.BackportEntry(branch="v4.28.0", pr_number=13))

    def test_run_rejects_pending_entries_for_ready_default_dev_prs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            event_path = Path(tmp) / "event.json"
            write_pull_request_event(
                event_path,
                draft=False,
                body=required_backport_body("pending"),
            )
            with self.assertRaisesRegex(backport_mod.BackportCheckError, "pending backport entries are not allowed"):
                run_with_required_backport(event_path, token=None)

    def test_run_accepts_ready_docs_only_exemptions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            event_path = Path(tmp) / "event.json"
            write_pull_request_event(
                event_path,
                draft=False,
                body=required_backport_body("exempt: docs-only change"),
            )
            api = FakeGitHubApi(pull_request_files={11: ["doc/API.md", "README.md"]})
            with patch.object(backport_mod, "GitHubApi", return_value=api):
                self.assertEqual(run_with_required_backport(event_path, token="token"), 0)

    def test_run_rejects_source_change_exemptions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            event_path = Path(tmp) / "event.json"
            write_pull_request_event(
                event_path,
                draft=False,
                body=required_backport_body("exempt: no reported release-line regression"),
            )
            api = FakeGitHubApi(pull_request_files={11: ["src/VersoBlueprint/GraphApi.lean", "doc/API.md"]})
            with patch.object(backport_mod, "GitHubApi", return_value=api):
                with self.assertRaisesRegex(backport_mod.BackportCheckError, "paired backports are required"):
                    run_with_required_backport(event_path, token="token")

    def test_run_requires_token_to_validate_exemptions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            event_path = Path(tmp) / "event.json"
            write_pull_request_event(
                event_path,
                draft=False,
                body=required_backport_body("exempt: docs-only change"),
            )
            with self.assertRaisesRegex(backport_mod.BackportCheckError, "missing GitHub token"):
                run_with_required_backport(event_path, token=None)


if __name__ == "__main__":
    unittest.main()
