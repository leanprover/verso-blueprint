import json
import unittest
from unittest.mock import patch

from scripts.emit_reference_deploy_matrix import automatic_deploy_skip_reason, has_successful_push


REPOSITORY = "example/blueprints"
RELEASE = "v4.35.0"
ARCHIVE = "v4.34.0"
HEAD = "a" * 40
OTHER_HEAD = "b" * 40


class ReferenceDeployAdmissionTests(unittest.TestCase):
    def reason(self, revisions, branch=RELEASE, sha=HEAD):
        return automatic_deploy_skip_reason(
            revisions, branch, sha, repository=REPOSITORY,
            controller_branch=RELEASE, controller_revision=HEAD,
        )

    @patch("scripts.emit_reference_deploy_matrix.has_successful_push")
    def test_trigger_must_be_the_current_head_of_a_published_release(self, check):
        self.assertIn("outside", self.reason({RELEASE: HEAD}, ARCHIVE, OTHER_HEAD))
        self.assertIn("moved", self.reason({RELEASE: HEAD}, RELEASE, OTHER_HEAD))
        self.assertIsNone(self.reason({RELEASE: HEAD}))
        check.assert_not_called()

    @patch("scripts.emit_reference_deploy_matrix.has_successful_push")
    def test_second_release_must_pass_at_its_exact_head(self, check):
        revisions = {RELEASE: HEAD, ARCHIVE: OTHER_HEAD}
        for passed in (False, True):
            with self.subTest(passed=passed):
                check.return_value = passed
                self.assertEqual(self.reason(revisions) is None, passed)
                check.assert_called_once_with(REPOSITORY, ARCHIVE, OTHER_HEAD)
                check.reset_mock()

    @patch("scripts.emit_reference_deploy_matrix.has_successful_push", return_value=False)
    def test_controller_is_checked_even_when_it_has_no_published_projects(self, check):
        self.assertIn(RELEASE, self.reason({ARCHIVE: OTHER_HEAD}, ARCHIVE, OTHER_HEAD))
        check.assert_called_once_with(REPOSITORY, RELEASE, HEAD)

    @patch("scripts.emit_reference_deploy_matrix.subprocess.check_output")
    def test_only_the_latest_matching_successful_same_repo_push_counts(self, request):
        successful = {
            "head_branch": RELEASE, "head_sha": HEAD, "head_repository": {"full_name": REPOSITORY},
            "conclusion": "success", "event": "push",
        }
        for runs, expected in [
            ([], False),
            ([successful], True),
            ([{**successful, "conclusion": None}, successful], False),
            ([{**successful, "conclusion": "failure"}], False),
            ([{**successful, "event": "workflow_dispatch"}], False),
            ([{**successful, "head_sha": OTHER_HEAD}], False),
            ([{**successful, "head_repository": {"full_name": "other/fork"}}], False),
        ]:
            with self.subTest(runs=runs):
                request.return_value = json.dumps({"workflow_runs": runs})
                self.assertEqual(has_successful_push(REPOSITORY, RELEASE, HEAD), expected)
        command = request.call_args.args[0]
        self.assertIn("event=push", command)
        self.assertIn(f"head_sha={HEAD}", command)
        self.assertIn(f"branch={RELEASE}", command)
        self.assertIn("per_page=1", command)
