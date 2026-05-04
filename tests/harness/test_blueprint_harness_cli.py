from __future__ import annotations

import argparse
from contextlib import redirect_stderr, redirect_stdout
import io
from pathlib import Path
from types import SimpleNamespace
import unittest

import scripts.blueprint_harness as harness_mod
import scripts.blueprint_reference_harness as reference_harness_mod
from scripts.blueprint_harness import build_parser, create_worktree_sync_policy
from scripts.blueprint_reference_harness import generate_projects
from scripts.blueprint_harness_projects import (
    HarnessProject,
    HarnessProjectCatalog,
    HarnessProjectTarget,
    HarnessReleaseTarget,
)
from scripts.blueprint_harness_worktrees import GitWorktree


class BlueprintHarnessCliTests(unittest.TestCase):
    def test_create_worktree_sync_policy_respects_lightweight_mode(self) -> None:
        args = argparse.Namespace(skip_sync=False, skip_reference_sync=False, lightweight=True)
        self.assertEqual(create_worktree_sync_policy(args), (True, True))

    def test_create_worktree_sync_policy_preserves_explicit_flags(self) -> None:
        args = argparse.Namespace(skip_sync=True, skip_reference_sync=False, lightweight=False)
        self.assertEqual(create_worktree_sync_policy(args), (True, False))

    def test_reference_sync_does_not_accept_example_alias(self) -> None:
        parser = reference_harness_mod.build_parser()
        with self.assertRaises(SystemExit):
            parser.parse_args(["sync", "--example", "noperthedron"])

    def test_reference_status_does_not_accept_example_alias(self) -> None:
        parser = reference_harness_mod.build_parser()
        with self.assertRaises(SystemExit):
            parser.parse_args(["status", "--example", "noperthedron"])

    def test_reference_generate_parses_allow_unsafe_root_release(self) -> None:
        parser = reference_harness_mod.build_parser()
        args = parser.parse_args(["generate", "--allow-unsafe-root-release", "--release", "v4.29.0"])
        self.assertTrue(args.allow_unsafe_root_release)
        self.assertEqual(args.release, "v4.29.0")

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

    def test_reference_projects_parses_release_filter(self) -> None:
        parser = reference_harness_mod.build_parser()
        args = parser.parse_args(["projects", "--release", "v4.29.0"])
        self.assertEqual(args.release, "v4.29.0")

    def test_reference_release_status_parses_flags(self) -> None:
        parser = reference_harness_mod.build_parser()
        args = parser.parse_args(["release-status", "--release", "v4.28.0", "--outdated-only"])
        self.assertEqual(args.release, "v4.28.0")
        self.assertTrue(args.outdated_only)

    def test_main_status_parses_require_sync(self) -> None:
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

    def test_bump_toolchain_parses_optional_flags(self) -> None:
        parser = build_parser()
        args = parser.parse_args(["bump-toolchain", "4.29.0", "--verso-ref", "v4.29.0", "--skip-validation"])
        self.assertEqual(args.toolchain, "4.29.0")
        self.assertEqual(args.verso_ref, "v4.29.0")
        self.assertTrue(args.skip_validation)

    def test_create_worktree_parses_lock_flag(self) -> None:
        parser = build_parser()
        args = parser.parse_args(["create-worktree", "demo", "--lock"])
        self.assertTrue(args.lock)

    def test_worktree_claim_parses_lock_flags(self) -> None:
        parser = build_parser()
        lock_args = parser.parse_args(["worktree-claim", "demo", "--lock"])
        unlock_args = parser.parse_args(["worktree-claim", "demo", "--unlock"])
        self.assertTrue(lock_args.lock)
        self.assertFalse(lock_args.unlock)
        self.assertFalse(unlock_args.lock)
        self.assertTrue(unlock_args.unlock)

    def test_land_main_parses_cleanup_flags(self) -> None:
        parser = build_parser()
        args = parser.parse_args(["land-release", "feat/demo", "--cleanup", "--keep-remote", "--no-push"])
        self.assertEqual(args.source, "feat/demo")
        self.assertTrue(args.cleanup)
        self.assertTrue(args.keep_remote)
        self.assertTrue(args.no_push)

    def test_reference_edit_parses_project_branch_and_base(self) -> None:
        parser = reference_harness_mod.build_parser()
        args = parser.parse_args(["edit", "noperthedron", "--branch", "wip/noperthedron", "--base", "origin/main"])
        self.assertEqual(args.project, "noperthedron")
        self.assertEqual(args.branch, "wip/noperthedron")
        self.assertEqual(args.base, "origin/main")

    def test_reference_bump_blueprint_parses_ref_and_push(self) -> None:
        parser = reference_harness_mod.build_parser()
        args = parser.parse_args(
            ["bump-verso-blueprint", "--project", "noperthedron", "--ref", "v1.2.3", "--push"]
        )
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

    def test_create_worktree_uses_preferred_main_ref_by_default(self) -> None:
        layout = SimpleNamespace(repo_root=Path("/tmp/repo"))
        originals = {
            "preferred_main_ref": harness_mod.preferred_main_ref,
            "active_release_branch": harness_mod.active_release_branch,
        }
        try:
            harness_mod.preferred_main_ref = lambda _repo_root: "origin/v4.29.0"
            harness_mod.active_release_branch = lambda _repo_root: "v4.29.0"
            self.assertEqual(harness_mod.resolve_create_worktree_base(layout, None), "origin/v4.29.0")
        finally:
            for name, value in originals.items():
                setattr(harness_mod, name, value)

    def test_create_worktree_rejects_unsynced_local_main_base(self) -> None:
        layout = SimpleNamespace(repo_root=Path("/tmp/repo"))
        originals = {
            "preferred_main_ref": harness_mod.preferred_main_ref,
            "main_sync_status": harness_mod.main_sync_status,
            "active_release_branch": harness_mod.active_release_branch,
        }
        try:
            harness_mod.preferred_main_ref = lambda _repo_root: "origin/v4.29.0"
            harness_mod.active_release_branch = lambda _repo_root: "v4.29.0"
            harness_mod.main_sync_status = lambda _repo_root: harness_mod.RefSyncStatus(
                local_ref="v4.29.0",
                upstream_ref="origin/v4.29.0",
                local_oid="abc",
                upstream_oid="def",
                relationship="diverged",
            )
            with self.assertRaisesRegex(SystemExit, "refusing to use local `v4.29.0` as the worktree base"):
                harness_mod.resolve_create_worktree_base(layout, "v4.29.0")
        finally:
            for name, value in originals.items():
                setattr(harness_mod, name, value)

    def test_main_status_require_sync_returns_nonzero_when_unsynced(self) -> None:
        args = argparse.Namespace(require_sync=True)
        layout = SimpleNamespace(repo_root=Path("/tmp/repo"), package_root=Path("/tmp/worktree"))
        originals = {
            "detect_harness_layout": harness_mod.detect_harness_layout,
            "main_sync_status": harness_mod.main_sync_status,
            "current_branch_name": harness_mod.current_branch_name,
            "active_release_branch": harness_mod.active_release_branch,
            "branch_policy_path": harness_mod.branch_policy_path,
            "default_dev_branch": harness_mod.default_dev_branch,
            "checkout_branch_role": harness_mod.checkout_branch_role,
            "checkout_is_backport_only": harness_mod.checkout_is_backport_only,
        }
        try:
            harness_mod.detect_harness_layout = lambda _start=None: layout
            harness_mod.main_sync_status = lambda _repo_root: harness_mod.RefSyncStatus(
                local_ref="v4.29.0",
                upstream_ref="origin/v4.29.0",
                local_oid="abc",
                upstream_oid="def",
                relationship="behind",
            )
            harness_mod.current_branch_name = lambda _repo_root: "fix/demo"
            harness_mod.active_release_branch = lambda _repo_root: "v4.29.0"
            harness_mod.branch_policy_path = lambda _repo_root: Path("/tmp/worktree/branch-policy.json")
            harness_mod.default_dev_branch = lambda _repo_root: "v4.29.0"
            harness_mod.checkout_branch_role = lambda _repo_root: "default_dev"
            harness_mod.checkout_is_backport_only = lambda _repo_root: False
            self.assertEqual(harness_mod.command_main_status(args), 1)
        finally:
            for name, value in originals.items():
                setattr(harness_mod, name, value)

    def test_release_status_reports_backport_policy_fields(self) -> None:
        args = argparse.Namespace(require_sync=False)
        layout = SimpleNamespace(repo_root=Path("/tmp/repo"), package_root=Path("/tmp/worktree"))
        originals = {
            "detect_harness_layout": harness_mod.detect_harness_layout,
            "main_sync_status": harness_mod.main_sync_status,
            "current_branch_name": harness_mod.current_branch_name,
            "active_release_branch": harness_mod.active_release_branch,
            "branch_policy_path": harness_mod.branch_policy_path,
            "default_dev_branch": harness_mod.default_dev_branch,
            "checkout_branch_role": harness_mod.checkout_branch_role,
            "checkout_is_backport_only": harness_mod.checkout_is_backport_only,
        }
        out = io.StringIO()
        try:
            harness_mod.detect_harness_layout = lambda _start=None: layout
            harness_mod.main_sync_status = lambda _repo_root: harness_mod.RefSyncStatus(
                local_ref="v4.28.0",
                upstream_ref="origin/v4.28.0",
                local_oid="abc",
                upstream_oid="abc",
                relationship="in_sync",
            )
            harness_mod.current_branch_name = lambda _repo_root: "fix/backport"
            harness_mod.active_release_branch = lambda _repo_root: "v4.28.0"
            harness_mod.branch_policy_path = lambda _repo_root: Path("/tmp/worktree/branch-policy.json")
            harness_mod.default_dev_branch = lambda _repo_root: "v4.29.0"
            harness_mod.checkout_branch_role = lambda _repo_root: "backport"
            harness_mod.checkout_is_backport_only = lambda _repo_root: True

            with redirect_stdout(out):
                self.assertEqual(harness_mod.command_main_status(args), 0)
        finally:
            for name, value in originals.items():
                setattr(harness_mod, name, value)

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
        originals = {
            "detect_harness_layout": harness_mod.detect_harness_layout,
            "load_branch_policy": harness_mod.load_branch_policy,
        }
        out = io.StringIO()
        try:
            harness_mod.detect_harness_layout = lambda _start=None: layout
            harness_mod.load_branch_policy = lambda _checkout_root: SimpleNamespace(
                default_dev_branch="v4.29.0",
                required_backport_branches=("v4.28.0", "v4.27.0"),
            )
            with redirect_stdout(out):
                self.assertEqual(harness_mod.command_prepare_backports(args), 0)
        finally:
            for name, value in originals.items():
                setattr(harness_mod, name, value)

        output = out.getvalue()
        self.assertIn("default_dev_branch=v4.29.0", output)
        self.assertIn("required_backports=v4.28.0,v4.27.0", output)
        self.assertIn("Backport v4.28.0: pending", output)
        self.assertIn("Backport v4.27.0: pending", output)

    def test_prepare_backports_rejects_unknown_exemption_branch(self) -> None:
        args = argparse.Namespace(exempt=["v4.27.0=docs-only"])
        layout = SimpleNamespace(package_root=Path("/tmp/worktree"))
        originals = {
            "detect_harness_layout": harness_mod.detect_harness_layout,
            "load_branch_policy": harness_mod.load_branch_policy,
        }
        try:
            harness_mod.detect_harness_layout = lambda _start=None: layout
            harness_mod.load_branch_policy = lambda _checkout_root: SimpleNamespace(
                default_dev_branch="v4.29.0",
                required_backport_branches=("v4.28.0",),
            )
            with self.assertRaisesRegex(SystemExit, "unknown required backport branch"):
                harness_mod.command_prepare_backports(args)
        finally:
            for name, value in originals.items():
                setattr(harness_mod, name, value)

    def test_prepare_pr_prints_public_scaffold(self) -> None:
        args = argparse.Namespace(
            title=None,
            summary="This PR removes private mirror assumptions from the maintainer harness.",
            change=["Accept only the public upstream package repo"],
            source_branch=None,
            exempt=None,
        )
        layout = SimpleNamespace(package_root=Path("/tmp/worktree"))
        originals = {
            "detect_harness_layout": harness_mod.detect_harness_layout,
            "load_branch_policy": harness_mod.load_branch_policy,
            "require_checkout_role": harness_mod.require_checkout_role,
            "current_branch_name": harness_mod.current_branch_name,
            "current_commit_subject": harness_mod.current_commit_subject,
        }
        out = io.StringIO()
        try:
            harness_mod.detect_harness_layout = lambda _start=None: layout
            harness_mod.load_branch_policy = lambda _checkout_root: SimpleNamespace(
                default_dev_branch="v4.29.0",
                required_backport_branches=("v4.28.0",),
            )
            harness_mod.require_checkout_role = lambda *_args, **_kwargs: None
            harness_mod.current_branch_name = lambda _checkout_root: "fix/public-pr-scaffold"
            harness_mod.current_commit_subject = lambda _checkout_root: "fix: tighten public PR scaffolds"
            with redirect_stdout(out):
                self.assertEqual(harness_mod.command_prepare_pr(args), 0)
        finally:
            for name, value in originals.items():
                setattr(harness_mod, name, value)

        output = out.getvalue()
        self.assertIn("repository=leanprover/verso-blueprint", output)
        self.assertIn("base=v4.29.0", output)
        self.assertIn("head=fix/public-pr-scaffold", output)
        self.assertIn("draft=true", output)
        self.assertIn("## PR Submission Guardrails", output)
        self.assertIn("Use the PR title and body below as the public PR metadata", output)
        self.assertIn("Do not add generator or tool prefixes such as `[codex]`", output)
        self.assertIn("Do not add routine validation transcripts to the PR body", output)
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

    def test_prepare_backport_pr_prints_standardized_scaffold(self) -> None:
        args = argparse.Namespace(
            release="v4.28.0",
            all_required=False,
            main_pr=11,
            main_title="fix: require draft plans and base-aware retire",
            source_branch="fix/backport-discipline",
        )
        layout = SimpleNamespace(package_root=Path("/tmp/worktree"))
        originals = {
            "detect_harness_layout": harness_mod.detect_harness_layout,
            "load_branch_policy": harness_mod.load_branch_policy,
            "default_dev_branch": harness_mod.default_dev_branch,
            "require_checkout_role": harness_mod.require_checkout_role,
            "source_commit_series": harness_mod.source_commit_series,
        }
        out = io.StringIO()
        try:
            harness_mod.detect_harness_layout = lambda _start=None: layout
            harness_mod.load_branch_policy = lambda _checkout_root: SimpleNamespace(
                default_dev_branch="v4.29.0",
                required_backport_branches=("v4.28.0",),
            )
            harness_mod.default_dev_branch = lambda _checkout_root: "v4.29.0"
            harness_mod.require_checkout_role = lambda *_args, **_kwargs: None
            harness_mod.source_commit_series = lambda _repo_root, _source_branch: ["abc123", "def456"]
            with redirect_stdout(out):
                self.assertEqual(harness_mod.command_prepare_backport_pr(args), 0)
        finally:
            for name, value in originals.items():
                setattr(harness_mod, name, value)

        output = out.getvalue()
        self.assertIn("## Local Backport Plan", output)
        self.assertIn("repository=leanprover/verso-blueprint", output)
        self.assertIn("default_dev_branch=v4.29.0", output)
        self.assertIn("backport_release=v4.28.0", output)
        self.assertIn("paired_worktree=backport-v428-backport-discipline", output)
        self.assertIn("paired_branch=fix/backport-v428-backport-discipline", output)
        self.assertIn("paired_title=[backport v4.28.0] fix: require draft plans and base-aware retire", output)
        self.assertIn("source_commits=abc123,def456", output)
        self.assertIn("git cherry-pick -x abc123 def456", output)
        self.assertIn("## PR Submission Guardrails", output)
        self.assertIn("Use the PR title and body below as the public backport PR metadata", output)
        self.assertIn("Keep review-facing discussion on the default-development PR", output)
        self.assertIn("Do not add routine validation transcripts to the backport PR body", output)
        self.assertIn("## PR Title\n[backport v4.28.0] fix: require draft plans and base-aware retire", output)
        self.assertIn("## PR Body", output)
        self.assertIn("Primary review: #11", output)
        self.assertIn("Keep review comments on #11 unless this backport diverges materially.", output)

    def test_prepare_backport_pr_all_required_prints_multiple_scaffolds(self) -> None:
        args = argparse.Namespace(
            release=None,
            all_required=True,
            main_pr=11,
            main_title="fix: require draft plans and base-aware retire",
            source_branch="fix/backport-discipline",
        )
        layout = SimpleNamespace(package_root=Path("/tmp/worktree"))
        originals = {
            "detect_harness_layout": harness_mod.detect_harness_layout,
            "load_branch_policy": harness_mod.load_branch_policy,
            "default_dev_branch": harness_mod.default_dev_branch,
            "require_checkout_role": harness_mod.require_checkout_role,
            "source_commit_series": harness_mod.source_commit_series,
        }
        out = io.StringIO()
        try:
            harness_mod.detect_harness_layout = lambda _start=None: layout
            harness_mod.load_branch_policy = lambda _checkout_root: SimpleNamespace(
                default_dev_branch="v4.29.0",
                required_backport_branches=("v4.28.0", "v4.27.0"),
            )
            harness_mod.default_dev_branch = lambda _checkout_root: "v4.29.0"
            harness_mod.require_checkout_role = lambda *_args, **_kwargs: None
            harness_mod.source_commit_series = lambda _repo_root, _source_branch: ["abc123"]
            with redirect_stdout(out):
                self.assertEqual(harness_mod.command_prepare_backport_pr(args), 0)
        finally:
            for name, value in originals.items():
                setattr(harness_mod, name, value)

        output = out.getvalue()
        self.assertIn("backport_release=v4.28.0", output)
        self.assertIn("paired_branch=fix/backport-v428-backport-discipline", output)
        self.assertIn("backport_release=v4.27.0", output)
        self.assertIn("paired_branch=fix/backport-v427-backport-discipline", output)
        self.assertIn("\n---\n", output)

    def test_land_main_rejects_unsynced_main(self) -> None:
        args = argparse.Namespace(source="feat/demo", no_push=False, cleanup=False, keep_remote=False)
        layout = SimpleNamespace(repo_root=Path("/tmp/repo"), package_root=Path("/tmp/repo"), in_linked_worktree=False)
        originals = {
            "detect_harness_layout": harness_mod.detect_harness_layout,
            "current_branch_name": harness_mod.current_branch_name,
            "worktree_is_clean": harness_mod.worktree_is_clean,
            "main_sync_status": harness_mod.main_sync_status,
            "active_release_branch": harness_mod.active_release_branch,
        }
        try:
            harness_mod.detect_harness_layout = lambda _start=None: layout
            harness_mod.current_branch_name = lambda _repo_root: "v4.29.0"
            harness_mod.worktree_is_clean = lambda _path: True
            harness_mod.main_sync_status = lambda _repo_root: harness_mod.RefSyncStatus(
                local_ref="v4.29.0",
                upstream_ref="origin/v4.29.0",
                local_oid="abc",
                upstream_oid="def",
                relationship="behind",
            )
            harness_mod.active_release_branch = lambda _repo_root: "v4.29.0"
            with self.assertRaisesRegex(SystemExit, "sync `v4.29.0` before landing"):
                harness_mod.command_land_main(args)
        finally:
            for name, value in originals.items():
                setattr(harness_mod, name, value)

    def test_land_main_fast_forwards_and_pushes(self) -> None:
        args = argparse.Namespace(source="feat/demo", no_push=False, cleanup=False, keep_remote=False)
        layout = SimpleNamespace(repo_root=Path("/tmp/repo"), package_root=Path("/tmp/repo"), in_linked_worktree=False)
        originals = {
            "detect_harness_layout": harness_mod.detect_harness_layout,
            "current_branch_name": harness_mod.current_branch_name,
            "worktree_is_clean": harness_mod.worktree_is_clean,
            "main_sync_status": harness_mod.main_sync_status,
            "ref_oid": harness_mod.ref_oid,
            "is_ancestor": harness_mod.is_ancestor,
            "preferred_main_ref": harness_mod.preferred_main_ref,
            "active_release_branch": harness_mod.active_release_branch,
            "run": harness_mod.run,
        }
        commands: list[list[str]] = []
        try:
            harness_mod.detect_harness_layout = lambda _start=None: layout
            harness_mod.current_branch_name = lambda _repo_root: "v4.29.0"
            harness_mod.worktree_is_clean = lambda _path: True
            harness_mod.main_sync_status = lambda _repo_root: harness_mod.RefSyncStatus(
                local_ref="v4.29.0",
                upstream_ref="origin/v4.29.0",
                local_oid="abc",
                upstream_oid="abc",
                relationship="in_sync",
            )
            harness_mod.ref_oid = lambda _repo_root, ref: "deadbeef" if ref == "feat/demo" else None
            harness_mod.is_ancestor = lambda _repo_root, ancestor, descendant: (ancestor, descendant) == ("v4.29.0", "feat/demo")
            harness_mod.preferred_main_ref = lambda _repo_root: "origin/v4.29.0"
            harness_mod.active_release_branch = lambda _repo_root: "v4.29.0"
            harness_mod.run = lambda command, *, cwd: commands.append(command)

            self.assertEqual(harness_mod.command_land_main(args), 0)
        finally:
            for name, value in originals.items():
                setattr(harness_mod, name, value)

        self.assertEqual(commands, [["git", "merge", "--ff-only", "feat/demo"], ["git", "push", "origin", "v4.29.0"]])

    def test_land_main_cleanup_removes_branch_worktree_and_remote(self) -> None:
        args = argparse.Namespace(source="feat/demo", no_push=False, cleanup=True, keep_remote=False)
        layout = SimpleNamespace(repo_root=Path("/tmp/repo"), package_root=Path("/tmp/repo"), in_linked_worktree=False)
        demo_worktree = GitWorktree(
            name="demo",
            path=Path("/tmp/repo/.worktrees/demo"),
            head="abc123",
            branch="feat/demo",
            root_checkout=False,
        )
        originals = {
            "detect_harness_layout": harness_mod.detect_harness_layout,
            "current_branch_name": harness_mod.current_branch_name,
            "worktree_is_clean": harness_mod.worktree_is_clean,
            "main_sync_status": harness_mod.main_sync_status,
            "ref_oid": harness_mod.ref_oid,
            "is_ancestor": harness_mod.is_ancestor,
            "preferred_main_ref": harness_mod.preferred_main_ref,
            "active_release_branch": harness_mod.active_release_branch,
            "run": harness_mod.run,
            "branch_worktrees": harness_mod.branch_worktrees,
            "local_branch_ref": harness_mod.local_branch_ref,
            "origin_branch_exists": harness_mod.origin_branch_exists,
        }
        commands: list[list[str]] = []
        try:
            harness_mod.detect_harness_layout = lambda _start=None: layout
            harness_mod.current_branch_name = lambda _repo_root: "v4.29.0"
            harness_mod.worktree_is_clean = lambda _path: True
            harness_mod.main_sync_status = lambda _repo_root: harness_mod.RefSyncStatus(
                local_ref="v4.29.0",
                upstream_ref="origin/v4.29.0",
                local_oid="abc",
                upstream_oid="abc",
                relationship="in_sync",
            )
            harness_mod.ref_oid = lambda _repo_root, ref: "deadbeef" if ref in {"feat/demo", "refs/heads/feat/demo", "refs/remotes/origin/feat/demo"} else None
            harness_mod.is_ancestor = lambda _repo_root, ancestor, descendant: (ancestor, descendant) == ("v4.29.0", "feat/demo")
            harness_mod.preferred_main_ref = lambda _repo_root: "origin/v4.29.0"
            harness_mod.active_release_branch = lambda _repo_root: "v4.29.0"
            harness_mod.run = lambda command, *, cwd: commands.append(command)
            harness_mod.branch_worktrees = lambda _repo_root, branch: [demo_worktree] if branch == "feat/demo" else []
            harness_mod.local_branch_ref = lambda _repo_root, branch: branch if branch == "feat/demo" else None
            harness_mod.origin_branch_exists = lambda _repo_root, branch: branch == "feat/demo"

            self.assertEqual(harness_mod.command_land_main(args), 0)
        finally:
            for name, value in originals.items():
                setattr(harness_mod, name, value)

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

    def test_generate_keeps_example_alias(self) -> None:
        parser = reference_harness_mod.build_parser()
        args = parser.parse_args(["generate", "--example", "noperthedron"])
        self.assertEqual(args.project, ["noperthedron"])

    def test_reference_generate_rejects_unsafe_root_main_without_override(self) -> None:
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
        originals = {
            "detect_harness_layout": reference_harness_mod.detect_harness_layout,
            "require_safe_root_main": reference_harness_mod.require_safe_root_main,
        }
        seen: dict[str, object] = {}
        try:
            reference_harness_mod.detect_harness_layout = lambda _start=None: layout

            def fake_require(_layout, *, allow_unsafe, command_name):
                seen["layout"] = _layout
                seen["allow_unsafe"] = allow_unsafe
                seen["command_name"] = command_name
                raise SystemExit("blocked")

            reference_harness_mod.require_safe_root_main = fake_require

            with self.assertRaisesRegex(SystemExit, "blocked"):
                reference_harness_mod.command_generate(args)
        finally:
            for name, value in originals.items():
                setattr(reference_harness_mod, name, value)

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
        originals = {
            "detect_harness_layout": reference_harness_mod.detect_harness_layout,
            "require_safe_root_main": reference_harness_mod.require_safe_root_main,
            "resolve_output_root": reference_harness_mod.resolve_output_root,
            "resolve_manifest_path": reference_harness_mod.resolve_manifest_path,
            "load_project_catalog": reference_harness_mod.load_project_catalog,
            "select_release_projects": reference_harness_mod.select_release_projects,
            "active_release_branch": reference_harness_mod.active_release_branch,
        }
        try:
            reference_harness_mod.detect_harness_layout = lambda _start=None: layout
            reference_harness_mod.require_safe_root_main = lambda _layout, *, allow_unsafe, command_name: None
            reference_harness_mod.resolve_output_root = lambda _path_text, _start=None: Path("/tmp/out")
            reference_harness_mod.resolve_manifest_path = lambda _path_text, _package_root: Path("/tmp/projects.json")
            reference_harness_mod.load_project_catalog = lambda _manifest_path: SimpleNamespace(projects=(), release_targets=())
            reference_harness_mod.select_release_projects = lambda _catalog, *, release, project_ids, package_root: ("v4.28.0", [])
            reference_harness_mod.active_release_branch = lambda _package_root: "v4.29.0"

            with self.assertRaisesRegex(SystemExit, "Create or switch to a `v4.28.0` checkout first"):
                reference_harness_mod.command_generate(args)
        finally:
            for name, value in originals.items():
                setattr(reference_harness_mod, name, value)

    def test_bump_toolchain_uses_helper(self) -> None:
        args = argparse.Namespace(toolchain="4.29.0", verso_ref=None, skip_validation=False)
        layout = SimpleNamespace(package_root=Path("/tmp/package"))
        originals = {
            "detect_harness_layout": harness_mod.detect_harness_layout,
            "bump_toolchain_checkout": harness_mod.bump_toolchain_checkout,
            "require_checkout_role": harness_mod.require_checkout_role,
        }
        seen: dict[str, object] = {}
        try:
            harness_mod.detect_harness_layout = lambda _start=None: layout
            harness_mod.require_checkout_role = lambda checkout_root, *, required_role, operation: seen.update(
                {
                    "role_checkout_root": checkout_root,
                    "required_role": required_role,
                    "operation": operation,
                }
            )

            def fake_bump(package_root, toolchain, *, verso_ref, validate):
                seen["package_root"] = package_root
                seen["toolchain"] = toolchain
                seen["verso_ref"] = verso_ref
                seen["validate"] = validate
                return SimpleNamespace(
                    lean_ref="v4.29.0",
                    toolchain_spec="leanprover/lean4:v4.29.0",
                    verso_ref="v4.29.0",
                    verso_tag_oid="deadbeef",
                )

            harness_mod.bump_toolchain_checkout = fake_bump

            self.assertEqual(harness_mod.command_bump_toolchain(args), 0)
        finally:
            for name, value in originals.items():
                setattr(harness_mod, name, value)

        self.assertEqual(seen["package_root"], layout.package_root)
        self.assertEqual(seen["role_checkout_root"], layout.package_root)
        self.assertEqual(seen["required_role"], "default_dev")
        self.assertEqual(seen["operation"], "bump-toolchain")
        self.assertEqual(seen["toolchain"], "4.29.0")
        self.assertEqual(seen["verso_ref"], None)
        self.assertTrue(seen["validate"])

    def test_paths_prints_current_release_project_sites_by_default(self) -> None:
        args = argparse.Namespace(all_projects=False)
        layout = SimpleNamespace(
            repo_root=Path("/tmp/repo"),
            package_root=Path("/tmp/package"),
            worktree_name=None,
            artifact_root=Path("/tmp/package/_out"),
            reference_output_root=Path("/tmp/package/_out/reference-blueprints"),
            test_blueprint_output_root=Path("/tmp/package/_out/test-blueprints"),
            reference_project_cache_root=Path("/tmp/repo/.worktrees/_reference-blueprints/cache"),
            reference_project_checkout_root=Path("/tmp/repo/.worktrees/_reference-blueprints/by-worktree/v4.29.0"),
            reference_project_edit_root=Path("/tmp/repo/.worktrees/_reference-blueprints/edit/v4.29.0"),
        )
        release = HarnessReleaseTarget(
            release_id="v4.29.0",
            toolchain="v4.29.0",
            verso_ref="v4.29.0",
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
            generate_command=("lake", "exe", "blueprint-gen"),
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
            targets=(HarnessProjectTarget(release="v4.29.0", ref="abc123"),),
        )
        old_project = HarnessProject(
            project_id="old-example",
            source_kind="git_checkout",
            project_root=".",
            build_target=None,
            generator=None,
            repository="https://github.com/example/old.git",
            ref=None,
            build_command=("lake", "build"),
            generate_command=("lake", "exe", "blueprint-gen"),
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
        originals = {
            "detect_harness_layout": harness_mod.detect_harness_layout,
            "resolve_manifest_path": harness_mod.resolve_manifest_path,
            "load_project_catalog_manifest": harness_mod.load_project_catalog_manifest,
            "resolve_release_target": harness_mod.resolve_release_target,
            "resolve_projects_for_release": harness_mod.resolve_projects_for_release,
            "active_release_branch": harness_mod.active_release_branch,
            "preferred_main_ref": harness_mod.preferred_main_ref,
            "canonical_test_blueprint_site_dir": harness_mod.canonical_test_blueprint_site_dir,
            "canonical_example_site_dir": harness_mod.canonical_example_site_dir,
        }
        try:
            harness_mod.detect_harness_layout = lambda _start=None: layout
            harness_mod.resolve_manifest_path = lambda _path_text, _package_root: Path("/tmp/projects.json")
            harness_mod.load_project_catalog_manifest = lambda _manifest_path: catalog
            harness_mod.resolve_release_target = lambda _catalog, _release, _package_root: release
            harness_mod.resolve_projects_for_release = lambda _catalog, _release, _selected_ids: [selected_project]
            harness_mod.active_release_branch = lambda _repo_root: "v4.29.0"
            harness_mod.preferred_main_ref = lambda _repo_root: "origin/v4.29.0"
            harness_mod.canonical_test_blueprint_site_dir = (
                lambda _name, _start=None: Path("/tmp/package/_out/test-blueprints/preview_runtime_showcase/html-multi")
            )
            harness_mod.canonical_example_site_dir = (
                lambda project_id, _start=None: Path(f"/tmp/package/_out/reference-blueprints/{project_id}/html-multi")
            )
            buffer = io.StringIO()
            with redirect_stdout(buffer):
                self.assertEqual(harness_mod.command_paths(args), 0)
        finally:
            for name, value in originals.items():
                setattr(harness_mod, name, value)

        output = buffer.getvalue()
        self.assertIn("selected_release_target=v4.29.0", output)
        self.assertIn("project_path_scope=selected_release", output)
        self.assertIn("noperthedron_site=/tmp/package/_out/reference-blueprints/noperthedron/html-multi", output)
        self.assertNotIn("old-example_site=", output)

    def test_require_branch_role_parses_requested_role(self) -> None:
        parser = build_parser()
        args = parser.parse_args(["require-branch-role", "default_dev"])
        self.assertEqual(args.role, "default_dev")

    def test_require_branch_role_returns_nonzero_on_mismatch(self) -> None:
        args = argparse.Namespace(role="default_dev")
        layout = SimpleNamespace(repo_root=Path("/tmp/repo"), package_root=Path("/tmp/worktree"))
        originals = {
            "detect_harness_layout": harness_mod.detect_harness_layout,
            "print_branch_policy_status": harness_mod.print_branch_policy_status,
            "checkout_branch_role": harness_mod.checkout_branch_role,
            "active_release_branch": harness_mod.active_release_branch,
            "default_dev_branch": harness_mod.default_dev_branch,
        }
        out = io.StringIO()
        err = io.StringIO()
        try:
            harness_mod.detect_harness_layout = lambda _start=None: layout
            harness_mod.print_branch_policy_status = lambda _layout: None
            harness_mod.checkout_branch_role = lambda _checkout_root: "backport"
            harness_mod.active_release_branch = lambda _checkout_root: "v4.28.0"
            harness_mod.default_dev_branch = lambda _checkout_root: "v4.29.0"
            with redirect_stdout(out), redirect_stderr(err):
                self.assertEqual(harness_mod.command_require_branch_role(args), 1)
        finally:
            for name, value in originals.items():
                setattr(harness_mod, name, value)

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
            generate_command=("lake", "exe", "blueprint-gen"),
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
        )
        args = argparse.Namespace(manifest=None, project="noperthedron", branch="wip/noperthedron", base="origin/main")
        layout = SimpleNamespace(package_root=Path("/tmp/package"), reference_project_edit_root=Path("/tmp/edit"))
        originals = {
            "detect_harness_layout": reference_harness_mod.detect_harness_layout,
            "resolve_manifest_path": reference_harness_mod.resolve_manifest_path,
            "load_project_catalog": reference_harness_mod.load_project_catalog,
            "prepare_reference_edit_checkout": reference_harness_mod.prepare_reference_edit_checkout,
        }
        seen: dict[str, object] = {}
        try:
            reference_harness_mod.detect_harness_layout = lambda _start=None: layout
            reference_harness_mod.resolve_manifest_path = lambda _path_text, _package_root: Path("/tmp/projects.json")
            reference_harness_mod.load_project_catalog = lambda _manifest_path: SimpleNamespace(projects=(project,))

            def fake_prepare(_layout, _project, *, branch, base_ref):
                seen["layout"] = _layout
                seen["project"] = _project
                seen["branch"] = branch
                seen["base_ref"] = base_ref
                return Path("/tmp/edit/noperthedron"), branch or "wip/noperthedron", base_ref or "origin/main"

            reference_harness_mod.prepare_reference_edit_checkout = fake_prepare

            self.assertEqual(reference_harness_mod.command_reference_edit(args), 0)
        finally:
            for name, value in originals.items():
                setattr(reference_harness_mod, name, value)

        self.assertEqual(seen["layout"], layout)
        self.assertEqual(seen["project"], project)
        self.assertEqual(seen["branch"], "wip/noperthedron")
        self.assertEqual(seen["base_ref"], "origin/main")

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
            generate_command=("lake", "exe", "blueprint-gen"),
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
        )
        args = argparse.Namespace(
            manifest=None,
            project=["noperthedron"],
            ref="v1.2.3",
            branch="chore/bump-verso-blueprint-v1-2-3",
            base="origin/main",
            skip_build=False,
            generate=True,
            commit=False,
            push=False,
            commit_message=None,
        )
        layout = SimpleNamespace(package_root=Path("/tmp/package"), artifact_root=Path("/tmp/out"))
        originals = {
            "detect_harness_layout": reference_harness_mod.detect_harness_layout,
            "resolve_manifest_path": reference_harness_mod.resolve_manifest_path,
            "load_project_catalog": reference_harness_mod.load_project_catalog,
            "bump_reference_project": reference_harness_mod.bump_reference_project,
        }
        seen: dict[str, object] = {}
        try:
            reference_harness_mod.detect_harness_layout = lambda _start=None: layout
            reference_harness_mod.resolve_manifest_path = lambda _path_text, _package_root: Path("/tmp/projects.json")
            reference_harness_mod.load_project_catalog = lambda _manifest_path: SimpleNamespace(projects=(project,))
            seen["selected_values"] = ["noperthedron"]

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
                    base_ref=base_ref,
                    previous_ref="old-ref",
                    changed=True,
                    committed=False,
                    pushed=False,
                    output_dir=output_root / "noperthedron",
                )

            reference_harness_mod.bump_reference_project = fake_bump

            self.assertEqual(reference_harness_mod.command_reference_bump_blueprint(args), 0)
        finally:
            for name, value in originals.items():
                setattr(reference_harness_mod, name, value)

        self.assertEqual(seen["layout"], layout)
        self.assertEqual(seen["project"], project)
        self.assertEqual(seen["selected_values"], ["noperthedron"])
        self.assertEqual(seen["ref"], "v1.2.3")
        self.assertEqual(seen["branch"], "chore/bump-verso-blueprint-v1-2-3")
        self.assertEqual(seen["base_ref"], "origin/main")
        self.assertTrue(seen["build_project"])
        self.assertTrue(seen["generate_site"])
        self.assertEqual(seen["output_root"], Path("/tmp/out/reference-blueprints-edit"))
        self.assertFalse(seen["commit"])
        self.assertFalse(seen["push"])

    def test_worktree_retire_supports_detached_merged_worktree(self) -> None:
        args = argparse.Namespace(name="reference-edit", dry_run=False)
        layout = SimpleNamespace(
            repo_root=Path("/tmp/repo"),
            package_root=Path("/tmp/package"),
            worktree_name=None,
            reference_project_cache_root=Path("/tmp/cache"),
            reference_project_root=Path("/tmp/reference-root"),
        )
        detached = GitWorktree(
            name="reference-edit",
            path=Path("/tmp/repo/.worktrees/reference-edit"),
            head="abc123",
            branch=None,
            root_checkout=False,
        )
        originals = {
            "detect_harness_layout": harness_mod.detect_harness_layout,
            "worktree_record_map": harness_mod.worktree_record_map,
            "git_worktree_map": harness_mod.git_worktree_map,
            "preferred_worktree_base_ref": harness_mod.preferred_worktree_base_ref,
            "ref_merged_into_worktree_base": harness_mod.ref_merged_into_worktree_base,
            "worktree_is_clean": harness_mod.worktree_is_clean,
            "local_release_ref": harness_mod.local_release_ref,
            "run": harness_mod.run,
            "resolve_manifest_path": harness_mod.resolve_manifest_path,
            "load_project_catalog": harness_mod.load_project_catalog,
            "git_worktrees": harness_mod.git_worktrees,
            "reference_prune_plan": harness_mod.reference_prune_plan,
        }
        commands: list[list[str]] = []
        try:
            harness_mod.detect_harness_layout = lambda _start=None: layout
            harness_mod.worktree_record_map = lambda _repo_root: (
                {
                    "reference-edit": SimpleNamespace(
                        name="reference-edit",
                        locked=False,
                    )
                },
                Path("/tmp/repo/.worktrees/registry.json"),
            )
            harness_mod.git_worktree_map = lambda _repo_root: {"reference-edit": detached}
            harness_mod.preferred_worktree_base_ref = lambda _path: "origin/v4.29.0"
            harness_mod.ref_merged_into_worktree_base = lambda _repo_root, ref, _path: ref == "abc123"
            harness_mod.worktree_is_clean = lambda _path: True
            harness_mod.local_release_ref = lambda _repo_root: "v4.29.0"
            harness_mod.run = lambda command, *, cwd: commands.append(command)
            harness_mod.resolve_manifest_path = lambda _path_text, _package_root: Path("/tmp/projects.json")
            harness_mod.load_project_catalog = lambda _manifest_path: []
            harness_mod.git_worktrees = lambda _repo_root: []
            harness_mod.reference_prune_plan = lambda *_args, **_kwargs: []

            self.assertEqual(harness_mod.command_worktree_retire(args), 0)
        finally:
            for name, value in originals.items():
                setattr(harness_mod, name, value)

        self.assertEqual(commands, [["git", "worktree", "remove", str(detached.path)]])

    def test_worktree_retire_accepts_backport_branch_merged_into_its_release_base(self) -> None:
        args = argparse.Namespace(name="backport-demo", dry_run=False)
        layout = SimpleNamespace(
            repo_root=Path("/tmp/repo"),
            package_root=Path("/tmp/package"),
            worktree_name=None,
            reference_project_cache_root=Path("/tmp/cache"),
            reference_project_root=Path("/tmp/reference-root"),
        )
        backport = GitWorktree(
            name="backport-demo",
            path=Path("/tmp/repo/.worktrees/backport-demo"),
            head="def456",
            branch="fix/backport-demo",
            root_checkout=False,
        )
        originals = {
            "detect_harness_layout": harness_mod.detect_harness_layout,
            "worktree_record_map": harness_mod.worktree_record_map,
            "git_worktree_map": harness_mod.git_worktree_map,
            "preferred_worktree_base_ref": harness_mod.preferred_worktree_base_ref,
            "ref_merged_into_worktree_base": harness_mod.ref_merged_into_worktree_base,
            "worktree_is_clean": harness_mod.worktree_is_clean,
            "local_release_ref": harness_mod.local_release_ref,
            "run": harness_mod.run,
            "resolve_manifest_path": harness_mod.resolve_manifest_path,
            "load_project_catalog": harness_mod.load_project_catalog,
            "git_worktrees": harness_mod.git_worktrees,
            "reference_prune_plan": harness_mod.reference_prune_plan,
        }
        commands: list[list[str]] = []
        try:
            harness_mod.detect_harness_layout = lambda _start=None: layout
            harness_mod.worktree_record_map = lambda _repo_root: (
                {
                    "backport-demo": SimpleNamespace(
                        name="backport-demo",
                        locked=False,
                    )
                },
                Path("/tmp/repo/.worktrees/registry.json"),
            )
            harness_mod.git_worktree_map = lambda _repo_root: {"backport-demo": backport}
            harness_mod.preferred_worktree_base_ref = lambda _path: "origin/v4.28.0"
            harness_mod.ref_merged_into_worktree_base = lambda _repo_root, ref, _path: ref == "fix/backport-demo"
            harness_mod.worktree_is_clean = lambda _path: True
            harness_mod.local_release_ref = lambda _repo_root: "v4.29.0"
            harness_mod.run = lambda command, *, cwd: commands.append(command)
            harness_mod.resolve_manifest_path = lambda _path_text, _package_root: Path("/tmp/projects.json")
            harness_mod.load_project_catalog = lambda _manifest_path: []
            harness_mod.git_worktrees = lambda _repo_root: []
            harness_mod.reference_prune_plan = lambda *_args, **_kwargs: []

            self.assertEqual(harness_mod.command_worktree_retire(args), 0)
        finally:
            for name, value in originals.items():
                setattr(harness_mod, name, value)

        self.assertEqual(
            commands,
            [
                ["git", "worktree", "remove", str(backport.path)],
                ["git", "branch", "-d", backport.branch],
            ],
        )

    def test_worktree_retire_rejects_locked_worktree(self) -> None:
        args = argparse.Namespace(name="demo", dry_run=False)
        layout = SimpleNamespace(
            repo_root=Path("/tmp/repo"),
            package_root=Path("/tmp/package"),
            worktree_name=None,
        )
        originals = {
            "detect_harness_layout": harness_mod.detect_harness_layout,
            "worktree_record_map": harness_mod.worktree_record_map,
            "git_worktree_map": harness_mod.git_worktree_map,
            "local_release_ref": harness_mod.local_release_ref,
        }
        try:
            harness_mod.detect_harness_layout = lambda _start=None: layout
            harness_mod.local_release_ref = lambda _repo_root: "v4.29.0"
            harness_mod.worktree_record_map = lambda _repo_root: (
                {
                    "demo": SimpleNamespace(
                        name="demo",
                        locked=True,
                    )
                },
                Path("/tmp/repo/.worktrees/registry.json"),
            )
            harness_mod.git_worktree_map = lambda _repo_root: {
                "demo": GitWorktree(
                    name="demo",
                    path=Path("/tmp/repo/.worktrees/demo"),
                    head="abc123",
                    branch="feat/demo",
                    root_checkout=False,
                )
            }

            with self.assertRaisesRegex(SystemExit, "is locked; unlock it before retiring"):
                harness_mod.command_worktree_retire(args)
        finally:
            for name, value in originals.items():
                setattr(harness_mod, name, value)

    def test_generate_projects_does_not_auto_sync_root_lake(self) -> None:
        project = HarnessProject(
            project_id="demo",
            source_kind="in_repo_example",
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

        original_ensure = reference_harness_mod.ensure_prebuilt_executable
        original_render = reference_harness_mod.render_in_repo_projects
        try:
            reference_harness_mod.ensure_prebuilt_executable = lambda _package_root, _exe_name: Path("/tmp/demo")
            reference_harness_mod.render_in_repo_projects = lambda _package_root, _output_root, _projects, _serial: None

            generate_projects(
                layout,
                Path("/tmp/out"),
                [project],
                skip_build=False,
                serial=False,
                allow_local_build=False,
            )
        finally:
            reference_harness_mod.ensure_prebuilt_executable = original_ensure
            reference_harness_mod.render_in_repo_projects = original_render

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
        originals = {
            "detect_harness_layout": reference_harness_mod.detect_harness_layout,
            "resolve_output_root": reference_harness_mod.resolve_output_root,
            "resolve_manifest_path": reference_harness_mod.resolve_manifest_path,
            "load_project_catalog": reference_harness_mod.load_project_catalog,
            "select_release_projects": reference_harness_mod.select_release_projects,
            "require_checkout_release": reference_harness_mod.require_checkout_release,
            "should_use_local_build": reference_harness_mod.should_use_local_build,
            "find_prebuilt_lean_test_artifact": reference_harness_mod.find_prebuilt_lean_test_artifact,
            "run_capturing_failure": reference_harness_mod.run_capturing_failure,
            "generate_projects": reference_harness_mod.generate_projects,
        }
        try:
            reference_harness_mod.detect_harness_layout = lambda _start=None: layout
            reference_harness_mod.resolve_output_root = lambda _path_text, _start=None: Path("/tmp/out")
            reference_harness_mod.resolve_manifest_path = lambda _path_text, _package_root: Path("/tmp/projects.json")
            reference_harness_mod.load_project_catalog = lambda _manifest_path: SimpleNamespace(projects=(), release_targets=())
            reference_harness_mod.select_release_projects = lambda _catalog, *, release, project_ids, package_root: ("v4.29.0", [])
            reference_harness_mod.require_checkout_release = lambda _layout, release_id, *, command_name: None
            reference_harness_mod.should_use_local_build = lambda _layout, _allow_local_build: False
            reference_harness_mod.find_prebuilt_lean_test_artifact = lambda _package_root: Path("/tmp/VersoBlueprintTests.olean")
            reference_harness_mod.run_capturing_failure = lambda _step, _command, cwd: None
            reference_harness_mod.generate_projects = lambda *_args, **_kwargs: None

            self.assertEqual(reference_harness_mod.command_validate(args), 0)
        finally:
            for name, value in originals.items():
                setattr(reference_harness_mod, name, value)

    def test_reference_validate_rejects_unsafe_root_main_without_override(self) -> None:
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
        originals = {
            "detect_harness_layout": reference_harness_mod.detect_harness_layout,
            "require_safe_root_main": reference_harness_mod.require_safe_root_main,
        }
        seen: dict[str, object] = {}
        try:
            reference_harness_mod.detect_harness_layout = lambda _start=None: layout

            def fake_require(_layout, *, allow_unsafe, command_name):
                seen["layout"] = _layout
                seen["allow_unsafe"] = allow_unsafe
                seen["command_name"] = command_name
                raise SystemExit("blocked")

            reference_harness_mod.require_safe_root_main = fake_require

            with self.assertRaisesRegex(SystemExit, "blocked"):
                reference_harness_mod.command_validate(args)
        finally:
            for name, value in originals.items():
                setattr(reference_harness_mod, name, value)

        self.assertEqual(seen["layout"], layout)
        self.assertFalse(seen["allow_unsafe"])
        self.assertEqual(seen["command_name"], "validate")

    def test_reference_sync_allows_unsafe_root_main_with_override(self) -> None:
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
            reference_project_cache_root=Path("/tmp/cache"),
            reference_project_checkout_root=Path("/tmp/checkouts"),
        )
        originals = {
            "detect_harness_layout": reference_harness_mod.detect_harness_layout,
            "require_safe_root_main": reference_harness_mod.require_safe_root_main,
            "resolve_manifest_path": reference_harness_mod.resolve_manifest_path,
            "load_project_catalog": reference_harness_mod.load_project_catalog,
            "select_release_projects": reference_harness_mod.select_release_projects,
            "require_checkout_release": reference_harness_mod.require_checkout_release,
            "sync_reference_blueprints": reference_harness_mod.sync_reference_blueprints,
        }
        seen: dict[str, object] = {}
        try:
            reference_harness_mod.detect_harness_layout = lambda _start=None: layout

            def fake_require(_layout, *, allow_unsafe, command_name):
                seen["layout"] = _layout
                seen["allow_unsafe"] = allow_unsafe
                seen["command_name"] = command_name

            reference_harness_mod.require_safe_root_main = fake_require
            reference_harness_mod.resolve_manifest_path = lambda _path_text, _package_root: Path("/tmp/projects.json")
            reference_harness_mod.load_project_catalog = lambda _manifest_path: SimpleNamespace(projects=(), release_targets=())
            reference_harness_mod.select_release_projects = lambda _catalog, *, release, project_ids, package_root: ("v4.29.0", [])
            reference_harness_mod.require_checkout_release = lambda _layout, release_id, *, command_name: None
            reference_harness_mod.sync_reference_blueprints = lambda *_args, **_kwargs: None

            self.assertEqual(reference_harness_mod.command_reference_sync(args), 0)
        finally:
            for name, value in originals.items():
                setattr(reference_harness_mod, name, value)

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
            generate_command=("lake", "exe", "blueprint-gen"),
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
        )
        args = argparse.Namespace(manifest=None, project=None, release=None)
        layout = SimpleNamespace(package_root=Path("/tmp/package"), repo_root=Path("/tmp/repo"))
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
        originals = {
            "detect_harness_layout": reference_harness_mod.detect_harness_layout,
            "resolve_manifest_path": reference_harness_mod.resolve_manifest_path,
            "load_project_catalog": reference_harness_mod.load_project_catalog,
            "select_release_projects": reference_harness_mod.select_release_projects,
            "main_sync_status": reference_harness_mod.main_sync_status,
            "collect_reference_project_status": reference_harness_mod.collect_reference_project_status,
            "active_release_branch": reference_harness_mod.active_release_branch,
        }
        out = io.StringIO()
        try:
            reference_harness_mod.detect_harness_layout = lambda _start=None: layout
            reference_harness_mod.resolve_manifest_path = lambda _path_text, _package_root: Path("/tmp/projects.json")
            reference_harness_mod.load_project_catalog = lambda _manifest_path: SimpleNamespace(projects=(project,), release_targets=())
            reference_harness_mod.select_release_projects = lambda _catalog, *, release, project_ids, package_root: ("v4.29.0", [project])
            reference_harness_mod.main_sync_status = lambda _repo_root: harness_mod.RefSyncStatus(
                local_ref="v4.29.0",
                upstream_ref="origin/v4.29.0",
                local_oid="111",
                upstream_oid="111",
                relationship="in_sync",
            )
            reference_harness_mod.active_release_branch = lambda _repo_root: "v4.29.0"
            reference_harness_mod.collect_reference_project_status = lambda _layout, _project: status

            with redirect_stdout(out):
                self.assertEqual(reference_harness_mod.command_status(args), 0)
        finally:
            for name, value in originals.items():
                setattr(reference_harness_mod, name, value)

        output = out.getvalue()
        self.assertIn("project_manifest=/tmp/projects.json", output)
        self.assertIn("release_relationship=in_sync", output)
        self.assertIn("verso_blueprint_ref=v4.29.0", output)
        self.assertIn("noperthedron\tsource=git:https://github.com/example/noperthedron.git@abc123", output)
        self.assertIn("catalog_status=behind", output)
        self.assertIn("catalog_behind=12", output)
        self.assertIn("blueprint_pin_source=lake-manifest.json", output)
        self.assertIn("blueprint_resolved_ref=deadbeef", output)
        self.assertIn("blueprint_status=behind", output)

    def test_reference_release_status_summarizes_and_filters_outdated_targets(self) -> None:
        template = HarnessProject(
            project_id="project-template",
            source_kind="in_repo_example",
            project_root="project_template",
            build_target=None,
            generator=None,
            repository=None,
            ref=None,
            build_command=("lake", "build"),
            generate_command=("lake", "exe", "blueprint-gen"),
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
            generate_command=("lake", "exe", "blueprint-gen"),
            site_subdir="html-multi",
            panel_regression_script=None,
            browser_tests_path=None,
            description=None,
            targets=(HarnessProjectTarget(release="v4.29.0", ref="deadbeef"),),
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
            generate_command=("lake", "exe", "blueprint-gen"),
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
        originals = {
            "detect_harness_layout": reference_harness_mod.detect_harness_layout,
            "resolve_manifest_path": reference_harness_mod.resolve_manifest_path,
            "load_project_catalog": reference_harness_mod.load_project_catalog,
            "collect_reference_project_status": reference_harness_mod.collect_reference_project_status,
        }
        out = io.StringIO()
        try:
            reference_harness_mod.detect_harness_layout = lambda _start=None: layout
            reference_harness_mod.resolve_manifest_path = lambda _path_text, _package_root: Path("/tmp/projects.json")
            reference_harness_mod.load_project_catalog = lambda _manifest_path: catalog

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
                    skipped="in_repo_example" if project.in_repo_example else None,
                )

            reference_harness_mod.collect_reference_project_status = fake_collect

            with redirect_stdout(out):
                self.assertEqual(reference_harness_mod.command_release_status(args), 0)
        finally:
            for name, value in originals.items():
                setattr(reference_harness_mod, name, value)

        output = out.getvalue()
        self.assertIn("project_manifest=/tmp/projects.json", output)
        self.assertIn("release=v4.29.0", output)
        self.assertIn("outdated_projects=1", output)
        self.assertIn("downstream_pin_drift=0", output)
        self.assertIn("project=noperthedron", output)
        self.assertNotIn("project=spherepackingblueprint", output)


if __name__ == "__main__":
    unittest.main()
