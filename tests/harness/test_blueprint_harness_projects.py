from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest

from scripts.blueprint_harness_projects import (
    deploy_project_matrix,
    HarnessProject,
    IN_REPO_PROJECT_SOURCE_KIND,
    default_project_manifest,
    load_project_catalog,
    load_projects_manifest,
    reference_build_matrix,
    resolve_projects_for_release,
    resolve_release_target,
)
from scripts.blueprint_harness_references import (
    OFFICIAL_BLUEPRINT_REQUIRE,
    bootstrap_reference_checkout,
    bump_reference_project,
    clone_git_project,
    default_reference_bump_branch,
    discard_untracked_project_manifest,
    default_reference_edit_base,
    generate_git_project,
    reference_update_command,
    reference_submodule_update_command,
    require_reference_harness_layout,
    rewrite_local_blueprint_dependency,
    rewrite_pinned_blueprint_dependency,
    seed_reference_edit_checkout_lake,
    tracked_project_manifest_path,
    update_git_checkout,
    use_shared_reference_checkout,
)


PACKAGE_ROOT = Path(__file__).resolve().parents[2]


class BlueprintHarnessProjectsTests(unittest.TestCase):
    def init_git_repo(self, root: Path) -> None:
        subprocess.run(["git", "init"], cwd=root, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def run_git(self, root: Path, *args: str) -> None:
        subprocess.run(["git", *args], cwd=root, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def commit(self, root: Path, message: str) -> str:
        self.run_git(root, "config", "user.name", "Test User")
        self.run_git(root, "config", "user.email", "test@example.com")
        self.run_git(root, "config", "commit.gpgsign", "false")
        self.run_git(root, "commit", "-m", message)
        return subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=root,
            check=True,
            text=True,
            capture_output=True,
        ).stdout.strip()

    def test_default_manifest_contains_current_external_projects(self) -> None:
        manifest = default_project_manifest(PACKAGE_ROOT)
        catalog = load_project_catalog(manifest)
        projects = list(catalog.projects)

        self.assertEqual(
            [project.project_id for project in projects],
            ["project-template", "noperthedron", "spherepackingblueprint", "verso-flt", "algebraic-combinatorics"],
        )
        self.assertEqual([target.release_id for target in catalog.release_targets], ["v4.28.0", "v4.29.0"])
        self.assertTrue(projects[0].in_repo_project)
        self.assertTrue(projects[0].in_repo_command_project)
        self.assertEqual(projects[0].project_root, "project_template")
        self.assertEqual(projects[0].generate_command, ("lake", "exe", "blueprint-gen", "--output", "{output_dir}"))
        self.assertEqual([target.release for target in projects[0].targets], ["v4.28.0", "v4.29.0"])
        self.assertTrue(projects[1].git_checkout)
        self.assertEqual(projects[1].repository, "https://github.com/ejgallego/verso-noperthedron.git")
        self.assertEqual([target.release for target in projects[1].targets], ["v4.29.0"])
        self.assertEqual(projects[1].targets[0].ref, "47f28af5e6d3edf0de439b7de9c3f121e14e4707")
        self.assertEqual(projects[1].browser_tests_path, None)
        self.assertEqual(projects[1].panel_regression_script, None)
        self.assertEqual(projects[3].repository, "https://github.com/ejgallego/verso-flt.git")
        self.assertEqual(projects[4].repository, "https://github.com/ejgallego/verso-algebraic-combinatorics.git")
        self.assertEqual([target.release for target in projects[4].targets], ["v4.28.0"])
        self.assertEqual(projects[4].targets[0].ref, "6506b992702a6e47a29d90d504f9e55eb65e13e9")

    def test_reference_pages_workflow_stages_every_manifest_project(self) -> None:
        catalog = load_project_catalog(default_project_manifest(PACKAGE_ROOT))
        release = resolve_release_target(catalog, "v4.29.0", PACKAGE_ROOT)
        projects = resolve_projects_for_release(catalog, release.release_id, None)
        matrix = reference_build_matrix(projects)
        workflow_text = (PACKAGE_ROOT / ".github" / "workflows" / "reference-blueprints.yml").read_text(
            encoding="utf-8"
        )

        self.assertIn("emit_reference_release_matrix.py", workflow_text)
        self.assertIn("pattern: reference-blueprints-*", workflow_text)
        self.assertIn("--project ${{ matrix.project_id }}", workflow_text)

        for entry in matrix["include"]:
            self.assertEqual(entry["artifact_name"], f"reference-blueprints-{entry['project_id']}")
            self.assertEqual(entry["artifact_path"], f"_out/reference-blueprints/{entry['project_id']}")

    def test_deploy_project_matrix_includes_only_deployable_projects(self) -> None:
        catalog = load_project_catalog(default_project_manifest(PACKAGE_ROOT))
        matrix = deploy_project_matrix(catalog.release_targets, catalog)

        self.assertEqual(
            matrix,
            {
                "include": [
                    {
                        "release_id": "v4.28.0",
                        "toolchain": "v4.28.0",
                        "verso_ref": "v4.28.0",
                        "branch": "v4.28.0",
                        "project_id": "project-template",
                        "artifact_name": "reference-blueprints-release-v4.28.0__project__project-template",
                        "artifact_path": "_out/reference-blueprints/v4.28.0/project-template",
                    },
                    {
                        "release_id": "v4.28.0",
                        "toolchain": "v4.28.0",
                        "verso_ref": "v4.28.0",
                        "branch": "v4.28.0",
                        "project_id": "spherepackingblueprint",
                        "artifact_name": "reference-blueprints-release-v4.28.0__project__spherepackingblueprint",
                        "artifact_path": "_out/reference-blueprints/v4.28.0/spherepackingblueprint",
                    },
                    {
                        "release_id": "v4.28.0",
                        "toolchain": "v4.28.0",
                        "verso_ref": "v4.28.0",
                        "branch": "v4.28.0",
                        "project_id": "verso-flt",
                        "artifact_name": "reference-blueprints-release-v4.28.0__project__verso-flt",
                        "artifact_path": "_out/reference-blueprints/v4.28.0/verso-flt",
                    },
                    {
                        "release_id": "v4.28.0",
                        "toolchain": "v4.28.0",
                        "verso_ref": "v4.28.0",
                        "branch": "v4.28.0",
                        "project_id": "algebraic-combinatorics",
                        "artifact_name": "reference-blueprints-release-v4.28.0__project__algebraic-combinatorics",
                        "artifact_path": "_out/reference-blueprints/v4.28.0/algebraic-combinatorics",
                    },
                    {
                        "release_id": "v4.29.0",
                        "toolchain": "v4.29.0",
                        "verso_ref": "v4.29.0",
                        "branch": "v4.29.0",
                        "project_id": "project-template",
                        "artifact_name": "reference-blueprints-release-v4.29.0__project__project-template",
                        "artifact_path": "_out/reference-blueprints/v4.29.0/project-template",
                    },
                    {
                        "release_id": "v4.29.0",
                        "toolchain": "v4.29.0",
                        "verso_ref": "v4.29.0",
                        "branch": "v4.29.0",
                        "project_id": "noperthedron",
                        "artifact_name": "reference-blueprints-release-v4.29.0__project__noperthedron",
                        "artifact_path": "_out/reference-blueprints/v4.29.0/noperthedron",
                    },
                ]
            },
        )

    def test_git_checkout_project_is_supported(self) -> None:
        manifest_data = {
            "version": 2,
            "release_targets": [
                {
                    "id": "v4.29.0",
                    "toolchain": "v4.29.0",
                    "verso_ref": "v4.29.0",
                    "branch": "v4.29.0",
                    "deploy_pages": True,
                }
            ],
            "projects": [
                {
                    "id": "external-blueprint",
                    "source": {
                        "kind": "git_checkout",
                        "repository": "https://github.com/example/external-blueprint.git",
                        "project_root": "."
                    },
                    "targets": [
                        {
                            "release": "v4.29.0",
                            "ref": "main",
                        }
                    ],
                    "build_command": ["lake", "build"],
                    "generate_command": ["lake", "exe", "blueprint-gen", "--output", "{output_dir}"],
                    "site_subdir": "html-multi"
                }
            ]
        }

        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "projects.json"
            manifest.write_text(json.dumps(manifest_data), encoding="utf-8")
            projects = load_projects_manifest(manifest)

        self.assertEqual(len(projects), 1)
        self.assertTrue(projects[0].git_checkout)
        self.assertEqual(projects[0].generate_command, ("lake", "exe", "blueprint-gen", "--output", "{output_dir}"))

    def test_in_repo_command_project_is_supported(self) -> None:
        manifest_data = {
            "version": 2,
            "release_targets": [
                {
                    "id": "v4.29.0",
                    "toolchain": "v4.29.0",
                    "verso_ref": "v4.29.0",
                    "branch": "v4.29.0",
                    "deploy_pages": True,
                }
            ],
            "projects": [
                {
                    "id": "project-template",
                    "source": {
                        "kind": IN_REPO_PROJECT_SOURCE_KIND,
                        "project_root": "project_template",
                    },
                    "targets": [
                        {
                            "release": "v4.29.0",
                        }
                    ],
                    "build_command": ["lake", "build"],
                    "generate_command": ["lake", "exe", "blueprint-gen", "--output", "{output_dir}"],
                    "site_subdir": "html-multi",
                }
            ],
        }

        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "projects.json"
            manifest.write_text(json.dumps(manifest_data), encoding="utf-8")
            projects = load_projects_manifest(manifest)

        self.assertEqual(len(projects), 1)
        self.assertTrue(projects[0].in_repo_project)
        self.assertTrue(projects[0].in_repo_command_project)
        self.assertEqual(projects[0].project_root, "project_template")
        self.assertEqual(projects[0].build_command, ("lake", "build"))
        self.assertEqual(projects[0].generate_command, ("lake", "exe", "blueprint-gen", "--output", "{output_dir}"))

    def test_resolve_projects_for_release_filters_to_matching_targets(self) -> None:
        catalog = load_project_catalog(default_project_manifest(PACKAGE_ROOT))

        release = resolve_release_target(catalog, "v4.29.0", PACKAGE_ROOT)
        projects = resolve_projects_for_release(catalog, release.release_id, None)

        self.assertEqual([project.project_id for project in projects], ["project-template", "noperthedron"])
        self.assertEqual(projects[1].selected_release, "v4.29.0")
        self.assertEqual(projects[1].ref, "47f28af5e6d3edf0de439b7de9c3f121e14e4707")

    def test_resolve_projects_for_older_release_uses_matching_targets(self) -> None:
        catalog = load_project_catalog(default_project_manifest(PACKAGE_ROOT))

        release = resolve_release_target(catalog, "v4.28.0", PACKAGE_ROOT)
        projects = resolve_projects_for_release(catalog, release.release_id, None)

        self.assertEqual(
            [project.project_id for project in projects],
            ["project-template", "spherepackingblueprint", "verso-flt", "algebraic-combinatorics"],
        )
        self.assertEqual(projects[1].selected_release, "v4.28.0")
        self.assertEqual(projects[1].ref, "4346c148b91c3a0d1060a0413176e8290a3e0839")
        self.assertEqual(projects[2].ref, "1d4f671ee5aa6169bd263384d52d97b8957d2d15")
        self.assertEqual(projects[3].ref, "6506b992702a6e47a29d90d504f9e55eb65e13e9")

    def test_duplicate_project_ids_are_rejected(self) -> None:
        manifest_data = {
            "version": 2,
            "release_targets": [
                {
                    "id": "v4.29.0",
                    "toolchain": "v4.29.0",
                    "verso_ref": "v4.29.0",
                    "branch": "v4.29.0",
                    "deploy_pages": True,
                }
            ],
            "projects": [
                {
                    "id": "dup",
                    "source": {"kind": IN_REPO_PROJECT_SOURCE_KIND},
                    "targets": [{"release": "v4.29.0"}],
                    "build_target": "a",
                    "generator": "a"
                },
                {
                    "id": "dup",
                    "source": {"kind": IN_REPO_PROJECT_SOURCE_KIND},
                    "targets": [{"release": "v4.29.0"}],
                    "build_target": "b",
                    "generator": "b"
                }
            ]
        }

        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "projects.json"
            manifest.write_text(json.dumps(manifest_data), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "duplicate project id"):
                load_projects_manifest(manifest)

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

    def test_default_reference_bump_branch_shortens_commit_hash(self) -> None:
        self.assertEqual(
            default_reference_bump_branch("9b50e39c17434ee1a574fd27ed97006adfdc5dc1"),
            "chore/bump-verso-blueprint-9b50e39c1743",
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

    def test_reference_update_command_targets_blueprint_when_manifest_is_committed(self) -> None:
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

            command = reference_update_command(PACKAGE_ROOT, project_dir)

            self.assertEqual(command[-3:], ["lake", "update", "VersoBlueprint"])

    def test_reference_update_command_falls_back_to_full_update_without_tracked_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project_dir = Path(tmp)
            self.init_git_repo(project_dir)

            command = reference_update_command(PACKAGE_ROOT, project_dir)

            self.assertEqual(command[-2:], ["lake", "update"])

    def test_project_template_manifest_keeps_verso_and_subverso_in_sync_with_root_without_mathlib(self) -> None:
        root_manifest = json.loads((PACKAGE_ROOT / "lake-manifest.json").read_text(encoding="utf-8"))
        template_manifest = json.loads((PACKAGE_ROOT / "project_template" / "lake-manifest.json").read_text(encoding="utf-8"))

        def package_rev(manifest_data: dict, package_name: str) -> str:
            package = next(entry for entry in manifest_data["packages"] if entry["name"] == package_name)
            rev = package.get("rev")
            self.assertIsInstance(rev, str)
            return rev

        self.assertEqual(package_rev(template_manifest, "verso"), package_rev(root_manifest, "verso"))
        self.assertEqual(package_rev(template_manifest, "subverso"), package_rev(root_manifest, "subverso"))
        self.assertNotIn("mathlib", {entry["name"] for entry in root_manifest["packages"]})
        self.assertNotIn("mathlib", {entry["name"] for entry in template_manifest["packages"]})

    def test_clone_git_project_checks_out_commit_ref_without_branch_name(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            remote = root / "remote.git"
            seed = root / "seed"
            checkout = root / "checkout"

            subprocess.run(["git", "init", "--bare", str(remote)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            seed.mkdir()
            self.init_git_repo(seed)
            (seed / "file.txt").write_text("first\n", encoding="utf-8")
            self.run_git(seed, "add", "file.txt")
            first = self.commit(seed, "first")
            (seed / "file.txt").write_text("second\n", encoding="utf-8")
            self.run_git(seed, "commit", "-am", "second")
            self.run_git(seed, "branch", "-M", "main")
            self.run_git(seed, "remote", "add", "origin", str(remote))
            self.run_git(seed, "push", "-u", "origin", "main")

            project = HarnessProject(
                project_id="external-blueprint",
                source_kind="git_checkout",
                project_root=".",
                build_target=None,
                generator=None,
                repository=str(remote),
                ref=first,
                build_command=None,
                generate_command=("lake", "exe", "blueprint-gen"),
                site_subdir="html-multi",
                panel_regression_script=None,
                browser_tests_path=None,
                description=None,
            )

            clone_git_project(project, checkout, cwd=root)

            head = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=checkout,
                check=True,
                text=True,
                capture_output=True,
            ).stdout.strip()
            self.assertEqual(head, first)

    def test_default_reference_edit_base_uses_detached_commit_for_sha_ref(self) -> None:
        project = HarnessProject(
            project_id="external-blueprint",
            source_kind="git_checkout",
            project_root=".",
            build_target=None,
            generator=None,
            repository="https://github.com/example/external-blueprint.git",
            ref="9b50e39c17434ee1a574fd27ed97006adfdc5dc1",
            build_command=None,
            generate_command=("lake", "exe", "blueprint-gen"),
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
        )

        self.assertEqual(default_reference_edit_base(project), project.ref)

    def test_update_git_checkout_discards_stale_untracked_manifest_before_checkout(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            remote = root / "remote.git"
            seed = root / "seed"
            checkout = root / "checkout"

            subprocess.run(["git", "init", "--bare", str(remote)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            seed.mkdir()
            self.init_git_repo(seed)
            (seed / "lakefile.lean").write_text("import Lake\n", encoding="utf-8")
            self.run_git(seed, "add", "lakefile.lean")
            self.commit(seed, "seed")
            self.run_git(seed, "branch", "-M", "main")
            self.run_git(seed, "remote", "add", "origin", str(remote))
            self.run_git(seed, "push", "-u", "origin", "main")

            subprocess.run(["git", "clone", str(remote), str(checkout)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            (checkout / "lake-manifest.json").write_text("{}\n", encoding="utf-8")

            (seed / "lake-manifest.json").write_text('{"version":"1.1.0"}\n', encoding="utf-8")
            self.run_git(seed, "add", "lake-manifest.json")
            target = self.commit(seed, "add manifest")
            self.run_git(seed, "push", "origin", "main")

            project = HarnessProject(
                project_id="external-blueprint",
                source_kind="git_checkout",
                project_root=".",
                build_target=None,
                generator=None,
                repository=str(remote),
                ref=target,
                build_command=None,
                generate_command=("lake", "exe", "blueprint-gen"),
                site_subdir="html-multi",
                panel_regression_script=None,
                browser_tests_path=None,
                description=None,
            )

            update_git_checkout(project, checkout)

            manifest = checkout / "lake-manifest.json"
            self.assertEqual(tracked_project_manifest_path(checkout), manifest)
            self.assertEqual(manifest.read_text(encoding="utf-8"), '{"version":"1.1.0"}\n')

    def test_update_git_checkout_resets_tracked_files_before_checkout(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            remote = root / "remote.git"
            seed = root / "seed"
            checkout = root / "checkout"

            subprocess.run(["git", "init", "--bare", str(remote)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            seed.mkdir()
            self.init_git_repo(seed)
            (seed / "lakefile.lean").write_text("import Lake\n", encoding="utf-8")
            (seed / "lake-manifest.json").write_text('{"version":"1.1.0"}\n', encoding="utf-8")
            self.run_git(seed, "add", "lakefile.lean", "lake-manifest.json")
            target = self.commit(seed, "seed")
            self.run_git(seed, "branch", "-M", "main")
            self.run_git(seed, "remote", "add", "origin", str(remote))
            self.run_git(seed, "push", "-u", "origin", "main")

            subprocess.run(["git", "clone", str(remote), str(checkout)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            (checkout / "lakefile.lean").write_text('require VersoBlueprint from "../local"\n', encoding="utf-8")
            (checkout / "lake-manifest.json").write_text('{"version":"dirty"}\n', encoding="utf-8")

            project = HarnessProject(
                project_id="external-blueprint",
                source_kind="git_checkout",
                project_root=".",
                build_target=None,
                generator=None,
                repository=str(remote),
                ref=target,
                build_command=None,
                generate_command=("lake", "exe", "blueprint-gen"),
                site_subdir="html-multi",
                panel_regression_script=None,
                browser_tests_path=None,
                description=None,
            )

            update_git_checkout(project, checkout)

            self.assertEqual((checkout / "lakefile.lean").read_text(encoding="utf-8"), "import Lake\n")
            self.assertEqual((checkout / "lake-manifest.json").read_text(encoding="utf-8"), '{"version":"1.1.0"}\n')
            status = subprocess.run(
                ["git", "status", "--short"],
                cwd=checkout,
                check=True,
                text=True,
                capture_output=True,
            ).stdout.strip()
            self.assertEqual(status, "")

    def test_use_shared_reference_checkout_env_switch(self) -> None:
        old = os.environ.get("BP_REFERENCE_CHECKOUT_MODE")
        try:
            os.environ.pop("BP_REFERENCE_CHECKOUT_MODE", None)
            self.assertFalse(use_shared_reference_checkout())
            os.environ["BP_REFERENCE_CHECKOUT_MODE"] = "shared"
            self.assertTrue(use_shared_reference_checkout())
        finally:
            if old is None:
                os.environ.pop("BP_REFERENCE_CHECKOUT_MODE", None)
            else:
                os.environ["BP_REFERENCE_CHECKOUT_MODE"] = old

    def test_generate_git_project_skips_cache_warm_build_for_local_checkout_mode(self) -> None:
        import scripts.blueprint_harness_references as refs_mod

        project = HarnessProject(
            project_id="external-blueprint",
            source_kind="git_checkout",
            project_root=".",
            build_target=None,
            generator=None,
            repository="https://github.com/example/external-blueprint.git",
            ref="main",
            build_command=("lake", "build"),
            generate_command=("lake", "exe", "blueprint-gen", "--output", "{output_dir}"),
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
        )

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_dir = root / "cache"
            local_dir = root / "local"
            output_root = root / "out"
            cache_dir.mkdir()
            local_dir.mkdir()
            (local_dir / "lakefile.lean").write_text('require VersoBlueprint from "../pkg"\n', encoding="utf-8")
            (local_dir / ".gitmodules").write_text(
                '[submodule "tools/verso-harness"]\n\tpath = tools/verso-harness\n\turl = git@github.com:ejgallego/leanblueprint-to-verso.git\n',
                encoding="utf-8",
            )
            (local_dir / "verso-harness.toml").write_text(
                'package_name = "Demo"\nblueprint_main = "Main"\nformalization_path = "DemoFormalization"\nchapter_root = "Chapters"\ntex_source_glob = "./blueprint/*.tex"\n[lt]\ndefault_chapters = []\n',
                encoding="utf-8",
            )
            (local_dir / "tools" / "verso-harness" / "scripts").mkdir(parents=True)
            (local_dir / "tools" / "verso-harness" / "scripts" / "check_harness.py").write_text(
                "#!/usr/bin/env python3\n",
                encoding="utf-8",
            )
            (local_dir / "DemoFormalization").mkdir()

            layout = SimpleNamespace(
                package_root=root / "pkg",
                repo_root=root / "repo",
            )
            layout.package_root.mkdir()
            layout.repo_root.mkdir()

            originals = {
                "sync_reference_cache_checkout": refs_mod.sync_reference_cache_checkout,
                "sync_reference_local_checkout": refs_mod.sync_reference_local_checkout,
                "rewrite_local_blueprint_dependency": refs_mod.rewrite_local_blueprint_dependency,
                "reference_update_command": refs_mod.reference_update_command,
                "run": refs_mod.run,
                "use_shared_reference_checkout": refs_mod.use_shared_reference_checkout,
            }
            commands: list[list[str]] = []
            warm_build_values: list[bool] = []
            try:
                refs_mod.sync_reference_cache_checkout = lambda _layout, _project, *, warm_build: warm_build_values.append(warm_build) or cache_dir
                refs_mod.sync_reference_local_checkout = lambda _layout, _project, _cache_dir: local_dir
                refs_mod.rewrite_local_blueprint_dependency = lambda _project_dir, _package_root: local_dir / "lakefile.lean"
                refs_mod.reference_update_command = lambda _package_root, _project_dir: ["lake", "update", "VersoBlueprint"]
                refs_mod.run = lambda command, *, cwd: commands.append(command)
                refs_mod.use_shared_reference_checkout = lambda: False

                generate_git_project(layout, output_root, project, skip_build=False)
            finally:
                for name, value in originals.items():
                    setattr(refs_mod, name, value)

        self.assertEqual(warm_build_values, [False])
        self.assertEqual(commands[0], reference_submodule_update_command())
        self.assertIn(["lake", "update", "VersoBlueprint"], commands)
        self.assertTrue(any(command[1:] == ["lake", "build"] for command in commands))

    def test_bootstrap_reference_checkout_requires_harness_layout(self) -> None:
        import scripts.blueprint_harness_references as refs_mod

        with tempfile.TemporaryDirectory() as tmp:
            project_dir = Path(tmp)
            (project_dir / ".gitmodules").write_text(
                '[submodule "tools/verso-harness"]\n\tpath = tools/verso-harness\n\turl = git@github.com:ejgallego/leanblueprint-to-verso.git\n',
                encoding="utf-8",
            )
            (project_dir / "verso-harness.toml").write_text(
                'package_name = "Demo"\nblueprint_main = "Main"\nformalization_path = "DemoFormalization"\nchapter_root = "Chapters"\ntex_source_glob = "./blueprint/*.tex"\n[lt]\ndefault_chapters = []\n',
                encoding="utf-8",
            )
            (project_dir / "tools" / "verso-harness" / "scripts").mkdir(parents=True)
            (project_dir / "tools" / "verso-harness" / "scripts" / "check_harness.py").write_text(
                "#!/usr/bin/env python3\n",
                encoding="utf-8",
            )
            (project_dir / "DemoFormalization").mkdir()

            original_run = refs_mod.run
            commands: list[list[str]] = []
            try:
                refs_mod.run = lambda command, *, cwd: commands.append(command)
                bootstrap_reference_checkout(project_dir=project_dir)
            finally:
                refs_mod.run = original_run

        self.assertEqual(commands, [reference_submodule_update_command()])

    def test_require_reference_harness_layout_rejects_missing_config(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project_dir = Path(tmp)
            (project_dir / "tools" / "verso-harness" / "scripts").mkdir(parents=True)
            (project_dir / "tools" / "verso-harness" / "scripts" / "check_harness.py").write_text(
                "#!/usr/bin/env python3\n",
                encoding="utf-8",
            )
            (project_dir / "DemoFormalization").mkdir()

            with self.assertRaisesRegex(SystemExit, "missing .*verso-harness.toml"):
                require_reference_harness_layout(project_dir)

    def test_bump_reference_project_commits_and_pushes_when_requested(self) -> None:
        import scripts.blueprint_harness_references as refs_mod

        project = HarnessProject(
            project_id="external-blueprint",
            source_kind="git_checkout",
            project_root=".",
            build_target=None,
            generator=None,
            repository="https://github.com/example/external-blueprint.git",
            ref="main",
            build_command=("lake", "build"),
            generate_command=("lake", "exe", "blueprint-gen", "--output", "{output_dir}"),
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
        )
        layout = SimpleNamespace(
            package_root=Path("/tmp/package"),
            artifact_root=Path("/tmp/out"),
            reference_project_checkout_root=Path("/tmp/checkouts"),
            reference_project_cache_root=Path("/tmp/cache"),
        )
        edit_dir = Path("/tmp/edit/external-blueprint")
        originals = {
            "prepare_reference_edit_checkout": refs_mod.prepare_reference_edit_checkout,
            "git_checkout_is_clean": refs_mod.git_checkout_is_clean,
            "rewrite_pinned_blueprint_dependency": refs_mod.rewrite_pinned_blueprint_dependency,
            "reference_update_command": refs_mod.reference_update_command,
            "run": refs_mod.run,
            "git_has_tracked_changes": refs_mod.git_has_tracked_changes,
            "commit_project_tracked_changes": refs_mod.commit_project_tracked_changes,
            "push_reference_edit_branch": refs_mod.push_reference_edit_branch,
        }
        commands: list[list[str]] = []
        seen: dict[str, object] = {}
        try:
            refs_mod.prepare_reference_edit_checkout = lambda _layout, _project, *, branch, base_ref: (
                edit_dir,
                branch or "chore/bump-verso-blueprint-v1-2-3",
                base_ref or "origin/main",
            )
            refs_mod.git_checkout_is_clean = lambda _checkout_root: True
            refs_mod.rewrite_pinned_blueprint_dependency = lambda _project_dir, _ref: (
                edit_dir / "lakefile.lean",
                "old-ref",
            )
            refs_mod.reference_update_command = lambda _package_root, _project_dir: ["lake", "update", "VersoBlueprint"]
            refs_mod.run = lambda command, *, cwd: commands.append(command)
            refs_mod.git_has_tracked_changes = lambda _checkout_root, _pathspec: True

            def fake_commit(_checkout_root, pathspec, message):
                seen["pathspec"] = pathspec
                seen["message"] = message
                return True

            refs_mod.commit_project_tracked_changes = fake_commit
            refs_mod.push_reference_edit_branch = lambda _checkout_root, branch: seen.setdefault("branch", branch)

            result = bump_reference_project(
                layout,
                project,
                ref="v1.2.3",
                branch=None,
                base_ref=None,
                build_project=False,
                generate_site=False,
                output_root=None,
                commit=True,
                push=True,
                commit_message=None,
            )
        finally:
            for name, value in originals.items():
                setattr(refs_mod, name, value)

        self.assertEqual(commands, [["lake", "update", "VersoBlueprint"]])
        self.assertTrue(result.changed)
        self.assertTrue(result.committed)
        self.assertTrue(result.pushed)
        self.assertEqual(seen["pathspec"], ".")
        self.assertEqual(seen["message"], "chore: bump VersoBlueprint to v1.2.3")
        self.assertEqual(seen["branch"], "chore/bump-verso-blueprint-v1-2-3")

    def test_bump_reference_project_can_generate_review_output(self) -> None:
        import scripts.blueprint_harness_references as refs_mod

        project = HarnessProject(
            project_id="external-blueprint",
            source_kind="git_checkout",
            project_root=".",
            build_target=None,
            generator=None,
            repository="https://github.com/example/external-blueprint.git",
            ref="main",
            build_command=("lake", "build"),
            generate_command=("lake", "exe", "blueprint-gen", "--output", "{output_dir}"),
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
        )

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            layout = SimpleNamespace(
                package_root=root / "pkg",
                artifact_root=root / "out",
                reference_project_checkout_root=root / "checkouts",
                reference_project_cache_root=root / "cache",
            )
            edit_dir = root / "edit" / "external-blueprint"
            output_root = root / "review"
            originals = {
                "prepare_reference_edit_checkout": refs_mod.prepare_reference_edit_checkout,
                "git_checkout_is_clean": refs_mod.git_checkout_is_clean,
                "rewrite_pinned_blueprint_dependency": refs_mod.rewrite_pinned_blueprint_dependency,
                "reference_update_command": refs_mod.reference_update_command,
                "run": refs_mod.run,
                "git_has_tracked_changes": refs_mod.git_has_tracked_changes,
            }
            commands: list[list[str]] = []
            try:
                refs_mod.prepare_reference_edit_checkout = lambda _layout, _project, *, branch, base_ref: (
                    edit_dir,
                    branch or "demo",
                    base_ref or "origin/main",
                )
                refs_mod.git_checkout_is_clean = lambda _checkout_root: True
                refs_mod.rewrite_pinned_blueprint_dependency = lambda _project_dir, _ref: (
                    edit_dir / "lakefile.lean",
                    "old-ref",
                )
                refs_mod.reference_update_command = lambda _package_root, _project_dir: ["lake", "update", "VersoBlueprint"]
                refs_mod.run = lambda command, *, cwd: commands.append(command)
                refs_mod.git_has_tracked_changes = lambda _checkout_root, _pathspec: False

                result = bump_reference_project(
                    layout,
                    project,
                    ref="v1.2.3",
                    branch="demo",
                    base_ref="origin/main",
                    build_project=True,
                    generate_site=True,
                    output_root=output_root,
                    commit=False,
                    push=False,
                    commit_message=None,
                )
            finally:
                for name, value in originals.items():
                    setattr(refs_mod, name, value)

        self.assertEqual(result.output_dir, output_root / "external-blueprint")
        self.assertTrue(any(command[-2:] == ["lake", "build"] for command in commands))
        self.assertTrue(any(str(output_root / "external-blueprint") in part for command in commands for part in command))

    def test_seed_reference_edit_checkout_lake_prefers_local_checkout(self) -> None:
        import scripts.blueprint_harness_references as refs_mod

        project = HarnessProject(
            project_id="external-blueprint",
            source_kind="git_checkout",
            project_root=".",
            build_target=None,
            generator=None,
            repository="https://github.com/example/external-blueprint.git",
            ref="main",
            build_command=("lake", "build"),
            generate_command=("lake", "exe", "blueprint-gen"),
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
        )

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            local_dir = root / "local" / project.project_id
            cache_dir = root / "cache" / project.project_id
            edit_dir = root / "edit" / project.project_id
            (local_dir / ".lake" / "packages").mkdir(parents=True)
            (cache_dir / ".lake" / "packages").mkdir(parents=True)
            edit_dir.mkdir(parents=True)
            layout = SimpleNamespace(
                package_root=root / "pkg",
                reference_project_checkout_root=root / "local",
                reference_project_cache_root=root / "cache",
            )
            layout.package_root.mkdir()

            originals = {
                "run": refs_mod.run,
            }
            commands: list[list[str]] = []
            try:
                refs_mod.run = lambda command, *, cwd: commands.append(command)

                source = seed_reference_edit_checkout_lake(layout, project, edit_dir)
            finally:
                for name, value in originals.items():
                    setattr(refs_mod, name, value)

        self.assertEqual(source, local_dir)
        self.assertEqual(
            commands,
            [["rsync", "-a", "--delete", f"{local_dir / '.lake'}/", f"{edit_dir / '.lake'}/"]],
        )

    def test_sync_reference_local_checkout_rsyncs_warmed_cache_lake(self) -> None:
        import scripts.blueprint_harness_references as refs_mod

        project = HarnessProject(
            project_id="external-blueprint",
            source_kind="git_checkout",
            project_root=".",
            build_target=None,
            generator=None,
            repository="https://github.com/example/external-blueprint.git",
            ref="main",
            build_command=("lake", "build"),
            generate_command=("lake", "exe", "blueprint-gen"),
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
        )

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_dir = root / "cache" / project.project_id
            cache_dir.mkdir(parents=True)
            (cache_dir / ".lake" / "packages" / "mathlib" / ".lake" / "build").mkdir(parents=True)
            layout = SimpleNamespace(
                package_root=root / "pkg",
                reference_project_checkout_root=root / "checkouts",
            )
            layout.package_root.mkdir()

            originals = {
                "clone_git_project": refs_mod.clone_git_project,
                "update_git_checkout": refs_mod.update_git_checkout,
                "run": refs_mod.run,
            }
            commands: list[list[str]] = []
            try:
                refs_mod.clone_git_project = lambda _project, destination, *, cwd, source=None, shallow=True: destination.mkdir(parents=True) or destination
                refs_mod.update_git_checkout = lambda _project, _checkout_root: None
                refs_mod.run = lambda command, *, cwd: commands.append(command)

                local_dir = refs_mod.sync_reference_local_checkout(layout, project, cache_dir)
            finally:
                for name, value in originals.items():
                    setattr(refs_mod, name, value)

        self.assertEqual(local_dir, root / "checkouts" / project.project_id)
        self.assertIn(
            [
                "rsync",
                "-a",
                "--delete",
                f"{cache_dir / '.lake'}/",
                f"{local_dir / '.lake'}/",
            ],
            commands,
        )

    def test_reference_prune_plan_finds_stale_cache_and_checkout_paths(self) -> None:
        from scripts.blueprint_harness import reference_prune_plan

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_root = root / "cache"
            checkout_root = root / "by-worktree"
            (cache_root / "noperthedron").mkdir(parents=True)
            (cache_root / "oldproject").mkdir(parents=True)
            (checkout_root / "v4.29.0" / "noperthedron").mkdir(parents=True)
            (checkout_root / "v4.29.0" / "oldproject").mkdir(parents=True)
            (checkout_root / "stale-worktree" / "noperthedron").mkdir(parents=True)

            removals = reference_prune_plan(
                {"v4.29.0", "cleanup-automation"},
                {"noperthedron"},
                cache_root,
                checkout_root,
            )

            self.assertEqual(
                {path.relative_to(root).as_posix() for path in removals},
                {
                    "cache/oldproject",
                    "by-worktree/v4.29.0/oldproject",
                    "by-worktree/stale-worktree",
                },
            )


if __name__ == "__main__":
    unittest.main()
