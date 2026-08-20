import contextlib
import io
import os
import signal
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.blueprint_harness_utils import (
    EMBEDDED_ASSET_OWNERS,
    EmbeddedAssetOwner,
    discover_embedded_asset_owners,
    run_with_heartbeat,
)


def _command_arg(command: list[str], option: str) -> str:
    return command[command.index(option) + 1]


class TestBlueprintHarnessUtils(unittest.TestCase):
    def test_embedded_asset_inventory_matches_browser_include_strs(self) -> None:
        package_root = Path(__file__).resolve().parents[2]

        self.assertEqual(
            set(EMBEDDED_ASSET_OWNERS),
            set(discover_embedded_asset_owners(package_root)),
        )

    def test_common_module_does_not_own_runtime_js_assets(self) -> None:
        for asset in (
            "src/VersoBlueprint/blueprint-graph-core.mjs",
            "src/VersoBlueprint/blueprint-preview-core.mjs",
            "src/VersoBlueprint/Commands/preview-runtime-base.mjs",
            "src/VersoBlueprint/Commands/preview-runtime-data.mjs",
            "src/VersoBlueprint/Commands/preview-runtime-render.mjs",
            "src/VersoBlueprint/Commands/preview-runtime-source-metadata.mjs",
            "src/VersoBlueprint/Commands/preview-runtime-hydration.mjs",
            "src/VersoBlueprint/Commands/preview-runtime-lifecycle.mjs",
            "src/VersoBlueprint/Commands/preview-runtime-surface.mjs",
            "src/VersoBlueprint/Commands/preview-runtime-template.mjs",
            "src/VersoBlueprint/Commands/preview-runtime-api.mjs",
            "src/VersoBlueprint/Commands/inline-preview.mjs",
        ):
            self.assertNotIn(
                EmbeddedAssetOwner(
                    asset,
                    "src/VersoBlueprint/Commands/Common.lean",
                    "VersoBlueprint.Commands.Common",
                ),
                EMBEDDED_ASSET_OWNERS,
            )

    def test_standalone_api_assets_are_owned_by_preview_manifest_module(self) -> None:
        for asset in (
            "src/VersoBlueprint/blueprint-graph-core.mjs",
            "src/VersoBlueprint/blueprint-preview-core.mjs",
            "src/VersoBlueprint/blueprint-api-common.mjs",
            "src/VersoBlueprint/blueprint-graph-api.mjs",
            "src/VersoBlueprint/blueprint-data-api.mjs",
            "src/VersoBlueprint/blueprint-preview-api.mjs",
            "src/VersoBlueprint/blueprint-page-runtime.mjs",
            "src/VersoBlueprint/Commands/open-target-details.mjs",
            "src/VersoBlueprint/Commands/inline-preview.mjs",
            "src/VersoBlueprint/Commands/graph-runtime-core.mjs",
            "src/VersoBlueprint/Commands/graph.mjs",
            "src/VersoBlueprint/Informal/Block/relation-panel.mjs",
            "src/VersoBlueprint/Commands/preview-runtime-base.mjs",
            "src/VersoBlueprint/Commands/preview-runtime-data.mjs",
            "src/VersoBlueprint/Commands/preview-runtime-render.mjs",
            "src/VersoBlueprint/Commands/preview-runtime-source-metadata.mjs",
            "src/VersoBlueprint/Commands/preview-runtime-hydration.mjs",
            "src/VersoBlueprint/Commands/preview-runtime-lifecycle.mjs",
            "src/VersoBlueprint/Commands/preview-runtime-surface.mjs",
            "src/VersoBlueprint/Commands/preview-runtime-template.mjs",
            "src/VersoBlueprint/Commands/preview-runtime-api.mjs",
        ):
            self.assertIn(
                EmbeddedAssetOwner(
                    asset,
                    "src/VersoBlueprint/PreviewManifest.lean",
                    "VersoBlueprint.PreviewManifest",
                ),
                EMBEDDED_ASSET_OWNERS,
            )

    def test_graph_js_assets_are_owned_by_graph_module(self) -> None:
        for asset in (
            "src/VersoBlueprint/Commands/graph.css",
        ):
            self.assertIn(
                EmbeddedAssetOwner(
                    asset,
                    "src/VersoBlueprint/Commands/Graph.lean",
                    "VersoBlueprint.Commands.Graph",
                ),
                EMBEDDED_ASSET_OWNERS,
            )

    def test_slide_esm_assets_are_owned_by_slide_assets_module(self) -> None:
        for asset, owner, target in (
            (
                "src/VersoBlueprint/Slides/blueprint-slides.mjs",
                "src/VersoBlueprint/Slides/Assets.lean",
                "VersoBlueprint.Slides.Assets",
            ),
            (
                "src/VersoBlueprint/Slides/blueprint-slide-runtime.mjs",
                "src/VersoBlueprint/Slides/Assets.lean",
                "VersoBlueprint.Slides.Assets",
            ),
        ):
            self.assertIn(EmbeddedAssetOwner(asset, owner, target), EMBEDDED_ASSET_OWNERS)

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
