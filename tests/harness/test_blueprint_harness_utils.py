import contextlib
import io
import os
import re
import signal
import subprocess
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.blueprint_harness_utils import run_with_heartbeat


INCLUDE_STR_RE = re.compile(r'include_str\s+"([^"]+)"')
BROWSER_ASSET_SUFFIXES = {".css", ".js", ".mjs"}


def _browser_include_assets(source_root: Path) -> set[Path]:
    assets: set[Path] = set()
    for owner in sorted(source_root.rglob("*.lean")):
        source = owner.read_text(encoding="utf-8")
        for include_path in INCLUDE_STR_RE.findall(source):
            asset = (owner.parent / include_path).resolve()
            if asset.suffix in BROWSER_ASSET_SUFFIXES:
                assets.add(asset)
    return assets


def _normalized_whitespace(source: str) -> str:
    return " ".join(source.split())


class TestBlueprintHarnessUtils(unittest.TestCase):
    def test_blueprint_browser_include_strs_are_covered_by_lake_inputs(self) -> None:
        package_root = Path(__file__).resolve().parents[2]
        source_root = package_root / "src" / "VersoBlueprint"
        math_js = (package_root / "static-web" / "math.js").resolve()
        assets = _browser_include_assets(source_root)
        missing = {asset for asset in assets if not asset.is_file()}
        uncovered = {
            asset
            for asset in assets
            if not (
                (asset.is_relative_to(source_root) and asset.suffix in BROWSER_ASSET_SUFFIXES)
                or asset == math_js
            )
        }

        self.assertTrue(assets)
        self.assertEqual(missing, set())
        self.assertEqual(uncovered, set())

        lakefile = (package_root / "lakefile.lean").read_text(encoding="utf-8")
        normalized = _normalized_whitespace(lakefile)
        self.assertIn(
            'input_dir embeddedBlueprintAssets where path := "src/VersoBlueprint" '
            'text := true filter := .extension <| .mem #["css", "js", "mjs"]',
            normalized,
        )
        self.assertIn(
            'input_file blueprintMathJs where path := "static-web/math.js" text := true',
            normalized,
        )
        library = normalized.split("lean_lib VersoBlueprint where", 1)[1].split(
            "@[default_target]", 1
        )[0]
        self.assertIn("needs := #[embeddedBlueprintAssets, blueprintMathJs]", library)

    def test_preview_showcase_browser_include_strs_are_covered_by_lake_input(self) -> None:
        package_root = Path(__file__).resolve().parents[2]
        project_root = package_root / "tests" / "test_blueprints" / "preview_runtime_showcase"
        asset_root = (project_root / "PreviewRuntimeShowcase" / "Chapters").resolve()
        assets = _browser_include_assets(asset_root)
        missing = {asset for asset in assets if not asset.is_file()}
        uncovered = {
            asset
            for asset in assets
            if not (asset.is_relative_to(asset_root) and asset.suffix == ".js")
        }

        self.assertTrue(assets)
        self.assertEqual(missing, set())
        self.assertEqual(uncovered, set())

        lakefile = (project_root / "lakefile.lean").read_text(encoding="utf-8")
        normalized = _normalized_whitespace(lakefile)
        self.assertIn(
            'input_dir previewRuntimeShowcaseAssets where path := "PreviewRuntimeShowcase/Chapters" '
            'text := true filter := .extension "js"',
            normalized,
        )
        self.assertIn("needs := #[previewRuntimeShowcaseAssets]", normalized)

    def test_run_with_heartbeat_reports_long_running_command(self) -> None:
        class FakeProcess:
            def __init__(self) -> None:
                self.wait_calls = 0

            def wait(self, timeout: int | None = None) -> int:
                self.wait_calls += 1
                if self.wait_calls == 1:
                    raise subprocess.TimeoutExpired(["slow"], timeout)
                return 0

        fake_process = FakeProcess()
        out = io.StringIO()
        with (
            patch("scripts.blueprint_harness_utils.subprocess.Popen", return_value=fake_process) as popen_mock,
            patch("scripts.blueprint_harness_utils.time.monotonic", side_effect=[0.0, 0.0, 61.0, 62.0]),
            contextlib.redirect_stdout(out),
        ):
            run_with_heartbeat(["slow"], cwd=Path("/tmp"), label="external build")

        popen_mock.assert_called_once_with(["slow"], cwd=Path("/tmp"), start_new_session=os.name == "posix")
        output = out.getvalue()
        self.assertIn("[blueprint-harness] $ slow", output)
        self.assertIn("[blueprint-harness] starting external build", output)
        self.assertIn("[blueprint-harness] still running external build after 1m01s", output)
        self.assertIn("[blueprint-harness] finished external build in 1m02s", output)

    @unittest.skipUnless(os.name == "posix", "process-group cleanup is POSIX-specific")
    def test_run_with_heartbeat_terminates_the_whole_process_group_on_interrupt(self) -> None:
        class FakeProcess:
            pid = 4242

            def __init__(self) -> None:
                self.cleanup_waits: list[int | None] = []

            def wait(self, timeout: int | None = None) -> int:
                if timeout == 60:
                    raise KeyboardInterrupt
                self.cleanup_waits.append(timeout)
                return -signal.SIGTERM

            def poll(self) -> None:
                return None

        fake_process = FakeProcess()
        with (
            patch("scripts.blueprint_harness_utils.subprocess.Popen", return_value=fake_process),
            patch("scripts.blueprint_harness_utils.os.killpg") as killpg_mock,
            self.assertRaises(KeyboardInterrupt),
        ):
            run_with_heartbeat(["slow"], cwd=Path("/tmp"), label="external build")

        killpg_mock.assert_called_once_with(fake_process.pid, signal.SIGTERM)
        self.assertEqual(fake_process.cleanup_waits, [5])
