from __future__ import annotations

import base64
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
    branch_policy_json,
    lean_toolchain,
    release_target,
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
        file_texts: dict[tuple[str, str], str] | None = None,
    ) -> None:
        self._pull_requests = pull_requests or {}
        self._pull_request_commits = pull_request_commits or {}
        self._pull_request_files = pull_request_files or {}
        self._file_texts = file_texts or {}

    def pull_request(self, number: int) -> dict[str, object]:
        return self._pull_requests[number]

    def pull_request_commits(self, number: int) -> list[backport_mod.PullRequestCommit]:
        return self._pull_request_commits[number]

    def pull_request_files(self, number: int) -> list[str]:
        return self._pull_request_files[number]

    def file_text(self, path: str, ref: str) -> str:
        return self._file_texts[(path, ref)]


def write_pull_request_event(path: Path, *, draft: bool, body: str) -> None:
    path.write_text(
        json.dumps(
            {
                "repository": {"full_name": "leanprover/verso-blueprint"},
                "pull_request": {
                    "number": 11,
                    "base": {"ref": DEFAULT_DEV_RELEASE, "sha": "base-sha"},
                    "head": {"sha": "head-sha"},
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


def run_release_transition(
    *,
    body: str,
    base_default: str,
    base_backports: tuple[str, ...],
    head_default: str,
    head_backports: tuple[str, ...],
    changed_files: tuple[str, ...],
    base_targets: list[dict[str, object]] | None = None,
    head_targets: list[dict[str, object]] | None = None,
    base_toolchain: str | None = None,
    head_toolchain: str | None = None,
) -> int:
    with tempfile.TemporaryDirectory() as tmp:
        package_root = Path(tmp) / "package"
        package_root.mkdir()
        (package_root / "branch-policy.json").write_text(
            branch_policy_json(
                default_dev=base_default,
                required_backports=base_backports,
                release_targets=base_targets,
            ),
            encoding="utf-8",
        )
        (package_root / "lean-toolchain").write_text(
            f"{lean_toolchain(base_toolchain or base_default)}\n",
            encoding="utf-8",
        )
        event_path = Path(tmp) / "event.json"
        write_pull_request_event(event_path, draft=False, body=body)
        api = FakeGitHubApi(
            pull_request_files={11: list(changed_files)},
            file_texts={
                ("lean-toolchain", "base-sha"): f"{lean_toolchain(base_toolchain or base_default)}\n",
                ("branch-policy.json", "head-sha"): branch_policy_json(
                    default_dev=head_default,
                    required_backports=head_backports,
                    release_targets=head_targets,
                ),
                ("lean-toolchain", "head-sha"): f"{lean_toolchain(head_toolchain or head_default)}\n",
            },
        )
        with (
            patch.object(backport_mod, "GitHubApi", return_value=api),
            patch.object(backport_mod, "PACKAGE_ROOT", package_root),
        ):
            return backport_mod.run(str(event_path), token="token")


class BackportPrCheckTests(unittest.TestCase):
    def test_github_api_decodes_repository_file_contents(self) -> None:
        api = backport_mod.GitHubApi("leanprover/verso-blueprint", "token")
        encoded = base64.b64encode(b"release policy\n").decode("ascii")
        with patch.object(api, "get_json", return_value={"encoding": "base64", "content": encoded}):
            self.assertEqual(api.file_text("branch-policy.json", "head-sha"), "release policy\n")

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
Backport v4.25.0: release-line bootstrap
Backport v4.24.0: release-line retirement
"""
        entries = backport_mod.parse_backport_entries(body)
        self.assertEqual(entries["v4.28.0"].pr_number, 42)
        self.assertIsNone(entries["v4.28.0"].exempt_reason)
        self.assertTrue(entries["v4.27.0"].pending)
        self.assertEqual(entries["v4.26.0"].exempt_reason, "no longer maintained")
        self.assertTrue(entries["v4.25.0"].release_line_bootstrap)
        self.assertTrue(entries["v4.24.0"].release_line_retirement)

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

    def test_run_accepts_ready_documentation_and_catalog_exemptions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            event_path = Path(tmp) / "event.json"
            write_pull_request_event(
                event_path,
                draft=False,
                body=required_backport_body("exempt: docs-only change"),
            )
            api = FakeGitHubApi(
                pull_request_files={11: ["doc/API.md", "README.md", "tests/harness/projects.json"]}
            )
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

    def test_run_accepts_machine_checked_release_line_bootstrap(self) -> None:
        self.assertEqual(
            run_release_transition(
                body=backport_line("v4.32.0", backport_mod.RELEASE_LINE_BOOTSTRAP_STATUS),
                base_default="v4.32.0",
                base_backports=(),
                head_default="v4.33.0",
                head_backports=("v4.32.0",),
                changed_files=("branch-policy.json", "lean-toolchain", "scripts/release.py"),
            ),
            0,
        )

    def test_run_accepts_bootstrap_that_retires_oldest_backport(self) -> None:
        base_targets = [release_target("v4.31.0"), release_target("v4.32.0")]
        head_targets = [
            release_target("v4.32.0"),
            release_target("v4.33.0", deploy_pages=False),
        ]
        self.assertEqual(
            run_release_transition(
                body=backport_line("v4.32.0", backport_mod.RELEASE_LINE_BOOTSTRAP_STATUS),
                base_default="v4.32.0",
                base_backports=("v4.31.0",),
                head_default="v4.33.0",
                head_backports=("v4.32.0",),
                changed_files=("branch-policy.json", "lean-toolchain", "tests/harness/projects.json"),
                base_targets=base_targets,
                head_targets=head_targets,
            ),
            0,
        )

    def test_run_rejects_backward_release_line_bootstrap(self) -> None:
        with self.assertRaisesRegex(backport_mod.BackportCheckError, "newer default development release line"):
            run_release_transition(
                body=backport_line("v4.32.0", backport_mod.RELEASE_LINE_BOOTSTRAP_STATUS),
                base_default="v4.32.0",
                base_backports=(),
                head_default="v4.31.0",
                head_backports=("v4.32.0",),
                changed_files=("branch-policy.json", "lean-toolchain"),
            )

    def test_run_rejects_bootstrap_that_changes_a_retained_target(self) -> None:
        with self.assertRaisesRegex(backport_mod.BackportCheckError, "preserve retained release targets"):
            run_release_transition(
                body=backport_line("v4.32.0", backport_mod.RELEASE_LINE_BOOTSTRAP_STATUS),
                base_default="v4.32.0",
                base_backports=("v4.31.0",),
                head_default="v4.33.0",
                head_backports=("v4.32.0",),
                changed_files=("branch-policy.json", "lean-toolchain"),
                base_targets=[release_target("v4.31.0"), release_target("v4.32.0")],
                head_targets=[
                    release_target("v4.32.0", deploy_pages=False),
                    release_target("v4.33.0", deploy_pages=False),
                ],
            )

    def test_run_rejects_bootstrap_with_mismatched_head_toolchain(self) -> None:
        with self.assertRaisesRegex(backport_mod.BackportCheckError, "head is internally inconsistent"):
            run_release_transition(
                body=backport_line("v4.32.0", backport_mod.RELEASE_LINE_BOOTSTRAP_STATUS),
                base_default="v4.32.0",
                base_backports=(),
                head_default="v4.33.0",
                head_backports=("v4.32.0",),
                changed_files=("branch-policy.json", "lean-toolchain"),
                head_toolchain="v4.34.0",
            )

    def test_run_rejects_release_line_bootstrap_without_release_identity_changes(self) -> None:
        with self.assertRaisesRegex(backport_mod.BackportCheckError, "missing lean-toolchain"):
            run_release_transition(
                body=backport_line("v4.32.0", backport_mod.RELEASE_LINE_BOOTSTRAP_STATUS),
                base_default="v4.32.0",
                base_backports=(),
                head_default="v4.33.0",
                head_backports=("v4.32.0",),
                changed_files=("branch-policy.json",),
            )

    def test_run_accepts_machine_checked_release_line_retirement(self) -> None:
        retired = SAMPLE_PREVIOUS_RELEASE
        base_targets = [release_target(retired), release_target(DEFAULT_DEV_RELEASE)]
        head_targets = [target for target in base_targets if target["id"] != retired]
        self.assertEqual(
            run_release_transition(
                body=backport_line(retired, backport_mod.RELEASE_LINE_RETIREMENT_STATUS),
                base_default=DEFAULT_DEV_RELEASE,
                base_backports=(retired,),
                head_default=DEFAULT_DEV_RELEASE,
                head_backports=(),
                changed_files=("branch-policy.json", "tests/harness/projects.json"),
                base_targets=base_targets,
                head_targets=head_targets,
            ),
            0,
        )

    def test_run_rejects_retiring_a_non_oldest_backport(self) -> None:
        newest = "v4.31.0"
        oldest = "v4.30.0"
        base_targets = [
            release_target(oldest),
            release_target(newest),
            release_target(DEFAULT_DEV_RELEASE),
        ]
        with self.assertRaisesRegex(backport_mod.BackportCheckError, "oldest contiguous suffix"):
            run_release_transition(
                body=backport_line(newest, backport_mod.RELEASE_LINE_RETIREMENT_STATUS),
                base_default=DEFAULT_DEV_RELEASE,
                base_backports=(newest, oldest),
                head_default=DEFAULT_DEV_RELEASE,
                head_backports=(oldest,),
                changed_files=("branch-policy.json",),
                base_targets=base_targets,
                head_targets=[release_target(oldest), release_target(DEFAULT_DEV_RELEASE)],
            )


if __name__ == "__main__":
    unittest.main()
