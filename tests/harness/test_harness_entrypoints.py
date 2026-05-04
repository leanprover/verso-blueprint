from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import unittest


PACKAGE_ROOT = Path(__file__).resolve().parents[2]


class HarnessEntrypointSmokeTests(unittest.TestCase):
    def run_command(self, command: list[str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            command,
            cwd=PACKAGE_ROOT,
            check=False,
            text=True,
            capture_output=True,
        )

    def test_blueprint_harness_help(self) -> None:
        result = self.run_command([sys.executable, "-m", "scripts.blueprint_harness", "--help"])
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("create-worktree", result.stdout)
        self.assertIn("prepare-backports", result.stdout)
        self.assertIn("prepare-pr", result.stdout)
        self.assertIn("prepare-backport-pr", result.stdout)
        self.assertIn("bump-toolchain", result.stdout)
        self.assertIn("land-release", result.stdout)

    def test_blueprint_reference_harness_help(self) -> None:
        result = self.run_command([sys.executable, "-m", "scripts.blueprint_reference_harness", "--help"])
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("generate", result.stdout)
        self.assertIn("sync", result.stdout)
        self.assertIn("edit", result.stdout)
        self.assertIn("bump-verso-blueprint", result.stdout)

    def test_blueprint_test_blueprints_help(self) -> None:
        result = self.run_command([sys.executable, "-m", "scripts.blueprint_test_blueprints", "--help"])
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("list-json", result.stdout)
        self.assertIn("generate", result.stdout)
        self.assertIn("generate-all", result.stdout)

    def test_blueprint_test_blueprints_list_json(self) -> None:
        result = self.run_command([sys.executable, "-m", "scripts.blueprint_test_blueprints", "list-json"])
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("preview_runtime_showcase", result.stdout)
        self.assertIn("standalone_project", result.stdout)
        self.assertIn('"category":"Runtime"', result.stdout)
        self.assertIn('"tags":["preview","runtime","browser"', result.stdout)

    def test_blueprint_test_blueprints_list(self) -> None:
        result = self.run_command([sys.executable, "-m", "scripts.blueprint_test_blueprints", "list"])
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertEqual(result.stdout.strip(), "preview_runtime_showcase")

    def test_generate_reference_wrapper_help(self) -> None:
        result = self.run_command(["bash", "scripts/generate-reference-blueprints.sh", "--help"])
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("python3 -m scripts.blueprint_reference_harness", result.stdout)

    def test_generate_review_artifacts_wrapper_help(self) -> None:
        result = self.run_command(["bash", "scripts/generate-review-artifacts.sh", "--help"])
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("reference blueprints", result.stdout)
        self.assertIn("test blueprints", result.stdout)

    def test_validate_reference_wrapper_help(self) -> None:
        result = self.run_command(["bash", "scripts/validate-reference-blueprints.sh", "--help"])
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("python3 -m scripts.blueprint_reference_harness", result.stdout)

    def test_validate_test_blueprints_wrapper_help(self) -> None:
        result = self.run_command(["bash", "scripts/validate-test-blueprints.sh", "--help"])
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("standalone", result.stdout)

    def test_validate_branch_wrapper_help(self) -> None:
        result = self.run_command(["bash", "scripts/validate-branch.sh", "--help"])
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("branch-validation workflow", result.stdout)

    def test_project_template_fresh_repo_smoke_help(self) -> None:
        result = self.run_command([sys.executable, "scripts/check_project_template_fresh_repo.py", "--help"])
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("--site-output", result.stdout)

    def test_math_lint_fresh_repo_smoke_help(self) -> None:
        result = self.run_command([sys.executable, "scripts/check_math_lint_fresh_repo.py", "--help"])
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("fresh consumer Blueprint projects", result.stdout)

    def test_backport_pr_check_help(self) -> None:
        result = self.run_command([sys.executable, "scripts/check_backport_pr.py", "--help"])
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("paired backport", result.stdout)


if __name__ == "__main__":
    unittest.main()
