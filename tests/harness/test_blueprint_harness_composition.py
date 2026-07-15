from __future__ import annotations

from contextlib import contextmanager
import json
from pathlib import Path
import tempfile
import unittest

import scripts.blueprint_harness_composition as composition


class BlueprintHarnessCompositionTests(unittest.TestCase):
    def test_resolve_nested_composed_blueprint(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            source_root = Path(tmp) / "demo-source"
            project_dir = source_root / "nested" / "blueprint"
            project_dir.mkdir(parents=True)
            (project_dir / "lakefile.lean").write_text("import Lake\n", encoding="utf-8")

            project = composition.resolve_composed_blueprint(
                source_root,
                "nested/blueprint",
                Path(tmp) / "out",
                project_id=None,
            )

            self.assertEqual(project.project_id, "demo-source")
            self.assertEqual(project.project_dir, project_dir.resolve())
            self.assertEqual(project.output_dir, (Path(tmp) / "out" / "demo-source").resolve())

    def test_resolve_rejects_project_root_escape(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            source_root = Path(tmp) / "source"
            source_root.mkdir()
            with self.assertRaisesRegex(SystemExit, "stay inside"):
                composition.resolve_composed_blueprint(
                    source_root,
                    "../other",
                    Path(tmp) / "out",
                    project_id="demo",
                )

    def test_validate_toolchain_accepts_source_root_inheritance(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package_root = root / "verso-blueprint"
            source_root = root / "source"
            project_dir = source_root / "blueprint"
            package_root.mkdir()
            project_dir.mkdir(parents=True)
            (package_root / "lean-toolchain").write_text("leanprover/lean4:v4.32.0\n", encoding="utf-8")
            (source_root / "lean-toolchain").write_text("leanprover/lean4:v4.32.0\n", encoding="utf-8")
            project = composition.ComposedBlueprint("demo", source_root, project_dir, root / "out", root / "out/html-multi")

            self.assertEqual(composition.validate_composed_toolchain(package_root, project), "v4.32.0")

    def test_manifest_uses_mathlib(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "lake-manifest.json"
            manifest.write_text(json.dumps({"packages": [{"name": "mathlib"}]}), encoding="utf-8")
            self.assertTrue(composition.manifest_uses_mathlib(manifest))

            manifest.write_text(json.dumps({"packages": [{"name": "verso"}]}), encoding="utf-8")
            self.assertFalse(composition.manifest_uses_mathlib(manifest))

    def test_mathlib_dependency_requires_cache_get(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package_root = root / "verso-blueprint"
            project_dir = root / "project"
            package_root.mkdir()
            project_dir.mkdir()
            (project_dir / "lake-manifest.json").write_text(
                json.dumps({"packages": [{"name": "mathlib"}]}),
                encoding="utf-8",
            )
            commands: list[list[str]] = []
            original = composition.run_with_heartbeat
            try:
                composition.run_with_heartbeat = lambda command, **_kwargs: commands.append(command)
                self.assertTrue(composition.ensure_composed_mathlib_cache(package_root, project_dir))
            finally:
                composition.run_with_heartbeat = original

            self.assertEqual(commands, [[str(package_root / "scripts/lean-low-priority"), "lake", "exe", "cache", "get"]])

    def test_preserve_file_restores_existing_and_removes_generated(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            existing = Path(tmp) / "existing"
            generated = Path(tmp) / "generated"
            existing.write_text("before", encoding="utf-8")

            with composition.preserve_file(existing):
                existing.write_text("during", encoding="utf-8")
            with composition.preserve_file(generated):
                generated.write_text("during", encoding="utf-8")

            self.assertEqual(existing.read_text(encoding="utf-8"), "before")
            self.assertFalse(generated.exists())

    def test_compose_builds_and_checks_while_preserving_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package_root = root / "verso-blueprint"
            source_root = root / "source"
            project_dir = source_root / "blueprint"
            package_root.mkdir()
            project_dir.mkdir(parents=True)
            lakefile = project_dir / "lakefile.lean"
            manifest = project_dir / "lake-manifest.json"
            lakefile.write_text('require VersoBlueprint from "../../verso-blueprint"\n', encoding="utf-8")
            manifest.write_text('{"packages": []}\n', encoding="utf-8")
            project = composition.ComposedBlueprint(
                "demo",
                source_root,
                project_dir,
                root / "out" / "demo",
                root / "out" / "demo" / "html-multi",
            )
            project.output_dir.mkdir(parents=True)
            stale_output = project.output_dir / "stale.html"
            stale_output.write_text("old", encoding="utf-8")
            commands: list[list[str]] = []

            @contextmanager
            def fake_override(*_args, **_kwargs):
                yield lakefile

            originals = {
                "validate_composed_toolchain": composition.validate_composed_toolchain,
                "rebuild_and_log_embedded_asset_owners": composition.rebuild_and_log_embedded_asset_owners,
                "local_blueprint_dependency_override": composition.local_blueprint_dependency_override,
                "run_project_lake_update": composition.run_project_lake_update,
                "ensure_composed_mathlib_cache": composition.ensure_composed_mathlib_cache,
                "ensure_and_log_embedded_asset_owner_outputs": composition.ensure_and_log_embedded_asset_owner_outputs,
                "run_with_heartbeat": composition.run_with_heartbeat,
            }
            try:
                composition.validate_composed_toolchain = lambda *_args, **_kwargs: "leanprover/lean4:v4.32.0"
                composition.rebuild_and_log_embedded_asset_owners = lambda *_args, **_kwargs: []
                composition.local_blueprint_dependency_override = fake_override
                composition.run_project_lake_update = lambda *_args, **_kwargs: manifest.write_text("changed", encoding="utf-8")
                composition.ensure_composed_mathlib_cache = lambda *_args, **_kwargs: False
                composition.ensure_and_log_embedded_asset_owner_outputs = lambda *_args, **_kwargs: []
                composition.run_with_heartbeat = lambda command, **_kwargs: commands.append(command)
                composition.compose_blueprint(package_root, project)
            finally:
                for name, value in originals.items():
                    setattr(composition, name, value)

            self.assertEqual(manifest.read_text(encoding="utf-8"), '{"packages": []}\n')
            self.assertFalse(stale_output.exists())
            self.assertIn([str(package_root / "scripts/lean-low-priority"), "lake", "exe", "vbp", "build", "--output", str(project.output_dir)], commands)
            self.assertIn([str(package_root / "scripts/lean-low-priority"), "lake", "exe", "vbp", "check", "--site", str(project.output_dir)], commands)


if __name__ == "__main__":
    unittest.main()
