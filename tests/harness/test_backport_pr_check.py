from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import scripts.check_backport_pr as backport_mod


class BackportPrCheckTests(unittest.TestCase):
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
