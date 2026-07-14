from __future__ import annotations

import argparse
from collections.abc import Iterator
from contextlib import contextmanager, redirect_stderr, redirect_stdout
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import scripts.blueprint_harness as harness_mod
import scripts.blueprint_reference_harness as reference_harness_mod
from scripts.blueprint_harness import build_parser, create_worktree_sync_policy
from scripts.blueprint_harness_cli import selected_output_root
from scripts.blueprint_reference_harness import generate_projects
from scripts.blueprint_harness_projects import (
    HarnessProject,
    HarnessProjectCatalog,
    HarnessProjectTarget,
    HarnessReleaseTarget,
    IN_REPO_PROJECT_SOURCE_KIND,
)
from scripts.blueprint_harness_worktrees import GitWorktree


VBP_BUILD_COMMAND = ("lake", "exe", "vbp", "build")


@contextmanager
def patched_attrs(target: object, **replacements: object) -> Iterator[None]:
    originals = {name: getattr(target, name) for name in replacements}
    try:
        for name, value in replacements.items():
            setattr(target, name, value)
        yield
    finally:
        for name, value in originals.items():
            setattr(target, name, value)


class BlueprintHarnessCliTests(unittest.TestCase):
    def assertParseFails(self, parser: argparse.ArgumentParser, argv: list[str]) -> None:
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            parser.parse_args(argv)

    def test_create_worktree_sync_policy_respects_lightweight_mode(self) -> None:
        args = argparse.Namespace(skip_sync=False, skip_reference_sync=False, lightweight=True)
        self.assertEqual(create_worktree_sync_policy(args), (True, True))

    def test_create_worktree_sync_policy_preserves_explicit_flags(self) -> None:
        args = argparse.Namespace(skip_sync=True, skip_reference_sync=False, lightweight=False)
        self.assertEqual(create_worktree_sync_policy(args), (True, False))

    def test_reference_generate_parses_allow_unsafe_root_release(self) -> None:
        parser = reference_harness_mod.build_parser()
        args = parser.parse_args(["generate", "--allow-unsafe-root-release", "--release", "v4.29.0"])
        self.assertTrue(args.allow_unsafe_root_release)
        self.assertEqual(args.release, "v4.29.0")

    def test_reference_generate_rejects_allow_unsafe_root_main_alias(self) -> None:
        parser = reference_harness_mod.build_parser()
        self.assertParseFails(parser, ["generate", "--allow-unsafe-root-main"])

    def test_reference_generate_accepts_named_output_root(self) -> None:
        parser = reference_harness_mod.build_parser()
        args = parser.parse_args(["generate", "--output-root", "/tmp/out"])
        self.assertIsNone(args.output_root)
        self.assertEqual(args.output_root_option, "/tmp/out")
        self.assertEqual(selected_output_root(args), "/tmp/out")

    def test_reference_validate_named_output_root_overrides_positional_root(self) -> None:
        parser = reference_harness_mod.build_parser()
        args = parser.parse_args(["validate", "/tmp/old", "--output-root", "/tmp/new"])
        self.assertEqual(args.output_root, "/tmp/old")
        self.assertEqual(args.output_root_option, "/tmp/new")
        self.assertEqual(selected_output_root(args), "/tmp/new")

    def test_reference_validate_parses_allow_unsafe_root_release(self) -> None:
        parser = reference_harness_mod.build_parser()
        args = parser.parse_args(["validate", "--allow-unsafe-root-release", "--release", "v4.29.0"])
        self.assertTrue(args.allow_unsafe_root_release)
        self.assertEqual(args.release, "v4.29.0")

    def test_reference_sync_parses_allow_unsafe_root_release(self) -> None:
        parser = reference_harness_mod.build_parser()
        args = parser.parse_args(["sync", "--allow-unsafe-root-release", "--release", "v4.29.0"])
        self.assertTrue(args.allow_unsafe_root_release)
        self.assertEqual(args.release, "v4.29.0")

    def test_reference_commands_parse_package_mode(self) -> None:
        parser = reference_harness_mod.build_parser()
        self.assertEqual(parser.parse_args(["generate"]).reference_package_mode, "copy")
        self.assertEqual(parser.parse_args(["generate", "--reference-package-mode", "move"]).reference_package_mode, "move")
        self.assertEqual(parser.parse_args(["validate", "--reference-package-mode", "move"]).reference_package_mode, "move")

    def test_reference_generation_commands_parse_verbose(self) -> None:
        parser = reference_harness_mod.build_parser()
        self.assertFalse(parser.parse_args(["generate"]).verbose)
        self.assertTrue(parser.parse_args(["generate", "--verbose"]).verbose)
        self.assertFalse(parser.parse_args(["validate"]).verbose)
        self.assertTrue(parser.parse_args(["validate", "--verbose"]).verbose)

    def test_reference_projects_parses_release_filter(self) -> None:
        parser = reference_harness_mod.build_parser()
        args = parser.parse_args(["projects", "--release", "v4.29.0"])
        self.assertEqual(args.release, "v4.29.0")

    def test_reference_release_status_parses_flags(self) -> None:
        parser = reference_harness_mod.build_parser()
        args = parser.parse_args(["release-status", "--release", "v4.28.0", "--outdated-only"])
        self.assertEqual(args.release, "v4.28.0")
        self.assertTrue(args.outdated_only)

    def test_release_status_parses_require_sync(self) -> None:
        parser = build_parser()
        args = parser.parse_args(["release-status", "--require-sync"])
        self.assertTrue(args.require_sync)

    def test_paths_parses_all_projects_flag(self) -> None:
        parser = build_parser()
        args = parser.parse_args(["paths", "--all-projects"])
        self.assertTrue(args.all_projects)

    def test_prepare_backports_parses_exemption_flag(self) -> None:
        parser = build_parser()
        args = parser.parse_args(["prepare-backports", "--exempt", "v4.28.0=docs-only"])
        self.assertEqual(args.exempt, ["v4.28.0=docs-only"])

    def test_prepare_pr_parses_public_message_fields(self) -> None:
        parser = build_parser()
        args = parser.parse_args(
            [
                "prepare-pr",
                "--title",
                "fix: tighten PR scaffolds",
                "--summary",
                "Update the public PR scaffold.",
                "--change",
                "Add a public PR message helper",
                "--source-branch",
                "fix/public-pr-scaffold",
                "--exempt",
                "v4.28.0=docs-only",
            ]
        )
        self.assertEqual(args.title, "fix: tighten PR scaffolds")
        self.assertEqual(args.summary, "Update the public PR scaffold.")
        self.assertEqual(args.change, ["Add a public PR message helper"])
        self.assertEqual(args.source_branch, "fix/public-pr-scaffold")
        self.assertEqual(args.exempt, ["v4.28.0=docs-only"])

    def test_prepare_backport_pr_parses_required_fields(self) -> None:
        parser = build_parser()
        args = parser.parse_args(["prepare-backport-pr", "v4.28.0", "--main-pr", "11"])
        self.assertEqual(args.release, "v4.28.0")
        self.assertFalse(args.all_required)
        self.assertEqual(args.main_pr, 11)
        self.assertIsNone(args.main_title)
        self.assertIsNone(args.source_branch)

    def test_prepare_backport_pr_parses_all_required_flag(self) -> None:
        parser = build_parser()
        args = parser.parse_args(["prepare-backport-pr", "--all-required", "--main-pr", "11"])
        self.assertIsNone(args.release)
        self.assertTrue(args.all_required)
        self.assertEqual(args.main_pr, 11)

    def test_backport_label_for_release_uses_normalized_release_ref(self) -> None:
        self.assertEqual(harness_mod.backport_label_for_release("v4.28.0"), "backport-v4.28.0")
        self.assertEqual(
            harness_mod.backport_label_for_release("leanprover/lean4:v4.28.0"),
            "backport-v4.28.0",
        )
        self.assertEqual(harness_mod.backport_label_for_release("4.28.0"), "backport-v4.28.0")

    def test_bump_toolchain_parses_optional_flags(self) -> None:
        parser = build_parser()
        args = parser.parse_args(["bump-toolchain", "4.29.0", "--verso-ref", "v4.29.0", "--skip-validation"])
        self.assertEqual(args.toolchain, "4.29.0")
        self.assertEqual(args.verso_ref, "v4.29.0")
        self.assertTrue(args.skip_validation)

    def test_start_release_line_parses_optional_flags(self) -> None:
        parser = build_parser()
        args = parser.parse_args(["start-release-line", "4.30-rc2", "--deploy-pages", "--skip-validation"])
        self.assertEqual(args.toolchain, "4.30-rc2")
        self.assertTrue(args.deploy_pages)
        self.assertTrue(args.skip_validation)

    def test_set_default_dev_branch_parses_branch(self) -> None:
        parser = build_parser()
        args = parser.parse_args(["set-default-dev-branch", "v4.30.0"])
        self.assertEqual(args.branch, "v4.30.0")

    def test_create_worktree_parses_lock_flag(self) -> None:
        parser = build_parser()
        args = parser.parse_args(["create-worktree", "demo", "--lock"])
        self.assertTrue(args.lock)

    def test_worktree_sync_alias_is_retired(self) -> None:
        parser = build_parser()
        self.assertParseFails(parser, ["worktree-sync"])

    def test_release_status_alias_is_retired(self) -> None:
        parser = build_parser()
        self.assertParseFails(parser, ["main-status"])

    def test_land_release_alias_is_retired(self) -> None:
        parser = build_parser()
        self.assertParseFails(parser, ["land-main", "feat/demo"])

    def test_worktree_claim_parses_lock_flags(self) -> None:
        parser = build_parser()
        lock_args = parser.parse_args(["worktree-claim", "demo", "--lock"])
        unlock_args = parser.parse_args(["worktree-claim", "demo", "--unlock"])
        self.assertTrue(lock_args.lock)
        self.assertFalse(lock_args.unlock)
        self.assertFalse(unlock_args.lock)
        self.assertTrue(unlock_args.unlock)

    def test_land_release_parses_cleanup_flags(self) -> None:
        parser = build_parser()
        args = parser.parse_args(["land-release", "feat/demo", "--cleanup", "--keep-remote", "--no-push"])
        self.assertEqual(args.source, "feat/demo")
        self.assertTrue(args.cleanup)
        self.assertTrue(args.keep_remote)
        self.assertTrue(args.no_push)

    def test_reference_edit_parses_project_branch_and_base(self) -> None:
        parser = reference_harness_mod.build_parser()
        args = parser.parse_args(
            ["edit", "noperthedron", "--release", "v4.29.0", "--branch", "wip/noperthedron", "--base", "origin/main"]
        )
        self.assertEqual(args.project, "noperthedron")
        self.assertEqual(args.release, "v4.29.0")
        self.assertEqual(args.branch, "wip/noperthedron")
        self.assertEqual(args.base, "origin/main")

    def test_reference_bump_blueprint_parses_ref_and_push(self) -> None:
        parser = reference_harness_mod.build_parser()
        args = parser.parse_args(
            ["bump-verso-blueprint", "--release", "v4.29.0", "--project", "noperthedron", "--ref", "v1.2.3", "--push"]
        )
        self.assertEqual(args.release, "v4.29.0")
        self.assertEqual(args.project, ["noperthedron"])
        self.assertEqual(args.ref, "v1.2.3")
        self.assertTrue(args.push)
        self.assertFalse(args.skip_build)
        self.assertFalse(args.generate)

    def test_parse_blueprint_manifest_pin_reads_committed_rev(self) -> None:
        text = """
        {
          "packages": [
            {
              "name": "VersoBlueprint",
              "type": "git",
              "url": "https://github.com/leanprover/verso-blueprint.git",
              "inputRev": "main",
              "rev": "deadbeef"
            }
          ]
        }
        """

        pin = reference_harness_mod.parse_blueprint_manifest_pin(text, source_path="lake-manifest.json")

        self.assertIsNotNone(pin)
        self.assertEqual(pin.source_path, "lake-manifest.json")
        self.assertEqual(pin.input_ref, "main")
        self.assertEqual(pin.resolved_ref, "deadbeef")

    def test_parse_blueprint_manifest_pin_ignores_unofficial_source(self) -> None:
        text = """
        {
          "packages": [
            {
              "name": "VersoBlueprint",
              "type": "git",
              "url": "https://github.com/example/verso-blueprint.git",
              "inputRev": "main",
              "rev": "deadbeef"
            }
          ]
        }
        """

        pin = reference_harness_mod.parse_blueprint_manifest_pin(text, source_path="lake-manifest.json")

        self.assertIsNone(pin)

    def test_parse_blueprint_lakefile_pin_handles_split_ref(self) -> None:
        text = """
        import Lake
        open Lake DSL

        require VersoBlueprint from git "https://github.com/leanprover/verso-blueprint.git" @
          "7e15d20e6a03859de535a359bca3760c039858b2"
        """

        pin = reference_harness_mod.parse_blueprint_lakefile_pin(text, source_path="lakefile.lean")

        self.assertIsNotNone(pin)
        self.assertEqual(pin.source_path, "lakefile.lean")
        self.assertEqual(pin.input_ref, "7e15d20e6a03859de535a359bca3760c039858b2")
        self.assertEqual(pin.resolved_ref, "7e15d20e6a03859de535a359bca3760c039858b2")

    def test_parse_blueprint_lakefile_pin_ignores_unofficial_source(self) -> None:
        text = """
        import Lake
        open Lake DSL

        require VersoBlueprint from git "https://github.com/example/verso-blueprint.git" @
          "7e15d20e6a03859de535a359bca3760c039858b2"
        """

        pin = reference_harness_mod.parse_blueprint_lakefile_pin(text, source_path="lakefile.lean")

        self.assertIsNone(pin)

    def test_create_worktree_uses_default_dev_ref_by_default(self) -> None:
        layout = SimpleNamespace(repo_root=Path("/tmp/repo"))
        with patched_attrs(
            harness_mod,
            default_dev_branch=lambda _repo_root: "v4.30.0",
            ref_oid=lambda _repo_root, ref: "abc" if ref == "origin/v4.30.0" else None,
            preferred_release_ref=lambda _repo_root: "origin/v4.29.0",
            active_release_branch=lambda _repo_root: "v4.29.0",
        ):
            self.assertEqual(harness_mod.resolve_create_worktree_base(layout, None), "origin/v4.30.0")

    def test_create_worktree_rejects_unsynced_local_release_base(self) -> None:
        layout = SimpleNamespace(repo_root=Path("/tmp/repo"))
        with patched_attrs(
            harness_mod,
            preferred_release_ref=lambda _repo_root: "origin/v4.29.0",
            active_release_branch=lambda _repo_root: "v4.29.0",
            release_sync_status=lambda _repo_root: harness_mod.RefSyncStatus(
                local_ref="v4.29.0",
                upstream_ref="origin/v4.29.0",
                local_oid="abc",
                upstream_oid="def",
                relationship="diverged",
            ),
        ):
            with self.assertRaisesRegex(SystemExit, "refusing to use local `v4.29.0` as the worktree base"):
                harness_mod.resolve_create_worktree_base(layout, "v4.29.0")

    def test_create_worktree_syncs_resolved_release_projects(self) -> None:
        args = argparse.Namespace(
            name="demo",
            branch=None,
            base=None,
            skip_sync=True,
            skip_reference_sync=False,
            lightweight=False,
            owner=None,
            priority=None,
            summary=None,
            status=None,
            scope=None,
            lock=False,
        )
        root_layout = SimpleNamespace(repo_root=Path("/tmp/repo"), package_root=Path("/tmp/repo"))
        new_layout = SimpleNamespace(
            repo_root=Path("/tmp/repo"),
            package_root=Path("/tmp/repo/.worktrees/demo"),
            artifact_root=Path("/tmp/repo/_out/demo"),
            in_linked_worktree=True,
        )
        project = HarnessProject(
            project_id="published",
            source_kind="git_checkout",
            project_root=".",
            build_target=None,
            generator=None,
            repository="https://github.com/example/published.git",
            ref="published-ref",
            build_command=("lake", "build"),
            generate_command=VBP_BUILD_COMMAND,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
            selected_release="v4.30.0",
        )
        catalog = SimpleNamespace(projects=())
        seen: dict[str, object] = {}

        def fake_resolve(_catalog, release, package_root, selected_ids):
            seen["resolve_args"] = (_catalog, release, package_root, selected_ids)
            return SimpleNamespace(release_id="v4.30.0"), [project]

        def fake_sync(_layout, projects, *, warm_build, prepare_local_checkout):
            seen["sync_args"] = (_layout, projects, warm_build, prepare_local_checkout)

        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda start=None: new_layout if start == Path("/tmp/repo/.worktrees/demo") else root_layout,
            resolve_create_worktree_base=lambda _layout, _base: "origin/v4.30.0",
            branch_exists=lambda _repo_root, _branch: False,
            run=lambda command, *, cwd: seen.setdefault("commands", []).append(command),
            resolve_manifest_path=lambda _path_text, _package_root: Path("/tmp/projects.json"),
            load_project_catalog_manifest=lambda _manifest_path: catalog,
            resolve_release_projects=fake_resolve,
            sync_reference_blueprints=fake_sync,
        ):
            self.assertEqual(harness_mod.command_create_worktree(args), 0)

        self.assertEqual(
            seen["commands"],
            [["git", "worktree", "add", "-b", "feat/demo", "/tmp/repo/.worktrees/demo", "origin/v4.30.0"]],
        )
        self.assertEqual(seen["resolve_args"], (catalog, None, new_layout.package_root, None))
        self.assertEqual(seen["sync_args"], (new_layout, [project], True, True))

    def test_release_status_require_sync_returns_nonzero_when_unsynced(self) -> None:
        args = argparse.Namespace(require_sync=True)
        layout = SimpleNamespace(repo_root=Path("/tmp/repo"), package_root=Path("/tmp/worktree"))
        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            release_sync_status=lambda _repo_root: harness_mod.RefSyncStatus(
                local_ref="v4.29.0",
                upstream_ref="origin/v4.29.0",
                local_oid="abc",
                upstream_oid="def",
                relationship="behind",
            ),
            current_branch_name=lambda _repo_root: "fix/demo",
            active_release_branch=lambda _repo_root: "v4.29.0",
            branch_policy_path=lambda _repo_root: Path("/tmp/worktree/branch-policy.json"),
            default_dev_branch=lambda _repo_root: "v4.29.0",
            checkout_branch_role=lambda _repo_root: "default_dev",
            checkout_is_backport_only=lambda _repo_root: False,
        ):
            self.assertEqual(harness_mod.command_release_status(args), 1)

    def test_release_status_reports_backport_policy_fields(self) -> None:
        args = argparse.Namespace(require_sync=False)
        layout = SimpleNamespace(repo_root=Path("/tmp/repo"), package_root=Path("/tmp/worktree"))
        out = io.StringIO()
        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            release_sync_status=lambda _repo_root: harness_mod.RefSyncStatus(
                local_ref="v4.28.0",
                upstream_ref="origin/v4.28.0",
                local_oid="abc",
                upstream_oid="abc",
                relationship="in_sync",
            ),
            current_branch_name=lambda _repo_root: "fix/backport",
            active_release_branch=lambda _repo_root: "v4.28.0",
            branch_policy_path=lambda _repo_root: Path("/tmp/worktree/branch-policy.json"),
            default_dev_branch=lambda _repo_root: "v4.29.0",
            checkout_branch_role=lambda _repo_root: "backport",
            checkout_is_backport_only=lambda _repo_root: True,
        ):
            with redirect_stdout(out):
                self.assertEqual(harness_mod.command_release_status(args), 0)

        output = out.getvalue()
        self.assertIn("current_branch=fix/backport", output)
        self.assertIn("branch_policy=/tmp/worktree/branch-policy.json", output)
        self.assertIn("default_dev_branch=v4.29.0", output)
        self.assertIn("active_release_branch=v4.28.0", output)
        self.assertIn("checkout_role=backport", output)
        self.assertIn("backport_only=true", output)

    def test_prepare_backports_prints_pending_lines(self) -> None:
        args = argparse.Namespace(exempt=None)
        layout = SimpleNamespace(package_root=Path("/tmp/worktree"))
        out = io.StringIO()
        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            load_branch_policy=lambda _checkout_root: SimpleNamespace(
                default_dev_branch="v4.29.0",
                required_backport_branches=("v4.28.0", "v4.27.0"),
            ),
        ):
            with redirect_stdout(out):
                self.assertEqual(harness_mod.command_prepare_backports(args), 0)

        output = out.getvalue()
        self.assertIn("default_dev_branch=v4.29.0", output)
        self.assertIn("required_backports=v4.28.0,v4.27.0", output)
        self.assertIn("Backport v4.28.0: pending", output)
        self.assertIn("Backport v4.27.0: pending", output)

    def test_prepare_backports_rejects_unknown_exemption_branch(self) -> None:
        args = argparse.Namespace(exempt=["v4.27.0=docs-only"])
        layout = SimpleNamespace(package_root=Path("/tmp/worktree"))
        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            load_branch_policy=lambda _checkout_root: SimpleNamespace(
                default_dev_branch="v4.29.0",
                required_backport_branches=("v4.28.0",),
            ),
        ):
            with self.assertRaisesRegex(SystemExit, "unknown required backport branch"):
                harness_mod.command_prepare_backports(args)

    def test_prepare_pr_prints_public_scaffold(self) -> None:
        args = argparse.Namespace(
            title=None,
            summary="This PR removes private mirror assumptions from the maintainer harness.",
            change=["Accept only the public upstream package repo"],
            source_branch=None,
            exempt=None,
        )
        layout = SimpleNamespace(package_root=Path("/tmp/worktree"))
        out = io.StringIO()
        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            load_branch_policy=lambda _checkout_root: SimpleNamespace(
                default_dev_branch="v4.29.0",
                required_backport_branches=("v4.28.0",),
            ),
            require_checkout_role=lambda *_args, **_kwargs: None,
            current_branch_name=lambda _checkout_root: "fix/public-pr-scaffold",
            current_commit_subject=lambda _checkout_root: "fix: tighten public PR scaffolds",
        ):
            with redirect_stdout(out):
                self.assertEqual(harness_mod.command_prepare_pr(args), 0)

        output = out.getvalue()
        self.assertIn("repository=leanprover/verso-blueprint", output)
        self.assertIn("base=v4.29.0", output)
        self.assertIn("head=fix/public-pr-scaffold", output)
        self.assertIn("draft=true", output)
        self.assertIn("## PR Submission Guardrails", output)
        self.assertIn("Use the PR title and body below as the public PR metadata", output)
        self.assertIn("Follow Lean upstream title style", output)
        self.assertIn("without type scopes such as `feat(entry): ...`", output)
        self.assertIn("Do not add generator or tool prefixes such as `[codex]`", output)
        self.assertIn("Do not add routine validation transcripts to the PR body", output)
        self.assertIn("recommended_merge_method=merge", output)
        self.assertIn("Use a merge commit when landing", output)
        self.assertIn("## PR Title\nfix: tighten public PR scaffolds", output)
        self.assertIn("## PR Body", output)
        self.assertIn("This PR removes private mirror assumptions from the maintainer harness.", output)
        self.assertIn("- Accept only the public upstream package repo", output)
        self.assertIn("Backport v4.28.0: pending", output)
        self.assertNotIn("## Backports", output)
        self.assertNotIn("## Validation", output)
        self.assertNotIn("## Coordination", output)
        self.assertNotIn("## Risks", output)
        self.assertNotIn("Worktree:", output)
        self.assertNotIn("Write scope:", output)

    def test_public_pr_title_validation_rejects_scopes(self) -> None:
        self.assertEqual(
            harness_mod.validate_public_pr_title("feat: support Blueprint preview nodes in slides"),
            "feat: support Blueprint preview nodes in slides",
        )
        with self.assertRaisesRegex(SystemExit, "without type scopes"):
            harness_mod.validate_public_pr_title("feat(slides): render Blueprint preview nodes")
        with self.assertRaisesRegex(SystemExit, "expected Lean upstream style"):
            harness_mod.validate_public_pr_title("update slides")

    def test_prepare_pr_rejects_scoped_current_commit_subject(self) -> None:
        args = argparse.Namespace(
            title=None,
            summary=None,
            change=None,
            source_branch=None,
            exempt=None,
        )
        layout = SimpleNamespace(package_root=Path("/tmp/worktree"))
        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            load_branch_policy=lambda _checkout_root: SimpleNamespace(
                default_dev_branch="v4.30.0",
                required_backport_branches=("v4.29.0",),
            ),
            require_checkout_role=lambda *_args, **_kwargs: None,
            current_branch_name=lambda _checkout_root: "feat/slides",
            current_commit_subject=lambda _checkout_root: "feat(slides): render Blueprint preview nodes",
        ):
            with self.assertRaisesRegex(SystemExit, "without type scopes"):
                harness_mod.command_prepare_pr(args)

    def test_prepare_pr_rejects_source_change_exemptions(self) -> None:
        args = argparse.Namespace(
            title="fix: report malformed graph cache entries",
            summary=None,
            change=None,
            source_branch="fix/traversal-decode-errors",
            exempt=["v4.28.0=no reported release-line regression"],
        )
        layout = SimpleNamespace(package_root=Path("/tmp/worktree"))
        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            load_branch_policy=lambda _checkout_root: SimpleNamespace(
                default_dev_branch="v4.29.0",
                required_backport_branches=("v4.28.0",),
            ),
            require_checkout_role=lambda *_args, **_kwargs: None,
            source_changed_files=lambda _repo_root, _source_branch: [
                "src/VersoBlueprint/GraphApi.lean",
                "doc/API.md",
            ],
        ):
            with self.assertRaisesRegex(SystemExit, "paired backports are required for: src/VersoBlueprint/GraphApi.lean"):
                harness_mod.command_prepare_pr(args)

    def test_prepare_pr_accepts_documentation_only_exemptions(self) -> None:
        args = argparse.Namespace(
            title="doc: clarify backport policy",
            summary=None,
            change=None,
            source_branch="doc/backport-policy",
            exempt=["v4.28.0=documentation-only change"],
        )
        layout = SimpleNamespace(package_root=Path("/tmp/worktree"))
        out = io.StringIO()
        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            load_branch_policy=lambda _checkout_root: SimpleNamespace(
                default_dev_branch="v4.29.0",
                required_backport_branches=("v4.28.0",),
            ),
            require_checkout_role=lambda *_args, **_kwargs: None,
            source_changed_files=lambda _repo_root, _source_branch: ["doc/MAINTAINER_GUIDE.md"],
        ):
            with redirect_stdout(out):
                self.assertEqual(harness_mod.command_prepare_pr(args), 0)

        self.assertIn("Backport v4.28.0: exempt: documentation-only change", out.getvalue())

    def test_prepare_pr_allows_squash_when_all_backports_are_exempt(self) -> None:
        out = io.StringIO()
        with redirect_stdout(out):
            harness_mod.print_public_pr_message_scaffold(
                default_dev="v4.30.0",
                source_branch="docs/release-note",
                title="doc: update release note",
                backport_lines=[
                    "Backport v4.29.0: exempt: docs-only",
                    "Backport v4.28.0: exempt: docs-only",
                ],
                summary=None,
                changes=None,
            )

        output = out.getvalue()
        self.assertIn("recommended_merge_method=squash", output)
        self.assertNotIn("Use a merge commit when landing", output)

    def test_prepare_backport_pr_prints_standardized_scaffold(self) -> None:
        args = argparse.Namespace(
            release="v4.28.0",
            all_required=False,
            main_pr=11,
            main_title="fix: require draft plans and base-aware retire",
            source_branch="fix/backport-discipline",
        )
        layout = SimpleNamespace(package_root=Path("/tmp/worktree"))
        out = io.StringIO()
        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            load_branch_policy=lambda _checkout_root: SimpleNamespace(
                default_dev_branch="v4.29.0",
                required_backport_branches=("v4.28.0",),
            ),
            default_dev_branch=lambda _checkout_root: "v4.29.0",
            require_checkout_role=lambda *_args, **_kwargs: None,
            source_commit_series=lambda _repo_root, _source_branch: ["abc123", "def456"],
        ):
            with redirect_stdout(out):
                self.assertEqual(harness_mod.command_prepare_backport_pr(args), 0)

        output = out.getvalue()
        self.assertIn("## Local Backport Plan", output)
        self.assertIn("repository=leanprover/verso-blueprint", output)
        self.assertIn("default_dev_branch=v4.29.0", output)
        self.assertIn("backport_release=v4.28.0", output)
        self.assertIn("paired_worktree=backport-v428-backport-discipline", output)
        self.assertIn("paired_branch=fix/backport-v428-backport-discipline", output)
        self.assertIn("paired_title=[backport v4.28.0] fix: require draft plans and base-aware retire", output)
        self.assertIn("paired_label=backport-v4.28.0", output)
        self.assertIn("source_commits=abc123,def456", output)
        self.assertIn("git cherry-pick -x abc123 def456", output)
        self.assertIn("## PR Submission Guardrails", output)
        self.assertIn("Use the PR title and body below as the public backport PR metadata", output)
        self.assertIn("Keep the title after the backport prefix in Lean upstream style", output)
        self.assertIn("Apply the release label `backport-v4.28.0`", output)
        self.assertIn("Keep review-facing discussion on the default-development PR", output)
        self.assertIn("Do not add routine validation transcripts to the backport PR body", output)
        self.assertIn("## PR Title\n[backport v4.28.0] fix: require draft plans and base-aware retire", output)
        self.assertIn("## PR Body", output)
        self.assertIn("Primary review: #11", output)
        self.assertIn("Keep review comments on #11 unless this backport diverges materially.", output)

    def test_prepare_backport_pr_defaults_to_github_pr_title(self) -> None:
        args = argparse.Namespace(
            release="v4.28.0",
            all_required=False,
            main_pr=11,
            main_title=None,
            source_branch="feat/multi-commit-branch",
        )
        layout = SimpleNamespace(package_root=Path("/tmp/worktree"))
        out = io.StringIO()
        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            load_branch_policy=lambda _checkout_root: SimpleNamespace(
                default_dev_branch="v4.29.0",
                required_backport_branches=("v4.28.0",),
            ),
            default_dev_branch=lambda _checkout_root: "v4.29.0",
            require_checkout_role=lambda *_args, **_kwargs: None,
            source_commit_series=lambda _repo_root, _source_branch: ["abc123", "def456"],
            github_pr_title=lambda _repo_root, _main_pr: "feat: branch-level render API cleanup",
            current_commit_subject=lambda _checkout_root: "fix: support release-line highlight patches",
        ):
            with redirect_stdout(out):
                self.assertEqual(harness_mod.command_prepare_backport_pr(args), 0)

        output = out.getvalue()
        self.assertIn("paired_title=[backport v4.28.0] feat: branch-level render API cleanup", output)
        self.assertIn("## PR Title\n[backport v4.28.0] feat: branch-level render API cleanup", output)
        self.assertNotIn("fix: support release-line highlight patches", output)

    def test_prepare_backport_pr_defaults_source_to_main_pr(self) -> None:
        args = argparse.Namespace(
            release="v4.28.0",
            all_required=False,
            main_pr=11,
            main_title="fix: report malformed graph cache entries",
            source_branch=None,
        )
        layout = SimpleNamespace(package_root=Path("/tmp/worktree"))
        out = io.StringIO()
        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            load_branch_policy=lambda _checkout_root: SimpleNamespace(
                default_dev_branch="v4.29.0",
                required_backport_branches=("v4.28.0",),
            ),
            default_dev_branch=lambda _checkout_root: "v4.29.0",
            require_checkout_role=lambda *_args, **_kwargs: None,
            github_pr_backport_source=lambda _repo_root, _main_pr: (
                "fix/traversal-decode-errors",
                ["abc123"],
            ),
        ):
            with redirect_stdout(out):
                self.assertEqual(harness_mod.command_prepare_backport_pr(args), 0)

        output = out.getvalue()
        self.assertIn("source_branch=fix/traversal-decode-errors", output)
        self.assertIn("source_commits=abc123", output)
        self.assertIn("paired_branch=fix/backport-v428-traversal-decode-errors", output)

    def test_github_pr_backport_source_reads_head_and_commits(self) -> None:
        with patched_attrs(
            harness_mod,
            github_pr_view_json=lambda _repo_root, _pr_number, _fields: {
                "headRefName": "fix/traversal-decode-errors",
                "commits": [{"oid": "abc123"}, {"oid": "def456"}],
            },
        ):
            source = harness_mod.github_pr_backport_source(Path("/tmp/worktree"), 11)

        self.assertEqual(source, ("fix/traversal-decode-errors", ["abc123", "def456"]))

    def test_github_pr_title_reads_public_title(self) -> None:
        with patch(
            "scripts.blueprint_harness.subprocess.run",
            return_value=SimpleNamespace(returncode=0, stdout='{"title":"doc: clarify API"}'),
        ) as run_mock:
            title = harness_mod.github_pr_title(Path("/tmp/worktree"), 11)

        self.assertEqual(title, "doc: clarify API")
        run_mock.assert_called_once_with(
            ["gh", "pr", "view", "11", "--repo", "leanprover/verso-blueprint", "--json", "title"],
            cwd=Path("/tmp/worktree"),
            check=False,
            text=True,
            capture_output=True,
        )

    def test_github_pr_title_returns_none_for_lookup_failure(self) -> None:
        with patch(
            "scripts.blueprint_harness.subprocess.run",
            return_value=SimpleNamespace(returncode=1, stdout=""),
        ):
            self.assertIsNone(harness_mod.github_pr_title(Path("/tmp/worktree"), 11))

    def test_worktree_merged_pr_validation_accepts_matching_metadata(self) -> None:
        worktree = GitWorktree(
            name="demo",
            path=Path("/tmp/repo/.worktrees/demo"),
            head="abc123",
            branch="feat/demo",
            root_checkout=False,
        )
        with patched_attrs(
            harness_mod,
            github_pr_view_json=lambda _repo_root, _pr_number, _fields: {
                "state": "MERGED",
                "baseRefName": "v4.31.0",
                "headRefName": "feat/demo",
                "headRefOid": "abc123",
            },
        ):
            self.assertIsNone(
                harness_mod.worktree_merged_pr_validation_error(
                    Path("/tmp/repo"),
                    152,
                    worktree,
                    "origin/v4.31.0",
                )
            )

    def test_worktree_merged_pr_validation_rejects_mismatched_head(self) -> None:
        worktree = GitWorktree(
            name="demo",
            path=Path("/tmp/repo/.worktrees/demo"),
            head="abc123",
            branch="feat/demo",
            root_checkout=False,
        )
        with patched_attrs(
            harness_mod,
            github_pr_view_json=lambda _repo_root, _pr_number, _fields: {
                "state": "MERGED",
                "baseRefName": "v4.31.0",
                "headRefName": "feat/demo",
                "headRefOid": "def456",
            },
        ):
            error = harness_mod.worktree_merged_pr_validation_error(
                Path("/tmp/repo"),
                152,
                worktree,
                "origin/v4.31.0",
            )

        self.assertIn("does not match worktree head", error)

    def test_worktree_merged_pr_validation_rejects_unmerged_pr(self) -> None:
        worktree = GitWorktree(
            name="demo",
            path=Path("/tmp/repo/.worktrees/demo"),
            head="abc123",
            branch="feat/demo",
            root_checkout=False,
        )
        with patched_attrs(
            harness_mod,
            github_pr_view_json=lambda _repo_root, _pr_number, _fields: {
                "state": "OPEN",
                "baseRefName": "v4.31.0",
                "headRefName": "feat/demo",
                "headRefOid": "abc123",
            },
        ):
            error = harness_mod.worktree_merged_pr_validation_error(
                Path("/tmp/repo"),
                152,
                worktree,
                "origin/v4.31.0",
            )

        self.assertIn("is not merged", error)

    def test_worktree_merged_pr_validation_rejects_mismatched_base(self) -> None:
        worktree = GitWorktree(
            name="demo",
            path=Path("/tmp/repo/.worktrees/demo"),
            head="abc123",
            branch="feat/demo",
            root_checkout=False,
        )
        with patched_attrs(
            harness_mod,
            github_pr_view_json=lambda _repo_root, _pr_number, _fields: {
                "state": "MERGED",
                "baseRefName": "v4.30.0",
                "headRefName": "feat/demo",
                "headRefOid": "abc123",
            },
        ):
            error = harness_mod.worktree_merged_pr_validation_error(
                Path("/tmp/repo"),
                152,
                worktree,
                "origin/v4.31.0",
            )

        self.assertIn("base `v4.30.0` does not match `origin/v4.31.0`", error)

    def test_worktree_merged_pr_validation_rejects_mismatched_branch(self) -> None:
        worktree = GitWorktree(
            name="demo",
            path=Path("/tmp/repo/.worktrees/demo"),
            head="abc123",
            branch="feat/demo",
            root_checkout=False,
        )
        with patched_attrs(
            harness_mod,
            github_pr_view_json=lambda _repo_root, _pr_number, _fields: {
                "state": "MERGED",
                "baseRefName": "v4.31.0",
                "headRefName": "feat/other",
                "headRefOid": "abc123",
            },
        ):
            error = harness_mod.worktree_merged_pr_validation_error(
                Path("/tmp/repo"),
                152,
                worktree,
                "origin/v4.31.0",
            )

        self.assertIn("head branch `feat/other` does not match `feat/demo`", error)

    def test_prepare_backport_pr_rejects_scoped_main_title(self) -> None:
        args = argparse.Namespace(
            release="v4.28.0",
            all_required=False,
            main_pr=11,
            main_title="fix(harness): require public PR titles",
            source_branch="fix/public-pr-title",
        )
        layout = SimpleNamespace(package_root=Path("/tmp/worktree"))
        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            load_branch_policy=lambda _checkout_root: SimpleNamespace(
                default_dev_branch="v4.30.0",
                required_backport_branches=("v4.28.0",),
            ),
            default_dev_branch=lambda _checkout_root: "v4.30.0",
            require_checkout_role=lambda *_args, **_kwargs: None,
            source_commit_series=lambda _repo_root, _source_branch: ["abc123"],
        ):
            with self.assertRaisesRegex(SystemExit, "without type scopes"):
                harness_mod.command_prepare_backport_pr(args)

    def test_prepare_backport_pr_all_required_prints_multiple_scaffolds(self) -> None:
        args = argparse.Namespace(
            release=None,
            all_required=True,
            main_pr=11,
            main_title="fix: require draft plans and base-aware retire",
            source_branch="fix/backport-discipline",
        )
        layout = SimpleNamespace(package_root=Path("/tmp/worktree"))
        out = io.StringIO()
        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            load_branch_policy=lambda _checkout_root: SimpleNamespace(
                default_dev_branch="v4.29.0",
                required_backport_branches=("v4.28.0", "v4.27.0"),
            ),
            default_dev_branch=lambda _checkout_root: "v4.29.0",
            require_checkout_role=lambda *_args, **_kwargs: None,
            source_commit_series=lambda _repo_root, _source_branch: ["abc123"],
        ):
            with redirect_stdout(out):
                self.assertEqual(harness_mod.command_prepare_backport_pr(args), 0)

        output = out.getvalue()
        self.assertIn("backport_release=v4.28.0", output)
        self.assertIn("paired_branch=fix/backport-v428-backport-discipline", output)
        self.assertIn("paired_label=backport-v4.28.0", output)
        self.assertIn("backport_release=v4.27.0", output)
        self.assertIn("paired_branch=fix/backport-v427-backport-discipline", output)
        self.assertIn("paired_label=backport-v4.27.0", output)
        self.assertIn("\n---\n", output)

    def test_land_release_rejects_unsynced_release(self) -> None:
        args = argparse.Namespace(source="feat/demo", no_push=False, cleanup=False, keep_remote=False)
        layout = SimpleNamespace(repo_root=Path("/tmp/repo"), package_root=Path("/tmp/repo"), in_linked_worktree=False)
        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            current_branch_name=lambda _repo_root: "v4.29.0",
            worktree_is_clean=lambda _path: True,
            release_sync_status=lambda _repo_root: harness_mod.RefSyncStatus(
                local_ref="v4.29.0",
                upstream_ref="origin/v4.29.0",
                local_oid="abc",
                upstream_oid="def",
                relationship="behind",
            ),
            active_release_branch=lambda _repo_root: "v4.29.0",
        ):
            with self.assertRaisesRegex(SystemExit, "sync `v4.29.0` before landing"):
                harness_mod.command_land_release(args)

    def test_land_release_fast_forwards_and_pushes(self) -> None:
        args = argparse.Namespace(source="feat/demo", no_push=False, cleanup=False, keep_remote=False)
        layout = SimpleNamespace(repo_root=Path("/tmp/repo"), package_root=Path("/tmp/repo"), in_linked_worktree=False)
        commands: list[list[str]] = []
        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            current_branch_name=lambda _repo_root: "v4.29.0",
            worktree_is_clean=lambda _path: True,
            release_sync_status=lambda _repo_root: harness_mod.RefSyncStatus(
                local_ref="v4.29.0",
                upstream_ref="origin/v4.29.0",
                local_oid="abc",
                upstream_oid="abc",
                relationship="in_sync",
            ),
            ref_oid=lambda _repo_root, ref: "deadbeef" if ref == "feat/demo" else None,
            is_ancestor=lambda _repo_root, ancestor, descendant: (ancestor, descendant) == ("v4.29.0", "feat/demo"),
            preferred_release_ref=lambda _repo_root: "origin/v4.29.0",
            active_release_branch=lambda _repo_root: "v4.29.0",
            run=lambda command, *, cwd: commands.append(command),
        ):
            self.assertEqual(harness_mod.command_land_release(args), 0)

        self.assertEqual(commands, [["git", "merge", "--ff-only", "feat/demo"], ["git", "push", "origin", "v4.29.0"]])

    def test_land_release_cleanup_removes_branch_worktree_and_remote(self) -> None:
        args = argparse.Namespace(source="feat/demo", no_push=False, cleanup=True, keep_remote=False)
        layout = SimpleNamespace(repo_root=Path("/tmp/repo"), package_root=Path("/tmp/repo"), in_linked_worktree=False)
        demo_worktree = GitWorktree(
            name="demo",
            path=Path("/tmp/repo/.worktrees/demo"),
            head="abc123",
            branch="feat/demo",
            root_checkout=False,
        )
        commands: list[list[str]] = []
        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            current_branch_name=lambda _repo_root: "v4.29.0",
            worktree_is_clean=lambda _path: True,
            release_sync_status=lambda _repo_root: harness_mod.RefSyncStatus(
                local_ref="v4.29.0",
                upstream_ref="origin/v4.29.0",
                local_oid="abc",
                upstream_oid="abc",
                relationship="in_sync",
            ),
            ref_oid=lambda _repo_root, ref: (
                "deadbeef" if ref in {"feat/demo", "refs/heads/feat/demo", "refs/remotes/origin/feat/demo"} else None
            ),
            is_ancestor=lambda _repo_root, ancestor, descendant: (ancestor, descendant) == ("v4.29.0", "feat/demo"),
            preferred_release_ref=lambda _repo_root: "origin/v4.29.0",
            active_release_branch=lambda _repo_root: "v4.29.0",
            run=lambda command, *, cwd: commands.append(command),
            branch_worktrees=lambda _repo_root, branch: [demo_worktree] if branch == "feat/demo" else [],
            local_branch_ref=lambda _repo_root, branch: branch if branch == "feat/demo" else None,
            origin_branch_exists=lambda _repo_root, branch: branch == "feat/demo",
        ):
            self.assertEqual(harness_mod.command_land_release(args), 0)

        self.assertEqual(
            commands,
            [
                ["git", "merge", "--ff-only", "feat/demo"],
                ["git", "push", "origin", "v4.29.0"],
                ["git", "worktree", "remove", str(demo_worktree.path)],
                ["git", "branch", "-d", "feat/demo"],
                ["git", "push", "origin", "--delete", "feat/demo"],
            ],
        )

    def test_reference_generate_rejects_unsafe_root_release_without_override(self) -> None:
        args = argparse.Namespace(
            output_root=None,
            manifest=None,
            project=None,
            release=None,
            skip_build=False,
            allow_unsafe_root_release=False,
            serial=False,
            allow_local_build=False,
        )
        layout = SimpleNamespace(package_root=Path("/tmp/package"), repo_root=Path("/tmp/package"), in_linked_worktree=False)
        seen: dict[str, object] = {}

        def fake_require(_layout, *, allow_unsafe, command_name):
            seen["layout"] = _layout
            seen["allow_unsafe"] = allow_unsafe
            seen["command_name"] = command_name
            raise SystemExit("blocked")

        with patched_attrs(
            reference_harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            require_safe_root_release=fake_require,
        ):
            with self.assertRaisesRegex(SystemExit, "blocked"):
                reference_harness_mod.command_generate(args)

        self.assertEqual(seen["layout"], layout)
        self.assertFalse(seen["allow_unsafe"])
        self.assertEqual(seen["command_name"], "generate")

    def test_reference_generate_rejects_mismatched_release_target(self) -> None:
        args = argparse.Namespace(
            output_root=None,
            manifest=None,
            project=None,
            release="v4.28.0",
            skip_build=False,
            allow_unsafe_root_release=False,
            serial=False,
            allow_local_build=False,
        )
        layout = SimpleNamespace(package_root=Path("/tmp/package"), repo_root=Path("/tmp/package"), in_linked_worktree=False)
        with patched_attrs(
            reference_harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            require_safe_root_release=lambda _layout, *, allow_unsafe, command_name: None,
            resolve_output_root=lambda _path_text, _start=None: Path("/tmp/out"),
            resolve_manifest_path=lambda _path_text, _package_root: Path("/tmp/projects.json"),
            load_project_catalog=lambda _manifest_path: SimpleNamespace(projects=(), release_targets=()),
            select_release_projects=lambda _catalog, *, release, project_ids, package_root: ("v4.28.0", []),
            active_release_branch=lambda _package_root: "v4.29.0",
        ):
            with self.assertRaisesRegex(SystemExit, "Create or switch to a `v4.28.0` checkout first"):
                reference_harness_mod.command_generate(args)

    def test_bump_toolchain_uses_helper(self) -> None:
        args = argparse.Namespace(toolchain="4.29.0", verso_ref=None, skip_validation=False)
        layout = SimpleNamespace(package_root=Path("/tmp/package"))
        seen: dict[str, object] = {}
        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            require_checkout_role=lambda checkout_root, *, required_role, operation: seen.update(
                {
                    "role_checkout_root": checkout_root,
                    "required_role": required_role,
                    "operation": operation,
                }
            ),
            bump_toolchain_checkout=lambda package_root, toolchain, *, verso_ref, validate: seen.update(
                {
                    "package_root": package_root,
                    "toolchain": toolchain,
                    "verso_ref": verso_ref,
                    "validate": validate,
                }
            )
            or SimpleNamespace(
                lean_ref="v4.29.0",
                toolchain_spec="leanprover/lean4:v4.29.0",
                verso_ref="v4.29.0",
                verso_tag_oid="deadbeef",
            ),
        ):
            self.assertEqual(harness_mod.command_bump_toolchain(args), 0)

        self.assertEqual(seen["package_root"], layout.package_root)
        self.assertEqual(seen["role_checkout_root"], layout.package_root)
        self.assertEqual(seen["required_role"], "default_dev")
        self.assertEqual(seen["operation"], "bump-toolchain")
        self.assertEqual(seen["toolchain"], "4.29.0")
        self.assertEqual(seen["verso_ref"], None)
        self.assertTrue(seen["validate"])

    def test_start_release_line_updates_policy_and_in_repo_targets(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "branch-policy.json").write_text(
                json.dumps(
                    {
                        "version": 2,
                        "default_dev_branch": "v4.29.0",
                        "required_backport_branches": ["v4.28.0"],
                        "release_targets": [
                            {
                                "id": "v4.28.0",
                                "toolchain": "v4.28.0",
                                "verso_ref": "v4.28.0",
                                "branch": "v4.28.0",
                                "deploy_pages": False,
                            },
                            {
                                "id": "v4.29.0",
                                "toolchain": "v4.29.0",
                                "verso_ref": "v4.29.0",
                                "branch": "v4.29.0",
                                "deploy_pages": True,
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            manifest_path = root / "tests" / "harness" / "projects.json"
            manifest_path.parent.mkdir(parents=True)
            manifest_path.write_text(
                json.dumps(
                    {
                        "version": 2,
                        "projects": [
                            {
                                "id": "project-template",
                                "source": {"kind": "in_repo_project", "project_root": "project_template"},
                                "targets": [{"release": "v4.29.0"}],
                            },
                            {
                                "id": "external",
                                "source": {
                                    "kind": "git_checkout",
                                    "repository": "https://github.com/example/external.git",
                                    "project_root": ".",
                                },
                                "targets": [{"release": "v4.29.0", "ref": "abc"}],
                            },
                        ],
                    }
                ),
                encoding="utf-8",
            )
            args = argparse.Namespace(
                toolchain="4.30-rc2",
                verso_ref=None,
                deploy_pages=False,
                skip_validation=True,
            )
            layout = SimpleNamespace(package_root=root)
            seen: dict[str, object] = {}

            def fake_bump(package_root, toolchain, *, verso_ref, validate):
                seen["package_root"] = package_root
                seen["toolchain"] = toolchain
                seen["verso_ref"] = verso_ref
                seen["validate"] = validate
                return SimpleNamespace(
                    lean_ref="v4.30.0-rc2",
                    toolchain_spec="leanprover/lean4:v4.30.0-rc2",
                    verso_ref="v4.30.0-rc2",
                    verso_tag_oid="deadbeef",
                )

            out = io.StringIO()
            with patched_attrs(
                harness_mod,
                detect_harness_layout=lambda _start=None: layout,
                current_branch_name=lambda _checkout_root: "v4.30.0",
                bump_toolchain_checkout=fake_bump,
            ):
                with redirect_stdout(out):
                    self.assertEqual(harness_mod.command_start_release_line(args), 0)

            self.assertEqual(seen["toolchain"], "4.30-rc2")
            self.assertFalse(seen["validate"])
            self.assertEqual(
                json.loads((root / "branch-policy.json").read_text(encoding="utf-8")),
                {
                    "version": 2,
                    "default_dev_branch": "v4.30.0",
                    "required_backport_branches": ["v4.29.0", "v4.28.0"],
                    "release_targets": [
                        {
                            "id": "v4.28.0",
                            "toolchain": "v4.28.0",
                            "verso_ref": "v4.28.0",
                            "branch": "v4.28.0",
                            "deploy_pages": False,
                        },
                        {
                            "id": "v4.29.0",
                            "toolchain": "v4.29.0",
                            "verso_ref": "v4.29.0",
                            "branch": "v4.29.0",
                            "deploy_pages": True,
                        },
                        {
                            "id": "v4.30.0",
                            "toolchain": "v4.30.0",
                            "verso_ref": "v4.30.0",
                            "branch": "v4.30.0",
                            "deploy_pages": False,
                        },
                    ],
                },
            )
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            self.assertNotIn("release_targets", manifest)
            self.assertEqual(
                [target["release"] for target in manifest["projects"][0]["targets"]],
                ["v4.29.0", "v4.30.0"],
            )
            self.assertEqual(
                [target["release"] for target in manifest["projects"][1]["targets"]],
                ["v4.29.0"],
            )
            self.assertIn("set-default-dev-branch v4.30.0", out.getvalue())

    def test_set_default_dev_branch_preserves_required_backports(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "lean-toolchain").write_text("leanprover/lean4:v4.29.0\n", encoding="utf-8")
            (root / "branch-policy.json").write_text(
                '{\n  "version": 1,\n  "default_dev_branch": "v4.29.0",\n  "required_backport_branches": ["v4.28.0"]\n}\n',
                encoding="utf-8",
            )
            args = argparse.Namespace(branch="v4.30.0")
            layout = SimpleNamespace(package_root=root)
            out = io.StringIO()
            with patched_attrs(
                harness_mod,
                detect_harness_layout=lambda _start=None: layout,
            ):
                with redirect_stdout(out):
                    self.assertEqual(harness_mod.command_set_default_dev_branch(args), 0)

            self.assertEqual(
                (root / "branch-policy.json").read_text(encoding="utf-8"),
                '{\n  "version": 1,\n  "default_dev_branch": "v4.30.0",\n  "required_backport_branches": [\n    "v4.28.0"\n  ]\n}\n',
            )
            self.assertIn("checkout_role=backport", out.getvalue())

    def test_paths_prints_current_release_project_sites_by_default(self) -> None:
        args = argparse.Namespace(all_projects=False)
        layout = SimpleNamespace(
            repo_root=Path("/tmp/repo"),
            package_root=Path("/tmp/package"),
            worktree_name=None,
            artifact_root=Path("/tmp/package/_out"),
            reference_output_root=Path("/tmp/package/_out/reference-blueprints"),
            test_blueprint_output_root=Path("/tmp/package/_out/test-blueprints"),
            reference_source_cache_root=Path("/tmp/repo/.worktrees/_reference-blueprints/cache"),
            reference_dependency_cache_root=Path("/tmp/repo/.worktrees/_reference-blueprints/deps"),
            reference_project_checkout_root=Path("/tmp/repo/.worktrees/_reference-blueprints/by-worktree/v4.29.0"),
            reference_project_edit_root=Path("/tmp/repo/.worktrees/_reference-blueprints/edit/v4.29.0"),
        )
        release = HarnessReleaseTarget(
            release_id="v4.29.0",
            release_toolchain="v4.29.0",
            release_verso_ref="v4.29.0",
            branch="v4.29.0",
            deploy_pages=True,
        )
        selected_project = HarnessProject(
            project_id="noperthedron",
            source_kind="git_checkout",
            project_root=".",
            build_target=None,
            generator=None,
            repository="https://github.com/example/noperthedron.git",
            ref=None,
            build_command=("lake", "build"),
            generate_command=VBP_BUILD_COMMAND,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
            targets=(HarnessProjectTarget(release="v4.29.0", ref="abc123"),),
        )
        old_project = HarnessProject(
            project_id="old-project",
            source_kind="git_checkout",
            project_root=".",
            build_target=None,
            generator=None,
            repository="https://github.com/example/old.git",
            ref=None,
            build_command=("lake", "build"),
            generate_command=VBP_BUILD_COMMAND,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
            targets=(HarnessProjectTarget(release="v4.28.0", ref="def456"),),
        )
        catalog = HarnessProjectCatalog(
            version=2,
            release_targets=(release,),
            projects=(selected_project, old_project),
        )
        buffer = io.StringIO()
        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            resolve_manifest_path=lambda _path_text, _package_root: Path("/tmp/projects.json"),
            load_project_catalog_manifest=lambda _manifest_path: catalog,
            resolve_release_target=lambda _catalog, _release, _package_root: release,
            resolve_projects_for_release=lambda _catalog, _release, _selected_ids: [selected_project],
            active_release_branch=lambda _repo_root: "v4.29.0",
            preferred_release_ref=lambda _repo_root: "origin/v4.29.0",
            canonical_test_blueprint_site_dir=(
                lambda _name, _start=None: Path("/tmp/package/_out/test-blueprints/preview_runtime_showcase/html-multi")
            ),
            canonical_reference_project_site_dir=(
                lambda project_id, _start=None: Path(f"/tmp/package/_out/reference-blueprints/{project_id}/html-multi")
            ),
        ):
            with redirect_stdout(buffer):
                self.assertEqual(harness_mod.command_paths(args), 0)

        output = buffer.getvalue()
        self.assertIn("selected_release_target=v4.29.0", output)
        self.assertIn("project_path_scope=selected_release", output)
        self.assertIn("noperthedron_site=/tmp/package/_out/reference-blueprints/noperthedron/html-multi", output)
        self.assertNotIn("old-project_site=", output)

    def test_require_branch_role_parses_requested_role(self) -> None:
        parser = build_parser()
        args = parser.parse_args(["require-branch-role", "default_dev"])
        self.assertEqual(args.role, "default_dev")

    def test_require_branch_role_returns_nonzero_on_mismatch(self) -> None:
        args = argparse.Namespace(role="default_dev")
        layout = SimpleNamespace(repo_root=Path("/tmp/repo"), package_root=Path("/tmp/worktree"))
        out = io.StringIO()
        err = io.StringIO()
        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            print_branch_policy_status=lambda _layout: None,
            checkout_branch_role=lambda _checkout_root: "backport",
            active_release_branch=lambda _checkout_root: "v4.28.0",
            default_dev_branch=lambda _checkout_root: "v4.29.0",
        ):
            with redirect_stdout(out), redirect_stderr(err):
                self.assertEqual(harness_mod.command_require_branch_role(args), 1)

        self.assertEqual(out.getvalue(), "")
        self.assertIn("checkout `v4.28.0` is backport-only", err.getvalue())

    def test_reference_edit_uses_prepare_reference_checkout(self) -> None:
        project = HarnessProject(
            project_id="noperthedron",
            source_kind="git_checkout",
            project_root=".",
            build_target=None,
            generator=None,
            repository="https://github.com/example/noperthedron.git",
            ref="main",
            build_command=("lake", "build"),
            generate_command=VBP_BUILD_COMMAND,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
        )
        selected_project = HarnessProject(
            project_id="noperthedron",
            source_kind="git_checkout",
            project_root=".",
            build_target=None,
            generator=None,
            repository="https://github.com/example/noperthedron.git",
            ref="target-ref",
            build_command=("lake", "build"),
            generate_command=VBP_BUILD_COMMAND,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
            selected_release="v4.29.0",
        )
        args = argparse.Namespace(
            manifest=None,
            project="noperthedron",
            release="v4.29.0",
            branch="wip/noperthedron",
            base=None,
        )
        layout = SimpleNamespace(package_root=Path("/tmp/package"), reference_project_edit_root=Path("/tmp/edit"))
        seen: dict[str, object] = {}

        def fake_prepare(_layout, _project, *, branch, base_ref):
            seen["layout"] = _layout
            seen["project"] = _project
            seen["branch"] = branch
            seen["base_ref"] = base_ref
            return Path("/tmp/edit/noperthedron"), branch or "wip/noperthedron", base_ref or "origin/target-ref"

        with patched_attrs(
            reference_harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            resolve_manifest_path=lambda _path_text, _package_root: Path("/tmp/projects.json"),
            load_project_catalog=lambda _manifest_path: SimpleNamespace(projects=(project,)),
            select_release_projects=lambda _catalog, *, release, project_ids, package_root: ("v4.29.0", [selected_project]),
            prepare_reference_edit_checkout=fake_prepare,
        ):
            self.assertEqual(reference_harness_mod.command_reference_edit(args), 0)

        self.assertEqual(seen["layout"], layout)
        self.assertEqual(seen["project"], selected_project)
        self.assertEqual(seen["branch"], "wip/noperthedron")
        self.assertIsNone(seen["base_ref"])

    def test_reference_bump_blueprint_uses_bump_helper(self) -> None:
        project = HarnessProject(
            project_id="noperthedron",
            source_kind="git_checkout",
            project_root=".",
            build_target=None,
            generator=None,
            repository="https://github.com/example/noperthedron.git",
            ref="main",
            build_command=("lake", "build"),
            generate_command=VBP_BUILD_COMMAND,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
        )
        args = argparse.Namespace(
            manifest=None,
            project=["noperthedron"],
            release="v4.29.0",
            ref="v1.2.3",
            branch="chore/bump-verso-blueprint-v1-2-3",
            base=None,
            skip_build=False,
            generate=True,
            commit=False,
            push=False,
            commit_message=None,
        )
        layout = SimpleNamespace(package_root=Path("/tmp/package"), artifact_root=Path("/tmp/out"))
        seen: dict[str, object] = {}

        def fake_select(_catalog, *, release, project_ids, package_root, default_to_published_catalog=True):
            seen["default_to_published_catalog"] = default_to_published_catalog
            return "v4.29.0", [project]

        def fake_bump(
            _layout,
            _project,
            *,
            ref,
            branch,
            base_ref,
            build_project,
            generate_site,
            output_root,
            commit,
            push,
            commit_message,
        ):
            seen["layout"] = _layout
            seen["project"] = _project
            seen["ref"] = ref
            seen["branch"] = branch
            seen["base_ref"] = base_ref
            seen["build_project"] = build_project
            seen["generate_site"] = generate_site
            seen["output_root"] = output_root
            seen["commit"] = commit
            seen["push"] = push
            seen["commit_message"] = commit_message
            return SimpleNamespace(
                edit_dir=Path("/tmp/edit/noperthedron"),
                branch=branch,
                base_ref=base_ref or "origin/main",
                previous_ref="old-ref",
                changed=True,
                committed=False,
                pushed=False,
                output_dir=output_root / "noperthedron",
            )

        seen["selected_values"] = ["noperthedron"]
        with patched_attrs(
            reference_harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            resolve_manifest_path=lambda _path_text, _package_root: Path("/tmp/projects.json"),
            load_project_catalog=lambda _manifest_path: SimpleNamespace(projects=(project,)),
            select_release_projects=fake_select,
            bump_reference_project=fake_bump,
        ):
            self.assertEqual(reference_harness_mod.command_reference_bump_blueprint(args), 0)

        self.assertEqual(seen["layout"], layout)
        self.assertEqual(seen["project"], project)
        self.assertEqual(seen["selected_values"], ["noperthedron"])
        self.assertFalse(seen["default_to_published_catalog"])
        self.assertEqual(seen["ref"], "v1.2.3")
        self.assertEqual(seen["branch"], "chore/bump-verso-blueprint-v1-2-3")
        self.assertIsNone(seen["base_ref"])
        self.assertTrue(seen["build_project"])
        self.assertTrue(seen["generate_site"])
        self.assertEqual(seen["output_root"], Path("/tmp/out/reference-blueprints-edit"))
        self.assertFalse(seen["commit"])
        self.assertFalse(seen["push"])

    def test_reference_bump_blueprint_defaults_to_release_git_checkout_targets(self) -> None:
        def external_project(project_id: str, release: str, ref: str, *, publish: bool = False) -> HarnessProject:
            return HarnessProject(
                project_id=project_id,
                source_kind="git_checkout",
                project_root=".",
                build_target=None,
                generator=None,
                repository=f"https://github.com/example/{project_id}.git",
                ref=None,
                build_command=("lake", "build"),
                generate_command=VBP_BUILD_COMMAND,
                site_subdir="html-multi",
                panel_regression_script=None,
                browser_tests_path=None,
                description=None,
                targets=(HarnessProjectTarget(release=release, ref=ref, publish_reference=publish),),
            )

        in_repo_project = HarnessProject(
            project_id="project-template",
            source_kind=IN_REPO_PROJECT_SOURCE_KIND,
            project_root="project_template",
            build_target=None,
            generator=None,
            repository=None,
            ref=None,
            build_command=None,
            generate_command=VBP_BUILD_COMMAND,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
            targets=(HarnessProjectTarget(release="v4.29.0", ref=None),),
        )
        catalog = HarnessProjectCatalog(
            version=2,
            release_targets=(
                HarnessReleaseTarget("v4.28.0", "v4.28.0", "v4.28.0", "v4.28.0", False),
                HarnessReleaseTarget("v4.29.0", "v4.29.0", "v4.29.0", "v4.29.0", True),
            ),
            projects=(
                external_project("published", "v4.29.0", "published-ref", publish=True),
                external_project("validation-only", "v4.29.0", "validation-ref"),
                in_repo_project,
                external_project("old-release", "v4.28.0", "old-ref"),
            ),
        )
        args = argparse.Namespace(
            manifest=None,
            project=None,
            release="v4.29.0",
            ref="v1.2.3",
            branch=None,
            base=None,
            skip_build=True,
            generate=False,
            commit=False,
            push=False,
            commit_message=None,
        )
        layout = SimpleNamespace(package_root=Path("/tmp/package"), artifact_root=Path("/tmp/out"))
        seen_projects: list[HarnessProject] = []

        def fake_bump(_layout, project, **_kwargs):
            seen_projects.append(project)
            return SimpleNamespace(
                edit_dir=Path(f"/tmp/edit/{project.project_id}"),
                branch="chore/bump-verso-blueprint-v1-2-3",
                base_ref="origin/main",
                previous_ref="old-ref",
                changed=True,
                committed=False,
                pushed=False,
                output_dir=None,
            )

        with patched_attrs(
            reference_harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            resolve_manifest_path=lambda _path_text, _package_root: Path("/tmp/projects.json"),
            load_project_catalog=lambda _manifest_path: catalog,
            bump_reference_project=fake_bump,
        ):
            self.assertEqual(reference_harness_mod.command_reference_bump_blueprint(args), 0)

        self.assertEqual(
            [(project.project_id, project.ref) for project in seen_projects],
            [("published", "published-ref"), ("validation-only", "validation-ref")],
        )

    def test_worktree_retire_supports_detached_merged_worktree(self) -> None:
        args = argparse.Namespace(name="reference-edit", dry_run=False)
        layout = SimpleNamespace(
            repo_root=Path("/tmp/repo"),
            package_root=Path("/tmp/package"),
            worktree_name=None,
            reference_source_cache_root=Path("/tmp/cache"),
            reference_dependency_cache_root=Path("/tmp/deps"),
            reference_project_root=Path("/tmp/reference-root"),
        )
        detached = GitWorktree(
            name="reference-edit",
            path=Path("/tmp/repo/.worktrees/reference-edit"),
            head="abc123",
            branch=None,
            root_checkout=False,
        )
        commands: list[list[str]] = []
        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            worktree_record_map=lambda _repo_root: (
                {
                    "reference-edit": SimpleNamespace(
                        name="reference-edit",
                        locked=False,
                    )
                },
                Path("/tmp/repo/.worktrees/registry.json"),
            ),
            git_worktree_map=lambda _repo_root: {"reference-edit": detached},
            preferred_worktree_base_ref=lambda _path: "origin/v4.29.0",
            ref_merged_into_worktree_base=lambda _repo_root, ref, _path: ref == "abc123",
            worktree_is_clean=lambda _path: True,
            local_release_ref=lambda _repo_root: "v4.29.0",
            run=lambda command, *, cwd: commands.append(command),
            resolve_manifest_path=lambda _path_text, _package_root: Path("/tmp/projects.json"),
            load_project_catalog_manifest=lambda _manifest_path: SimpleNamespace(projects=()),
            git_worktrees=lambda _repo_root: [],
            reference_prune_plan=lambda *_args, **_kwargs: [],
        ):
            self.assertEqual(harness_mod.command_worktree_retire(args), 0)

        self.assertEqual(commands, [["git", "worktree", "remove", str(detached.path)]])

    def test_worktree_retire_accepts_backport_branch_merged_into_its_release_base(self) -> None:
        args = argparse.Namespace(name="backport-demo", dry_run=False)
        layout = SimpleNamespace(
            repo_root=Path("/tmp/repo"),
            package_root=Path("/tmp/package"),
            worktree_name=None,
            reference_source_cache_root=Path("/tmp/cache"),
            reference_dependency_cache_root=Path("/tmp/deps"),
            reference_project_root=Path("/tmp/reference-root"),
        )
        backport = GitWorktree(
            name="backport-demo",
            path=Path("/tmp/repo/.worktrees/backport-demo"),
            head="def456",
            branch="fix/backport-demo",
            root_checkout=False,
        )
        commands: list[list[str]] = []
        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            worktree_record_map=lambda _repo_root: (
                {
                    "backport-demo": SimpleNamespace(
                        name="backport-demo",
                        locked=False,
                    )
                },
                Path("/tmp/repo/.worktrees/registry.json"),
            ),
            git_worktree_map=lambda _repo_root: {"backport-demo": backport},
            preferred_worktree_base_ref=lambda _path: "origin/v4.28.0",
            ref_merged_into_worktree_base=lambda _repo_root, ref, _path: ref == "fix/backport-demo",
            worktree_is_clean=lambda _path: True,
            local_release_ref=lambda _repo_root: "v4.29.0",
            run=lambda command, *, cwd: commands.append(command),
            resolve_manifest_path=lambda _path_text, _package_root: Path("/tmp/projects.json"),
            load_project_catalog_manifest=lambda _manifest_path: SimpleNamespace(projects=()),
            git_worktrees=lambda _repo_root: [],
            reference_prune_plan=lambda *_args, **_kwargs: [],
        ):
            self.assertEqual(harness_mod.command_worktree_retire(args), 0)

        self.assertEqual(
            commands,
            [
                ["git", "worktree", "remove", str(backport.path)],
                ["git", "branch", "-d", backport.branch],
            ],
        )

    def test_worktree_retire_accepts_verified_squash_merged_pr(self) -> None:
        args = argparse.Namespace(name="demo", dry_run=False, merged_pr=152)
        layout = SimpleNamespace(
            repo_root=Path("/tmp/repo"),
            package_root=Path("/tmp/package"),
            worktree_name=None,
            reference_source_cache_root=Path("/tmp/cache"),
            reference_dependency_cache_root=Path("/tmp/deps"),
            reference_project_root=Path("/tmp/reference-root"),
        )
        demo = GitWorktree(
            name="demo",
            path=Path("/tmp/repo/.worktrees/demo"),
            head="abc123",
            branch="feat/demo",
            root_checkout=False,
        )
        commands: list[list[str]] = []
        seen_prs: list[int] = []

        def fake_pr_validation(_repo_root, pr_number, worktree, base_ref):
            seen_prs.append(pr_number)
            self.assertEqual(worktree, demo)
            self.assertEqual(base_ref, "origin/v4.31.0")
            return None

        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            worktree_record_map=lambda _repo_root: (
                {
                    "demo": SimpleNamespace(
                        name="demo",
                        locked=False,
                    )
                },
                Path("/tmp/repo/.worktrees/registry.json"),
            ),
            git_worktree_map=lambda _repo_root: {"demo": demo},
            preferred_worktree_base_ref=lambda _path: "origin/v4.31.0",
            ref_merged_into_worktree_base=lambda _repo_root, _ref, _path: False,
            worktree_merged_pr_validation_error=fake_pr_validation,
            worktree_is_clean=lambda _path: True,
            local_release_ref=lambda _repo_root: "v4.31.0",
            run=lambda command, *, cwd: commands.append(command),
            resolve_manifest_path=lambda _path_text, _package_root: Path("/tmp/projects.json"),
            load_project_catalog_manifest=lambda _manifest_path: SimpleNamespace(projects=()),
            git_worktrees=lambda _repo_root: [],
            reference_prune_plan=lambda *_args, **_kwargs: [],
        ):
            self.assertEqual(harness_mod.command_worktree_retire(args), 0)

        self.assertEqual(seen_prs, [152])
        self.assertEqual(
            commands,
            [
                ["git", "worktree", "remove", str(demo.path)],
                ["git", "branch", "-D", demo.branch],
            ],
        )

    def test_worktree_retire_rejects_unverified_squash_merged_pr(self) -> None:
        args = argparse.Namespace(name="demo", dry_run=False, merged_pr=152)
        layout = SimpleNamespace(
            repo_root=Path("/tmp/repo"),
            package_root=Path("/tmp/package"),
            worktree_name=None,
        )
        demo = GitWorktree(
            name="demo",
            path=Path("/tmp/repo/.worktrees/demo"),
            head="abc123",
            branch="feat/demo",
            root_checkout=False,
        )
        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            worktree_record_map=lambda _repo_root: (
                {
                    "demo": SimpleNamespace(
                        name="demo",
                        locked=False,
                    )
                },
                Path("/tmp/repo/.worktrees/registry.json"),
            ),
            git_worktree_map=lambda _repo_root: {"demo": demo},
            preferred_worktree_base_ref=lambda _path: "origin/v4.31.0",
            ref_merged_into_worktree_base=lambda _repo_root, _ref, _path: False,
            worktree_merged_pr_validation_error=lambda *_args: "GitHub PR #152 is not merged",
            local_release_ref=lambda _repo_root: "v4.31.0",
        ):
            with self.assertRaisesRegex(SystemExit, "GitHub PR #152 is not merged"):
                harness_mod.command_worktree_retire(args)

    def test_worktree_retire_hints_for_unverified_squash_merge(self) -> None:
        args = argparse.Namespace(name="demo", dry_run=False)
        layout = SimpleNamespace(
            repo_root=Path("/tmp/repo"),
            package_root=Path("/tmp/package"),
            worktree_name=None,
        )
        demo = GitWorktree(
            name="demo",
            path=Path("/tmp/repo/.worktrees/demo"),
            head="abc123",
            branch="feat/demo",
            root_checkout=False,
        )
        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            worktree_record_map=lambda _repo_root: (
                {
                    "demo": SimpleNamespace(
                        name="demo",
                        locked=False,
                    )
                },
                Path("/tmp/repo/.worktrees/registry.json"),
            ),
            git_worktree_map=lambda _repo_root: {"demo": demo},
            preferred_worktree_base_ref=lambda _path: "origin/v4.31.0",
            ref_merged_into_worktree_base=lambda _repo_root, _ref, _path: False,
            local_release_ref=lambda _repo_root: "v4.31.0",
        ):
            with self.assertRaisesRegex(SystemExit, "pass `--merged-pr <number>` after a squash merge"):
                harness_mod.command_worktree_retire(args)

    def test_worktree_retire_rejects_locked_worktree(self) -> None:
        args = argparse.Namespace(name="demo", dry_run=False)
        layout = SimpleNamespace(
            repo_root=Path("/tmp/repo"),
            package_root=Path("/tmp/package"),
            worktree_name=None,
        )
        with patched_attrs(
            harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            local_release_ref=lambda _repo_root: "v4.29.0",
            worktree_record_map=lambda _repo_root: (
                {
                    "demo": SimpleNamespace(
                        name="demo",
                        locked=True,
                    )
                },
                Path("/tmp/repo/.worktrees/registry.json"),
            ),
            git_worktree_map=lambda _repo_root: {
                "demo": GitWorktree(
                    name="demo",
                    path=Path("/tmp/repo/.worktrees/demo"),
                    head="abc123",
                    branch="feat/demo",
                    root_checkout=False,
                )
            },
        ):
            with self.assertRaisesRegex(SystemExit, "is locked; unlock it before retiring"):
                harness_mod.command_worktree_retire(args)

    def test_generate_projects_does_not_auto_sync_root_lake(self) -> None:
        project = HarnessProject(
            project_id="demo",
            source_kind=IN_REPO_PROJECT_SOURCE_KIND,
            project_root=".",
            build_target="Demo",
            generator="demo",
            repository=None,
            ref=None,
            build_command=None,
            generate_command=None,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
        )
        layout = SimpleNamespace(package_root=Path("/tmp/package"), in_linked_worktree=True)

        with patched_attrs(
            reference_harness_mod,
            ensure_prebuilt_executable=lambda _package_root, _exe_name: Path("/tmp/demo"),
            render_in_repo_projects=lambda _package_root, _output_root, _projects, _serial, *, verbose=False: None,
        ):
            generate_projects(
                layout,
                Path("/tmp/out"),
                [project],
                skip_build=False,
                serial=False,
                allow_local_build=False,
                reference_package_mode="copy",
            )

    def test_validate_run_lean_tests_does_not_auto_sync_root_lake(self) -> None:
        args = argparse.Namespace(
            output_root=None,
            manifest=None,
            project=None,
            release=None,
            run_lean_tests=True,
            allow_unsafe_root_release=False,
            skip_panel_regression=False,
            skip_browser_tests=False,
            serial=False,
            pytest_arg=[],
            allow_local_build=False,
            stop_on_first_failure=False,
        )
        layout = SimpleNamespace(package_root=Path("/tmp/package"), in_linked_worktree=True)
        with patched_attrs(
            reference_harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            resolve_output_root=lambda _path_text, _start=None: Path("/tmp/out"),
            resolve_manifest_path=lambda _path_text, _package_root: Path("/tmp/projects.json"),
            load_project_catalog=lambda _manifest_path: SimpleNamespace(projects=(), release_targets=()),
            select_release_projects=lambda _catalog, *, release, project_ids, package_root: ("v4.29.0", []),
            require_checkout_release=lambda _layout, release_id, *, command_name: None,
            should_use_local_build=lambda _layout, _allow_local_build: False,
            find_prebuilt_lean_test_artifact=lambda _package_root: Path("/tmp/VersoBlueprintTests.olean"),
            run_capturing_failure=lambda _step, _command, cwd: None,
            generate_projects=lambda *_args, **_kwargs: None,
        ):
            self.assertEqual(reference_harness_mod.command_validate(args), 0)

    def test_reference_validate_rejects_unsafe_root_release_without_override(self) -> None:
        args = argparse.Namespace(
            output_root=None,
            manifest=None,
            project=None,
            release=None,
            run_lean_tests=False,
            allow_unsafe_root_release=False,
            skip_panel_regression=False,
            skip_browser_tests=False,
            serial=False,
            pytest_arg=[],
            allow_local_build=False,
            stop_on_first_failure=False,
        )
        layout = SimpleNamespace(package_root=Path("/tmp/package"), repo_root=Path("/tmp/package"), in_linked_worktree=False)
        seen: dict[str, object] = {}

        def fake_require(_layout, *, allow_unsafe, command_name):
            seen["layout"] = _layout
            seen["allow_unsafe"] = allow_unsafe
            seen["command_name"] = command_name
            raise SystemExit("blocked")

        with patched_attrs(
            reference_harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            require_safe_root_release=fake_require,
        ):
            with self.assertRaisesRegex(SystemExit, "blocked"):
                reference_harness_mod.command_validate(args)

        self.assertEqual(seen["layout"], layout)
        self.assertFalse(seen["allow_unsafe"])
        self.assertEqual(seen["command_name"], "validate")

    def test_reference_sync_allows_unsafe_root_release_with_override(self) -> None:
        args = argparse.Namespace(
            manifest=None,
            project=None,
            release=None,
            skip_build=False,
            allow_unsafe_root_release=True,
            skip_local_checkout=False,
        )
        layout = SimpleNamespace(
            package_root=Path("/tmp/package"),
            repo_root=Path("/tmp/package"),
            in_linked_worktree=False,
            reference_source_cache_root=Path("/tmp/cache"),
            reference_dependency_cache_root=Path("/tmp/deps"),
            reference_project_checkout_root=Path("/tmp/checkouts"),
        )
        seen: dict[str, object] = {}

        def fake_require(_layout, *, allow_unsafe, command_name):
            seen["layout"] = _layout
            seen["allow_unsafe"] = allow_unsafe
            seen["command_name"] = command_name

        with patched_attrs(
            reference_harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            require_safe_root_release=fake_require,
            resolve_manifest_path=lambda _path_text, _package_root: Path("/tmp/projects.json"),
            load_project_catalog=lambda _manifest_path: SimpleNamespace(projects=(), release_targets=()),
            select_release_projects=lambda _catalog, *, release, project_ids, package_root: ("v4.29.0", []),
            require_checkout_release=lambda _layout, release_id, *, command_name: None,
            sync_reference_blueprints=lambda *_args, **_kwargs: None,
        ):
            self.assertEqual(reference_harness_mod.command_reference_sync(args), 0)

        self.assertEqual(seen["layout"], layout)
        self.assertTrue(seen["allow_unsafe"])
        self.assertEqual(seen["command_name"], "sync")

    def test_reference_status_prints_catalog_and_blueprint_drift(self) -> None:
        project = HarnessProject(
            project_id="noperthedron",
            source_kind="git_checkout",
            project_root=".",
            build_target=None,
            generator=None,
            repository="https://github.com/example/noperthedron.git",
            ref="abc123",
            build_command=("lake", "build"),
            generate_command=VBP_BUILD_COMMAND,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
        )
        args = argparse.Namespace(manifest=None, project=None, release=None)
        layout = SimpleNamespace(package_root=Path("/tmp/package"), repo_root=Path("/tmp/repo"))
        release = HarnessReleaseTarget("v4.29.0", "v4.29.0", "v4.29.0", "v4.29.0", True)
        status = reference_harness_mod.ReferenceProjectStatus(
            project=project,
            catalog_ref="abc123",
            project_upstream_ref="origin/main",
            project_relationship="behind",
            project_ahead=0,
            project_behind=12,
            blueprint_pin=reference_harness_mod.BlueprintDependencyPin(
                source_path="lake-manifest.json",
                input_ref="main",
                resolved_ref="deadbeef",
            ),
            blueprint_relationship="behind",
            blueprint_ahead=0,
            blueprint_behind=5,
        )
        out = io.StringIO()
        with patched_attrs(
            reference_harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            resolve_manifest_path=lambda _path_text, _package_root: Path("/tmp/projects.json"),
            load_project_catalog=lambda _manifest_path: SimpleNamespace(projects=(project,), release_targets=()),
            select_release_projects=lambda _catalog, *, release, project_ids, package_root: ("v4.29.0", [project]),
            require_checkout_release=lambda _layout, _release_id, *, command_name: None,
            resolve_release_target=lambda _catalog, _release, _package_root: release,
            ref_sync_status=lambda _repo_root, _local_ref, _upstream_ref: harness_mod.RefSyncStatus(
                local_ref="v4.29.0",
                upstream_ref="origin/v4.29.0",
                local_oid="111",
                upstream_oid="111",
                relationship="in_sync",
            ),
            collect_reference_project_status=lambda _layout, _project, *, blueprint_base_ref=None: status,
        ):
            with redirect_stdout(out):
                self.assertEqual(reference_harness_mod.command_status(args), 0)

        output = out.getvalue()
        self.assertIn("project_manifest=/tmp/projects.json", output)
        self.assertIn("release_relationship=in_sync", output)
        self.assertIn("verso_blueprint_ref=v4.29.0", output)
        self.assertIn("noperthedron\tsource=git:https://github.com/example/noperthedron.git@abc123", output)
        self.assertIn("rc=\ttoolchain=v4.29.0\tverso_ref=v4.29.0", output)
        self.assertIn("catalog_status=behind", output)
        self.assertIn("catalog_behind=12", output)
        self.assertIn("blueprint_pin_source=lake-manifest.json", output)
        self.assertIn("blueprint_resolved_ref=deadbeef", output)
        self.assertIn("blueprint_status=behind", output)

    def test_reference_release_status_summarizes_and_filters_outdated_targets(self) -> None:
        template = HarnessProject(
            project_id="project-template",
            source_kind=IN_REPO_PROJECT_SOURCE_KIND,
            project_root="project_template",
            build_target=None,
            generator=None,
            repository=None,
            ref=None,
            build_command=("lake", "build"),
            generate_command=VBP_BUILD_COMMAND,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
            targets=(
                HarnessProjectTarget(release="v4.28.0", ref=None),
                HarnessProjectTarget(release="v4.29.0", ref=None),
            ),
        )
        nop = HarnessProject(
            project_id="noperthedron",
            source_kind="git_checkout",
            project_root=".",
            build_target=None,
            generator=None,
            repository="https://github.com/example/noperthedron.git",
            ref=None,
            build_command=("lake", "build"),
            generate_command=VBP_BUILD_COMMAND,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
            targets=(HarnessProjectTarget(release="v4.29.0", ref="deadbeef", publish_reference=True),),
        )
        sphere = HarnessProject(
            project_id="spherepackingblueprint",
            source_kind="git_checkout",
            project_root=".",
            build_target=None,
            generator=None,
            repository="https://github.com/example/sphere.git",
            ref=None,
            build_command=("lake", "build"),
            generate_command=VBP_BUILD_COMMAND,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
            targets=(HarnessProjectTarget(release="v4.28.0", ref="cafebabe"),),
        )
        catalog = HarnessProjectCatalog(
            version=2,
            release_targets=(
                HarnessReleaseTarget("v4.28.0", "v4.28.0", "v4.28.0", "v4.28.0", False),
                HarnessReleaseTarget("v4.29.0", "v4.29.0", "v4.29.0", "v4.29.0", True),
            ),
            projects=(template, nop, sphere),
        )
        args = argparse.Namespace(manifest=None, project=None, release=None, outdated_only=True)
        layout = SimpleNamespace(package_root=Path("/tmp/package"), repo_root=Path("/tmp/repo"))
        out = io.StringIO()

        def fake_collect(_layout, project, *, blueprint_base_ref=None):
            if project.project_id == "noperthedron":
                return reference_harness_mod.ReferenceProjectStatus(
                    project=project,
                    catalog_ref="deadbeef",
                    project_upstream_ref="origin/main",
                    project_relationship="behind",
                    project_ahead=0,
                    project_behind=3,
                    blueprint_pin=None,
                    blueprint_relationship=None,
                    blueprint_ahead=None,
                    blueprint_behind=None,
                )
            return reference_harness_mod.ReferenceProjectStatus(
                project=project,
                catalog_ref=project.ref,
                project_upstream_ref="origin/main" if project.git_checkout else None,
                project_relationship="in_sync" if project.git_checkout else None,
                project_ahead=0 if project.git_checkout else None,
                project_behind=0 if project.git_checkout else None,
                blueprint_pin=None,
                blueprint_relationship=None,
                blueprint_ahead=None,
                blueprint_behind=None,
                skipped="in_repo_project" if project.in_repo_project else None,
            )

        with patched_attrs(
            reference_harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            resolve_manifest_path=lambda _path_text, _package_root: Path("/tmp/projects.json"),
            load_project_catalog=lambda _manifest_path: catalog,
            collect_reference_project_status=fake_collect,
        ):
            with redirect_stdout(out):
                self.assertEqual(reference_harness_mod.command_release_status(args), 0)

        output = out.getvalue()
        self.assertIn("project_manifest=/tmp/projects.json", output)
        self.assertIn("release=v4.29.0", output)
        self.assertIn("outdated_projects=1", output)
        self.assertIn("downstream_pin_drift=0", output)
        self.assertIn("project=noperthedron", output)
        self.assertNotIn("project=spherepackingblueprint", output)

    def test_reference_release_status_project_filter_includes_validation_only_targets(self) -> None:
        validation_project = HarnessProject(
            project_id="validation-only",
            source_kind="git_checkout",
            project_root=".",
            build_target=None,
            generator=None,
            repository="https://github.com/example/validation-only.git",
            ref=None,
            build_command=("lake", "build"),
            generate_command=VBP_BUILD_COMMAND,
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
            targets=(HarnessProjectTarget(release="v4.29.0", ref="validation-ref"),),
        )
        catalog = HarnessProjectCatalog(
            version=2,
            release_targets=(
                HarnessReleaseTarget("v4.28.0", "v4.28.0", "v4.28.0", "v4.28.0", False),
                HarnessReleaseTarget("v4.29.0", "v4.29.0", "v4.29.0", "v4.29.0", True),
            ),
            projects=(validation_project,),
        )
        args = argparse.Namespace(manifest=None, project=["validation-only"], release=None, outdated_only=False)
        layout = SimpleNamespace(package_root=Path("/tmp/package"), repo_root=Path("/tmp/repo"))
        out = io.StringIO()
        seen_projects: list[HarnessProject] = []

        def fake_collect(_layout, project, *, blueprint_base_ref=None):
            seen_projects.append(project)
            return reference_harness_mod.ReferenceProjectStatus(
                project=project,
                catalog_ref=project.ref,
                project_upstream_ref="origin/main",
                project_relationship="in_sync",
                project_ahead=0,
                project_behind=0,
                blueprint_pin=None,
                blueprint_relationship=None,
                blueprint_ahead=None,
                blueprint_behind=None,
            )

        with patched_attrs(
            reference_harness_mod,
            detect_harness_layout=lambda _start=None: layout,
            resolve_manifest_path=lambda _path_text, _package_root: Path("/tmp/projects.json"),
            load_project_catalog=lambda _manifest_path: catalog,
            collect_reference_project_status=fake_collect,
        ):
            with redirect_stdout(out):
                self.assertEqual(reference_harness_mod.command_release_status(args), 0)

        output = out.getvalue()
        self.assertIn("release=v4.29.0", output)
        self.assertIn("project=validation-only", output)
        self.assertNotIn("release=v4.28.0", output)
        self.assertEqual([(project.project_id, project.ref) for project in seen_projects], [("validation-only", "validation-ref")])


if __name__ == "__main__":
    unittest.main()
