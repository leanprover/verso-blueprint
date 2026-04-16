from __future__ import annotations

from pathlib import Path
import tempfile
import unittest

import scripts.blueprint_harness_branches as branches_mod


class BlueprintHarnessBranchPolicyTests(unittest.TestCase):
    def write(self, path: Path, text: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def test_load_branch_policy_reads_default_dev_branch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write(root / "branch-policy.json", '{\n  "version": 1,\n  "default_dev_branch": "4.29.0"\n}\n')

            policy = branches_mod.load_branch_policy(root)

            self.assertEqual(policy.version, 1)
            self.assertEqual(policy.default_dev_branch, "v4.29.0")
            self.assertEqual(policy.required_backport_branches, ())
            self.assertEqual(policy.source_path, root / "branch-policy.json")

    def test_load_branch_policy_reads_required_backport_branches(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write(
                root / "branch-policy.json",
                '{\n  "version": 1,\n  "default_dev_branch": "v4.29.0",\n  "required_backport_branches": ["4.28.0"]\n}\n',
            )

            policy = branches_mod.load_branch_policy(root)

            self.assertEqual(policy.required_backport_branches, ("v4.28.0",))

    def test_load_branch_policy_falls_back_to_active_release_branch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write(root / "lean-toolchain", "leanprover/lean4:v4.29.0\n")

            policy = branches_mod.load_branch_policy(root)

            self.assertEqual(policy.default_dev_branch, "v4.29.0")

    def test_checkout_branch_role_reports_default_dev_when_policy_matches(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write(root / "lean-toolchain", "leanprover/lean4:v4.29.0\n")
            self.write(root / "branch-policy.json", '{\n  "version": 1,\n  "default_dev_branch": "v4.29.0"\n}\n')

            self.assertEqual(branches_mod.checkout_branch_role(root), "default_dev")
            self.assertFalse(branches_mod.checkout_is_backport_only(root))

    def test_checkout_branch_role_reports_backport_when_policy_differs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write(root / "lean-toolchain", "leanprover/lean4:v4.28.0\n")
            self.write(root / "branch-policy.json", '{\n  "version": 1,\n  "default_dev_branch": "v4.29.0"\n}\n')

            self.assertEqual(branches_mod.checkout_branch_role(root), "backport")
            self.assertTrue(branches_mod.checkout_is_backport_only(root))

    def test_require_checkout_role_rejects_backport_for_default_dev_only_operation(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write(root / "lean-toolchain", "leanprover/lean4:v4.28.0\n")
            self.write(root / "branch-policy.json", '{\n  "version": 1,\n  "default_dev_branch": "v4.29.0"\n}\n')

            with self.assertRaisesRegex(SystemExit, "refusing to run `bump-toolchain` from backport-only checkout `v4.28.0`"):
                branches_mod.require_checkout_role(root, required_role="default_dev", operation="bump-toolchain")


if __name__ == "__main__":
    unittest.main()
