from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from scripts.blueprint_harness_worktrees import (
    METADATA_DIRNAME,
    ROOT_WORKTREE_NAME,
    WorktreeRecord,
    collect_worktree_facts,
    metadata_path,
    parse_git_worktree_porcelain,
    resolve_worktree_name,
    sync_worktree_registry,
)


class BlueprintHarnessWorktreesTests(unittest.TestCase):
    def test_parse_git_worktree_porcelain(self) -> None:
        repo_root = Path("/tmp/repo")
        text = """
worktree /tmp/repo
HEAD abc
branch refs/heads/v4.29.0

worktree /tmp/repo/.worktrees/harness-rework
HEAD def
branch refs/heads/feat/harness-rework

worktree /tmp/repo/.worktrees/detached-edit
HEAD 1234567
"""
        worktrees = parse_git_worktree_porcelain(text, repo_root)

        self.assertEqual([(worktree.name, worktree.branch, worktree.head) for worktree in worktrees], [
            (ROOT_WORKTREE_NAME, "v4.29.0", "abc"),
            ("harness-rework", "feat/harness-rework", "def"),
            ("detached-edit", None, "1234567"),
        ])
        self.assertTrue(worktrees[0].root_checkout)
        self.assertFalse(worktrees[1].root_checkout)

    def test_resolve_worktree_name_prefers_explicit_name(self) -> None:
        self.assertEqual(resolve_worktree_name("harness-rework", "doc-polish"), "doc-polish")
        self.assertEqual(resolve_worktree_name("harness-rework", None), "harness-rework")
        self.assertEqual(resolve_worktree_name(None, None), ROOT_WORKTREE_NAME)

    def test_sync_worktree_registry_creates_local_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            worktree_dir = repo_root / ".worktrees" / "demo"
            worktree_dir.mkdir(parents=True)
            subprocess_text = f"""
worktree {repo_root}
HEAD abc
branch refs/heads/v4.29.0

worktree {worktree_dir}
HEAD def
branch refs/heads/feat/demo
"""

            import scripts.blueprint_harness_worktrees as worktrees_mod

            originals = {
                "git_worktrees": worktrees_mod.git_worktrees,
                "collect_worktree_facts": worktrees_mod.collect_worktree_facts,
            }
            try:
                worktrees_mod.git_worktrees = lambda _repo_root: parse_git_worktree_porcelain(subprocess_text, repo_root)
                worktrees_mod.collect_worktree_facts = lambda _repo_root, git_wt: {
                    "dirty": git_wt.name == ROOT_WORKTREE_NAME,
                    "tracked_changes": 1 if git_wt.name == ROOT_WORKTREE_NAME else 0,
                    "untracked_changes": 0,
                    "base_ref": "origin/v4.29.0",
                    "merged_into_main": git_wt.name == ROOT_WORKTREE_NAME,
                    "main_ahead": 0 if git_wt.name == ROOT_WORKTREE_NAME else 1,
                    "main_behind": 0 if git_wt.name == ROOT_WORKTREE_NAME else 2,
                    "upstream": "origin/v4.29.0" if git_wt.name == ROOT_WORKTREE_NAME else None,
                    "upstream_ahead": 0 if git_wt.name == ROOT_WORKTREE_NAME else None,
                    "upstream_behind": 0 if git_wt.name == ROOT_WORKTREE_NAME else None,
                    "last_commit": "abc1234" if git_wt.name == ROOT_WORKTREE_NAME else "def5678",
                    "last_commit_at": "2026-03-19T00:00:00Z",
                    "last_commit_subject": "demo",
                }
                records, registry = sync_worktree_registry(repo_root)
            finally:
                for name, value in originals.items():
                    setattr(worktrees_mod, name, value)

            self.assertEqual([record.name for record in records], [ROOT_WORKTREE_NAME, "demo"])
            self.assertTrue(metadata_path(repo_root, ROOT_WORKTREE_NAME).exists())
            self.assertTrue(metadata_path(repo_root, "demo").exists())
            self.assertEqual(metadata_path(repo_root, "demo"), repo_root / ".worktrees" / METADATA_DIRNAME / "demo.json")
            self.assertFalse((worktree_dir / ".codex-worktree.json").exists())
            self.assertTrue(registry.exists())
            root_metadata = json.loads(metadata_path(repo_root, ROOT_WORKTREE_NAME).read_text(encoding="utf-8"))
            demo_metadata = json.loads(metadata_path(repo_root, "demo").read_text(encoding="utf-8"))
            self.assertEqual(root_metadata["status"], "base")
            self.assertFalse(root_metadata["locked"])
            self.assertEqual(demo_metadata["summary"], "demo")
            self.assertFalse(demo_metadata["locked"])
            self.assertNotIn("path", demo_metadata)
            self.assertNotIn("dirty", demo_metadata)
            generated_registry = json.loads(registry.read_text(encoding="utf-8"))
            by_name = {entry["name"]: WorktreeRecord(**entry) for entry in generated_registry["worktrees"]}
            self.assertTrue(by_name[ROOT_WORKTREE_NAME].dirty)
            self.assertEqual(by_name[ROOT_WORKTREE_NAME].tracked_changes, 1)
            self.assertEqual(by_name["demo"].main_ahead, 1)
            self.assertEqual(by_name["demo"].main_behind, 2)

    def test_sync_worktree_registry_ignores_missing_git_worktree_paths(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            stale_dir = repo_root / ".worktrees" / "stale"
            subprocess_text = f"""
worktree {repo_root}
HEAD abc
branch refs/heads/v4.32.0

worktree {stale_dir}
HEAD def
branch refs/heads/feat/stale
"""
            stale_metadata = metadata_path(repo_root, "stale")
            stale_metadata.parent.mkdir(parents=True)
            stale_metadata.write_text(
                json.dumps({"version": 1, "name": "stale", "status": "merged"}) + "\n",
                encoding="utf-8",
            )

            import scripts.blueprint_harness_worktrees as worktrees_mod

            originals = {
                "git_worktrees": worktrees_mod.git_worktrees,
                "collect_worktree_facts": worktrees_mod.collect_worktree_facts,
            }
            seen: list[str] = []
            try:
                worktrees_mod.git_worktrees = lambda _repo_root: parse_git_worktree_porcelain(subprocess_text, repo_root)

                def fake_facts(_repo_root, git_wt):
                    seen.append(git_wt.name)
                    return {
                        "dirty": False,
                        "tracked_changes": 0,
                        "untracked_changes": 0,
                        "base_ref": "origin/v4.32.0",
                        "merged_into_main": True,
                        "main_ahead": 0,
                        "main_behind": 0,
                        "upstream": "origin/v4.32.0",
                        "upstream_ahead": 0,
                        "upstream_behind": 0,
                        "last_commit": "abc",
                        "last_commit_at": "2026-07-15T00:00:00Z",
                        "last_commit_subject": "root",
                    }

                worktrees_mod.collect_worktree_facts = fake_facts
                records, _registry = sync_worktree_registry(repo_root)
            finally:
                for name, value in originals.items():
                    setattr(worktrees_mod, name, value)

            self.assertEqual(seen, [ROOT_WORKTREE_NAME])
            self.assertEqual([record.name for record in records], [ROOT_WORKTREE_NAME])
            self.assertFalse(stale_metadata.exists())

    def test_sync_worktree_registry_preserves_created_at_and_refreshes_canonical_fields(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            worktree_dir = repo_root / ".worktrees" / "demo"
            worktree_dir.mkdir(parents=True)
            for name, root_checkout, status, summary, priority, locked in [
                (ROOT_WORKTREE_NAME, True, "base", "root", None, False),
                ("demo", False, "active", "demo", "P1", True),
            ]:
                path = metadata_path(repo_root, name)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(
                    json.dumps(
                        {
                            "version": 1,
                            "name": name,
                            "status": status,
                            "locked": locked,
                            "priority": priority,
                            "summary": summary,
                            "write_scope": [],
                            "created_at": "2026-03-19T00:00:00Z",
                            "updated_at": "2026-03-19T01:00:00Z",
                        },
                        indent=2,
                    )
                    + "\n",
                    encoding="utf-8",
                )
            registry = repo_root / ".worktrees" / "registry.json"
            registry.parent.mkdir(parents=True, exist_ok=True)
            registry.write_text(
                json.dumps(
                    {
                        "version": 1,
                        "generated_at": "2026-03-19T00:00:00Z",
                        "worktrees": [
                            {
                                "version": 1,
                                "name": "demo",
                                "path": str(worktree_dir),
                                "branch": "feat/demo",
                                "root_checkout": False,
                                "status": "blocked",
                                "owner": "legacy",
                                "locked": False,
                                "priority": "P2",
                                "summary": "stale registry data",
                                "write_scope": ["legacy"],
                                "created_at": "2026-03-18T00:00:00Z",
                                "updated_at": "2026-03-18T00:00:00Z",
                                "dirty": True,
                                "tracked_changes": 9,
                                "untracked_changes": 9,
                                "base_ref": "origin/v4.29.0",
                                "merged_into_main": False,
                                "main_ahead": 9,
                                "main_behind": 9,
                                "upstream": None,
                                "upstream_ahead": None,
                                "upstream_behind": None,
                                "last_commit": "stale",
                                "last_commit_at": "2026-03-18T00:00:00Z",
                                "last_commit_subject": "stale",
                            }
                        ],
                    },
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )
            subprocess_text = f"""
worktree {repo_root}
HEAD abc
branch refs/heads/v4.29.0

worktree {worktree_dir}
HEAD def
branch refs/heads/feat/demo
"""

            import scripts.blueprint_harness_worktrees as worktrees_mod

            originals = {
                "git_worktrees": worktrees_mod.git_worktrees,
                "collect_worktree_facts": worktrees_mod.collect_worktree_facts,
            }
            try:
                worktrees_mod.git_worktrees = lambda _repo_root: parse_git_worktree_porcelain(subprocess_text, repo_root)
                worktrees_mod.collect_worktree_facts = lambda _repo_root, git_wt: {
                    "dirty": git_wt.name == "demo",
                    "tracked_changes": 5 if git_wt.name == "demo" else 0,
                    "untracked_changes": 1 if git_wt.name == "demo" else 0,
                    "base_ref": "origin/v4.29.0",
                    "merged_into_main": git_wt.name == ROOT_WORKTREE_NAME,
                    "main_ahead": 2 if git_wt.name == "demo" else 0,
                    "main_behind": 7 if git_wt.name == "demo" else 0,
                    "upstream": None if git_wt.name == "demo" else "origin/v4.29.0",
                    "upstream_ahead": None if git_wt.name == "demo" else 0,
                    "upstream_behind": None if git_wt.name == "demo" else 0,
                    "last_commit": "updated",
                    "last_commit_at": "2026-03-19T12:00:00Z",
                    "last_commit_subject": "updated subject",
                }
                records, _registry = sync_worktree_registry(repo_root)
            finally:
                for name, value in originals.items():
                    setattr(worktrees_mod, name, value)

            self.assertEqual([record.name for record in records], [ROOT_WORKTREE_NAME, "demo"])
            demo_metadata = json.loads(metadata_path(repo_root, "demo").read_text(encoding="utf-8"))
            self.assertEqual(demo_metadata["created_at"], "2026-03-19T00:00:00Z")
            self.assertEqual(demo_metadata["updated_at"], "2026-03-19T01:00:00Z")
            self.assertTrue(demo_metadata["locked"])
            self.assertEqual(demo_metadata["priority"], "P1")
            self.assertNotIn("tracked_changes", demo_metadata)
            rewritten = json.loads(registry.read_text(encoding="utf-8"))
            by_name = {entry["name"]: entry for entry in rewritten["worktrees"]}
            self.assertEqual(by_name[ROOT_WORKTREE_NAME]["created_at"], "2026-03-19T00:00:00Z")
            self.assertEqual(by_name["demo"]["created_at"], "2026-03-19T00:00:00Z")
            self.assertTrue(by_name["demo"]["locked"])
            self.assertEqual(by_name["demo"]["priority"], "P1")
            self.assertEqual(by_name["demo"]["status"], "active")
            self.assertEqual(by_name["demo"]["summary"], "demo")
            self.assertTrue(by_name["demo"]["dirty"])
            self.assertEqual(by_name["demo"]["tracked_changes"], 5)
            self.assertEqual(by_name["demo"]["untracked_changes"], 1)
            self.assertEqual(by_name["demo"]["main_ahead"], 2)
            self.assertEqual(by_name["demo"]["main_behind"], 7)
            self.assertEqual(by_name["demo"]["last_commit"], "updated")
            self.assertEqual(by_name["demo"]["last_commit_subject"], "updated subject")

    def test_sync_worktree_registry_ignores_registry_when_metadata_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            worktree_dir = repo_root / ".worktrees" / "demo"
            worktree_dir.mkdir(parents=True)
            registry = repo_root / ".worktrees" / "registry.json"
            registry.parent.mkdir(parents=True, exist_ok=True)
            registry.write_text(
                json.dumps(
                    {
                        "version": 1,
                        "generated_at": "2026-03-19T00:00:00Z",
                        "worktrees": [
                            {
                                "version": 1,
                                "name": "demo",
                                "path": str(worktree_dir),
                                "branch": "feat/demo",
                                "root_checkout": False,
                                "status": "blocked",
                                "owner": "legacy",
                                "locked": True,
                                "priority": "P0",
                                "summary": "stale registry data",
                                "write_scope": ["legacy"],
                                "created_at": "2026-03-18T00:00:00Z",
                                "updated_at": "2026-03-18T00:00:00Z",
                                "dirty": True,
                                "tracked_changes": 9,
                                "untracked_changes": 9,
                                "base_ref": "origin/v4.29.0",
                                "merged_into_main": False,
                                "main_ahead": 9,
                                "main_behind": 9,
                                "upstream": None,
                                "upstream_ahead": None,
                                "upstream_behind": None,
                                "last_commit": "stale",
                                "last_commit_at": "2026-03-18T00:00:00Z",
                                "last_commit_subject": "stale",
                            }
                        ],
                    },
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )
            subprocess_text = f"""
worktree {repo_root}
HEAD abc
branch refs/heads/v4.29.0

worktree {worktree_dir}
HEAD def
branch refs/heads/feat/demo
"""

            import scripts.blueprint_harness_worktrees as worktrees_mod

            originals = {
                "git_worktrees": worktrees_mod.git_worktrees,
                "collect_worktree_facts": worktrees_mod.collect_worktree_facts,
            }
            try:
                worktrees_mod.git_worktrees = lambda _repo_root: parse_git_worktree_porcelain(subprocess_text, repo_root)
                worktrees_mod.collect_worktree_facts = lambda _repo_root, _git_wt: {
                    "dirty": False,
                    "tracked_changes": 0,
                    "untracked_changes": 0,
                    "base_ref": "origin/v4.29.0",
                    "merged_into_main": False,
                    "main_ahead": 0,
                    "main_behind": 0,
                    "upstream": None,
                    "upstream_ahead": None,
                    "upstream_behind": None,
                    "last_commit": "updated",
                    "last_commit_at": "2026-03-19T12:00:00Z",
                    "last_commit_subject": "updated subject",
                }
                records, _registry = sync_worktree_registry(repo_root)
            finally:
                for name, value in originals.items():
                    setattr(worktrees_mod, name, value)

            by_name = {record.name: record for record in records}
            self.assertEqual(by_name["demo"].status, "active")
            self.assertIsNone(by_name["demo"].owner)
            self.assertFalse(by_name["demo"].locked)
            self.assertIsNone(by_name["demo"].priority)
            self.assertEqual(by_name["demo"].summary, "demo")

    def test_sync_worktree_registry_prunes_stale_metadata_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            worktree_dir = repo_root / ".worktrees" / "demo"
            worktree_dir.mkdir(parents=True)
            stale_path = repo_root / ".worktrees" / METADATA_DIRNAME / "stale.json"
            stale_path.parent.mkdir(parents=True, exist_ok=True)
            stale_path.write_text(
                json.dumps(
                    {
                        "version": 1,
                        "name": "stale",
                        "status": "done",
                    },
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )
            subprocess_text = f"""
worktree {repo_root}
HEAD abc
branch refs/heads/v4.29.0

worktree {worktree_dir}
HEAD def
branch refs/heads/feat/demo
"""

            import scripts.blueprint_harness_worktrees as worktrees_mod

            originals = {
                "git_worktrees": worktrees_mod.git_worktrees,
                "collect_worktree_facts": worktrees_mod.collect_worktree_facts,
            }
            try:
                worktrees_mod.git_worktrees = lambda _repo_root: parse_git_worktree_porcelain(subprocess_text, repo_root)
                worktrees_mod.collect_worktree_facts = lambda _repo_root, _git_wt: {
                    "dirty": False,
                    "tracked_changes": 0,
                    "untracked_changes": 0,
                    "base_ref": "origin/v4.29.0",
                    "merged_into_main": False,
                    "main_ahead": 0,
                    "main_behind": 0,
                    "upstream": None,
                    "upstream_ahead": None,
                    "upstream_behind": None,
                    "last_commit": "updated",
                    "last_commit_at": "2026-03-19T12:00:00Z",
                    "last_commit_subject": "updated subject",
                }
                sync_worktree_registry(repo_root)
            finally:
                for name, value in originals.items():
                    setattr(worktrees_mod, name, value)

            self.assertFalse(stale_path.exists())

    def test_collect_worktree_facts_reports_ref_relationships(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp) / "repo"
            repo_root.mkdir(parents=True)
            subprocess.run(["git", "init"], cwd=repo_root, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(["git", "config", "user.name", "Test User"], cwd=repo_root, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=repo_root, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(["git", "config", "commit.gpgsign", "false"], cwd=repo_root, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            (repo_root / "tracked.txt").write_text("base\n", encoding="utf-8")
            (repo_root / "lean-toolchain").write_text("leanprover/lean4:v4.29.0\n", encoding="utf-8")
            subprocess.run(["git", "add", "tracked.txt", "lean-toolchain"], cwd=repo_root, check=True)
            subprocess.run(["git", "commit", "-m", "base"], cwd=repo_root, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(["git", "branch", "-M", "v4.29.0"], cwd=repo_root, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            subprocess.run(["git", "branch", "feature"], cwd=repo_root, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(["git", "checkout", "feature"], cwd=repo_root, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            (repo_root / "tracked.txt").write_text("feature\n", encoding="utf-8")
            subprocess.run(["git", "commit", "-am", "feature"], cwd=repo_root, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            feature_head = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=repo_root,
                check=True,
                text=True,
                capture_output=True,
            ).stdout.strip()
            worktree = parse_git_worktree_porcelain(
                f"worktree {repo_root}\nHEAD {feature_head}\nbranch refs/heads/feature\n",
                repo_root,
            )[0]

            facts = collect_worktree_facts(repo_root, worktree)

            self.assertFalse(facts["dirty"])
            self.assertEqual(facts["tracked_changes"], 0)
            self.assertEqual(facts["untracked_changes"], 0)
            self.assertEqual(facts["base_ref"], "v4.29.0")
            self.assertFalse(facts["merged_into_main"])
            self.assertEqual((facts["main_ahead"], facts["main_behind"]), (1, 0))
            self.assertIsNone(facts["upstream"])
            self.assertEqual(facts["last_commit"], feature_head[:7])


if __name__ == "__main__":
    unittest.main()
