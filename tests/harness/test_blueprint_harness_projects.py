from __future__ import annotations

from dataclasses import replace
import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest

from scripts.blueprint_harness_projects import (
    HarnessProject,
    IN_REPO_PROJECT_SOURCE_KIND,
    command_with_pdf,
    default_project_manifest,
    deploy_matrix_from_controller_catalog,
    load_project_catalog,
    load_project_catalog_data,
    reference_build_matrix,
    reference_source_identity,
    reference_release_payload,
    resolve_projects_for_release,
    resolve_release_target,
    selected_project_toolchain,
)
from scripts.blueprint_harness_branches import load_branch_policy
from scripts.blueprint_harness_project_commands import tracked_project_manifest_path
from scripts.blueprint_harness_releases import release_candidate_ref
from scripts.blueprint_harness_references import (
    bootstrap_reference_checkout,
    bump_reference_project,
    clone_git_project,
    default_reference_bump_branch,
    default_reference_edit_base,
    generate_git_project,
    output_dir_for,
    reference_source_paths,
    reference_submodule_update_command,
    require_reference_harness_layout,
    run_external_reference_lake_update,
    seed_lake_path_builds_from_dependency_cache,
    seed_reference_edit_checkout_lake,
    seed_lake_packages_from_dependency_cache,
    store_lake_path_builds_in_dependency_cache,
    store_lake_packages_in_dependency_cache,
    update_git_checkout,
    validate_external_reference_toolchain,
)
from tests.harness.project_fixtures import TEST_OFFICIAL_BLUEPRINT_REQUIRE


PACKAGE_ROOT = Path(__file__).resolve().parents[2]
VBP_BUILD_COMMAND = ("lake", "exe", "vbp", "build")
VBP_BUILD_OUTPUT_COMMAND = (*VBP_BUILD_COMMAND, "--output", "{output_dir}")
VBP_BUILD_PDF_COMMAND = (*VBP_BUILD_COMMAND, "--pdf")

DEFAULT_EXTERNAL_PROJECT = HarnessProject(
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


def external_project(**changes) -> HarnessProject:
    return replace(DEFAULT_EXTERNAL_PROJECT, **changes)


def load_project_catalog_text(text: str, manifest_path: Path | str):
    raw = json.loads(text)
    if not isinstance(raw, dict):
        raise ValueError(f"{manifest_path}: expected JSON object")
    return load_project_catalog_data(raw, manifest_path)


class BlueprintHarnessProjectsTests(unittest.TestCase):
    def test_command_with_pdf_appends_pdf_once(self) -> None:
        self.assertEqual(
            command_with_pdf(VBP_BUILD_COMMAND),
            VBP_BUILD_PDF_COMMAND,
        )
        self.assertEqual(
            command_with_pdf(VBP_BUILD_PDF_COMMAND),
            VBP_BUILD_PDF_COMMAND,
        )

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
        expected_toolchains: dict[str, str | None] = {}
        expected_targets = [
            (project, target)
            for project in catalog.projects
            if (target := project.target_for_release(release.release_id)) is not None and target.publish_reference
        ]
        for project, target in expected_targets:
            expected_projects.append(project.project_id)
            expected_refs[project.project_id] = target.ref
            expected_rcs[project.project_id] = target.rc
            expected_toolchains[project.project_id] = target.toolchain

        self.assertEqual([project.project_id for project in projects], expected_projects)
        for project in projects:
            self.assertEqual(project.selected_release, release.release_id)
            self.assertEqual(project.selected_rc, expected_rcs[project.project_id])
            self.assertEqual(project.selected_toolchain, expected_toolchains[project.project_id])
            expected_ref = expected_refs[project.project_id]
            if expected_ref is not None:
                self.assertEqual(project.ref, expected_ref)

    def assert_single_maintained_release_target(
        self,
        project: HarnessProject,
        release_ids: set[str],
        *,
        publish_reference: bool | None = None,
    ) -> None:
        self.assertEqual(len(project.targets), 1)
        self.assertIn(project.targets[0].release, release_ids)
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
        release_id_set = {target.release_id for target in branch_policy.release_targets}
        self.assertEqual(branch_policy.required_backport_branches, ())
        self.assertTrue(projects[0].in_repo_project)
        self.assertTrue(projects[0].in_repo_command_project)
        self.assertEqual(projects[0].project_root, "project_template")
        self.assertIsNone(projects[0].build_command)
        self.assertEqual(projects[0].generate_command, VBP_BUILD_OUTPUT_COMMAND)
        expected_template_targets = [target.release_id for target in branch_policy.release_targets]
        self.assertEqual([target.release for target in projects[0].targets], expected_template_targets)
        default_template_target = projects[0].target_for_release(branch_policy.default_dev_branch)
        self.assertIsNotNone(default_template_target)
        self.assertFalse(default_template_target.publish_reference)
        self.assertFalse(any(target.publish_reference for target in projects[0].targets))
        for release_id in branch_policy.required_backport_branches:
            self.assertTrue(catalog.release_target(release_id).deploy_pages)
        self.assertEqual(current_release.release_toolchain, current_release.toolchain)
        self.assertEqual(current_release.release_verso_ref, current_release.verso_ref)
        if current_release.deploy_pages:
            self.assertTrue(resolve_projects_for_release(catalog, current_release.release_id, None))
        expected_external_repositories = {
            "noperthedron": "https://github.com/ejgallego/verso-noperthedron.git",
            "spherepackingblueprint": "https://github.com/ejgallego/verso-sphere-packing.git",
            "verso-flt": "https://github.com/ejgallego/verso-flt.git",
            "verso-carleson": "https://github.com/ejgallego/verso-carleson.git",
        }
        for project in projects[1:]:
            self.assertTrue(project.git_checkout)
            self.assertEqual(project.repository, expected_external_repositories[project.project_id])
            self.assert_single_maintained_release_target(project, release_id_set, publish_reference=True)
            self.assertIsNone(project.build_command)
            self.assertEqual(project.generate_command, VBP_BUILD_OUTPUT_COMMAND)

    def test_selected_project_toolchain_requires_resolved_release_metadata(self) -> None:
        catalog = load_project_catalog(default_project_manifest(PACKAGE_ROOT))
        noperthedron = resolve_projects_for_release(catalog, "v4.32.0", ["noperthedron"])[0]
        spherepacking = resolve_projects_for_release(catalog, "v4.32.0", ["spherepackingblueprint"])[0]

        self.assertEqual(selected_project_toolchain(noperthedron), "v4.32.0")
        self.assertEqual(selected_project_toolchain(spherepacking), "v4.32.0")
        with self.assertRaisesRegex(ValueError, "has no selected release target"):
            selected_project_toolchain(catalog.projects[1])

    def test_selected_project_toolchain_prefers_compiler_only_override(self) -> None:
        project = external_project(
            selected_release="v4.33.0",
            selected_rc=None,
            selected_toolchain="v4.33.0-rc1",
        )

        self.assertEqual(selected_project_toolchain(project), "v4.33.0-rc1")

    def test_project_catalog_requires_json_object(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "projects.json"
            manifest.write_text("[]\n", encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "expected JSON object"):
                load_project_catalog(manifest)

    def test_reference_source_identity_tracks_external_source(self) -> None:
        base_project = external_project(
            ref="0123456789abcdef0123456789abcdef01234567",
            selected_release="v4.29.0",
        )
        same_source_other_release = replace(base_project, selected_release="v4.30.0")
        changed_ref = replace(
            base_project,
            ref="fedcba9876543210fedcba9876543210fedcba98",
        )

        identity = reference_source_identity(base_project)

        self.assertTrue(identity.startswith("external-blueprint-0123456789ab-"))
        self.assertEqual(identity, reference_source_identity(same_source_other_release))
        self.assertNotEqual(identity, reference_source_identity(changed_ref))

    def test_reference_dependency_packages_seed_independent_consumers(self) -> None:
        project = external_project()

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source_identity = reference_source_identity(project)
            dependency_packages = root / "deps" / source_identity / "packages"
            first_project_dir = root / "first-checkout" / "nested" / "blueprint"
            second_project_dir = root / "second-checkout" / "nested" / "blueprint"
            dependency_packages.mkdir(parents=True)
            shared_marker = dependency_packages / "mathlib" / ".lake" / "build" / "Mathlib.olean"
            shared_marker.parent.mkdir(parents=True)
            shared_marker.write_text("shared", encoding="utf-8")
            layout = SimpleNamespace(
                package_root=root / "pkg",
                reference_source_cache_root=root / "cache",
                reference_dependency_cache_root=root / "deps",
                reference_project_checkout_root=root / "checkouts",
            )
            layout.package_root.mkdir()

            first_seed = seed_lake_packages_from_dependency_cache(layout, project, first_project_dir)
            second_seed = seed_lake_packages_from_dependency_cache(layout, project, second_project_dir)
            first_marker = first_project_dir / ".lake" / "packages" / "mathlib" / ".lake" / "build" / "Mathlib.olean"
            second_marker = second_project_dir / ".lake" / "packages" / "mathlib" / ".lake" / "build" / "Mathlib.olean"

            self.assertEqual(first_seed, dependency_packages)
            self.assertEqual(second_seed, dependency_packages)
            self.assertEqual(first_marker.read_text(encoding="utf-8"), "shared")
            self.assertEqual(second_marker.read_text(encoding="utf-8"), "shared")

            with self.assertRaisesRegex(RuntimeError, "consumer failed"):
                first_marker.write_text("dirty consumer", encoding="utf-8")
                raise RuntimeError("consumer failed")

            self.assertEqual(shared_marker.read_text(encoding="utf-8"), "shared")
            self.assertEqual(second_marker.read_text(encoding="utf-8"), "shared")

    def test_reference_dependency_packages_refresh_shared_cache_by_copy(self) -> None:
        project = external_project()

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source_identity = reference_source_identity(project)
            dependency_packages = root / "deps" / source_identity / "packages"
            shared_marker = dependency_packages / "mathlib" / ".lake" / "build" / "Mathlib.olean"
            shared_marker.parent.mkdir(parents=True)
            shared_marker.write_text("old", encoding="utf-8")
            project_dir = root / "checkout" / project.project_root
            local_marker = project_dir / ".lake" / "packages" / "mathlib" / ".lake" / "build" / "Mathlib.olean"
            local_marker.parent.mkdir(parents=True)
            local_marker.write_text("warm", encoding="utf-8")
            layout = SimpleNamespace(
                package_root=root / "pkg",
                reference_source_cache_root=root / "cache",
                reference_dependency_cache_root=root / "deps",
                reference_project_checkout_root=root / "checkouts",
            )
            layout.package_root.mkdir()

            stored_to = store_lake_packages_in_dependency_cache(layout, project, project_dir)

            self.assertEqual(stored_to, dependency_packages)
            self.assertEqual(shared_marker.read_text(encoding="utf-8"), "warm")
            self.assertEqual(local_marker.read_text(encoding="utf-8"), "warm")

    def test_reference_source_paths_share_one_identity_and_exclude_generated_output(self) -> None:
        project = external_project()
        layout = SimpleNamespace(
            reference_source_cache_root=Path("/tmp/cache"),
            reference_dependency_cache_root=Path("/tmp/deps"),
            reference_project_checkout_root=Path("/tmp/by-worktree/demo"),
        )

        paths = reference_source_paths(layout, project)
        output = output_dir_for(project, Path("/tmp/output"))

        self.assertEqual(paths.identity, reference_source_identity(project))
        self.assertEqual(paths.source_checkout, Path("/tmp/cache") / paths.identity)
        self.assertEqual(paths.dependency_packages, Path("/tmp/deps") / paths.identity / "packages")
        self.assertEqual(paths.dependency_path_builds, Path("/tmp/deps") / paths.identity / "path-builds")
        self.assertEqual(paths.local_checkout, Path("/tmp/by-worktree/demo") / paths.identity)
        self.assertEqual(output, Path("/tmp/output/external-blueprint"))
        for managed_path in (paths.source_checkout, paths.dependency_packages.parent, paths.local_checkout):
            self.assertFalse(output.is_relative_to(managed_path))

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

        project = external_project()

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source_identity = reference_source_identity(project)
            path_builds = root / "deps" / source_identity / "path-builds"
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
                reference_source_cache_root=root / "cache",
                reference_dependency_cache_root=root / "deps",
                reference_project_checkout_root=root / "checkouts",
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
        release = resolve_release_target(catalog, "v4.32.0", PACKAGE_ROOT)
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
        self.assertIn("path: _out/reference-blueprints-artifacts", workflow_text)
        self.assertIn("--reference-root _out/reference-blueprints-artifacts", workflow_text)
        self.assertNotIn("merge-multiple: true", workflow_text)
        self.assertIn("--project ${{ matrix.project_id }}", workflow_text)
        self.assertIn("--pdf --project ${{ matrix.project_id }}", workflow_text)
        self.assertIn("Install PDF toolchain", workflow_text)
        self.assertIn("Generate reference blueprint with PDF", workflow_text)
        self.assertIn("lualatex --version", workflow_text)
        self.assertIn("texlive-fonts-extra", workflow_text)
        self.assertIn("texlive-plain-generic", workflow_text)
        self.assertIn("matrix.reference_source_identity", workflow_text)
        self.assertIn("matrix.reference_dependency_packages_path", workflow_text)
        self.assertIn("matrix.reference_dependency_path_builds_path", workflow_text)
        self.assertIn("reference-deps-v2-${{ matrix.reference_source_identity }}", workflow_text)
        self.assertIn("matrix.reference_dependency_packages_path", deploy_workflow_text)
        self.assertIn("matrix.reference_dependency_path_builds_path", deploy_workflow_text)
        self.assertIn("reference-deploy-deps-v2-${{ matrix.reference_source_identity }}", deploy_workflow_text)
        self.assertIn(
            "group: ${{ github.repository }}-reference-blueprints-pages",
            deploy_workflow_text,
        )
        self.assertNotIn("reference-blueprints-pages-release-", deploy_workflow_text)
        self.assertNotIn("reference-blueprints-pages-dispatch-", deploy_workflow_text)
        self.assertIn("Install PDF toolchain", deploy_workflow_text)
        self.assertIn(
            "if: ${{ steps.generated-site-cache.outputs.cache-hit != 'true' && matrix.publish_pdf }}",
            deploy_workflow_text,
        )
        self.assertIn("publish_pdf=${{ matrix.publish_pdf }}", deploy_workflow_text)
        self.assertIn("Generate release reference blueprints", deploy_workflow_text)
        self.assertIn("lualatex --version", deploy_workflow_text)
        self.assertIn("texlive-fonts-extra", deploy_workflow_text)
        self.assertIn("texlive-plain-generic", deploy_workflow_text)
        self.assertIn("uses: actions/cache/restore@v5", deploy_workflow_text)
        self.assertIn("uses: actions/cache/save@v5", deploy_workflow_text)
        self.assertIn(
            "reference-site-v1-${{ steps.artifact-identity.outputs.sha256 }}",
            deploy_workflow_text,
        )
        self.assertIn("reference_artifact_identity.py create", deploy_workflow_text)
        self.assertIn("reference_artifact_identity.py install", deploy_workflow_text)
        self.assertIn("reference_artifact_identity.py validate", deploy_workflow_text)
        self.assertIn("reference_artifact_identity.py expected-matrix", deploy_workflow_text)
        self.assertIn("--expected-identities _out/expected-reference-artifacts.json", deploy_workflow_text)
        self.assertIn("steps.generated-site-cache.outputs.cache-hit != 'true'", deploy_workflow_text)

        for entry in matrix["include"]:
            self.assertEqual(entry["artifact_name"], f"reference-blueprints-{entry['project_id']}")
            self.assertEqual(entry["artifact_path"], f"_out/reference-blueprints/{entry['project_id']}")
            self.assertIn("project_root", entry)
            if entry["hash"] is not None:
                identity = entry["reference_source_identity"]
                self.assertTrue(identity)
                self.assertEqual(
                    entry["reference_dependency_packages_path"],
                    f".worktrees/_reference-blueprints/deps/{identity}/packages",
                )
                self.assertEqual(
                    entry["reference_dependency_path_builds_path"],
                    f".worktrees/_reference-blueprints/deps/{identity}/path-builds",
                )
            else:
                self.assertEqual(entry["reference_source_identity"], "")
                self.assertEqual(entry["reference_dependency_packages_path"], "")
                self.assertEqual(entry["reference_dependency_path_builds_path"], "")

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
            expected_toolchain = (
                target.toolchain
                if target.toolchain is not None
                else release_candidate_ref(target.rc)
                if target.rc is not None
                else release.toolchain
            )
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
                                    "toolchain": "v4.29.0-rc2",
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
            pdf_release_id="v4.29.0",
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
        self.assertFalse(matrix_by_project["old-release-project"]["publish_pdf"])
        self.assertEqual(matrix_by_project["old-release-project"]["project_root"], "old-controller")
        self.assertEqual(matrix_by_project["old-release-project"]["rc"], "")
        self.assertEqual(matrix_by_project["old-release-project"]["toolchain"], "v4.28.0")
        self.assertTrue(
            matrix_by_project["old-release-project"]["reference_source_identity"].startswith("old-release-project-")
        )
        self.assertEqual(
            manifest_by_project["new-release-project"]["projects"][0]["targets"],
            [{"release": "v4.29.0", "ref": "new-controller-ref", "rc": "4.29-rc1"}],
        )
        self.assertEqual(
            manifest_by_project["new-release-project"]["projects"][0]["generate_command"],
            list(VBP_BUILD_PDF_COMMAND),
        )
        self.assertTrue(matrix_by_project["new-release-project"]["publish_pdf"])
        self.assertNotIn("rc", manifest_by_project["new-release-project"]["release_targets"][0])
        self.assertEqual(matrix_by_project["new-release-project"]["rc"], "4.29-rc1")
        self.assertEqual(matrix_by_project["new-release-project"]["toolchain"], "v4.29.0-rc1")
        self.assertEqual(matrix_by_project["new-release-project"]["verso_ref"], "v4.29.0-rc1")
        self.assertEqual(
            manifest_by_project["new-release-second-project"]["projects"][0]["targets"],
            [{"release": "v4.29.0", "ref": "new-second-controller-ref", "toolchain": "v4.29.0-rc2"}],
        )
        self.assertEqual(
            manifest_by_project["new-release-second-project"]["projects"][0]["generate_command"],
            list(VBP_BUILD_PDF_COMMAND),
        )
        self.assertTrue(matrix_by_project["new-release-second-project"]["publish_pdf"])
        self.assertEqual(matrix_by_project["new-release-second-project"]["rc"], "")
        self.assertEqual(matrix_by_project["new-release-second-project"]["toolchain"], "v4.29.0-rc2")
        self.assertEqual(matrix_by_project["new-release-second-project"]["verso_ref"], "v4.29.0")

    def test_default_deploy_matrix_publishes_pdfs_only_for_default_dev_release(self) -> None:
        catalog = load_project_catalog(default_project_manifest(PACKAGE_ROOT))
        branch_policy = load_branch_policy(PACKAGE_ROOT)
        deployable_targets = tuple(target for target in catalog.release_targets if target.deploy_pages)

        matrix = deploy_matrix_from_controller_catalog(
            catalog,
            deployable_targets,
            pdf_release_id=branch_policy.default_dev_branch,
        )

        rows = {
            (entry["release_id"], entry["project_id"]): entry
            for entry in matrix["include"]
        }
        expected_rows = {
            (target.release_id, project.project_id)
            for target in deployable_targets
            for project in catalog.projects
            if (project_target := project.target_for_release(target.release_id)) is not None
            and project_target.publish_reference
        }
        self.assertEqual(set(rows), expected_rows)
        for (release_id, _project_id), entry in rows.items():
            expected_pdf = release_id == branch_policy.default_dev_branch
            self.assertEqual(entry["publish_pdf"], expected_pdf)
            generate_command = entry["project_manifest"]["projects"][0]["generate_command"]
            self.assertEqual("--pdf" in generate_command, expected_pdf)

        current_release_projects = [
            entry
            for (release_id, _project_id), entry in rows.items()
            if release_id == branch_policy.default_dev_branch
        ]
        self.assertFalse(current_release_projects)
        for entry in current_release_projects:
            self.assertTrue(entry["publish_pdf"])
            self.assertIn("--pdf", entry["project_manifest"]["projects"][0]["generate_command"])

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
                            "toolchain": "v4.29.0-rc1",
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
        self.assertEqual(projects[0].targets[0].toolchain, "v4.29.0-rc1")

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
        self.assert_resolved_projects_match_manifest("v4.32.0")

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

    def test_validate_reference_toolchains_preserves_rc_project_and_dependencies(self) -> None:
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

            selected_ref = validate_external_reference_toolchain(
                package_root,
                project_dir,
                expected_project_toolchain="4.30-rc1",
            )

            self.assertEqual(selected_ref, "v4.30.0-rc1")
            self.assertEqual(
                (project_dir / "lean-toolchain").read_text(encoding="utf-8"),
                "leanprover/lean4:4.30-rc1\n",
            )
            self.assertEqual(
                (mathlib_dir / "lean-toolchain").read_text(encoding="utf-8"),
                "leanprover/lean4:v4.30.0-rc2",
            )
            self.assertEqual(
                (other_dir / "lean-toolchain").read_text(encoding="utf-8"),
                "leanprover/lean4:v4.29.0\n",
            )

    def test_validate_reference_toolchains_rejects_different_release_branches(self) -> None:
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

            with self.assertRaisesRegex(
                SystemExit,
                "reference Blueprint release mismatch.*Catalog each external Blueprint only under its current matching release",
            ):
                validate_external_reference_toolchain(
                    package_root,
                    project_dir,
                    expected_project_toolchain="v4.29.0",
                )

            self.assertEqual(
                (project_dir / "lean-toolchain").read_text(encoding="utf-8"),
                "leanprover/lean4:v4.29.0\n",
            )
            self.assertEqual(
                (mathlib_dir / "lean-toolchain").read_text(encoding="utf-8"),
                "leanprover/lean4:v4.29.0\n",
            )

    def test_reference_lake_update_rejects_missing_toolchain_before_update(self) -> None:
        import scripts.blueprint_harness_references as refs_mod

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package_root = root / "pkg"
            project_dir = root / "external"
            package_root.mkdir()
            project_dir.mkdir()
            (package_root / "lean-toolchain").write_text("leanprover/lean4:v4.30.0\n", encoding="utf-8")
            update_called = False

            original_run = refs_mod.run
            try:
                def unexpected_run(_command, *, cwd):
                    nonlocal update_called
                    update_called = True

                refs_mod.run = unexpected_run
                with self.assertRaisesRegex(SystemExit, "external reference project has no valid `lean-toolchain`"):
                    run_external_reference_lake_update(
                        package_root,
                        project_dir,
                        expected_project_toolchain="v4.30.0",
                    )
            finally:
                refs_mod.run = original_run

            self.assertFalse(update_called)

    def test_reference_lake_update_rejects_catalog_toolchain_drift_before_update(self) -> None:
        import scripts.blueprint_harness_references as refs_mod

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package_root = root / "pkg"
            project_dir = root / "external"
            package_root.mkdir()
            project_dir.mkdir()
            (package_root / "lean-toolchain").write_text("leanprover/lean4:v4.30.0\n", encoding="utf-8")
            (project_dir / "lean-toolchain").write_text("leanprover/lean4:v4.30.0-rc1\n", encoding="utf-8")
            update_called = False

            original_run = refs_mod.run
            try:
                def unexpected_run(_command, *, cwd):
                    nonlocal update_called
                    update_called = True

                refs_mod.run = unexpected_run
                with self.assertRaisesRegex(
                    SystemExit,
                    "catalog target expects Lean `v4.30.0`.*keep its explicit project-target RC metadata",
                ):
                    run_external_reference_lake_update(
                        package_root,
                        project_dir,
                        expected_project_toolchain="v4.30.0",
                    )
            finally:
                refs_mod.run = original_run

            self.assertFalse(update_called)

    def test_reference_lake_update_never_mutates_project_or_dependency_toolchains(self) -> None:
        import scripts.blueprint_harness_references as refs_mod

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package_root = root / "pkg"
            project_dir = root / "external"
            dependency_dir = project_dir / ".lake" / "packages" / "verso-slides"
            package_root.mkdir()
            dependency_dir.mkdir(parents=True)
            (package_root / "lean-toolchain").write_text("leanprover/lean4:v4.30.0\n", encoding="utf-8")
            (project_dir / "lean-toolchain").write_text("leanprover/lean4:v4.30.0-rc1\n", encoding="utf-8")
            dependency_toolchain = dependency_dir / "lean-toolchain"
            dependency_toolchain.write_text("leanprover/lean4:v4.30.0\n", encoding="utf-8")

            original_run = refs_mod.run
            original_update_command = refs_mod.project_lake_update_command
            seen: dict[str, str] = {}

            def fake_run(command, *, cwd):
                self.assertEqual(command, ["lake", "update"])
                self.assertEqual(cwd, project_dir)
                seen["project"] = (project_dir / "lean-toolchain").read_text(encoding="utf-8")
                seen["dependency"] = dependency_toolchain.read_text(encoding="utf-8")

            try:
                refs_mod.run = fake_run
                refs_mod.project_lake_update_command = lambda _package_root, _project_dir: ["lake", "update"]
                result = run_external_reference_lake_update(
                    package_root,
                    project_dir,
                    expected_project_toolchain="v4.30.0-rc1",
                )
            finally:
                refs_mod.run = original_run
                refs_mod.project_lake_update_command = original_update_command

            self.assertEqual(seen["project"], "leanprover/lean4:v4.30.0-rc1\n")
            self.assertEqual(seen["dependency"], "leanprover/lean4:v4.30.0\n")
            self.assertEqual((project_dir / "lean-toolchain").read_text(encoding="utf-8"), seen["project"])
            self.assertEqual(dependency_toolchain.read_text(encoding="utf-8"), "leanprover/lean4:v4.30.0\n")
            self.assertEqual(result, ["lake", "update"])

    def test_reference_cache_checkout_uses_current_package_root_override(self) -> None:
        import scripts.blueprint_harness_project_commands as commands_mod
        import scripts.blueprint_harness_references as refs_mod

        project = external_project(selected_release="v4.30.0")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_dir = root / "cache" / reference_source_identity(project)
            project_dir = cache_dir / "nested" / "blueprint"
            project_dir.mkdir(parents=True)
            (cache_dir / ".git").mkdir()
            lakefile = project_dir / "lakefile.lean"
            lakefile.write_text(TEST_OFFICIAL_BLUEPRINT_REQUIRE + "\n", encoding="utf-8")
            layout = SimpleNamespace(
                package_root=root / "worktree",
                repo_root=root / "root",
                reference_source_cache_root=root / "cache",
                reference_dependency_cache_root=root / "deps",
                reference_project_checkout_root=root / "checkouts",
            )
            layout.package_root.mkdir()
            layout.repo_root.mkdir()

            originals = {
                "command_rewrite_local_blueprint_dependency": commands_mod.rewrite_local_blueprint_dependency,
                "update_git_checkout": refs_mod.update_git_checkout,
                "bootstrap_reference_checkout": refs_mod.bootstrap_reference_checkout,
                "project_lake_update_command": refs_mod.project_lake_update_command,
                "validate_external_reference_toolchain": refs_mod.validate_external_reference_toolchain,
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
                refs_mod.validate_external_reference_toolchain = lambda *_args, **_kwargs: "v4.30.0"
                refs_mod.run = lambda _command, *, cwd: None

                refs_mod.sync_reference_cache_checkout(layout, project, warm_build=False)
            finally:
                for name, value in originals.items():
                    if name == "command_rewrite_local_blueprint_dependency":
                        commands_mod.rewrite_local_blueprint_dependency = value
                    else:
                        setattr(refs_mod, name, value)

            self.assertEqual(seen["package_root"], layout.package_root)
            self.assertEqual(lakefile.read_text(encoding="utf-8"), TEST_OFFICIAL_BLUEPRINT_REQUIRE + "\n")

    def test_reference_cache_checkout_rewrites_override_to_absolute_linked_worktree_path(self) -> None:
        import scripts.blueprint_harness_references as refs_mod

        project = external_project(
            project_root=".",
            build_command=None,
            selected_release="v4.30.0",
        )
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            worktrees_root = root / ".worktrees"
            package_root = worktrees_root / "docs-431-reference-catalog"
            cache_dir = worktrees_root / "_reference-blueprints" / "cache" / reference_source_identity(project)
            cache_dir.mkdir(parents=True)
            (cache_dir / ".git").mkdir()
            lakefile = cache_dir / "lakefile.lean"
            lakefile.write_text(TEST_OFFICIAL_BLUEPRINT_REQUIRE + "\n", encoding="utf-8")
            package_root.mkdir(parents=True)
            layout = SimpleNamespace(
                package_root=package_root,
                repo_root=root,
                reference_source_cache_root=worktrees_root / "_reference-blueprints" / "cache",
                reference_dependency_cache_root=worktrees_root / "_reference-blueprints" / "deps",
                reference_project_checkout_root=worktrees_root / "_reference-blueprints" / "by-worktree" / "demo",
            )

            originals = {
                "update_git_checkout": refs_mod.update_git_checkout,
                "bootstrap_reference_checkout": refs_mod.bootstrap_reference_checkout,
                "project_lake_update_command": refs_mod.project_lake_update_command,
                "validate_external_reference_toolchain": refs_mod.validate_external_reference_toolchain,
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
                refs_mod.validate_external_reference_toolchain = lambda *_args, **_kwargs: "v4.30.0"
                refs_mod.run = fake_run

                refs_mod.sync_reference_cache_checkout(layout, project, warm_build=False)
            finally:
                for name, value in originals.items():
                    setattr(refs_mod, name, value)

            self.assertIn(f'require VersoBlueprint from "{package_root.resolve()}"', seen["lakefile_during_update"])
            self.assertNotIn("../../../docs-431-reference-catalog", seen["lakefile_during_update"])
            self.assertEqual(lakefile.read_text(encoding="utf-8"), TEST_OFFICIAL_BLUEPRINT_REQUIRE + "\n")

    def test_reference_cache_warm_build_failure_reports_recovery_hints(self) -> None:
        import scripts.blueprint_harness_references as refs_mod

        project = external_project(selected_release="v4.30.0")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source_identity = reference_source_identity(project)
            cache_dir = root / "cache" / source_identity
            project_dir = cache_dir / "nested" / "blueprint"
            project_dir.mkdir(parents=True)
            (cache_dir / ".git").mkdir()
            lakefile = project_dir / "lakefile.lean"
            lakefile.write_text(TEST_OFFICIAL_BLUEPRINT_REQUIRE + "\n", encoding="utf-8")
            layout = SimpleNamespace(
                package_root=root / "worktree",
                repo_root=root / "root",
                reference_source_cache_root=root / "cache",
                reference_dependency_cache_root=root / "deps",
                reference_project_checkout_root=root / "checkouts",
            )
            layout.package_root.mkdir()
            layout.repo_root.mkdir()

            originals = {
                "update_git_checkout": refs_mod.update_git_checkout,
                "bootstrap_reference_checkout": refs_mod.bootstrap_reference_checkout,
                "project_lake_update_command": refs_mod.project_lake_update_command,
                "validate_external_reference_toolchain": refs_mod.validate_external_reference_toolchain,
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
                refs_mod.validate_external_reference_toolchain = lambda *_args, **_kwargs: "v4.30.0"
                refs_mod.run = fake_run
                refs_mod.run_with_heartbeat = fake_run_with_heartbeat

                with self.assertRaises(SystemExit) as raised:
                    refs_mod.sync_reference_cache_checkout(layout, project, warm_build=True)
            finally:
                for name, value in originals.items():
                    setattr(refs_mod, name, value)

            message = str(raised.exception)
            self.assertIn("failed to warm reference cache for `external-blueprint`", message)
            self.assertIn(source_identity, message)
            self.assertIn(str(cache_dir), message)
            self.assertIn(str(root / "deps" / source_identity / "packages"), message)
            self.assertIn("incompatible `.olean` header", message)
            self.assertIn("create-worktree <name> --lightweight", message)
            self.assertIn("blueprint_reference_harness prune --dry-run", message)
            self.assertEqual(lakefile.read_text(encoding="utf-8"), TEST_OFFICIAL_BLUEPRINT_REQUIRE + "\n")

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

            project = external_project(
                project_root=".",
                repository=str(remote),
                ref=first,
                build_command=None,
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
        project = external_project(
            ref="9b50e39c17434ee1a574fd27ed97006adfdc5dc1",
            build_command=None,
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

            project = external_project(
                project_root=".",
                repository=str(remote),
                ref=target,
                build_command=None,
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

            project = external_project(
                project_root=".",
                repository=str(remote),
                ref=target,
                build_command=None,
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

        project = external_project(
            project_root=".",
            generate_command=VBP_BUILD_OUTPUT_COMMAND,
            selected_release="v4.30.0",
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
                reference_source_cache_root=root / "cache",
                reference_dependency_cache_root=root / "deps",
                reference_project_checkout_root=root / "checkouts",
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
                "validate_external_reference_toolchain": refs_mod.validate_external_reference_toolchain,
                "run": refs_mod.run,
            }
            commands: list[list[str]] = []
            warm_build_values: list[bool] = []

            def fake_sync_reference_cache_checkout(_layout, _project, *, warm_build):
                warm_build_values.append(warm_build)
                return cache_dir

            def fake_sync_reference_local_checkout(_layout, _project, _cache_dir):
                return local_dir

            try:
                refs_mod.sync_reference_cache_checkout = fake_sync_reference_cache_checkout
                refs_mod.sync_reference_local_checkout = fake_sync_reference_local_checkout
                commands_mod.rewrite_local_blueprint_dependency = (
                    lambda _project_dir, _package_root: local_dir / "lakefile.lean"
                )
                refs_mod.project_lake_update_command = lambda _package_root, _project_dir: ["lake", "update", "VersoBlueprint"]
                refs_mod.validate_external_reference_toolchain = lambda *_args, **_kwargs: "v4.30.0"
                refs_mod.run = lambda command, *, cwd: commands.append(command)
                commands_mod.run = lambda command, *, cwd: commands.append(command)
                commands_mod.run_with_heartbeat = lambda command, *, cwd, label: commands.append(command)

                generate_git_project(layout, output_root, project, skip_build=False, pdf=True, verbose=True)
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
        self.assertEqual(commands[0], reference_submodule_update_command())
        self.assertIn(["lake", "update", "VersoBlueprint"], commands)
        self.assertTrue(any(command[1:] == ["lake", "build"] for command in commands))
        self.assertTrue(
            any(
                command[1:]
                == [
                    *VBP_BUILD_COMMAND,
                    "--output",
                    str(output_root / "external-blueprint"),
                    "--pdf",
                    "--verbose",
                ]
                for command in commands
            )
        )

    def test_reference_submodule_update_skips_lfs_smudge(self) -> None:
        self.assertEqual(
            reference_submodule_update_command()[:3],
            ["env", "GIT_LFS_SKIP_SMUDGE=1", "git"],
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

        project = external_project(
            project_root=".",
            generate_command=VBP_BUILD_OUTPUT_COMMAND,
            selected_release="v4.30.0",
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
            "validate_external_reference_toolchain": refs_mod.validate_external_reference_toolchain,
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
            refs_mod.validate_external_reference_toolchain = lambda *_args, **_kwargs: "v4.30.0"
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

        project = external_project(
            project_root=".",
            generate_command=VBP_BUILD_OUTPUT_COMMAND,
            selected_release="v4.30.0",
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
                "validate_external_reference_toolchain": refs_mod.validate_external_reference_toolchain,
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
                refs_mod.validate_external_reference_toolchain = lambda *_args, **_kwargs: "v4.30.0"
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

        project = external_project()

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source_identity = reference_source_identity(project)
            local_dir = root / "local" / source_identity
            cache_dir = root / "cache" / source_identity
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
