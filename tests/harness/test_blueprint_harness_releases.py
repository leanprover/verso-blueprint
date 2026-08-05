from __future__ import annotations

from pathlib import Path
import tempfile
import unittest

import scripts.blueprint_harness_releases as releases_mod
from tests.harness.release_fixtures import (
    SAMPLE_DEFAULT_RELEASE,
    SAMPLE_NEXT_RC,
    SAMPLE_NEXT_RC_REF,
    SAMPLE_NEXT_RELEASE,
    lean_toolchain,
)


class BlueprintHarnessReleaseHelperTests(unittest.TestCase):
    def write(self, path: Path, text: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def test_release_candidate_names_normalize_to_tags_and_branch_ids(self) -> None:
        self.assertEqual(releases_mod.normalize_release_candidate_name(SAMPLE_NEXT_RC), SAMPLE_NEXT_RC)
        self.assertEqual(releases_mod.normalize_release_candidate_name(SAMPLE_NEXT_RC_REF), SAMPLE_NEXT_RC)
        self.assertEqual(releases_mod.release_candidate_name_or_none(SAMPLE_NEXT_RC_REF), SAMPLE_NEXT_RC)
        self.assertIsNone(releases_mod.release_candidate_name_or_none(SAMPLE_NEXT_RELEASE))
        self.assertEqual(releases_mod.release_candidate_ref(SAMPLE_NEXT_RC), SAMPLE_NEXT_RC_REF)
        self.assertEqual(releases_mod.normalize_lean_release_ref(SAMPLE_NEXT_RC), SAMPLE_NEXT_RC_REF)
        self.assertEqual(releases_mod.release_branch_from_lean_ref(lean_toolchain(SAMPLE_NEXT_RC_REF)), SAMPLE_NEXT_RELEASE)

    def test_release_branch_versions_are_comparable_across_stable_and_rc_refs(self) -> None:
        self.assertEqual(releases_mod.release_branch_version("v4.33.0"), (4, 33, 0))
        self.assertEqual(releases_mod.release_branch_version("4.33-rc2"), (4, 33, 0))
        self.assertGreater(
            releases_mod.release_branch_version("v4.33.0"),
            releases_mod.release_branch_version("v4.32.1"),
        )

    def test_release_branch_version_rejects_non_numeric_refs(self) -> None:
        with self.assertRaisesRegex(SystemExit, "expected a numeric Lean release branch"):
            releases_mod.release_branch_version("main")

    def test_rewrite_lean_toolchain_preserves_existing_final_newline_style(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with_newline = root / "with-newline" / "lean-toolchain"
            without_newline = root / "without-newline" / "lean-toolchain"
            self.write(with_newline, f"{lean_toolchain(SAMPLE_DEFAULT_RELEASE)}\n")
            self.write(without_newline, lean_toolchain(SAMPLE_DEFAULT_RELEASE))

            releases_mod.rewrite_lean_toolchain(with_newline, SAMPLE_NEXT_RELEASE)
            releases_mod.rewrite_lean_toolchain(without_newline, SAMPLE_NEXT_RELEASE)

            self.assertEqual(with_newline.read_text(encoding="utf-8"), f"{lean_toolchain(SAMPLE_NEXT_RELEASE)}\n")
            self.assertEqual(without_newline.read_text(encoding="utf-8"), lean_toolchain(SAMPLE_NEXT_RELEASE))


if __name__ == "__main__":
    unittest.main()
