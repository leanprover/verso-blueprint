from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


PACKAGE_ROOT = Path(__file__).resolve().parents[2]


class HarnessEntrypointSmokeTests(unittest.TestCase):
    def run_command(
        self,
        command: list[str],
        *,
        cwd: Path = PACKAGE_ROOT,
        env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            command,
            cwd=cwd,
            check=False,
            text=True,
            capture_output=True,
            env=env,
        )

    def cache_environment(self, **overrides: str) -> dict[str, str]:
        env = {
            key: value
            for key, value in os.environ.items()
            if key not in {"LAKE_CACHE_DIR", "LAKE_ARTIFACT_CACHE", "LAKE_RESTORE_ARTIFACTS"}
        }
        env.update(overrides)
        return env

    def parse_config(self, output: str) -> dict[str, str]:
        return dict(line.split("=", 1) for line in output.splitlines())

    def test_blueprint_harness_help(self) -> None:
        result = self.run_command([sys.executable, "-m", "scripts.blueprint_harness", "--help"])
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("create-worktree", result.stdout)
        self.assertIn("prepare-backports", result.stdout)
        self.assertIn("prepare-pr", result.stdout)
        self.assertIn("prepare-backport-pr", result.stdout)
        self.assertIn("bump-toolchain", result.stdout)
        self.assertIn("start-release-line", result.stdout)
        self.assertIn("set-default-dev-branch", result.stdout)
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
        self.assertIn("validate", result.stdout)

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

    def test_report_ci_disk_usage_help(self) -> None:
        result = self.run_command(["bash", "scripts/report-ci-disk-usage.sh", "--help"])
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("Print a compact disk-usage report", result.stdout)
        self.assertIn("BP_REFERENCE_SOURCE_IDENTITY", result.stdout)
        self.assertIn("BP_REFERENCE_DEPENDENCY_PACKAGES_PATH", result.stdout)
        self.assertIn("BP_REFERENCE_DEPENDENCY_PATH_BUILDS_PATH", result.stdout)
        self.assertIn("BP_REFERENCE_ARTIFACT_PATH", result.stdout)
        self.assertNotIn("--reference-source-identity", result.stdout)

    def test_report_ci_disk_usage_includes_reference_paths_from_environment(self) -> None:
        identity = "external-main-123456789abc"
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            reference_root = root / ".worktrees" / "_reference-blueprints"
            source_cache = reference_root / "cache" / identity
            local_checkout = reference_root / "by-worktree" / "demo" / identity
            dependency_root = reference_root / "deps" / identity
            packages = dependency_root / "packages" / "mathlib"
            path_build = dependency_root / "path-builds" / "Formalization"
            artifact = root / "_out" / "reference-blueprints" / "external-blueprint"
            source_cache.mkdir(parents=True)
            local_checkout.mkdir(parents=True)
            packages.mkdir(parents=True)
            path_build.mkdir(parents=True)
            artifact.mkdir(parents=True)
            result = subprocess.run(
                [
                    "bash",
                    str(PACKAGE_ROOT / "scripts" / "report-ci-disk-usage.sh"),
                    "test",
                ],
                cwd=root,
                check=False,
                text=True,
                capture_output=True,
                env={
                    **os.environ,
                    "BP_REFERENCE_SOURCE_IDENTITY": identity,
                    "BP_REFERENCE_DEPENDENCY_PACKAGES_PATH": str(packages.parent.relative_to(root)),
                    "BP_REFERENCE_DEPENDENCY_PATH_BUILDS_PATH": str(path_build.parent.relative_to(root)),
                    "BP_REFERENCE_ARTIFACT_PATH": str(artifact.relative_to(root)),
                },
            )

        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn(f"cache/{identity}", result.stdout)
        self.assertIn(f"by-worktree/demo/{identity}", result.stdout)
        self.assertIn(f"[ci-disk] packages for {identity}", result.stdout)
        self.assertIn("packages/mathlib", result.stdout)
        self.assertIn(f"[ci-disk] path builds for {identity}", result.stdout)
        self.assertIn("path-builds/Formalization", result.stdout)
        self.assertIn("artifact_path=_out/reference-blueprints/external-blueprint", result.stdout)

    def test_validate_reference_wrapper_help(self) -> None:
        result = self.run_command(["bash", "scripts/validate-reference-blueprints.sh", "--help"])
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("python3 -m scripts.blueprint_reference_harness", result.stdout)

    def test_validate_test_blueprints_wrapper_help(self) -> None:
        result = self.run_command(["bash", "scripts/validate-test-blueprints.sh", "--help"])
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("standalone", result.stdout)
        self.assertIn("--skip-browser-tests", result.stdout)
        self.assertIn("--pytest-arg", result.stdout)

    def test_validate_branch_wrapper_help(self) -> None:
        result = self.run_command(["bash", "scripts/validate-branch.sh", "--help"])
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("branch-validation workflow", result.stdout)

    def test_blueprint_lake_cache_uses_nearest_toolchain_and_cache_in_place_defaults(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            project = root / "nested" / "project"
            cache_root = root / "cache"
            project.mkdir(parents=True)
            (root / "lean-toolchain").write_text("leanprover/lean4:v9.99.0-test\n", encoding="utf-8")

            result = self.run_command(
                [str(PACKAGE_ROOT / "scripts" / "with-blueprint-lake-cache"), "--print-config"],
                cwd=project,
                env=self.cache_environment(BP_LAKE_ARTIFACT_CACHE_ROOT=str(cache_root)),
            )

            expected_cache = cache_root / "leanprover--lean4---v9.99.0-test"
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual(
                self.parse_config(result.stdout),
                {
                    "LAKE_CACHE_DIR": str(expected_cache),
                    "LAKE_ARTIFACT_CACHE": "true",
                    "LAKE_RESTORE_ARTIFACTS": "false",
                },
            )
            self.assertEqual(expected_cache.stat().st_mode & 0o777, 0o700)

    @unittest.skipUnless(os.name == "posix", "umask is POSIX-specific")
    def test_blueprint_lake_cache_preserves_child_umask(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            cache_root = Path(tmp) / "cache"
            wrapper = PACKAGE_ROOT / "scripts" / "with-blueprint-lake-cache"
            result = self.run_command(
                [
                    "/bin/bash",
                    "-c",
                    'umask 0027; exec "$1" /bin/sh -c umask',
                    "blueprint-cache-umask-test",
                    str(wrapper),
                ],
                env=self.cache_environment(BP_LAKE_ARTIFACT_CACHE_ROOT=str(cache_root)),
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual(result.stdout.strip(), "0027")

    def test_blueprint_lake_cache_help_does_not_create_cache(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            cache_root = Path(tmp) / "cache"
            result = self.run_command(
                [str(PACKAGE_ROOT / "scripts" / "with-blueprint-lake-cache"), "--help"],
                env=self.cache_environment(BP_LAKE_ARTIFACT_CACHE_ROOT=str(cache_root)),
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("Run a command with Blueprint's shared", result.stdout)
            self.assertFalse(cache_root.exists())

    def test_blueprint_lake_cache_preserves_explicit_lake_overrides(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            cache_dir = Path(tmp) / "explicit-cache"
            result = self.run_command(
                [str(PACKAGE_ROOT / "scripts" / "with-blueprint-lake-cache"), "--print-config"],
                env=self.cache_environment(
                    LAKE_CACHE_DIR=str(cache_dir),
                    LAKE_ARTIFACT_CACHE="false",
                    LAKE_RESTORE_ARTIFACTS="true",
                ),
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual(
                self.parse_config(result.stdout),
                {
                    "LAKE_CACHE_DIR": str(cache_dir),
                    "LAKE_ARTIFACT_CACHE": "false",
                    "LAKE_RESTORE_ARTIFACTS": "true",
                },
            )

    def test_lean_low_priority_exports_blueprint_lake_cache_defaults(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            cache_root = Path(tmp) / "cache"
            result = self.run_command(
                [str(PACKAGE_ROOT / "scripts" / "lean-low-priority"), "/usr/bin/env"],
                env=self.cache_environment(BP_LAKE_ARTIFACT_CACHE_ROOT=str(cache_root)),
            )

            config = self.parse_config(
                "\n".join(
                    line
                    for line in result.stdout.splitlines()
                    if line.startswith(("LAKE_CACHE_DIR=", "LAKE_ARTIFACT_CACHE=", "LAKE_RESTORE_ARTIFACTS="))
                )
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual(config["LAKE_ARTIFACT_CACHE"], "true")
            self.assertEqual(config["LAKE_RESTORE_ARTIFACTS"], "false")
            self.assertTrue(config["LAKE_CACHE_DIR"].startswith(str(cache_root)))

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
