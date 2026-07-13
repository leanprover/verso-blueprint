from __future__ import annotations

from pathlib import Path
import subprocess
import tempfile
import unittest

from scripts.blueprint_harness_project_commands import (
    OFFICIAL_BLUEPRINT_REQUIRE,
    discard_untracked_project_manifest,
    project_lake_update_command,
    rewrite_local_blueprint_dependency,
    rewrite_pinned_blueprint_dependency,
    run_project_update_build_generate,
    tracked_project_manifest_path,
)


PACKAGE_ROOT = Path(__file__).resolve().parents[2]
VBP_BUILD_COMMAND = ("lake", "exe", "vbp", "build")


class BlueprintHarnessProjectCommandTests(unittest.TestCase):
    def init_git_repo(self, root: Path) -> None:
        subprocess.run(["git", "init"], cwd=root, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def test_rewrite_local_blueprint_dependency_replaces_official_git_require(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project_dir = Path(tmp)
            lakefile = project_dir / "lakefile.lean"
            lakefile.write_text(
                "\n".join(
                    [
                        "import Lake",
                        "open Lake DSL",
                        OFFICIAL_BLUEPRINT_REQUIRE,
                        "",
                    ]
                ),
                encoding="utf-8",
            )

            result = rewrite_local_blueprint_dependency(project_dir, PACKAGE_ROOT)

            self.assertEqual(result, lakefile)
            text = lakefile.read_text(encoding="utf-8")
            self.assertNotIn(OFFICIAL_BLUEPRINT_REQUIRE, text)
            self.assertIn('require VersoBlueprint from "', text)

    def test_rewrite_local_blueprint_dependency_accepts_official_repo_with_non_main_ref(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project_dir = Path(tmp)
            lakefile = project_dir / "lakefile.lean"
            lakefile.write_text(
                'require VersoBlueprint from git "https://github.com/leanprover/verso-blueprint.git"@"v1.2.3"\n',
                encoding="utf-8",
            )

            rewrite_local_blueprint_dependency(project_dir, PACKAGE_ROOT)

            text = lakefile.read_text(encoding="utf-8")
            self.assertIn('require VersoBlueprint from "', text)
            self.assertNotIn('from git "https://github.com/leanprover/verso-blueprint.git"', text)

    def test_rewrite_local_blueprint_dependency_disables_mathlib_header_linter(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project_dir = Path(tmp)
            lakefile = project_dir / "lakefile.lean"
            lakefile.write_text(
                "\n".join(
                    [
                        "import Lake",
                        "open Lake DSL",
                        OFFICIAL_BLUEPRINT_REQUIRE,
                        "",
                        "package Blueprint where",
                        "  leanOptions := #[",
                        "    ⟨`autoImplicit, false⟩,",
                        "    ⟨`weak.linter.mathlibStandardSet, true⟩",
                        "  ]",
                        "",
                    ]
                ),
                encoding="utf-8",
            )

            rewrite_local_blueprint_dependency(project_dir, PACKAGE_ROOT)

            text = lakefile.read_text(encoding="utf-8")
            self.assertIn("    ⟨`weak.linter.style.header, false⟩,\n", text)
            self.assertIn("    ⟨`weak.linter.mathlibStandardSet, true⟩\n", text)

    def test_rewrite_local_blueprint_dependency_does_not_duplicate_header_linter_option(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project_dir = Path(tmp)
            lakefile = project_dir / "lakefile.lean"
            lakefile.write_text(
                "\n".join(
                    [
                        OFFICIAL_BLUEPRINT_REQUIRE,
                        "package Blueprint where",
                        "  leanOptions := #[",
                        "    ⟨`weak.linter.style.header, false⟩,",
                        "    ⟨`weak.linter.mathlibStandardSet, true⟩",
                        "  ]",
                        "",
                    ]
                ),
                encoding="utf-8",
            )

            rewrite_local_blueprint_dependency(project_dir, PACKAGE_ROOT)

            text = lakefile.read_text(encoding="utf-8")
            self.assertEqual(text.count("`weak.linter.style.header"), 1)

    def test_rewrite_local_blueprint_dependency_rejects_unofficial_source(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project_dir = Path(tmp)
            lakefile = project_dir / "lakefile.lean"
            lakefile.write_text(
                'require VersoBlueprint from git "https://github.com/example/verso-blueprint.git"@"v1.2.3"\n',
                encoding="utf-8",
            )

            with self.assertRaisesRegex(SystemExit, "approved `VersoBlueprint` Git source"):
                rewrite_local_blueprint_dependency(project_dir, PACKAGE_ROOT)

    def test_rewrite_local_blueprint_dependency_rejects_unexpected_require_shape(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project_dir = Path(tmp)
            lakefile = project_dir / "lakefile.lean"
            lakefile.write_text(
                'require VersoBlueprint from git "https://github.com/example/fork"@"main"\n',
                encoding="utf-8",
            )

            with self.assertRaisesRegex(SystemExit, "approved `VersoBlueprint` Git source"):
                rewrite_local_blueprint_dependency(project_dir, PACKAGE_ROOT)

    def test_rewrite_pinned_blueprint_dependency_updates_ref_and_preserves_repo_url(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project_dir = Path(tmp)
            lakefile = project_dir / "lakefile.lean"
            lakefile.write_text(
                'require VersoBlueprint from git "https://github.com/leanprover/verso-blueprint.git"@"old-ref"\n',
                encoding="utf-8",
            )

            result_path, previous_ref = rewrite_pinned_blueprint_dependency(project_dir, "v1.2.3")

            self.assertEqual(result_path, lakefile)
            self.assertEqual(previous_ref, "old-ref")
            self.assertEqual(
                lakefile.read_text(encoding="utf-8").strip(),
                'require VersoBlueprint from git "https://github.com/leanprover/verso-blueprint.git"@"v1.2.3"',
            )

    def test_tracked_project_manifest_path_accepts_git_tracked_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project_dir = Path(tmp)
            self.init_git_repo(project_dir)
            manifest = project_dir / "lake-manifest.json"
            manifest.write_text("{}\n", encoding="utf-8")
            subprocess.run(
                ["git", "add", "lake-manifest.json"],
                cwd=project_dir,
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

            self.assertEqual(tracked_project_manifest_path(project_dir), manifest)

    def test_tracked_project_manifest_path_ignores_untracked_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project_dir = Path(tmp)
            self.init_git_repo(project_dir)
            manifest = project_dir / "lake-manifest.json"
            manifest.write_text("{}\n", encoding="utf-8")

            self.assertIsNone(tracked_project_manifest_path(project_dir))

    def test_discard_untracked_project_manifest_removes_generated_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project_dir = Path(tmp)
            self.init_git_repo(project_dir)
            manifest = project_dir / "lake-manifest.json"
            manifest.write_text("{}\n", encoding="utf-8")

            discard_untracked_project_manifest(project_dir)

            self.assertFalse(manifest.exists())

    def test_discard_untracked_project_manifest_preserves_tracked_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project_dir = Path(tmp)
            self.init_git_repo(project_dir)
            manifest = project_dir / "lake-manifest.json"
            manifest.write_text("{}\n", encoding="utf-8")
            subprocess.run(
                ["git", "add", "lake-manifest.json"],
                cwd=project_dir,
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

            discard_untracked_project_manifest(project_dir)

            self.assertTrue(manifest.exists())

    def test_project_lake_update_command_uses_full_update_when_manifest_is_committed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project_dir = Path(tmp)
            self.init_git_repo(project_dir)
            manifest = project_dir / "lake-manifest.json"
            manifest.write_text("{}\n", encoding="utf-8")
            subprocess.run(
                ["git", "add", "lake-manifest.json"],
                cwd=project_dir,
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

            command = project_lake_update_command(PACKAGE_ROOT, project_dir)

            self.assertEqual(command[-2:], ["lake", "update"])

    def test_project_lake_update_command_falls_back_to_full_update_without_tracked_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project_dir = Path(tmp)
            self.init_git_repo(project_dir)

            command = project_lake_update_command(PACKAGE_ROOT, project_dir)

            self.assertEqual(command[-2:], ["lake", "update"])

    def test_run_project_update_build_generate_updates_builds_then_generates(self) -> None:
        import scripts.blueprint_harness_project_commands as commands_mod

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package_root = root / "pkg"
            project_dir = root / "project"
            package_root.mkdir()
            project_dir.mkdir()
            original_run = commands_mod.run
            original_run_with_heartbeat = commands_mod.run_with_heartbeat
            original_ensure = commands_mod.ensure_and_log_embedded_asset_owner_outputs
            commands: list[list[str]] = []
            try:
                commands_mod.run = lambda command, *, cwd: commands.append(command)
                commands_mod.run_with_heartbeat = lambda command, *, cwd, label: commands.append(command)
                commands_mod.ensure_and_log_embedded_asset_owner_outputs = (
                    lambda package_root: commands.append(["ensure", str(package_root)]) or []
                )

                run_project_update_build_generate(
                    package_root,
                    project_dir,
                    update_project=lambda: commands.append(["lake", "update"]),
                    build_command=("lake", "build"),
                    generate_command=VBP_BUILD_COMMAND,
                    format_command=lambda command: [*command, "--formatted"],
                    skip_build=False,
                )
            finally:
                commands_mod.run = original_run
                commands_mod.run_with_heartbeat = original_run_with_heartbeat
                commands_mod.ensure_and_log_embedded_asset_owner_outputs = original_ensure

        self.assertEqual(
            commands,
            [
                ["lake", "update"],
                [str(package_root / "scripts" / "lean-low-priority"), "lake", "build", "--formatted"],
                ["ensure", str(package_root)],
                [str(package_root / "scripts" / "lean-low-priority"), *VBP_BUILD_COMMAND, "--formatted"],
            ],
        )

    def test_run_project_update_build_generate_can_skip_build(self) -> None:
        import scripts.blueprint_harness_project_commands as commands_mod

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package_root = root / "pkg"
            project_dir = root / "project"
            package_root.mkdir()
            project_dir.mkdir()
            original_run = commands_mod.run
            original_run_with_heartbeat = commands_mod.run_with_heartbeat
            original_ensure = commands_mod.ensure_and_log_embedded_asset_owner_outputs
            commands: list[list[str]] = []
            try:
                commands_mod.run = lambda command, *, cwd: commands.append(command)
                commands_mod.run_with_heartbeat = lambda command, *, cwd, label: commands.append(command)
                commands_mod.ensure_and_log_embedded_asset_owner_outputs = (
                    lambda package_root: commands.append(["ensure", str(package_root)]) or []
                )

                run_project_update_build_generate(
                    package_root,
                    project_dir,
                    update_project=lambda: commands.append(["lake", "update"]),
                    build_command=("lake", "build"),
                    generate_command=VBP_BUILD_COMMAND,
                    format_command=list,
                    skip_build=True,
                )
            finally:
                commands_mod.run = original_run
                commands_mod.run_with_heartbeat = original_run_with_heartbeat
                commands_mod.ensure_and_log_embedded_asset_owner_outputs = original_ensure

        self.assertEqual(
            commands,
            [
                ["lake", "update"],
                ["ensure", str(package_root)],
                [str(package_root / "scripts" / "lean-low-priority"), *VBP_BUILD_COMMAND],
            ],
        )
