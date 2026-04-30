from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import scripts.check_backport_pr as backport_mod


class FakeGitHubApi:
    def __init__(
        self,
        *,
        pull_requests: dict[int, dict[str, object]] | None = None,
        pull_request_commits: dict[int, list[backport_mod.PullRequestCommit]] | None = None,
        commit_diffs: dict[str, str] | None = None,
    ) -> None:
        self._pull_requests = pull_requests or {}
        self._pull_request_commits = pull_request_commits or {}
        self._commit_diffs = commit_diffs or {}

    def pull_request(self, number: int) -> dict[str, object]:
        return self._pull_requests[number]

    def pull_request_commits(self, number: int) -> list[backport_mod.PullRequestCommit]:
        return self._pull_request_commits[number]

    def commit_diff(self, sha: str) -> str:
        return self._commit_diffs[sha]

    def check_runs(self, sha: str) -> dict[str, object]:
        return {"check_runs": []}

    def combined_status(self, sha: str) -> dict[str, object]:
        return {"state": "success"}


def diff_for(line: str) -> str:
    return (
        "diff --git a/demo.txt b/demo.txt\n"
        "index e69de29..4b825dc 100644\n"
        "--- a/demo.txt\n"
        "+++ b/demo.txt\n"
        "@@ -0,0 +1 @@\n"
        f"+{line}\n"
    )


class BackportPrCheckTests(unittest.TestCase):
    def test_pr_template_backport_placeholder_is_safe_for_drafts(self) -> None:
        template = Path(__file__).resolve().parents[2] / ".github" / "PULL_REQUEST_TEMPLATE.md"
        entries = backport_mod.parse_backport_entries(template.read_text(encoding="utf-8"))

        self.assertEqual(set(entries), {"v4.28.0"})
        self.assertTrue(entries["v4.28.0"].pending)

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
        pull_request = {"base": {"ref": "v4.29.0"}, "draft": True}
        self.assertTrue(backport_mod.should_enforce(pull_request, "v4.29.0", ("v4.28.0",)))

    def test_should_enforce_skips_non_default_dev_targets(self) -> None:
        pull_request = {"base": {"ref": "v4.28.0"}, "draft": False}
        self.assertFalse(backport_mod.should_enforce(pull_request, "v4.29.0", ("v4.28.0",)))

    def test_check_runs_state_rejects_pending_and_failing_runs(self) -> None:
        with self.assertRaisesRegex(backport_mod.BackportCheckError, "pending"):
            backport_mod.check_runs_state(
                {"check_runs": [{"name": "CI", "status": "in_progress", "conclusion": None}]},
                {"state": "pending"},
            )

        with self.assertRaisesRegex(backport_mod.BackportCheckError, "failing"):
            backport_mod.check_runs_state(
                {"check_runs": [{"name": "CI", "status": "completed", "conclusion": "failure"}]},
                {"state": "failure"},
            )

    def test_run_requires_metadata_for_draft_default_dev_prs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            event_path = Path(tmp) / "event.json"
            event_path.write_text(
                """
{
  "repository": {"full_name": "leanprover/verso-blueprint"},
  "pull_request": {
    "base": {"ref": "v4.29.0"},
    "draft": true,
    "body": ""
  }
}
""".strip(),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(backport_mod.BackportCheckError, "missing paired backport metadata"):
                backport_mod.run(str(event_path), token=None)

    def test_run_accepts_pending_entries_for_draft_default_dev_prs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            event_path = Path(tmp) / "event.json"
            event_path.write_text(
                """
{
  "repository": {"full_name": "leanprover/verso-blueprint"},
  "pull_request": {
    "base": {"ref": "v4.29.0"},
    "draft": true,
    "body": "Backport v4.28.0: pending\\n"
  }
}
""".strip(),
                encoding="utf-8",
            )
            self.assertEqual(backport_mod.run(str(event_path), token=None), 0)

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
            commit_diffs={
                "a" * 40: diff_for("one"),
                "b" * 40: diff_for("two"),
                "c" * 40: diff_for("one"),
                "d" * 40: diff_for("two"),
            },
        )
        backport_mod.verify_backport_commit_series(api, 11, 13)

    def test_verify_backport_commit_series_rejects_missing_cherry_pick_provenance(self) -> None:
        api = FakeGitHubApi(
            pull_request_commits={
                11: [backport_mod.PullRequestCommit(sha="a" * 40, message="fix: one")],
                13: [backport_mod.PullRequestCommit(sha="c" * 40, message="fix: one")],
            },
            commit_diffs={
                "a" * 40: diff_for("one"),
                "c" * 40: diff_for("one"),
            },
        )
        with self.assertRaisesRegex(backport_mod.BackportCheckError, "missing `\\(cherry picked from commit <sha>\\)` provenance"):
            backport_mod.verify_backport_commit_series(api, 11, 13)

    def test_verify_backport_commit_series_rejects_patch_mismatch(self) -> None:
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
            commit_diffs={
                "a" * 40: diff_for("one"),
                "c" * 40: diff_for("adapted"),
            },
        )
        with self.assertRaisesRegex(backport_mod.BackportCheckError, "does not match the patch from source commit"):
            backport_mod.verify_backport_commit_series(api, 11, 13)

    def test_verify_backport_pr_checks_commit_series_before_ci(self) -> None:
        api = FakeGitHubApi(
            pull_requests={
                13: {
                    "base": {"ref": "v4.28.0"},
                    "draft": False,
                    "state": "open",
                    "head": {"sha": "c" * 40},
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
            commit_diffs={
                "a" * 40: diff_for("one"),
                "c" * 40: diff_for("one"),
            },
        )
        backport_mod.verify_backport_pr(api, 11, "v4.28.0", backport_mod.BackportEntry(branch="v4.28.0", pr_number=13))

    def test_run_rejects_pending_entries_for_ready_default_dev_prs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            event_path = Path(tmp) / "event.json"
            event_path.write_text(
                """
{
  "repository": {"full_name": "leanprover/verso-blueprint"},
  "pull_request": {
    "base": {"ref": "v4.29.0"},
    "draft": false,
    "body": "Backport v4.28.0: pending\\n"
  }
}
""".strip(),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(backport_mod.BackportCheckError, "pending backport entries are not allowed"):
                backport_mod.run(str(event_path), token=None)

    def test_run_accepts_ready_default_dev_prs_with_only_exemptions_and_no_token(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            event_path = Path(tmp) / "event.json"
            event_path.write_text(
                """
{
  "repository": {"full_name": "leanprover/verso-blueprint"},
  "pull_request": {
    "base": {"ref": "v4.29.0"},
    "draft": false,
    "body": "Backport v4.28.0: exempt: docs-only change\\n"
  }
}
""".strip(),
                encoding="utf-8",
            )
            self.assertEqual(backport_mod.run(str(event_path), token=None), 0)


if __name__ == "__main__":
    unittest.main()
