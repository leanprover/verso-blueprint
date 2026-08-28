from __future__ import annotations

import json
import re
import tempfile
import unittest
from pathlib import Path

from scripts.blueprint_harness_branches import active_release_branch
from scripts.blueprint_harness_project_commands import OFFICIAL_BLUEPRINT_REQUIRE_PATTERN
import scripts.blueprint_harness_toolchains as toolchains_mod
from tests.harness.release_fixtures import (
    SAMPLE_DEFAULT_RC_REF,
    SAMPLE_DEFAULT_RELEASE,
    SAMPLE_NEXT_RC,
    SAMPLE_NEXT_RC_REF,
    SAMPLE_NEXT_RELEASE,
    SAMPLE_PREVIOUS_RELEASE,
    lean_toolchain,
    official_blueprint_require,
    official_verso_slides_require,
    official_verso_require,
)


PACKAGE_ROOT = Path(__file__).resolve().parents[2]


class BlueprintHarnessToolchainTests(unittest.TestCase):
    def write(self, path: Path, text: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def test_normalize_lean_release_ref_accepts_short_numeric_version(self) -> None:
        self.assertEqual(
            toolchains_mod.normalize_lean_release_ref(SAMPLE_DEFAULT_RELEASE.removeprefix("v")),
            SAMPLE_DEFAULT_RELEASE,
        )
        self.assertEqual(
            toolchains_mod.normalize_lean_release_ref(lean_toolchain(SAMPLE_DEFAULT_RELEASE)),
            SAMPLE_DEFAULT_RELEASE,
        )

    def test_rewrite_pinned_verso_dependency_replaces_official_git_require(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project_dir = Path(tmp)
            lakefile = project_dir / "lakefile.lean"
            lakefile.write_text(
                '\n'.join(
                    [
                        "import Lake",
                        "open Lake DSL",
                        'require verso from git "https://github.com/leanprover/verso"@"main"',
                        "",
                    ]
                ),
                encoding="utf-8",
            )

            result, previous_ref = toolchains_mod.rewrite_pinned_verso_dependency(project_dir, SAMPLE_DEFAULT_RELEASE)

            self.assertEqual(result, lakefile)
            self.assertEqual(previous_ref, "main")
            self.assertIn(official_verso_require(SAMPLE_DEFAULT_RELEASE), lakefile.read_text(encoding="utf-8"))

    def test_rewrite_pinned_verso_slides_dependency_replaces_official_git_require(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project_dir = Path(tmp)
            lakefile = project_dir / "lakefile.lean"
            lakefile.write_text(
                '\n'.join(
                    [
                        "import Lake",
                        "open Lake DSL",
                        (
                            'require «verso-slides» from git "https://github.com/leanprover/verso-slides"'
                            '@"main"'
                        ),
                        "",
                    ]
                ),
                encoding="utf-8",
            )

            result, previous_ref = toolchains_mod.rewrite_pinned_verso_slides_dependency(
                project_dir, SAMPLE_NEXT_RELEASE
            )

            self.assertEqual(result, lakefile)
            self.assertEqual(previous_ref, "main")
            self.assertIn(official_verso_slides_require(SAMPLE_NEXT_RELEASE), lakefile.read_text(encoding="utf-8"))

    def test_bump_toolchain_checkout_updates_managed_files_and_preserves_inherited_dependencies(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            package_root = Path(tmp)
            root_lakefile = "\n".join(
                [
                    "import Lake",
                    "open Lake DSL",
                    'require verso from git "https://github.com/leanprover/verso"@"main"',
                    'require «verso-slides» from git "https://github.com/leanprover/verso-slides"@"main"',
                    'require proofwidgets from git "https://github.com/leanprover-community/ProofWidgets4"@"v0.0.92"',
                    "",
                ]
            )
            template_lakefile = "\n".join(
                [
                    "import Lake",
                    "open Lake DSL",
                    official_blueprint_require(SAMPLE_PREVIOUS_RELEASE),
                    "",
                ]
            )
            preview_lakefile = "\n".join(
                [
                    "import Lake",
                    "open Lake DSL",
                    'require VersoBlueprint from "../../../"',
                    "",
                ]
            )

            self.write(package_root / "lean-toolchain", lean_toolchain(SAMPLE_DEFAULT_RC_REF))
            self.write(package_root / "lakefile.lean", root_lakefile)
            self.write(package_root / "project_template" / "lean-toolchain", f"{lean_toolchain(SAMPLE_DEFAULT_RC_REF)}\n")
            self.write(package_root / "project_template" / "lakefile.lean", template_lakefile)
            self.write(
                package_root / "tests" / "test_blueprints" / "preview_runtime_showcase" / "lean-toolchain",
                f"{lean_toolchain(SAMPLE_DEFAULT_RC_REF)}\n",
            )
            self.write(
                package_root / "tests" / "test_blueprints" / "preview_runtime_showcase" / "lakefile.lean",
                preview_lakefile,
            )

            originals = {
                "resolve_remote_verso_tag_oid": toolchains_mod.resolve_remote_verso_tag_oid,
                "resolve_remote_verso_slides_tag_oid": toolchains_mod.resolve_remote_verso_slides_tag_oid,
                "run": toolchains_mod.run,
            }
            commands: list[tuple[list[str], Path]] = []
            try:
                toolchains_mod.resolve_remote_verso_tag_oid = lambda _package_root, _ref: "deadbeef"
                toolchains_mod.resolve_remote_verso_slides_tag_oid = lambda _package_root, _ref: "feedface"
                toolchains_mod.run = lambda command, *, cwd: commands.append((command, cwd))

                result = toolchains_mod.bump_toolchain_checkout(
                    package_root,
                    SAMPLE_DEFAULT_RELEASE.removeprefix("v"),
                    validate=False,
                )
            finally:
                for name, value in originals.items():
                    setattr(toolchains_mod, name, value)

            self.assertEqual(result.lean_ref, SAMPLE_DEFAULT_RELEASE)
            self.assertEqual(result.verso_ref, SAMPLE_DEFAULT_RELEASE)
            self.assertEqual(result.verso_slides_ref, SAMPLE_DEFAULT_RELEASE)
            self.assertEqual(
                (package_root / "lean-toolchain").read_text(encoding="utf-8"),
                lean_toolchain(SAMPLE_DEFAULT_RELEASE),
            )
            self.assertEqual(
                (package_root / "project_template" / "lean-toolchain").read_text(encoding="utf-8"),
                f"{lean_toolchain(SAMPLE_DEFAULT_RELEASE)}\n",
            )
            self.assertEqual(
                (package_root / "tests" / "test_blueprints" / "preview_runtime_showcase" / "lean-toolchain").read_text(
                    encoding="utf-8"
                ),
                f"{lean_toolchain(SAMPLE_DEFAULT_RELEASE)}\n",
            )
            self.assertIn(
                official_verso_require(SAMPLE_DEFAULT_RELEASE),
                (package_root / "lakefile.lean").read_text(encoding="utf-8"),
            )
            self.assertIn(
                official_verso_slides_require(SAMPLE_DEFAULT_RELEASE),
                (package_root / "lakefile.lean").read_text(encoding="utf-8"),
            )
            template_text = (package_root / "project_template" / "lakefile.lean").read_text(encoding="utf-8")
            self.assertNotIn("require verso", template_text)
            self.assertIn(official_blueprint_require(SAMPLE_DEFAULT_RELEASE), template_text)
            preview_text = (
                package_root / "tests" / "test_blueprints" / "preview_runtime_showcase" / "lakefile.lean"
            ).read_text(encoding="utf-8")
            self.assertIn(
                'require VersoBlueprint from "../../../"',
                preview_text,
            )
            self.assertNotIn(
                "require verso",
                preview_text,
            )
            expected_script = str(package_root / "scripts" / "lean-low-priority")
            self.assertEqual(
                commands,
                [
                    ([expected_script, "lake", "update"], package_root),
                    ([expected_script, "lake", "update"], package_root / "project_template"),
                    (
                        [expected_script, "lake", "update"],
                        package_root / "tests" / "test_blueprints" / "preview_runtime_showcase",
                    ),
                ],
            )

    def test_bump_toolchain_checkout_accepts_release_candidate_name(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            package_root = Path(tmp)
            root_lakefile = (
                f"{official_verso_require(SAMPLE_DEFAULT_RELEASE)}\n"
                f"{official_verso_slides_require(SAMPLE_DEFAULT_RELEASE)}\n"
            )
            template_lakefile = f"{official_blueprint_require(SAMPLE_DEFAULT_RELEASE)}\n"
            preview_lakefile = 'require VersoBlueprint from "../../../"\n'

            self.write(package_root / "lean-toolchain", lean_toolchain(SAMPLE_DEFAULT_RELEASE))
            self.write(package_root / "lakefile.lean", root_lakefile)
            self.write(package_root / "project_template" / "lean-toolchain", f"{lean_toolchain(SAMPLE_DEFAULT_RELEASE)}\n")
            self.write(package_root / "project_template" / "lakefile.lean", template_lakefile)
            self.write(
                package_root / "tests" / "test_blueprints" / "preview_runtime_showcase" / "lean-toolchain",
                f"{lean_toolchain(SAMPLE_DEFAULT_RELEASE)}\n",
            )
            self.write(
                package_root / "tests" / "test_blueprints" / "preview_runtime_showcase" / "lakefile.lean",
                preview_lakefile,
            )

            originals = {
                "resolve_remote_verso_tag_oid": toolchains_mod.resolve_remote_verso_tag_oid,
                "resolve_remote_verso_slides_tag_oid": toolchains_mod.resolve_remote_verso_slides_tag_oid,
                "run": toolchains_mod.run,
            }
            commands: list[tuple[list[str], Path]] = []
            try:
                toolchains_mod.resolve_remote_verso_tag_oid = lambda _package_root, _ref: "deadbeef"
                toolchains_mod.resolve_remote_verso_slides_tag_oid = lambda _package_root, _ref: "feedface"
                toolchains_mod.run = lambda command, *, cwd: commands.append((command, cwd))

                result = toolchains_mod.bump_toolchain_checkout(
                    package_root,
                    SAMPLE_NEXT_RC,
                    validate=False,
                )
            finally:
                for name, value in originals.items():
                    setattr(toolchains_mod, name, value)

            self.assertEqual(result.lean_ref, SAMPLE_NEXT_RC_REF)
            self.assertEqual(result.toolchain_spec, lean_toolchain(SAMPLE_NEXT_RC_REF))
            self.assertEqual(result.verso_ref, SAMPLE_NEXT_RC_REF)
            self.assertEqual(result.verso_tag_oid, "deadbeef")
            self.assertEqual(result.verso_slides_ref, SAMPLE_NEXT_RC_REF)
            self.assertEqual(result.verso_slides_tag_oid, "feedface")
            self.assertEqual(
                (package_root / "lean-toolchain").read_text(encoding="utf-8"),
                lean_toolchain(SAMPLE_NEXT_RC_REF),
            )
            self.assertIn(
                official_verso_require(SAMPLE_NEXT_RC_REF),
                (package_root / "lakefile.lean").read_text(encoding="utf-8"),
            )
            self.assertIn(
                official_verso_slides_require(SAMPLE_NEXT_RC_REF),
                (package_root / "lakefile.lean").read_text(encoding="utf-8"),
            )
            self.assertIn(
                official_blueprint_require(SAMPLE_NEXT_RELEASE),
                (package_root / "project_template" / "lakefile.lean").read_text(encoding="utf-8"),
            )
            self.assertEqual(len(commands), 3)

    def test_bump_toolchain_checkout_rejects_missing_matching_verso_tag(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            package_root = Path(tmp)
            self.write(package_root / "lean-toolchain", lean_toolchain(SAMPLE_DEFAULT_RC_REF))
            self.write(
                package_root / "lakefile.lean",
                'require verso from git "https://github.com/leanprover/verso"@"main"\n',
                # The matching tag check happens before either managed dependency is rewritten.
            )
            self.write(package_root / "project_template" / "lean-toolchain", f"{lean_toolchain(SAMPLE_DEFAULT_RC_REF)}\n")
            self.write(
                package_root / "project_template" / "lakefile.lean",
                f"{official_blueprint_require(SAMPLE_PREVIOUS_RELEASE)}\n",
            )
            self.write(
                package_root / "tests" / "test_blueprints" / "preview_runtime_showcase" / "lean-toolchain",
                f"{lean_toolchain(SAMPLE_DEFAULT_RC_REF)}\n",
            )
            self.write(
                package_root / "tests" / "test_blueprints" / "preview_runtime_showcase" / "lakefile.lean",
                'require VersoBlueprint from "../../../"\n',
            )

            original = toolchains_mod.resolve_remote_verso_tag_oid
            try:
                toolchains_mod.resolve_remote_verso_tag_oid = lambda _package_root, _ref: None
                with self.assertRaisesRegex(SystemExit, "no matching `verso` tag"):
                    toolchains_mod.bump_toolchain_checkout(package_root, SAMPLE_DEFAULT_RELEASE, validate=False)
            finally:
                toolchains_mod.resolve_remote_verso_tag_oid = original

    def test_bump_toolchain_checkout_rejects_missing_matching_verso_slides_tag(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            package_root = Path(tmp)
            original_verso = toolchains_mod.resolve_remote_verso_tag_oid
            original_slides = toolchains_mod.resolve_remote_verso_slides_tag_oid
            try:
                toolchains_mod.resolve_remote_verso_tag_oid = lambda _package_root, _ref: "deadbeef"
                toolchains_mod.resolve_remote_verso_slides_tag_oid = lambda _package_root, _ref: None
                with self.assertRaisesRegex(SystemExit, "no matching `verso-slides` tag"):
                    toolchains_mod.bump_toolchain_checkout(package_root, SAMPLE_DEFAULT_RELEASE, validate=False)
            finally:
                toolchains_mod.resolve_remote_verso_tag_oid = original_verso
                toolchains_mod.resolve_remote_verso_slides_tag_oid = original_slides

    def test_project_template_blueprint_dependency_tracks_active_release_branch(self) -> None:
        text = (PACKAGE_ROOT / "project_template" / "lakefile.lean").read_text(encoding="utf-8")
        match = next(OFFICIAL_BLUEPRINT_REQUIRE_PATTERN.finditer(text), None)

        self.assertIsNotNone(match)
        assert match is not None
        self.assertEqual(match.group("ref"), active_release_branch(PACKAGE_ROOT))

    def test_root_release_dependencies_track_managed_release_pins(self) -> None:
        text = (PACKAGE_ROOT / "lakefile.lean").read_text(encoding="utf-8")
        verso_match = next(toolchains_mod.VERSO_REQUIRE_PATTERN.finditer(text), None)
        slides_match = next(toolchains_mod.VERSO_SLIDES_REQUIRE_PATTERN.finditer(text), None)
        manifest = json.loads((PACKAGE_ROOT / "lake-manifest.json").read_text(encoding="utf-8"))
        manifest_refs = {package["name"]: package["inputRev"] for package in manifest["packages"]}
        lean_ref = toolchains_mod.normalize_lean_release_ref(
            (PACKAGE_ROOT / "lean-toolchain").read_text(encoding="utf-8")
        )

        self.assertIsNotNone(verso_match)
        self.assertIsNotNone(slides_match)
        assert verso_match is not None
        assert slides_match is not None
        verso_ref = verso_match.group("ref")
        slides_ref = slides_match.group("ref")
        self.assertTrue(verso_ref == lean_ref or re.fullmatch(r"[0-9a-f]{40}", verso_ref))
        self.assertEqual(verso_ref, manifest_refs["verso"])
        self.assertEqual(slides_ref, lean_ref)
        self.assertEqual(slides_ref, manifest_refs["«verso-slides»"])


if __name__ == "__main__":
    unittest.main()
