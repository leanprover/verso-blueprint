import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.blueprint_harness_utils import rebuild_embedded_asset_owners, refresh_embedded_asset_owner_mtimes


class TestBlueprintHarnessUtils(unittest.TestCase):
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

            with patch("scripts.blueprint_harness_utils.run") as run_mock:
                rebuilt = rebuild_embedded_asset_owners(root)

            self.assertEqual(rebuilt, ["VersoBlueprint.Commands.Graph"])
            run_mock.assert_called_once()
            command = run_mock.call_args.kwargs["command"] if "command" in run_mock.call_args.kwargs else run_mock.call_args.args[0]
            self.assertEqual(command[1:3], ["lake", "build"])
            self.assertIn("VersoBlueprint.Commands.Graph", command)
            self.assertEqual(run_mock.call_args.kwargs["cwd"], root)
            self.assertFalse(cached_olean.exists())
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

            with patch("scripts.blueprint_harness_utils.run") as run_mock:
                rebuilt = rebuild_embedded_asset_owners(root)

            self.assertEqual(rebuilt, ["VersoBlueprint.Commands.Graph"])
            run_mock.assert_called_once()
