from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import scripts.blueprint_harness_composition as composition


class BlueprintHarnessCompositionTests(unittest.TestCase):
    def _make_composed_project(
        self,
        root: Path,
    ) -> tuple[Path, composition.ComposedBlueprint, Path, Path, str, str]:
        package_root = root / "verso-blueprint"
        source_root = root / "source"
        project_dir = source_root / "blueprint"
        package_root.mkdir()
        project_dir.mkdir(parents=True)
        lakefile = project_dir / "lakefile.lean"
        manifest = project_dir / "lake-manifest.json"
        lakefile_text = 'require VersoBlueprint from "../../verso-blueprint"\n'
        manifest_text = '{"packages": []}\n'
        lakefile.write_text(lakefile_text, encoding="utf-8")
        manifest.write_text(manifest_text, encoding="utf-8")
        project = composition.ComposedBlueprint(
            "demo",
            source_root,
            project_dir,
            root / "out" / "demo",
        )
        return package_root, project, lakefile, manifest, lakefile_text, manifest_text

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
            project = composition.ComposedBlueprint("demo", source_root, project_dir, root / "out")

            self.assertEqual(composition.validate_composed_toolchain(package_root, project), "v4.32.0")

    def test_validate_toolchain_rejects_missing_and_mismatched_project_toolchain(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package_root = root / "verso-blueprint"
            source_root = root / "source"
            project_dir = source_root / "blueprint"
            package_root.mkdir()
            project_dir.mkdir(parents=True)
            (package_root / "lean-toolchain").write_text("leanprover/lean4:v4.32.0\n", encoding="utf-8")
            project_toolchain = source_root / "lean-toolchain"
            project_toolchain.write_text("leanprover/lean4:v4.31.0\n", encoding="utf-8")
            project = composition.ComposedBlueprint("demo", source_root, project_dir, root / "out")

            with self.assertRaisesRegex(SystemExit, "toolchain mismatch"):
                composition.validate_composed_toolchain(package_root, project)

            project_toolchain.unlink()
            with self.assertRaisesRegex(SystemExit, "no valid lean-toolchain"):
                composition.validate_composed_toolchain(package_root, project)

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

    def test_compose_orders_steps_and_preserves_lake_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package_root, project, lakefile, manifest, lakefile_text, manifest_text = (
                self._make_composed_project(root)
            )
            project.output_dir.mkdir(parents=True)
            stale_output = project.output_dir / "stale.html"
            stale_output.write_text("old", encoding="utf-8")
            commands: list[list[str]] = []
            events: list[str] = []

            def fake_update(*_args, **_kwargs) -> None:
                events.append("update")
                manifest.write_text("changed", encoding="utf-8")

            def fake_cache(*_args, **_kwargs) -> bool:
                events.append("cache")
                return False

            def fake_owner_outputs(*_args, **_kwargs) -> list[str]:
                events.append("owner outputs")
                return []

            def fake_run(command: list[str], **_kwargs) -> None:
                commands.append(command)
                events.append("build" if "build" in command else "check")

            with patch.multiple(
                composition,
                validate_composed_toolchain=lambda *_args, **_kwargs: "v4.32.0",
                rebuild_and_log_embedded_asset_owners=lambda *_args, **_kwargs: [],
                run_project_lake_update=fake_update,
                ensure_composed_mathlib_cache=fake_cache,
                ensure_and_log_embedded_asset_owner_outputs=fake_owner_outputs,
                run_with_heartbeat=fake_run,
            ):
                composition.compose_blueprint(package_root, project)

            self.assertEqual(lakefile.read_text(encoding="utf-8"), lakefile_text)
            self.assertEqual(manifest.read_text(encoding="utf-8"), manifest_text)
            self.assertFalse(stale_output.exists())
            self.assertEqual(events, ["update", "cache", "owner outputs", "build", "check"])
            self.assertEqual(
                commands,
                [
                    [
                        str(package_root / "scripts/lean-low-priority"),
                        "lake",
                        "exe",
                        "vbp",
                        "build",
                        "--output",
                        str(project.output_dir),
                    ],
                    [
                        str(package_root / "scripts/lean-low-priority"),
                        "lake",
                        "exe",
                        "vbp",
                        "check",
                        "--site",
                        str(project.output_dir),
                    ],
                ],
            )

    def test_compose_restores_lake_files_when_build_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package_root, project, lakefile, manifest, lakefile_text, manifest_text = (
                self._make_composed_project(root)
            )

            def fake_update(*_args, **_kwargs) -> None:
                manifest.write_text("changed", encoding="utf-8")

            def fail_build(command: list[str], **_kwargs) -> None:
                if "build" in command:
                    raise RuntimeError("build failed")

            with patch.multiple(
                composition,
                validate_composed_toolchain=lambda *_args, **_kwargs: "v4.32.0",
                rebuild_and_log_embedded_asset_owners=lambda *_args, **_kwargs: [],
                run_project_lake_update=fake_update,
                ensure_composed_mathlib_cache=lambda *_args, **_kwargs: False,
                ensure_and_log_embedded_asset_owner_outputs=lambda *_args, **_kwargs: [],
                run_with_heartbeat=fail_build,
            ):
                with self.assertRaisesRegex(RuntimeError, "build failed"):
                    composition.compose_blueprint(package_root, project)

            self.assertEqual(lakefile.read_text(encoding="utf-8"), lakefile_text)
            self.assertEqual(manifest.read_text(encoding="utf-8"), manifest_text)


if __name__ == "__main__":
    unittest.main()
