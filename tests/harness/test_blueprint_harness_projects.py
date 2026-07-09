from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest

from scripts.blueprint_harness_projects import (
    HarnessProject,
    IN_REPO_PROJECT_SOURCE_KIND,
    default_project_manifest,
    deploy_matrix_from_controller_catalog,
    load_project_catalog,
    load_project_catalog_data,
    reference_build_matrix,
    reference_dependency_cache_key,
    reference_release_payload,
    resolve_projects_for_release,
    resolve_release_target,
)
from scripts.blueprint_harness_branches import load_branch_policy
from scripts.blueprint_harness_project_commands import (
    OFFICIAL_BLUEPRINT_REQUIRE,
    tracked_project_manifest_path,
)
from scripts.blueprint_harness_releases import release_candidate_ref
from scripts.blueprint_harness_references import (
    bootstrap_reference_checkout,
    bump_reference_project,
    clone_git_project,
    default_reference_bump_branch,
    default_reference_edit_base,
    generate_git_project,
    reference_submodule_update_command,
    reconcile_reference_toolchains,
    require_reference_harness_layout,
    seed_lake_path_builds_from_dependency_cache,
    seed_reference_edit_checkout_lake,
    seed_lake_packages_from_dependency_cache,
    store_lake_path_builds_in_dependency_cache,
    store_lake_packages_in_dependency_cache,
    update_git_checkout,
)


PACKAGE_ROOT = Path(__file__).resolve().parents[2]
VBP_BUILD_COMMAND = ("lake", "exe", "vbp", "build")
VBP_BUILD_OUTPUT_COMMAND = (*VBP_BUILD_COMMAND, "--output", "{output_dir}")


def load_project_catalog_text(text: str, manifest_path: Path | str):
    raw = json.loads(text)
    if not isinstance(raw, dict):
        raise ValueError(f"{manifest_path}: expected JSON object")
    return load_project_catalog_data(raw, manifest_path)


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

    def assert_resolved_projects_match_manifest(self, release_id: str) -> None:
        catalog = load_project_catalog(default_project_manifest(PACKAGE_ROOT))
        release = resolve_release_target(catalog, release_id, PACKAGE_ROOT)
        projects = resolve_projects_for_release(catalog, release.release_id, None)

        expected_projects: list[str] = []
        expected_refs: dict[str, str | None] = {}
        expected_rcs: dict[str, str | None] = {}
        expected_targets = [
            (project, target)
            for project in catalog.projects
            if (target := project.target_for_release(release.release_id)) is not None and target.publish_reference
        ]
        for project, target in expected_targets:
            expected_projects.append(project.project_id)
            expected_refs[project.project_id] = target.ref
            expected_rcs[project.project_id] = target.rc

        self.assertEqual([project.project_id for project in projects], expected_projects)
        for project in projects:
            self.assertEqual(project.selected_release, release.release_id)
            self.assertEqual(project.selected_rc, expected_rcs[project.project_id])
            expected_ref = expected_refs[project.project_id]
            if expected_ref is not None:
                self.assertEqual(project.ref, expected_ref)

    def assert_single_current_release_target(
        self,
        project: HarnessProject,
        release_id: str,
        *,
        publish_reference: bool | None = None,
    ) -> None:
        self.assertEqual([target.release for target in project.targets], [release_id])
        if publish_reference is not None:
            self.assertEqual(project.targets[0].publish_reference, publish_reference)

    def test_default_manifest_contains_release_projects(self) -> None:
        manifest = default_project_manifest(PACKAGE_ROOT)
        manifest_data = json.loads(manifest.read_text(encoding="utf-8"))
        self.assertNotIn("release_targets", manifest_data)
        catalog = load_project_catalog(manifest)
        projects = list(catalog.projects)
        current_release = resolve_release_target(catalog, None, PACKAGE_ROOT)
        branch_policy = load_branch_policy(PACKAGE_ROOT)

        self.assertEqual(
            [project.project_id for project in projects],
            [
                "project-template",
                "noperthedron",
                "spherepackingblueprint",
                "verso-flt",
                "verso-carleson",
            ],
        )
        self.assertEqual(catalog.release_targets, branch_policy.release_targets)
        self.assertTrue(projects[0].in_repo_project)
        self.assertTrue(projects[0].in_repo_command_project)
        self.assertEqual(projects[0].project_root, "project_template")
        self.assertEqual(projects[0].build_command, ("lake", "build", "ProjectTemplate"))
        self.assertEqual(
            projects[0].generate_command,
            (
                "lake",
                "lean",
                "ProjectTemplateMain.lean",
                "--",
                "--run",
                "ProjectTemplateMain.lean",
                "--output",
                "{output_dir}",
            ),
        )
        expected_template_targets = [target.release_id for target in branch_policy.release_targets]
        self.assertEqual([target.release for target in projects[0].targets], expected_template_targets)
        default_template_target = projects[0].target_for_release(branch_policy.default_dev_branch)
        self.assertIsNotNone(default_template_target)
        self.assertTrue(default_template_target.publish_reference)
        self.assertEqual(current_release.release_toolchain, current_release.toolchain)
        self.assertEqual(current_release.release_verso_ref, current_release.verso_ref)
        if current_release.deploy_pages:
            self.assertTrue(resolve_projects_for_release(catalog, current_release.release_id, None))
        expected_external_releases = {
            "noperthedron": "v4.31.0",
            "spherepackingblueprint": "v4.30.0",
            "verso-flt": "v4.31.0",
            "verso-carleson": "v4.30.0",
        }
        self.assertTrue(projects[1].git_checkout)
        self.assertEqual(projects[1].repository, "https://github.com/ejgallego/verso-noperthedron.git")
        self.assert_single_current_release_target(
            projects[1], expected_external_releases[projects[1].project_id], publish_reference=True
        )
        self.assertIsNone(projects[1].targets[0].rc)
        self.assertEqual(projects[1].build_command, ("lake", "build", "Contents"))
        self.assertEqual(
            projects[1].generate_command,
            ("lake", "lean", "Main.lean", "--", "--run", "Main.lean", "--output", "{output_dir}"),
        )
        self.assertEqual(projects[1].browser_tests_path, None)
        self.assertEqual(projects[1].panel_regression_script, None)
        self.assertEqual(projects[2].repository, "https://github.com/ejgallego/verso-sphere-packing.git")
        self.assert_single_current_release_target(
            projects[2], expected_external_releases[projects[2].project_id], publish_reference=True
        )
        self.assertIsNone(projects[2].targets[0].rc)
        self.assertEqual(projects[2].build_command, ("bash", "scripts/ci-reference-build.sh"))
        self.assertEqual(projects[3].repository, "https://github.com/ejgallego/verso-flt.git")
        self.assert_single_current_release_target(
            projects[3], expected_external_releases[projects[3].project_id], publish_reference=True
        )
        self.assertIsNone(projects[3].targets[0].rc)
        self.assertEqual(projects[4].repository, "https://github.com/ejgallego/verso-carleson.git")
        self.assert_single_current_release_target(
            projects[4], expected_external_releases[projects[4].project_id], publish_reference=True
        )
        self.assertIsNotNone(projects[4].targets[0].rc)
        self.assertEqual(projects[4].build_command, ("lake", "build", "CarlesonBlueprint"))
        self.assertEqual(
            projects[4].generate_command,
            ("lake", "lean", "BlueprintMain.lean", "--", "--run", "BlueprintMain.lean", "--output", "{output_dir}"),
        )

    def test_project_catalog_requires_json_object(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "projects.json"
            manifest.write_text("[]\n", encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "expected JSON object"):
                load_project_catalog(manifest)

    def test_reference_dependency_cache_key_tracks_external_source_identity(self) -> None:
        base_project = HarnessProject(
            project_id="external-blueprint",
            source_kind="git_checkout",
            project_root="nested/blueprint",
            build_target=None,
            generator=None,
            repository="https://github.com/example/external-blueprint.git",
            ref="0123456789abcdef0123456789abcdef01234567",
            build_command=("lake", "build"),
            generate_command=VBP_BUILD_COMMAND,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
            selected_release="v4.29.0",
        )
        same_source_other_release = HarnessProject(
            project_id="external-blueprint",
            source_kind="git_checkout",
            project_root="nested/blueprint",
            build_target=None,
            generator=None,
            repository="https://github.com/example/external-blueprint.git",
            ref="0123456789abcdef0123456789abcdef01234567",
            build_command=("lake", "build"),
            generate_command=VBP_BUILD_COMMAND,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
            selected_release="v4.30.0",
        )
        changed_ref = HarnessProject(
            project_id="external-blueprint",
            source_kind="git_checkout",
            project_root="nested/blueprint",
            build_target=None,
            generator=None,
            repository="https://github.com/example/external-blueprint.git",
            ref="fedcba9876543210fedcba9876543210fedcba98",
            build_command=("lake", "build"),
            generate_command=VBP_BUILD_COMMAND,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
            selected_release="v4.29.0",
        )

        key = reference_dependency_cache_key(base_project)

        self.assertTrue(key.startswith("external-blueprint-0123456789ab-"))
        self.assertEqual(key, reference_dependency_cache_key(same_source_other_release))
        self.assertNotEqual(key, reference_dependency_cache_key(changed_ref))

    def test_reference_dependency_package_cache_is_separate_from_checkout_cache(self) -> None:
        import scripts.blueprint_harness_references as refs_mod

        project = HarnessProject(
            project_id="external-blueprint",
            source_kind="git_checkout",
            project_root="nested/blueprint",
            build_target=None,
            generator=None,
            repository="https://github.com/example/external-blueprint.git",
            ref="main",
            build_command=("lake", "build"),
            generate_command=VBP_BUILD_COMMAND,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
        )

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_key = reference_dependency_cache_key(project)
            dependency_packages = root / "deps" / cache_key / "packages"
            project_dir = root / "checkout" / "nested" / "blueprint"
            dependency_packages.mkdir(parents=True)
            (project_dir / ".lake" / "packages" / "mathlib").mkdir(parents=True)
            layout = SimpleNamespace(
                package_root=root / "pkg",
                reference_dependency_cache_root=root / "deps",
            )
            layout.package_root.mkdir()

            original_run = refs_mod.run
            commands: list[list[str]] = []
            try:
                refs_mod.run = lambda command, *, cwd: commands.append(command)

                seeded_from = seed_lake_packages_from_dependency_cache(layout, project, project_dir)
                stored_to = store_lake_packages_in_dependency_cache(layout, project, project_dir)
            finally:
                refs_mod.run = original_run

        self.assertEqual(seeded_from, dependency_packages)
        self.assertEqual(stored_to, dependency_packages)
        self.assertEqual(
            commands,
            [
                ["rsync", "-a", f"{dependency_packages}/", f"{project_dir / '.lake' / 'packages'}/"],
                ["rsync", "-a", "--delete", f"{project_dir / '.lake' / 'packages'}/", f"{dependency_packages}/"],
            ],
        )

    def test_reference_dependency_package_move_mode_moves_into_checkout(self) -> None:
        project = HarnessProject(
            project_id="external-blueprint",
            source_kind="git_checkout",
            project_root="nested/blueprint",
            build_target=None,
            generator=None,
            repository="https://github.com/example/external-blueprint.git",
            ref="main",
            build_command=("lake", "build"),
            generate_command=VBP_BUILD_COMMAND,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
        )

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_key = reference_dependency_cache_key(project)
            dependency_packages = root / "deps" / cache_key / "packages"
            project_dir = root / "checkout" / "nested" / "blueprint"
            marker = dependency_packages / "mathlib" / ".lake" / "build" / "Mathlib.olean"
            marker.parent.mkdir(parents=True)
            marker.write_text("warm", encoding="utf-8")
            old_local_marker = project_dir / ".lake" / "packages" / "old" / "stale"
            old_local_marker.parent.mkdir(parents=True)
            old_local_marker.write_text("stale", encoding="utf-8")
            layout = SimpleNamespace(
                package_root=root / "pkg",
                reference_dependency_cache_root=root / "deps",
            )
            layout.package_root.mkdir()

            seeded_from = seed_lake_packages_from_dependency_cache(
                layout,
                project,
                project_dir,
                package_mode="move",
            )

            self.assertEqual(seeded_from, dependency_packages)
            self.assertFalse(dependency_packages.exists())
            self.assertFalse(old_local_marker.exists())
            self.assertEqual(
                (project_dir / ".lake" / "packages" / "mathlib" / ".lake" / "build" / "Mathlib.olean").read_text(
                    encoding="utf-8"
                ),
                "warm",
            )

    def test_reference_dependency_package_move_mode_restores_to_cache(self) -> None:
        project = HarnessProject(
            project_id="external-blueprint",
            source_kind="git_checkout",
            project_root="nested/blueprint",
            build_target=None,
            generator=None,
            repository="https://github.com/example/external-blueprint.git",
            ref="main",
            build_command=("lake", "build"),
            generate_command=VBP_BUILD_COMMAND,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
        )

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_key = reference_dependency_cache_key(project)
            dependency_packages = root / "deps" / cache_key / "packages"
            project_dir = root / "checkout" / "nested" / "blueprint"
            marker = project_dir / ".lake" / "packages" / "mathlib" / ".lake" / "build" / "Mathlib.olean"
            marker.parent.mkdir(parents=True)
            marker.write_text("warm", encoding="utf-8")
            old_cache_marker = dependency_packages / "old" / "stale"
            old_cache_marker.parent.mkdir(parents=True)
            old_cache_marker.write_text("stale", encoding="utf-8")
            layout = SimpleNamespace(
                package_root=root / "pkg",
                reference_dependency_cache_root=root / "deps",
            )
            layout.package_root.mkdir()

            stored_to = store_lake_packages_in_dependency_cache(
                layout,
                project,
                project_dir,
                package_mode="move",
            )

            self.assertEqual(stored_to, dependency_packages)
            self.assertFalse((project_dir / ".lake" / "packages").exists())
            self.assertFalse(old_cache_marker.exists())
            self.assertEqual(
                (dependency_packages / "mathlib" / ".lake" / "build" / "Mathlib.olean").read_text(encoding="utf-8"),
                "warm",
            )

    def test_discard_lake_packages_prunes_warmed_checkout_copy(self) -> None:
        import scripts.blueprint_harness_references as refs_mod

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            project_dir = root / "checkout"
            packages = project_dir / ".lake" / "packages"
            mathlib_artifact = packages / "mathlib" / ".lake" / "build" / "Mathlib.olean"
            mathlib_artifact.parent.mkdir(parents=True)
            mathlib_artifact.write_text("warm", encoding="utf-8")

            pruned = refs_mod.discard_lake_packages(project_dir)

        self.assertEqual(pruned, packages)
        self.assertFalse(packages.exists())

    def test_reference_dependency_path_build_cache_seeds_external_path_dependencies(self) -> None:
        import scripts.blueprint_harness_references as refs_mod

        project = HarnessProject(
            project_id="external-blueprint",
            source_kind="git_checkout",
            project_root="nested/blueprint",
            build_target=None,
            generator=None,
            repository="https://github.com/example/external-blueprint.git",
            ref="main",
            build_command=("lake", "build"),
            generate_command=VBP_BUILD_COMMAND,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
        )

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_key = reference_dependency_cache_key(project)
            path_builds = root / "deps" / cache_key / "path-builds"
            project_dir = root / "checkout" / "nested" / "blueprint"
            package_root = root / "pkg"
            project_dir.mkdir(parents=True)
            package_root.mkdir()
            (path_builds / "Formalization" / ".lake" / "build" / "lib").mkdir(parents=True)
            (project_dir / "Formalization" / ".lake" / "build" / "lib").mkdir(parents=True)
            (project_dir / "lake-manifest.json").write_text(
                json.dumps(
                    {
                        "packages": [
                            {
                                "name": "VersoBlueprint",
                                "type": "path",
                                "dir": "../../../pkg",
                            },
                            {
                                "name": "Formalization",
                                "type": "path",
                                "dir": "./Formalization",
                            },
                        ]
                    }
                ),
                encoding="utf-8",
            )
            layout = SimpleNamespace(
                package_root=package_root,
                reference_dependency_cache_root=root / "deps",
            )

            original_run = refs_mod.run
            commands: list[list[str]] = []
            try:
                refs_mod.run = lambda command, *, cwd: commands.append(command)

                seeded_from = seed_lake_path_builds_from_dependency_cache(layout, project, project_dir)
                stored_to = store_lake_path_builds_in_dependency_cache(layout, project, project_dir)
            finally:
                refs_mod.run = original_run

        self.assertEqual(seeded_from, path_builds)
        self.assertEqual(stored_to, path_builds)
        self.assertEqual(
            commands,
            [
                [
                    "rsync",
                    "-a",
                    f"{path_builds / 'Formalization' / '.lake' / 'build'}/",
                    f"{project_dir / 'Formalization' / '.lake' / 'build'}/",
                ],
                [
                    "rsync",
                    "-a",
                    "--delete",
                    f"{project_dir / 'Formalization' / '.lake' / 'build'}/",
                    f"{path_builds / 'Formalization' / '.lake' / 'build'}/",
                ],
            ],
        )

    def test_reference_pages_workflow_stages_every_manifest_project(self) -> None:
        catalog = load_project_catalog(default_project_manifest(PACKAGE_ROOT))
        release = resolve_release_target(catalog, "v4.30.0", PACKAGE_ROOT)
        projects = resolve_projects_for_release(catalog, release.release_id, None)
        matrix = reference_build_matrix(projects, release)
        workflow_text = (PACKAGE_ROOT / ".github" / "workflows" / "reference-blueprints.yml").read_text(
            encoding="utf-8"
        )
        deploy_workflow_text = (PACKAGE_ROOT / ".github" / "workflows" / "reference-blueprints-deploy.yml").read_text(
            encoding="utf-8"
        )

        self.assertIn("emit_reference_release_matrix.py", workflow_text)
        self.assertIn("pattern: reference-blueprints-*", workflow_text)
        self.assertIn("--project ${{ matrix.project_id }}", workflow_text)
        self.assertIn("matrix.reference_cache_key", workflow_text)
        self.assertIn(".worktrees/_reference-blueprints/deps/${{ matrix.reference_cache_key }}/packages", workflow_text)
        self.assertIn(".worktrees/_reference-blueprints/deps/${{ matrix.reference_cache_key }}/path-builds", workflow_text)
        self.assertIn("reference-deps-v2-${{ matrix.reference_cache_key }}", workflow_text)
        self.assertIn(".worktrees/_reference-blueprints/deps/${{ matrix.reference_cache_key }}/path-builds", deploy_workflow_text)
        self.assertIn("reference-deploy-deps-v2-${{ matrix.reference_cache_key }}", deploy_workflow_text)

        for entry in matrix["include"]:
            self.assertEqual(entry["artifact_name"], f"reference-blueprints-{entry['project_id']}")
            self.assertEqual(entry["artifact_path"], f"_out/reference-blueprints/{entry['project_id']}")
            self.assertIn("project_root", entry)
            if entry["hash"] is not None:
                self.assertTrue(entry["reference_cache_key"])
            else:
                self.assertEqual(entry["reference_cache_key"], "")

    def test_reference_release_payload_uses_project_target_rcs(self) -> None:
        manifest = default_project_manifest(PACKAGE_ROOT)
        catalog = load_project_catalog(manifest)

        release = resolve_release_target(catalog, None, PACKAGE_ROOT)
        payload = reference_release_payload(manifest, catalog, release.release_id, PACKAGE_ROOT)

        self.assertEqual(payload["manifest_path"], str(manifest))
        self.assertEqual(payload["release_id"], release.release_id)
        self.assertEqual(payload["rc"], "")
        self.assertEqual(payload["toolchain"], release.toolchain)
        self.assertEqual(payload["verso_ref"], release.verso_ref)
        expected_targets = [
            (project, target)
            for project in catalog.projects
            if (target := project.target_for_release(release.release_id)) is not None and target.publish_reference
        ]
        self.assertEqual(payload["reference_project_count"], len(expected_targets))
        rows = {
            entry["project_id"]: entry
            for entry in payload["reference_matrix"]["include"]
        }
        self.assertEqual(set(rows), {project.project_id for project, _target in expected_targets})
        for project, target in expected_targets:
            row = rows[project.project_id]
            expected_toolchain = release_candidate_ref(target.rc) if target.rc is not None else release.toolchain
            expected_verso_ref = release_candidate_ref(target.rc) if target.rc is not None else release.verso_ref
            self.assertEqual(row["rc"], target.rc or "")
            self.assertEqual(row["toolchain"], expected_toolchain)
            self.assertEqual(row["verso_ref"], expected_verso_ref)
            self.assertEqual(row["hash"], target.ref)

    def test_deploy_matrix_uses_controller_publish_targets_for_generated_manifests(self) -> None:
        controller_catalog = load_project_catalog_text(
            json.dumps(
                {
                    "version": 2,
                    "release_targets": [
                        {
                            "id": "v4.28.0",
                            "toolchain": "v4.28.0",
                            "verso_ref": "v4.28.0",
                            "branch": "v4.28.0",
                            "deploy_pages": True,
                        },
                        {
                            "id": "v4.29.0",
                            "toolchain": "v4.29.0",
                            "verso_ref": "v4.29.0",
                            "branch": "v4.29.0",
                            "deploy_pages": True,
                        },
                    ],
                    "projects": [
                        {
                            "id": "old-release-project",
                            "source": {
                                "kind": "git_checkout",
                                "repository": "https://example.com/old-release-project.git",
                                "project_root": "old-controller",
                            },
                            "targets": [
                                {
                                    "release": "v4.28.0",
                                    "ref": "old-controller-ref",
                                    "publish_reference": True,
                                }
                            ],
                            "build_command": ["lake", "build"],
                            "generate_command": list(VBP_BUILD_COMMAND),
                        },
                        {
                            "id": "new-release-older-project",
                            "source": {
                                "kind": "git_checkout",
                                "repository": "https://example.com/new-release-older-project.git",
                                "project_root": "new-controller-older",
                            },
                            "targets": [{"release": "v4.29.0", "ref": "new-older-controller-ref"}],
                            "build_command": ["lake", "build"],
                            "generate_command": list(VBP_BUILD_COMMAND),
                        },
                        {
                            "id": "new-release-project",
                            "source": {
                                "kind": "git_checkout",
                                "repository": "https://example.com/new-release-project.git",
                                "project_root": "new-controller",
                            },
                            "targets": [
                                {
                                    "release": "v4.29.0",
                                    "ref": "new-controller-ref",
                                    "rc": "4.29-rc1",
                                    "publish_reference": True,
                                }
                            ],
                            "build_command": ["lake", "build"],
                            "generate_command": list(VBP_BUILD_COMMAND),
                        },
                        {
                            "id": "new-release-second-project",
                            "source": {
                                "kind": "git_checkout",
                                "repository": "https://example.com/new-release-second-project.git",
                                "project_root": "new-controller-second",
                            },
                            "targets": [
                                {
                                    "release": "v4.29.0",
                                    "ref": "new-second-controller-ref",
                                    "rc": "v4.29.0-rc2",
                                    "publish_reference": True,
                                }
                            ],
                            "build_command": ["lake", "build"],
                            "generate_command": list(VBP_BUILD_COMMAND),
                        }
                    ],
                }
            ),
            "controller-projects.json",
        )
        matrix = deploy_matrix_from_controller_catalog(
            controller_catalog,
            controller_catalog.release_targets,
        )

        self.assertEqual(
            [(entry["release_id"], entry["project_id"]) for entry in matrix["include"]],
            [
                ("v4.28.0", "old-release-project"),
                ("v4.29.0", "new-release-project"),
                ("v4.29.0", "new-release-second-project"),
            ],
        )
        manifest_by_project = {
            entry["project_id"]: entry["project_manifest"]
            for entry in matrix["include"]
        }
        matrix_by_project = {
            entry["project_id"]: entry
            for entry in matrix["include"]
        }
        self.assertEqual(
            manifest_by_project["old-release-project"]["projects"][0]["targets"],
            [{"release": "v4.28.0", "ref": "old-controller-ref"}],
        )
        self.assertEqual(
            manifest_by_project["old-release-project"]["projects"][0]["source"]["project_root"],
            "old-controller",
        )
        self.assertEqual(
            manifest_by_project["old-release-project"]["projects"][0]["generate_command"],
            list(VBP_BUILD_COMMAND),
        )
        self.assertEqual(matrix_by_project["old-release-project"]["project_root"], "old-controller")
        self.assertEqual(matrix_by_project["old-release-project"]["rc"], "")
        self.assertEqual(matrix_by_project["old-release-project"]["toolchain"], "v4.28.0")
        self.assertTrue(matrix_by_project["old-release-project"]["reference_cache_key"].startswith("old-release-project-"))
        self.assertEqual(
            manifest_by_project["new-release-project"]["projects"][0]["targets"],
            [{"release": "v4.29.0", "ref": "new-controller-ref", "rc": "4.29-rc1"}],
        )
        self.assertEqual(
            manifest_by_project["new-release-project"]["projects"][0]["generate_command"],
            list(VBP_BUILD_COMMAND),
        )
        self.assertNotIn("rc", manifest_by_project["new-release-project"]["release_targets"][0])
        self.assertEqual(matrix_by_project["new-release-project"]["rc"], "4.29-rc1")
        self.assertEqual(matrix_by_project["new-release-project"]["toolchain"], "v4.29.0-rc1")
        self.assertEqual(matrix_by_project["new-release-project"]["verso_ref"], "v4.29.0-rc1")
        self.assertEqual(
            manifest_by_project["new-release-second-project"]["projects"][0]["targets"],
            [{"release": "v4.29.0", "ref": "new-second-controller-ref", "rc": "4.29-rc2"}],
        )
        self.assertEqual(
            manifest_by_project["new-release-second-project"]["projects"][0]["generate_command"],
            list(VBP_BUILD_COMMAND),
        )
        self.assertEqual(matrix_by_project["new-release-second-project"]["rc"], "4.29-rc2")
        self.assertEqual(matrix_by_project["new-release-second-project"]["toolchain"], "v4.29.0-rc2")
        self.assertEqual(matrix_by_project["new-release-second-project"]["verso_ref"], "v4.29.0-rc2")

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
                    "generate_command": list(VBP_BUILD_OUTPUT_COMMAND),
                    "site_subdir": "html-multi"
                }
            ]
        }

        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "projects.json"
            manifest.write_text(json.dumps(manifest_data), encoding="utf-8")
            projects = load_project_catalog(manifest).projects

        self.assertEqual(len(projects), 1)
        self.assertTrue(projects[0].git_checkout)
        self.assertEqual(projects[0].generate_command, VBP_BUILD_OUTPUT_COMMAND)

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
                    "generate_command": list(VBP_BUILD_OUTPUT_COMMAND),
                    "site_subdir": "html-multi",
                }
            ],
        }

        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "projects.json"
            manifest.write_text(json.dumps(manifest_data), encoding="utf-8")
            projects = load_project_catalog(manifest).projects

        self.assertEqual(len(projects), 1)
        self.assertTrue(projects[0].in_repo_project)
        self.assertTrue(projects[0].in_repo_command_project)
        self.assertEqual(projects[0].project_root, "project_template")
        self.assertEqual(projects[0].build_command, ("lake", "build"))
        self.assertEqual(projects[0].generate_command, VBP_BUILD_OUTPUT_COMMAND)

    def test_resolve_projects_for_release_filters_to_matching_targets(self) -> None:
        self.assert_resolved_projects_match_manifest("v4.30.0")

    def test_resolve_projects_for_default_release_uses_matching_targets(self) -> None:
        self.assert_resolved_projects_match_manifest(load_branch_policy(PACKAGE_ROOT).default_dev_branch)

    def test_project_template_has_default_release_target(self) -> None:
        catalog = load_project_catalog(default_project_manifest(PACKAGE_ROOT))
        default_release = load_branch_policy(PACKAGE_ROOT).default_dev_branch

        projects = resolve_projects_for_release(catalog, default_release, ["project-template"])

        self.assertEqual([project.project_id for project in projects], ["project-template"])
        self.assertEqual(projects[0].selected_release, default_release)
        self.assertTrue(projects[0].in_repo_project)

    def test_publish_reference_targets_select_default_release_catalog(self) -> None:
        catalog = load_project_catalog_text(
            json.dumps(
                {
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
                            "id": "validation-only",
                            "source": {
                                "kind": "git_checkout",
                                "repository": "https://example.com/validation-only.git",
                                "project_root": ".",
                            },
                            "targets": [{"release": "v4.29.0", "ref": "validation-ref"}],
                            "build_command": ["lake", "build"],
                            "generate_command": list(VBP_BUILD_COMMAND),
                        },
                        {
                            "id": "published",
                            "source": {
                                "kind": "git_checkout",
                                "repository": "https://example.com/published.git",
                                "project_root": ".",
                            },
                            "targets": [
                                {
                                    "release": "v4.29.0",
                                    "ref": "published-ref",
                                    "publish_reference": True,
                                }
                            ],
                            "build_command": ["lake", "build"],
                            "generate_command": list(VBP_BUILD_COMMAND),
                        },
                    ],
                }
            ),
            "projects.json",
        )

        default_projects = resolve_projects_for_release(catalog, "v4.29.0", None)
        explicit_projects = resolve_projects_for_release(catalog, "v4.29.0", ["validation-only"])

        self.assertEqual(
            [(project.project_id, project.ref) for project in default_projects],
            [("published", "published-ref")],
        )
        self.assertEqual(
            [(project.project_id, project.ref) for project in explicit_projects],
            [("validation-only", "validation-ref")],
        )

    def test_release_catalog_defaults_to_empty_without_publish_targets(self) -> None:
        catalog = load_project_catalog_text(
            json.dumps(
                {
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
                            "id": "validation-only",
                            "source": {
                                "kind": "git_checkout",
                                "repository": "https://example.com/validation-only.git",
                                "project_root": ".",
                            },
                            "targets": [{"release": "v4.29.0", "ref": "validation-ref"}],
                            "build_command": ["lake", "build"],
                            "generate_command": list(VBP_BUILD_COMMAND),
                        }
                    ],
                }
            ),
            "projects.json",
        )

        default_projects = resolve_projects_for_release(catalog, "v4.29.0", None)
        explicit_projects = resolve_projects_for_release(catalog, "v4.29.0", ["validation-only"])

        self.assertEqual(default_projects, [])
        self.assertEqual(
            [(project.project_id, project.ref) for project in explicit_projects],
            [("validation-only", "validation-ref")],
        )

    def test_legacy_reference_blueprints_are_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "top-level `reference_blueprints` is no longer supported"):
            load_project_catalog_text(
                json.dumps(
                    {
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
                        "reference_blueprints": [
                            {
                                "blueprint": "published",
                                "hash": "published-ref",
                                "toolchain": "v4.29.0",
                            }
                        ],
                        "projects": [],
                    }
                ),
                "legacy-projects.json",
            )

    def test_legacy_publish_alias_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "`publish` is no longer supported; use `publish_reference`"):
            load_project_catalog_text(
                json.dumps(
                    {
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
                                "id": "published",
                                "source": {
                                    "kind": "git_checkout",
                                    "repository": "https://example.com/published.git",
                                    "project_root": ".",
                                },
                                "targets": [
                                    {
                                        "release": "v4.29.0",
                                        "ref": "published-ref",
                                        "publish": True,
                                    }
                                ],
                                "build_command": ["lake", "build"],
                                "generate_command": list(VBP_BUILD_COMMAND),
                            }
                        ],
                    }
                ),
                "legacy-publish-projects.json",
            )

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
                load_project_catalog(manifest)

    def test_default_reference_bump_branch_shortens_commit_hash(self) -> None:
        self.assertEqual(
            default_reference_bump_branch("9b50e39c17434ee1a574fd27ed97006adfdc5dc1"),
            "chore/bump-verso-blueprint-9b50e39c1743",
        )

    def test_reconcile_reference_toolchains_promotes_same_release_branch_to_newest_ref(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package_root = root / "pkg"
            project_dir = root / "external"
            mathlib_dir = project_dir / ".lake" / "packages" / "mathlib"
            other_dir = project_dir / ".lake" / "packages" / "other"
            package_root.mkdir()
            mathlib_dir.mkdir(parents=True)
            other_dir.mkdir(parents=True)
            (package_root / "lean-toolchain").write_text("leanprover/lean4:v4.30.0\n", encoding="utf-8")
            (project_dir / "lean-toolchain").write_text("leanprover/lean4:4.30-rc1\n", encoding="utf-8")
            (mathlib_dir / "lean-toolchain").write_text("leanprover/lean4:v4.30.0-rc2", encoding="utf-8")
            (other_dir / "lean-toolchain").write_text("leanprover/lean4:v4.29.0\n", encoding="utf-8")

            result = reconcile_reference_toolchains(package_root, project_dir)

            self.assertTrue(result.changed)
            self.assertEqual(result.selected_ref, "v4.30.0")
            self.assertEqual(result.release_branch, "v4.30.0")
            self.assertEqual(
                set(result.changed_paths),
                {
                    project_dir / "lean-toolchain",
                    mathlib_dir / "lean-toolchain",
                },
            )
            self.assertEqual(
                (project_dir / "lean-toolchain").read_text(encoding="utf-8"),
                "leanprover/lean4:v4.30.0\n",
            )
            self.assertEqual(
                (mathlib_dir / "lean-toolchain").read_text(encoding="utf-8"),
                "leanprover/lean4:v4.30.0",
            )
            self.assertEqual(
                (other_dir / "lean-toolchain").read_text(encoding="utf-8"),
                "leanprover/lean4:v4.29.0\n",
            )

    def test_reconcile_reference_toolchains_leaves_different_release_branches_alone(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package_root = root / "pkg"
            project_dir = root / "external"
            mathlib_dir = project_dir / ".lake" / "packages" / "mathlib"
            package_root.mkdir()
            mathlib_dir.mkdir(parents=True)
            (package_root / "lean-toolchain").write_text("leanprover/lean4:v4.30.0\n", encoding="utf-8")
            (project_dir / "lean-toolchain").write_text("leanprover/lean4:v4.29.0\n", encoding="utf-8")
            (mathlib_dir / "lean-toolchain").write_text("leanprover/lean4:v4.29.0\n", encoding="utf-8")

            result = reconcile_reference_toolchains(package_root, project_dir)

            self.assertFalse(result.changed)
            self.assertIsNone(result.selected_ref)
            self.assertIsNone(result.release_branch)
            self.assertEqual(result.changed_paths, ())
            self.assertEqual(
                (project_dir / "lean-toolchain").read_text(encoding="utf-8"),
                "leanprover/lean4:v4.29.0\n",
            )
            self.assertEqual(
                (mathlib_dir / "lean-toolchain").read_text(encoding="utf-8"),
                "leanprover/lean4:v4.29.0\n",
            )

    def test_reference_cache_checkout_uses_current_package_root_override(self) -> None:
        import scripts.blueprint_harness_project_commands as commands_mod
        import scripts.blueprint_harness_references as refs_mod

        project = HarnessProject(
            project_id="external-blueprint",
            source_kind="git_checkout",
            project_root="nested/blueprint",
            build_target=None,
            generator=None,
            repository="https://github.com/example/external-blueprint.git",
            ref="main",
            build_command=("lake", "build"),
            generate_command=VBP_BUILD_COMMAND,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
        )
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_dir = root / "cache" / reference_dependency_cache_key(project)
            project_dir = cache_dir / "nested" / "blueprint"
            project_dir.mkdir(parents=True)
            (cache_dir / ".git").mkdir()
            lakefile = project_dir / "lakefile.lean"
            lakefile.write_text(OFFICIAL_BLUEPRINT_REQUIRE + "\n", encoding="utf-8")
            layout = SimpleNamespace(
                package_root=root / "worktree",
                repo_root=root / "root",
                reference_source_cache_root=root / "cache",
                reference_dependency_cache_root=root / "deps",
            )
            layout.package_root.mkdir()
            layout.repo_root.mkdir()

            originals = {
                "command_rewrite_local_blueprint_dependency": commands_mod.rewrite_local_blueprint_dependency,
                "update_git_checkout": refs_mod.update_git_checkout,
                "bootstrap_reference_checkout": refs_mod.bootstrap_reference_checkout,
                "project_lake_update_command": refs_mod.project_lake_update_command,
                "run": refs_mod.run,
            }
            seen: dict[str, object] = {}
            try:
                refs_mod.update_git_checkout = lambda _project, _cache_dir: None
                refs_mod.bootstrap_reference_checkout = lambda *, project_dir: None

                def fake_rewrite(_project_dir, package_root):
                    seen["package_root"] = package_root
                    return lakefile

                commands_mod.rewrite_local_blueprint_dependency = fake_rewrite
                refs_mod.project_lake_update_command = lambda _package_root, _project_dir: ["lake", "update"]
                refs_mod.run = lambda _command, *, cwd: None

                refs_mod.sync_reference_cache_checkout(layout, project, warm_build=False)
            finally:
                for name, value in originals.items():
                    if name == "command_rewrite_local_blueprint_dependency":
                        commands_mod.rewrite_local_blueprint_dependency = value
                    else:
                        setattr(refs_mod, name, value)

            self.assertEqual(seen["package_root"], layout.package_root)
            self.assertEqual(lakefile.read_text(encoding="utf-8"), OFFICIAL_BLUEPRINT_REQUIRE + "\n")

    def test_reference_cache_checkout_rewrites_override_to_absolute_linked_worktree_path(self) -> None:
        import scripts.blueprint_harness_references as refs_mod

        project = HarnessProject(
            project_id="external-blueprint",
            source_kind="git_checkout",
            project_root=".",
            build_target=None,
            generator=None,
            repository="https://github.com/example/external-blueprint.git",
            ref="main",
            build_command=None,
            generate_command=VBP_BUILD_COMMAND,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
        )
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            worktrees_root = root / ".worktrees"
            package_root = worktrees_root / "docs-431-reference-catalog"
            cache_dir = worktrees_root / "_reference-blueprints" / "cache" / reference_dependency_cache_key(project)
            cache_dir.mkdir(parents=True)
            (cache_dir / ".git").mkdir()
            lakefile = cache_dir / "lakefile.lean"
            lakefile.write_text(OFFICIAL_BLUEPRINT_REQUIRE + "\n", encoding="utf-8")
            package_root.mkdir(parents=True)
            layout = SimpleNamespace(
                package_root=package_root,
                repo_root=root,
                reference_source_cache_root=worktrees_root / "_reference-blueprints" / "cache",
                reference_dependency_cache_root=worktrees_root / "_reference-blueprints" / "deps",
            )

            originals = {
                "update_git_checkout": refs_mod.update_git_checkout,
                "bootstrap_reference_checkout": refs_mod.bootstrap_reference_checkout,
                "project_lake_update_command": refs_mod.project_lake_update_command,
                "run": refs_mod.run,
            }
            seen: dict[str, str] = {}

            def fake_run(command, *, cwd):
                if command == ["lake", "update"]:
                    seen["lakefile_during_update"] = lakefile.read_text(encoding="utf-8")
                    return
                raise AssertionError(f"unexpected command: {command}")

            try:
                refs_mod.update_git_checkout = lambda _project, _cache_dir: None
                refs_mod.bootstrap_reference_checkout = lambda *, project_dir: None
                refs_mod.project_lake_update_command = lambda _package_root, _project_dir: ["lake", "update"]
                refs_mod.run = fake_run

                refs_mod.sync_reference_cache_checkout(layout, project, warm_build=False)
            finally:
                for name, value in originals.items():
                    setattr(refs_mod, name, value)

            self.assertIn(f'require VersoBlueprint from "{package_root.resolve()}"', seen["lakefile_during_update"])
            self.assertNotIn("../../../docs-431-reference-catalog", seen["lakefile_during_update"])
            self.assertEqual(lakefile.read_text(encoding="utf-8"), OFFICIAL_BLUEPRINT_REQUIRE + "\n")

    def test_reference_cache_warm_build_failure_reports_recovery_hints(self) -> None:
        import scripts.blueprint_harness_references as refs_mod

        project = HarnessProject(
            project_id="external-blueprint",
            source_kind="git_checkout",
            project_root="nested/blueprint",
            build_target=None,
            generator=None,
            repository="https://github.com/example/external-blueprint.git",
            ref="main",
            build_command=("lake", "build"),
            generate_command=VBP_BUILD_COMMAND,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
        )
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_key = reference_dependency_cache_key(project)
            cache_dir = root / "cache" / cache_key
            project_dir = cache_dir / "nested" / "blueprint"
            project_dir.mkdir(parents=True)
            (cache_dir / ".git").mkdir()
            lakefile = project_dir / "lakefile.lean"
            lakefile.write_text(OFFICIAL_BLUEPRINT_REQUIRE + "\n", encoding="utf-8")
            layout = SimpleNamespace(
                package_root=root / "worktree",
                repo_root=root / "root",
                reference_source_cache_root=root / "cache",
                reference_dependency_cache_root=root / "deps",
            )
            layout.package_root.mkdir()
            layout.repo_root.mkdir()

            originals = {
                "update_git_checkout": refs_mod.update_git_checkout,
                "bootstrap_reference_checkout": refs_mod.bootstrap_reference_checkout,
                "project_lake_update_command": refs_mod.project_lake_update_command,
                "run": refs_mod.run,
                "run_with_heartbeat": refs_mod.run_with_heartbeat,
            }

            def fake_run(command, *, cwd):
                if command == ["lake", "update"]:
                    return
                raise subprocess.CalledProcessError(7, command)

            def fake_run_with_heartbeat(command, *, cwd, label):
                fake_run(command, cwd=cwd)

            try:
                refs_mod.update_git_checkout = lambda _project, _cache_dir: None
                refs_mod.bootstrap_reference_checkout = lambda *, project_dir: None
                refs_mod.project_lake_update_command = lambda _package_root, _project_dir: ["lake", "update"]
                refs_mod.run = fake_run
                refs_mod.run_with_heartbeat = fake_run_with_heartbeat

                with self.assertRaises(SystemExit) as raised:
                    refs_mod.sync_reference_cache_checkout(layout, project, warm_build=True)
            finally:
                for name, value in originals.items():
                    setattr(refs_mod, name, value)

            message = str(raised.exception)
            self.assertIn("failed to warm reference cache for `external-blueprint`", message)
            self.assertIn(cache_key, message)
            self.assertIn(str(cache_dir), message)
            self.assertIn(str(root / "deps" / cache_key / "packages"), message)
            self.assertIn("incompatible `.olean` header", message)
            self.assertIn("create-worktree <name> --lightweight", message)
            self.assertIn("blueprint_reference_harness prune --dry-run", message)
            self.assertEqual(lakefile.read_text(encoding="utf-8"), OFFICIAL_BLUEPRINT_REQUIRE + "\n")

    def test_child_manifests_inherit_verso_and_subverso_from_root_without_mathlib(self) -> None:
        root_manifest_path = PACKAGE_ROOT / "lake-manifest.json"
        child_manifest_paths = [
            PACKAGE_ROOT / "project_template" / "lake-manifest.json",
            PACKAGE_ROOT / "tests" / "test_blueprints" / "preview_runtime_showcase" / "lake-manifest.json",
        ]
        root_manifest = json.loads(root_manifest_path.read_text(encoding="utf-8"))
        child_manifests = [json.loads(path.read_text(encoding="utf-8")) for path in child_manifest_paths]

        def package_entry(manifest_data: dict, package_name: str) -> dict:
            return next(entry for entry in manifest_data["packages"] if entry["name"] == package_name)

        root_verso = package_entry(root_manifest, "verso")
        for child_manifest in child_manifests:
            child_verso = package_entry(child_manifest, "verso")
            self.assertTrue(child_verso["inherited"])
            if root_verso.get("rev") is not None:
                self.assertEqual(child_verso.get("rev"), root_verso.get("rev"))
            self.assertEqual(
                package_entry(child_manifest, "subverso").get("rev"),
                package_entry(root_manifest, "subverso").get("rev"),
            )
            self.assertNotIn("mathlib", {entry["name"] for entry in child_manifest["packages"]})
        self.assertNotIn("mathlib", {entry["name"] for entry in root_manifest["packages"]})

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
                generate_command=VBP_BUILD_COMMAND,
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
            project_root="nested/blueprint",
            build_target=None,
            generator=None,
            repository="https://github.com/example/external-blueprint.git",
            ref="9b50e39c17434ee1a574fd27ed97006adfdc5dc1",
            build_command=None,
            generate_command=VBP_BUILD_COMMAND,
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
                generate_command=VBP_BUILD_COMMAND,
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
                generate_command=VBP_BUILD_COMMAND,
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

    def test_generate_git_project_uses_local_checkout_without_cache_warm_build(self) -> None:
        import scripts.blueprint_harness_project_commands as commands_mod
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
            generate_command=VBP_BUILD_OUTPUT_COMMAND,
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
                reference_dependency_cache_root=root / "deps",
            )
            layout.package_root.mkdir()
            layout.repo_root.mkdir()

            originals = {
                "command_rewrite_local_blueprint_dependency": commands_mod.rewrite_local_blueprint_dependency,
                "command_run": commands_mod.run,
                "command_run_with_heartbeat": commands_mod.run_with_heartbeat,
                "sync_reference_cache_checkout": refs_mod.sync_reference_cache_checkout,
                "sync_reference_local_checkout": refs_mod.sync_reference_local_checkout,
                "project_lake_update_command": refs_mod.project_lake_update_command,
                "run": refs_mod.run,
            }
            commands: list[list[str]] = []
            warm_build_values: list[bool] = []
            package_modes: list[str] = []

            def fake_sync_reference_cache_checkout(_layout, _project, *, warm_build, package_mode="copy"):
                warm_build_values.append(warm_build)
                package_modes.append(package_mode)
                return cache_dir

            def fake_sync_reference_local_checkout(_layout, _project, _cache_dir, *, package_mode="copy"):
                package_modes.append(package_mode)
                return local_dir

            try:
                refs_mod.sync_reference_cache_checkout = fake_sync_reference_cache_checkout
                refs_mod.sync_reference_local_checkout = fake_sync_reference_local_checkout
                commands_mod.rewrite_local_blueprint_dependency = (
                    lambda _project_dir, _package_root: local_dir / "lakefile.lean"
                )
                refs_mod.project_lake_update_command = lambda _package_root, _project_dir: ["lake", "update", "VersoBlueprint"]
                refs_mod.run = lambda command, *, cwd: commands.append(command)
                commands_mod.run = lambda command, *, cwd: commands.append(command)
                commands_mod.run_with_heartbeat = lambda command, *, cwd, label: commands.append(command)

                generate_git_project(layout, output_root, project, skip_build=False)
            finally:
                for name, value in originals.items():
                    if name == "command_rewrite_local_blueprint_dependency":
                        commands_mod.rewrite_local_blueprint_dependency = value
                    elif name == "command_run":
                        commands_mod.run = value
                    elif name == "command_run_with_heartbeat":
                        commands_mod.run_with_heartbeat = value
                    else:
                        setattr(refs_mod, name, value)

        self.assertEqual(warm_build_values, [False])
        self.assertEqual(package_modes, ["copy", "copy"])
        self.assertEqual(commands[0], reference_submodule_update_command())
        self.assertIn(["lake", "update", "VersoBlueprint"], commands)
        self.assertTrue(any(command[1:] == ["lake", "build"] for command in commands))
        self.assertTrue(
            any(
                command[1:]
                == [*VBP_BUILD_COMMAND, "--output", str(output_root / "external-blueprint")]
                for command in commands
            )
        )

    def test_generate_git_project_move_mode_restores_packages_after_failure(self) -> None:
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
            generate_command=VBP_BUILD_OUTPUT_COMMAND,
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
            marker = local_dir / ".lake" / "packages" / "mathlib" / ".lake" / "build" / "Mathlib.olean"
            marker.parent.mkdir(parents=True)
            marker.write_text("warm", encoding="utf-8")
            layout = SimpleNamespace(
                package_root=root / "pkg",
                repo_root=root / "repo",
                reference_dependency_cache_root=root / "deps",
            )
            layout.package_root.mkdir()
            layout.repo_root.mkdir()

            originals = {
                "rebuild_and_log_embedded_asset_owners": refs_mod.rebuild_and_log_embedded_asset_owners,
                "sync_reference_cache_checkout": refs_mod.sync_reference_cache_checkout,
                "sync_reference_local_checkout": refs_mod.sync_reference_local_checkout,
                "bootstrap_reference_checkout": refs_mod.bootstrap_reference_checkout,
            }
            package_modes: list[str] = []

            def fake_sync_reference_cache_checkout(_layout, _project, *, warm_build, package_mode="copy"):
                package_modes.append(package_mode)
                return cache_dir

            def fake_sync_reference_local_checkout(_layout, _project, _cache_dir, *, package_mode="copy"):
                package_modes.append(package_mode)
                return local_dir

            try:
                refs_mod.rebuild_and_log_embedded_asset_owners = lambda _package_root: None
                refs_mod.sync_reference_cache_checkout = fake_sync_reference_cache_checkout
                refs_mod.sync_reference_local_checkout = fake_sync_reference_local_checkout
                refs_mod.bootstrap_reference_checkout = lambda *, project_dir: (_ for _ in ()).throw(RuntimeError("boom"))

                with self.assertRaisesRegex(RuntimeError, "boom"):
                    generate_git_project(layout, output_root, project, skip_build=False, package_mode="move")
            finally:
                for name, value in originals.items():
                    setattr(refs_mod, name, value)

            dependency_packages = root / "deps" / reference_dependency_cache_key(project) / "packages"

            self.assertEqual(package_modes, ["move", "move"])
            self.assertFalse((local_dir / ".lake" / "packages").exists())
            self.assertEqual(
                (dependency_packages / "mathlib" / ".lake" / "build" / "Mathlib.olean").read_text(encoding="utf-8"),
                "warm",
            )

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
            generate_command=VBP_BUILD_OUTPUT_COMMAND,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
        )
        layout = SimpleNamespace(
            package_root=Path("/tmp/package"),
            artifact_root=Path("/tmp/out"),
            reference_project_checkout_root=Path("/tmp/checkouts"),
            reference_source_cache_root=Path("/tmp/cache"),
            reference_dependency_cache_root=Path("/tmp/deps"),
        )
        edit_dir = Path("/tmp/edit/external-blueprint")
        originals = {
            "prepare_reference_edit_checkout": refs_mod.prepare_reference_edit_checkout,
            "git_checkout_is_clean": refs_mod.git_checkout_is_clean,
            "rewrite_pinned_blueprint_dependency": refs_mod.rewrite_pinned_blueprint_dependency,
            "project_lake_update_command": refs_mod.project_lake_update_command,
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
            refs_mod.project_lake_update_command = lambda _package_root, _project_dir: ["lake", "update", "VersoBlueprint"]
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
            generate_command=VBP_BUILD_OUTPUT_COMMAND,
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
                reference_source_cache_root=root / "cache",
                reference_dependency_cache_root=root / "deps",
            )
            edit_dir = root / "edit" / "external-blueprint"
            output_root = root / "review"
            originals = {
                "prepare_reference_edit_checkout": refs_mod.prepare_reference_edit_checkout,
                "git_checkout_is_clean": refs_mod.git_checkout_is_clean,
                "rewrite_pinned_blueprint_dependency": refs_mod.rewrite_pinned_blueprint_dependency,
                "project_lake_update_command": refs_mod.project_lake_update_command,
                "run": refs_mod.run,
                "run_with_heartbeat": refs_mod.run_with_heartbeat,
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
                refs_mod.project_lake_update_command = lambda _package_root, _project_dir: ["lake", "update", "VersoBlueprint"]
                refs_mod.run = lambda command, *, cwd: commands.append(command)
                refs_mod.run_with_heartbeat = lambda command, *, cwd, label: commands.append(command)
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
            project_root="nested/blueprint",
            build_target=None,
            generator=None,
            repository="https://github.com/example/external-blueprint.git",
            ref="main",
            build_command=("lake", "build"),
            generate_command=VBP_BUILD_COMMAND,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
        )

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_key = reference_dependency_cache_key(project)
            local_dir = root / "local" / cache_key
            cache_dir = root / "cache" / cache_key
            edit_dir = root / "edit" / project.project_id
            (local_dir / "nested" / "blueprint" / ".lake" / "packages").mkdir(parents=True)
            (cache_dir / "nested" / "blueprint" / ".lake" / "packages").mkdir(parents=True)
            (edit_dir / "nested" / "blueprint").mkdir(parents=True)
            layout = SimpleNamespace(
                package_root=root / "pkg",
                reference_project_checkout_root=root / "local",
                reference_source_cache_root=root / "cache",
                reference_dependency_cache_root=root / "deps",
            )
            layout.package_root.mkdir()

            originals = {
                "run": refs_mod.run,
            }
            original_shutil_which = refs_mod.shutil.which
            commands: list[list[str]] = []
            try:
                refs_mod.shutil.which = lambda _name: "/usr/bin/rsync"
                refs_mod.run = lambda command, *, cwd: commands.append(command)

                source = seed_reference_edit_checkout_lake(layout, project, edit_dir)
            finally:
                for name, value in originals.items():
                    setattr(refs_mod, name, value)
                refs_mod.shutil.which = original_shutil_which

        self.assertEqual(source, local_dir / "nested" / "blueprint" / ".lake")
        self.assertEqual(
            commands,
            [
                [
                    "rsync",
                    "-a",
                    "--delete",
                    f"{local_dir / 'nested' / 'blueprint' / '.lake'}/",
                    f"{edit_dir / 'nested' / 'blueprint' / '.lake'}/",
                ]
            ],
        )

    def test_sync_reference_local_checkout_rsyncs_warmed_cache_lake(self) -> None:
        import scripts.blueprint_harness_references as refs_mod

        project = HarnessProject(
            project_id="external-blueprint",
            source_kind="git_checkout",
            project_root="nested/blueprint",
            build_target=None,
            generator=None,
            repository="https://github.com/example/external-blueprint.git",
            ref="main",
            build_command=("lake", "build"),
            generate_command=VBP_BUILD_COMMAND,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
        )

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_key = reference_dependency_cache_key(project)
            cache_dir = root / "cache" / cache_key
            cache_dir.mkdir(parents=True)
            (cache_dir / "nested" / "blueprint" / ".lake" / "packages" / "mathlib" / ".lake" / "build").mkdir(
                parents=True
            )
            layout = SimpleNamespace(
                package_root=root / "pkg",
                reference_project_checkout_root=root / "checkouts",
                reference_dependency_cache_root=root / "deps",
            )
            layout.package_root.mkdir()

            originals = {
                "clone_git_project": refs_mod.clone_git_project,
                "update_git_checkout": refs_mod.update_git_checkout,
                "run": refs_mod.run,
            }
            commands: list[list[str]] = []
            try:
                refs_mod.clone_git_project = (
                    lambda _project, destination, *, cwd, source=None, shallow=True: (
                        destination / "nested" / "blueprint"
                    ).mkdir(parents=True)
                    or destination
                )
                refs_mod.update_git_checkout = lambda _project, _checkout_root: None
                refs_mod.run = lambda command, *, cwd: commands.append(command)

                local_dir = refs_mod.sync_reference_local_checkout(layout, project, cache_dir)
            finally:
                for name, value in originals.items():
                    setattr(refs_mod, name, value)

        self.assertEqual(local_dir, root / "checkouts" / cache_key)
        self.assertIn(
            [
                "rsync",
                "-a",
                "--exclude",
                "/build/",
                f"{cache_dir / 'nested' / 'blueprint' / '.lake'}/",
                f"{local_dir / 'nested' / 'blueprint' / '.lake'}/",
            ],
            commands,
        )

    def test_reference_prune_plan_finds_stale_cache_and_checkout_paths(self) -> None:
        from scripts.blueprint_harness_references import reference_prune_plan

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_root = root / "cache"
            dependency_cache_root = root / "deps"
            checkout_root = root / "by-worktree"
            (cache_root / "noperthedron-ref-active").mkdir(parents=True)
            (cache_root / "oldproject-ref-stale").mkdir(parents=True)
            (dependency_cache_root / "noperthedron-ref-active").mkdir(parents=True)
            (dependency_cache_root / "oldproject-ref-stale").mkdir(parents=True)
            (checkout_root / "v4.29.0" / "noperthedron-ref-active").mkdir(parents=True)
            (checkout_root / "v4.29.0" / "oldproject-ref-stale").mkdir(parents=True)
            (checkout_root / "stale-worktree" / "noperthedron-ref-active").mkdir(parents=True)

            removals = reference_prune_plan(
                {"v4.29.0", "cleanup-automation"},
                {"noperthedron-ref-active"},
                cache_root,
                checkout_root,
                dependency_cache_root,
            )

            self.assertEqual(
                {path.relative_to(root).as_posix() for path in removals},
                {
                    "cache/oldproject-ref-stale",
                    "deps/oldproject-ref-stale",
                    "by-worktree/v4.29.0/oldproject-ref-stale",
                    "by-worktree/stale-worktree",
                },
            )


if __name__ == "__main__":
    unittest.main()
