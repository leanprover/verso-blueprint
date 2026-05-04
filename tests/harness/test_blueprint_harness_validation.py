from __future__ import annotations

from pathlib import Path
import sys
import unittest

from scripts.blueprint_harness_validation import (
    UV_CACHE_DIR,
    browser_test_command,
    panel_regression_command,
    resolve_package_relative_path,
)
import scripts.blueprint_harness_validation as validation_mod


PACKAGE_ROOT = Path(__file__).resolve().parents[2]


class HarnessValidationCommandTests(unittest.TestCase):
    def test_resolve_package_relative_path_preserves_absolute_paths(self) -> None:
        self.assertEqual(
            resolve_package_relative_path(PACKAGE_ROOT, "/tmp/check.py"),
            Path("/tmp/check.py"),
        )
        self.assertEqual(
            resolve_package_relative_path(PACKAGE_ROOT, "tests/browser"),
            PACKAGE_ROOT / "tests/browser",
        )

    def test_panel_regression_command_targets_site_dir(self) -> None:
        site_dir = Path("/tmp/out/test-blueprints/runtime-showcase/html-multi")

        self.assertEqual(
            panel_regression_command(PACKAGE_ROOT, "tests/harness/runtime/check.py", site_dir),
            [
                sys.executable,
                str(PACKAGE_ROOT / "tests/harness/runtime/check.py"),
                "--site-dir",
                str(site_dir),
            ],
        )

    def test_browser_test_command_uses_python_pytest_without_uv(self) -> None:
        site_dir = Path("/tmp/out/test-blueprints/runtime-showcase/html-multi")
        original_which = validation_mod.shutil.which
        try:
            validation_mod.shutil.which = lambda _name: None

            self.assertEqual(
                browser_test_command(PACKAGE_ROOT, "tests/browser", site_dir, ["-k", "preview"]),
                [
                    sys.executable,
                    "-m",
                    "pytest",
                    str(PACKAGE_ROOT / "tests/browser"),
                    "-q",
                    "--browser",
                    "chromium",
                    "--site-dir",
                    str(site_dir),
                    "-k",
                    "preview",
                ],
            )
        finally:
            validation_mod.shutil.which = original_which

    def test_browser_test_command_uses_uv_project_when_available(self) -> None:
        site_dir = Path("/tmp/out/test-blueprints/runtime-showcase/html-multi")
        original_which = validation_mod.shutil.which
        try:
            validation_mod.shutil.which = lambda _name: "/usr/bin/uv"

            self.assertEqual(
                browser_test_command(PACKAGE_ROOT, "tests/browser", site_dir, []),
                [
                    "env",
                    f"UV_CACHE_DIR={UV_CACHE_DIR}",
                    "uv",
                    "run",
                    "--project",
                    str(PACKAGE_ROOT / "tests/browser"),
                    "--extra",
                    "test",
                    "python",
                    "-m",
                    "pytest",
                    str(PACKAGE_ROOT / "tests/browser"),
                    "-q",
                    "--browser",
                    "chromium",
                    "--site-dir",
                    str(site_dir),
                ],
            )
        finally:
            validation_mod.shutil.which = original_which


if __name__ == "__main__":
    unittest.main()
