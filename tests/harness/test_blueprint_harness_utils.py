import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.blueprint_harness_utils import (
    EMBEDDED_ASSET_OWNERS,
    EmbeddedAssetOwner,
    discover_embedded_asset_owners,
    ensure_embedded_asset_owner_outputs,
    rebuild_embedded_asset_owners,
    refresh_embedded_asset_owner_mtimes,
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

    def test_common_js_assets_are_owned_by_common_module(self) -> None:
        for asset in (
            "src/VersoBlueprint/Commands/open-target-details.js",
            "src/VersoBlueprint/Commands/preview-ready.js",
            "src/VersoBlueprint/Commands/preview-runtime.js",
            "src/VersoBlueprint/Commands/inline-preview.js",
        ):
            self.assertIn(
                EmbeddedAssetOwner(
                    asset,
                    "src/VersoBlueprint/Commands/Common.lean",
                    "VersoBlueprint.Commands.Common",
                ),
                EMBEDDED_ASSET_OWNERS,
            )

    def test_preview_client_js_assets_are_owned_by_rendering_modules(self) -> None:
        for asset, owner, target in (
            (
                "src/VersoBlueprint/Informal/Block/relation-panel.js",
                "src/VersoBlueprint/Informal/Block/Assets.lean",
                "VersoBlueprint.Informal.Block.Assets",
            ),
        ):
            self.assertIn(EmbeddedAssetOwner(asset, owner, target), EMBEDDED_ASSET_OWNERS)

    def test_refresh_embedded_asset_owner_mtimes_touches_owner_when_asset_is_newer(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            asset = root / "src" / "VersoBlueprint" / "Commands" / "graph.css"
            owner = root / "src" / "VersoBlueprint" / "Commands" / "Graph.lean"
            owner.parent.mkdir(parents=True, exist_ok=True)
            asset.write_text("/* css */", encoding="utf-8")
            owner.write_text("-- lean", encoding="utf-8")

            now = time.time()
            os.utime(owner, (now - 10, now - 10))
            os.utime(asset, (now, now))

            touched = refresh_embedded_asset_owner_mtimes(root)

            self.assertEqual(touched, [owner])
            self.assertGreaterEqual(owner.stat().st_mtime_ns, asset.stat().st_mtime_ns)

    def test_refresh_embedded_asset_owner_mtimes_skips_owner_when_asset_is_not_newer(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            asset = root / "src" / "VersoBlueprint" / "Commands" / "graph.css"
            owner = root / "src" / "VersoBlueprint" / "Commands" / "Graph.lean"
            owner.parent.mkdir(parents=True, exist_ok=True)
            asset.write_text("/* css */", encoding="utf-8")
            owner.write_text("-- lean", encoding="utf-8")

            now = time.time()
            os.utime(asset, (now - 10, now - 10))
            os.utime(owner, (now, now))
            original_owner_time = owner.stat().st_mtime_ns

            touched = refresh_embedded_asset_owner_mtimes(root)

            self.assertEqual(touched, [])
            self.assertEqual(owner.stat().st_mtime_ns, original_owner_time)

    def test_rebuild_embedded_asset_owners_runs_targeted_root_build(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            asset = root / "src" / "VersoBlueprint" / "Commands" / "graph.css"
            owner = root / "src" / "VersoBlueprint" / "Commands" / "Graph.lean"
            cached_olean = root / ".lake" / "build" / "lib" / "lean" / "VersoBlueprint" / "Commands" / "Graph.olean"
            cached_ir = root / ".lake" / "build" / "ir" / "VersoBlueprint" / "Commands" / "Graph.c"
            owner.parent.mkdir(parents=True, exist_ok=True)
            cached_olean.parent.mkdir(parents=True, exist_ok=True)
            cached_ir.parent.mkdir(parents=True, exist_ok=True)
            asset.write_text("/* css */", encoding="utf-8")
            owner.write_text("-- lean", encoding="utf-8")
            cached_olean.write_text("stale", encoding="utf-8")
            cached_ir.write_text("stale", encoding="utf-8")

            now = time.time()
            os.utime(owner, (now - 10, now - 10))
            os.utime(asset, (now, now))

            def fake_run(command: list[str], *, cwd: Path) -> None:
                self.assertEqual(cwd, root)
                cached_olean.write_text("fresh", encoding="utf-8")

            with (
                patch("scripts.blueprint_harness_utils.run", side_effect=fake_run) as run_mock,
                patch("scripts.blueprint_harness_utils.run_output", return_value=""),
            ):
                rebuilt = rebuild_embedded_asset_owners(root)

            self.assertEqual(rebuilt, ["VersoBlueprint.Commands.Graph"])
            run_mock.assert_called_once()
            command = run_mock.call_args.kwargs["command"] if "command" in run_mock.call_args.kwargs else run_mock.call_args.args[0]
            self.assertEqual(command[1:3], ["lake", "build"])
            self.assertIn("VersoBlueprint.Commands.Graph", command)
            self.assertEqual(run_mock.call_args.kwargs["cwd"], root)
            self.assertEqual(cached_olean.read_text(encoding="utf-8"), "fresh")
            self.assertFalse(cached_ir.exists())

    def test_rebuild_embedded_asset_owners_runs_even_when_owner_is_newer(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            asset = root / "src" / "VersoBlueprint" / "Commands" / "graph.css"
            owner = root / "src" / "VersoBlueprint" / "Commands" / "Graph.lean"
            owner.parent.mkdir(parents=True, exist_ok=True)
            asset.write_text("/* css */", encoding="utf-8")
            owner.write_text("-- lean", encoding="utf-8")

            now = time.time()
            os.utime(asset, (now - 10, now - 10))
            os.utime(owner, (now, now))

            cached_olean = root / ".lake" / "build" / "lib" / "lean" / "VersoBlueprint" / "Commands" / "Graph.olean"
            cached_olean.parent.mkdir(parents=True, exist_ok=True)

            def fake_run(command: list[str], *, cwd: Path) -> None:
                self.assertEqual(cwd, root)
                cached_olean.write_text("fresh", encoding="utf-8")

            with (
                patch("scripts.blueprint_harness_utils.run", side_effect=fake_run) as run_mock,
                patch("scripts.blueprint_harness_utils.run_output", return_value=""),
            ):
                rebuilt = rebuild_embedded_asset_owners(root)

            self.assertEqual(rebuilt, ["VersoBlueprint.Commands.Graph"])
            run_mock.assert_called_once()
            self.assertEqual(cached_olean.read_text(encoding="utf-8"), "fresh")

    def test_rebuild_embedded_asset_owners_materializes_missing_owner_olean(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            asset = root / "src" / "VersoBlueprint" / "Commands" / "graph.css"
            owner = root / "src" / "VersoBlueprint" / "Commands" / "Graph.lean"
            cached_olean = root / ".lake" / "build" / "lib" / "lean" / "VersoBlueprint" / "Commands" / "Graph.olean"
            cached_ilean = root / ".lake" / "build" / "lib" / "lean" / "VersoBlueprint" / "Commands" / "Graph.ilean"
            cached_ilean_hash = cached_ilean.with_suffix(".ilean.hash")
            cached_trace = cached_ilean.with_suffix(".trace")
            cached_c = root / ".lake" / "build" / "ir" / "VersoBlueprint" / "Commands" / "Graph.c"
            owner.parent.mkdir(parents=True, exist_ok=True)
            cached_ilean.parent.mkdir(parents=True, exist_ok=True)
            cached_c.parent.mkdir(parents=True, exist_ok=True)
            asset.write_text("/* css */", encoding="utf-8")
            owner.write_text("-- lean", encoding="utf-8")
            cached_ilean.write_text("fetched ilean", encoding="utf-8")
            cached_ilean_hash.write_text("old hash", encoding="utf-8")
            cached_trace.write_text("synthetic trace", encoding="utf-8")

            def fake_run(command: list[str], *, cwd: Path) -> None:
                self.assertEqual(cwd, root)
                if command[1:4] == ["lake", "env", "lean"]:
                    cached_olean.write_text("fresh", encoding="utf-8")
                    cached_ilean.write_text("fresh ilean", encoding="utf-8")
                    cached_c.write_text("fresh c", encoding="utf-8")

            with (
                patch("scripts.blueprint_harness_utils.run", side_effect=fake_run) as run_mock,
                patch("scripts.blueprint_harness_utils.run_output", return_value=""),
            ):
                rebuilt = rebuild_embedded_asset_owners(root)

            self.assertEqual(rebuilt, ["VersoBlueprint.Commands.Graph"])
            self.assertEqual(run_mock.call_count, 2)
            lake_command = run_mock.call_args_list[0].args[0]
            lean_command = run_mock.call_args_list[1].args[0]
            self.assertEqual(lake_command[1:3], ["lake", "build"])
            self.assertEqual(lean_command[1:4], ["lake", "env", "lean"])
            self.assertIn("-Dexperimental.module=true", lean_command)
            self.assertEqual(_command_arg(lean_command, "-R"), "src")
            self.assertEqual(
                _command_arg(lean_command, "-o"),
                ".lake/build/lib/lean/VersoBlueprint/Commands/Graph.olean",
            )
            self.assertEqual(
                _command_arg(lean_command, "-i"),
                ".lake/build/lib/lean/VersoBlueprint/Commands/Graph.ilean",
            )
            self.assertEqual(
                _command_arg(lean_command, "-c"),
                ".lake/build/ir/VersoBlueprint/Commands/Graph.c",
            )
            self.assertEqual(lean_command[-1], "src/VersoBlueprint/Commands/Graph.lean")
            self.assertEqual(cached_olean.read_text(encoding="utf-8"), "fresh")
            self.assertEqual(cached_ilean.read_text(encoding="utf-8"), "fresh ilean")
            self.assertFalse(cached_ilean_hash.exists())
            self.assertFalse(cached_trace.exists())

    def test_rebuild_embedded_asset_owners_materializes_missing_owner_deps(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            asset = root / "src" / "VersoBlueprint" / "Commands" / "summary.css"
            owner = root / "src" / "VersoBlueprint" / "Commands" / "Summary.lean"
            dep_source = root / "src" / "VersoBlueprint" / "Commands" / "Summary" / "Data.lean"
            owner_olean = root / ".lake" / "build" / "lib" / "lean" / "VersoBlueprint" / "Commands" / "Summary.olean"
            dep_olean = root / ".lake" / "build" / "lib" / "lean" / "VersoBlueprint" / "Commands" / "Summary" / "Data.olean"
            owner.parent.mkdir(parents=True, exist_ok=True)
            dep_source.parent.mkdir(parents=True, exist_ok=True)
            dep_olean.parent.mkdir(parents=True, exist_ok=True)
            asset.write_text("/* css */", encoding="utf-8")
            owner.write_text("-- lean", encoding="utf-8")
            dep_source.write_text("-- lean", encoding="utf-8")

            def fake_run(command: list[str], *, cwd: Path) -> None:
                self.assertEqual(cwd, root)
                if command[-1] == "src/VersoBlueprint/Commands/Summary/Data.lean":
                    dep_olean.write_text("fresh dep", encoding="utf-8")
                elif command[-1] == "src/VersoBlueprint/Commands/Summary.lean":
                    owner_olean.write_text("fresh owner", encoding="utf-8")

            def fake_run_output(command: list[str], *, cwd: Path) -> str:
                self.assertEqual(cwd, root)
                if command[-1] == "src/VersoBlueprint/Commands/Summary.lean":
                    return str(dep_olean) + "\n" + str(dep_olean) + "\n"
                return ""

            with (
                patch("scripts.blueprint_harness_utils.run", side_effect=fake_run) as run_mock,
                patch("scripts.blueprint_harness_utils.run_output", side_effect=fake_run_output) as deps_mock,
            ):
                rebuilt = rebuild_embedded_asset_owners(root)

            self.assertEqual(rebuilt, ["VersoBlueprint.Commands.Summary"])
            self.assertEqual(run_mock.call_count, 3)
            self.assertEqual(deps_mock.call_count, 2)
            dep_command = run_mock.call_args_list[1].args[0]
            owner_command = run_mock.call_args_list[2].args[0]
            self.assertEqual(dep_command[1:4], ["lake", "env", "lean"])
            self.assertEqual(owner_command[1:4], ["lake", "env", "lean"])
            self.assertEqual(dep_command[-1], "src/VersoBlueprint/Commands/Summary/Data.lean")
            self.assertEqual(owner_command[-1], "src/VersoBlueprint/Commands/Summary.lean")
            self.assertEqual(dep_olean.read_text(encoding="utf-8"), "fresh dep")
            self.assertEqual(owner_olean.read_text(encoding="utf-8"), "fresh owner")

    def test_ensure_embedded_asset_owner_outputs_materializes_without_lake_build(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            asset = root / "static-web" / "math.js"
            owner = root / "src" / "VersoBlueprint" / "Macros.lean"
            owner_olean = root / ".lake" / "build" / "lib" / "lean" / "VersoBlueprint" / "Macros.olean"
            owner.parent.mkdir(parents=True, exist_ok=True)
            asset.parent.mkdir(parents=True, exist_ok=True)
            owner_olean.parent.mkdir(parents=True, exist_ok=True)
            asset.write_text("// js", encoding="utf-8")
            owner.write_text("-- lean", encoding="utf-8")

            def fake_run(command: list[str], *, cwd: Path) -> None:
                self.assertEqual(cwd, root)
                self.assertEqual(command[1:4], ["lake", "env", "lean"])
                owner_olean.write_text("fresh", encoding="utf-8")

            with (
                patch("scripts.blueprint_harness_utils.run", side_effect=fake_run) as run_mock,
                patch("scripts.blueprint_harness_utils.run_output", return_value="") as deps_mock,
            ):
                materialized = ensure_embedded_asset_owner_outputs(root)

            self.assertEqual(materialized, ["VersoBlueprint.Macros"])
            run_mock.assert_called_once()
            deps_mock.assert_called_once()
            command = run_mock.call_args.args[0]
            self.assertEqual(command[-1], "src/VersoBlueprint/Macros.lean")
            self.assertEqual(owner_olean.read_text(encoding="utf-8"), "fresh")

    def test_rebuild_embedded_asset_owners_rebuilds_slide_asset_owner_once(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            css = root / "src" / "VersoBlueprint" / "Slides" / "blueprint-slides.css"
            js = root / "src" / "VersoBlueprint" / "Slides" / "blueprint-slides.js"
            owner = root / "src" / "VersoBlueprint" / "Slides" / "Assets.lean"
            cached_olean = root / ".lake" / "build" / "lib" / "lean" / "VersoBlueprint" / "Slides" / "Assets.olean"
            cached_ir = root / ".lake" / "build" / "ir" / "VersoBlueprint" / "Slides" / "Assets.c"
            owner.parent.mkdir(parents=True, exist_ok=True)
            cached_olean.parent.mkdir(parents=True, exist_ok=True)
            cached_ir.parent.mkdir(parents=True, exist_ok=True)
            css.write_text("/* css */", encoding="utf-8")
            js.write_text("// js", encoding="utf-8")
            owner.write_text("-- lean", encoding="utf-8")
            cached_olean.write_text("stale", encoding="utf-8")
            cached_ir.write_text("stale", encoding="utf-8")

            def fake_run(command: list[str], *, cwd: Path) -> None:
                self.assertEqual(cwd, root)
                cached_olean.write_text("fresh", encoding="utf-8")

            with patch("scripts.blueprint_harness_utils.run", side_effect=fake_run) as run_mock:
                rebuilt = rebuild_embedded_asset_owners(root)

            self.assertEqual(rebuilt, ["VersoBlueprint.Slides.Assets"])
            run_mock.assert_called_once()
            command = run_mock.call_args.kwargs["command"] if "command" in run_mock.call_args.kwargs else run_mock.call_args.args[0]
            self.assertEqual(command.count("VersoBlueprint.Slides.Assets"), 1)
            self.assertEqual(cached_olean.read_text(encoding="utf-8"), "fresh")
            self.assertFalse(cached_ir.exists())
