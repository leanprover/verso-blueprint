from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

from scripts.blueprint_test_blueprints import (
    StandaloneTestBlueprint,
    default_test_blueprint_manifest,
    find_test_blueprint,
    generate_test_blueprint_outputs,
    blueprint_meta_by_slug,
    load_test_blueprint_categories,
    load_test_blueprints_manifest,
    render_test_blueprint_index_html,
    split_generation_targets,
    validate_curated_test_doc_meta,
    validate_test_blueprint_outputs,
    write_test_blueprint_index,
)
from scripts.blueprint_harness_utils import StepFailure
import scripts.blueprint_harness_validation as validation_mod
import scripts.blueprint_test_blueprints as test_blueprints_mod


PACKAGE_ROOT = Path(__file__).resolve().parents[2]
VBP_BUILD_OUTPUT_COMMAND = ("lake", "exe", "vbp", "build", "--output", "{output_dir}")


class StandaloneTestBlueprintTests(unittest.TestCase):
    def test_default_manifest_contains_preview_runtime_showcase(self) -> None:
        manifest = default_test_blueprint_manifest(PACKAGE_ROOT)
        categories = load_test_blueprint_categories(manifest)
        fixtures = load_test_blueprints_manifest(manifest)
        fixture = find_test_blueprint(fixtures, "preview_runtime_showcase")

        self.assertEqual(
            categories,
            ("Code", "Preview", "Relationships", "Summary", "Metadata", "Imports", "Graph", "Runtime"),
        )
        self.assertEqual(fixture.slug, "preview_runtime_showcase")
        self.assertEqual(fixture.kind, "standalone_project")
        self.assertEqual(fixture.category, "Runtime")
        self.assertEqual(
            fixture.tags,
            ("preview", "runtime", "browser", "graph", "summary", "relationships"),
        )
        self.assertEqual(fixture.project_root, "tests/test_blueprints/preview_runtime_showcase")
        self.assertEqual(fixture.build_command, ("lake", "build", "PreviewRuntimeShowcase"))
        self.assertEqual(
            fixture.generate_command,
            (
                "lake",
                "lean",
                "PreviewRuntimeShowcaseMain.lean",
                "--",
                "--run",
                "PreviewRuntimeShowcaseMain.lean",
                "--output",
                "{output_dir}",
            ),
        )
        self.assertEqual(fixture.browser_tests_path, "tests/browser")
        self.assertEqual(
            fixture.panel_regression_script,
            "tests/harness/preview_runtime_showcase/check_blueprint_code_panels.py",
        )

    def test_test_blueprint_catalog_requires_json_object(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "test_blueprints.json"
            manifest.write_text("[]\n", encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "expected JSON object"):
                load_test_blueprints_manifest(manifest)

    def test_duplicate_fixture_slugs_are_rejected(self) -> None:
        manifest_data = {
            "version": 1,
            "fixtures": [
                {
                    "slug": "dup",
                    "title": "One",
                    "category": "Runtime",
                    "summary": "First",
                    "project_root": "tests/test_blueprints/one",
                    "generate_command": list(VBP_BUILD_OUTPUT_COMMAND),
                },
                {
                    "slug": "dup",
                    "title": "Two",
                    "category": "Runtime",
                    "summary": "Second",
                    "project_root": "tests/test_blueprints/two",
                    "generate_command": list(VBP_BUILD_OUTPUT_COMMAND),
                },
            ],
            "categories": ["Runtime"],
        }
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "test_blueprints.json"
            manifest.write_text(json.dumps(manifest_data), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "duplicate fixture slug"):
                load_test_blueprints_manifest(manifest)

    def test_missing_generate_command_is_rejected(self) -> None:
        manifest_data = {
            "version": 1,
            "fixtures": [
                {
                    "slug": "missing",
                    "title": "Missing Generate",
                    "category": "Runtime",
                    "summary": "Bad fixture",
                    "project_root": "tests/test_blueprints/bad",
                }
            ],
            "categories": ["Runtime"],
        }
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "test_blueprints.json"
            manifest.write_text(json.dumps(manifest_data), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "generate_command"):
                load_test_blueprints_manifest(manifest)

    def test_unknown_category_is_rejected(self) -> None:
        manifest_data = {
            "version": 1,
            "categories": ["Preview"],
            "fixtures": [
                {
                    "slug": "bad-category",
                    "title": "Bad Category",
                    "category": "Runtime",
                    "summary": "Bad fixture",
                    "project_root": "tests/test_blueprints/bad",
                    "generate_command": list(VBP_BUILD_OUTPUT_COMMAND),
                }
            ],
        }
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "test_blueprints.json"
            manifest.write_text(json.dumps(manifest_data), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "unknown category"):
                load_test_blueprints_manifest(manifest)

    def test_invalid_tags_are_rejected(self) -> None:
        manifest_data = {
            "version": 1,
            "categories": ["Runtime"],
            "fixtures": [
                {
                    "slug": "bad-tag",
                    "title": "Bad Tag",
                    "category": "Runtime",
                    "summary": "Bad fixture",
                    "tags": ["not valid"],
                    "project_root": "tests/test_blueprints/bad",
                    "generate_command": list(VBP_BUILD_OUTPUT_COMMAND),
                }
            ],
        }
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "test_blueprints.json"
            manifest.write_text(json.dumps(manifest_data), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "invalid tag"):
                load_test_blueprints_manifest(manifest)

    def test_curated_doc_metadata_uses_the_shared_catalog_vocabulary(self) -> None:
        manifest = default_test_blueprint_manifest(PACKAGE_ROOT)
        categories = load_test_blueprint_categories(manifest)
        entries = [
            {
                "slug": "demo",
                "title": "Demo",
                "category": "Runtime",
                "summary": "Demo entry",
                "tags": ["preview", "runtime"],
                "kind": "curated_doc",
            }
        ]

        self.assertEqual(validate_curated_test_doc_meta(entries, categories), entries)

    def test_curated_doc_metadata_rejects_invalid_catalog_fields(self) -> None:
        categories = ("Runtime",)
        valid = {
            "slug": "demo",
            "title": "Demo",
            "category": "Runtime",
            "summary": "Demo entry",
            "tags": ["preview", "runtime"],
            "kind": "curated_doc",
        }
        invalid_entries = (
            ({**valid, "title": ""}, "expected non-empty string field `title`"),
            ({**valid, "category": "Unknown"}, "unknown category"),
            ({**valid, "summary": None}, "expected non-empty string field `summary`"),
            ({**valid, "kind": "standalone_project"}, "expected kind `curated_doc`"),
            ({**valid, "tags": ["not valid"]}, "invalid tag"),
            ({**valid, "tags": ["preview", "preview"]}, "duplicate values"),
        )

        for entry, message in invalid_entries:
            with self.subTest(message=message):
                with self.assertRaisesRegex(ValueError, message):
                    validate_curated_test_doc_meta([entry], categories)

    def test_meta_uses_unified_shape(self) -> None:
        fixture = StandaloneTestBlueprint(
            slug="preview_runtime_showcase",
            title="Preview Runtime Showcase",
            category="Runtime",
            summary="Summary",
            tags=("preview", "runtime"),
            project_root="tests/test_blueprints/preview_runtime_showcase",
            build_command=("lake", "build"),
            generate_command=VBP_BUILD_OUTPUT_COMMAND,
            panel_regression_script=None,
            browser_tests_path=None,
        )
        self.assertEqual(
            fixture.meta,
            {
                "slug": "preview_runtime_showcase",
                "title": "Preview Runtime Showcase",
                "category": "Runtime",
                "summary": "Summary",
                "tags": ["preview", "runtime"],
                "kind": "standalone_project",
            },
        )

    def test_validate_parser_combines_pytest_arg_and_passthrough_args(self) -> None:
        parser = test_blueprints_mod.build_parser()
        args, passthrough_args = parser.parse_known_args(
            [
                "validate",
                "--pytest-arg=-k",
                "--pytest-arg",
                "preview",
                "--",
                "--maxfail=1",
            ]
        )

        self.assertEqual(args.cmd, "validate")
        self.assertEqual(args.pytest_arg, ["-k", "preview"])
        self.assertEqual(
            test_blueprints_mod._combined_pytest_args(args, passthrough_args),
            ["-k", "preview", "--maxfail=1"],
        )

    def test_render_test_blueprint_index_groups_entries_by_category(self) -> None:
        html = render_test_blueprint_index_html(
            ("Preview", "Runtime"),
            [
                {
                    "slug": "preview-doc",
                    "title": "Preview Doc",
                    "category": "Preview",
                    "summary": "Preview summary",
                    "tags": ["preview"],
                    "kind": "curated_doc",
                },
                {
                    "slug": "runtime-showcase",
                    "title": "Runtime Showcase",
                    "category": "Runtime",
                    "summary": "Runtime summary",
                    "tags": ["runtime", "browser"],
                    "kind": "standalone_project",
                },
            ],
        )

        self.assertIn('<a class="chip" href="#preview">Preview</a>', html)
        self.assertIn('<a class="chip" href="#runtime">Runtime</a>', html)
        self.assertIn('<a href="./preview-doc/html-multi/">Preview Doc</a>', html)
        self.assertIn('<a href="./runtime-showcase/html-multi/">Runtime Showcase</a>', html)
        self.assertIn("<li>runtime</li><li>browser</li>", html)
        self.assertIn("<p>1 site</p>", html)

    def test_write_test_blueprint_index_writes_index_html(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            output_root = Path(tmp) / "test-blueprints"
            write_test_blueprint_index(
                output_root,
                ("Runtime",),
                [
                    {
                        "slug": "runtime-showcase",
                        "title": "Runtime Showcase",
                        "category": "Runtime",
                        "summary": "Runtime summary",
                        "tags": [],
                        "kind": "standalone_project",
                    }
                ],
            )

            html = (output_root / "index.html").read_text(encoding="utf-8")
            self.assertIn("Test Blueprint Artifacts", html)
            self.assertIn("./runtime-showcase/html-multi/", html)

    def test_split_generation_targets_classifies_standalone_slugs(self) -> None:
        fixture = StandaloneTestBlueprint(
            slug="runtime-showcase",
            title="Runtime Showcase",
            category="Runtime",
            summary="Runtime summary",
            tags=(),
            project_root="tests/test_blueprints/runtime-showcase",
            build_command=None,
            generate_command=VBP_BUILD_OUTPUT_COMMAND,
            panel_regression_script=None,
            browser_tests_path=None,
        )
        doc_slugs, fixtures = split_generation_targets(
            [
                {
                    "slug": "summary-doc",
                    "title": "Summary",
                    "category": "Runtime",
                    "summary": "Summary fixture",
                    "tags": [],
                    "kind": "curated_doc",
                }
            ],
            [fixture],
            ["summary-doc", "runtime-showcase"],
        )

        self.assertEqual(doc_slugs, ["summary-doc"])
        self.assertEqual([entry.slug for entry in fixtures], ["runtime-showcase"])

    def test_test_blueprint_catalog_rejects_cross_catalog_slug_collisions(self) -> None:
        fixture = StandaloneTestBlueprint(
            slug="shared",
            title="Standalone",
            category="Runtime",
            summary="Standalone fixture",
            tags=(),
            project_root="tests/test_blueprints/shared",
            build_command=None,
            generate_command=VBP_BUILD_OUTPUT_COMMAND,
            panel_regression_script=None,
            browser_tests_path=None,
        )
        curated = [
            {
                "slug": "shared",
                "title": "Curated",
                "category": "Runtime",
                "summary": "Curated fixture",
                "tags": [],
                "kind": "curated_doc",
            }
        ]

        with self.assertRaisesRegex(ValueError, "declared by both"):
            blueprint_meta_by_slug(curated, [fixture])

    def test_generate_test_blueprint_outputs_prunes_only_full_generation(self) -> None:
        fixture = StandaloneTestBlueprint(
            slug="runtime-showcase",
            title="Runtime Showcase",
            category="Runtime",
            summary="Runtime summary",
            tags=(),
            project_root="tests/test_blueprints/runtime-showcase",
            build_command=None,
            generate_command=VBP_BUILD_OUTPUT_COMMAND,
            panel_regression_script=None,
            browser_tests_path=None,
        )
        originals = {
            "list_curated_test_doc_meta": test_blueprints_mod.list_curated_test_doc_meta,
            "generate_curated_test_doc": test_blueprints_mod.generate_curated_test_doc,
            "generate_standalone_test_blueprint": test_blueprints_mod.generate_standalone_test_blueprint,
        }
        generated: list[tuple[str, str]] = []
        metadata_calls: list[Path] = []
        try:
            def fake_curated_meta(package_root, _categories):
                metadata_calls.append(package_root)
                return [
                    {
                        "slug": "summary-doc",
                        "title": "summary-doc",
                        "category": "Runtime",
                        "summary": "summary",
                        "tags": [],
                        "kind": "curated_doc",
                    }
                ]

            test_blueprints_mod.list_curated_test_doc_meta = fake_curated_meta
            test_blueprints_mod.generate_curated_test_doc = (
                lambda _package_root, slug, _output_dir: generated.append(("doc", slug))
            )
            test_blueprints_mod.generate_standalone_test_blueprint = (
                lambda _package_root, standalone, _output_dir: generated.append(("standalone", standalone.slug))
            )

            with tempfile.TemporaryDirectory() as tmp:
                output_root = Path(tmp) / "test-blueprints"
                (output_root / "stale-fixture").mkdir(parents=True)
                generate_test_blueprint_outputs(
                    PACKAGE_ROOT,
                    ("Runtime",),
                    [fixture],
                    output_root,
                    [],
                )

                self.assertFalse((output_root / "stale-fixture").exists())
                self.assertEqual(metadata_calls, [PACKAGE_ROOT])
                self.assertEqual(generated, [("doc", "summary-doc"), ("standalone", "runtime-showcase")])
                html = (output_root / "index.html").read_text(encoding="utf-8")
                self.assertIn("./summary-doc/html-multi/", html)
                self.assertIn("./runtime-showcase/html-multi/", html)
        finally:
            for name, value in originals.items():
                setattr(test_blueprints_mod, name, value)

    def test_validate_test_blueprint_outputs_runs_generation_and_regressions(self) -> None:
        fixture = StandaloneTestBlueprint(
            slug="runtime-showcase",
            title="Runtime Showcase",
            category="Runtime",
            summary="Runtime summary",
            tags=(),
            project_root="tests/test_blueprints/runtime-showcase",
            build_command=None,
            generate_command=VBP_BUILD_OUTPUT_COMMAND,
            panel_regression_script="tests/harness/runtime/check.py",
            browser_tests_path="tests/browser",
        )
        originals = {
            "generate_test_blueprint_outputs": test_blueprints_mod.generate_test_blueprint_outputs,
            "run_capturing_failure": validation_mod.run_capturing_failure,
        }
        calls: list[tuple[str, object]] = []
        try:
            test_blueprints_mod.generate_test_blueprint_outputs = (
                lambda _package_root, _categories, _fixtures, output_root, requested: calls.append(
                    ("generate", (output_root, requested))
                )
            )
            validation_mod.run_capturing_failure = (
                lambda step, command, cwd: calls.append(("run", (step, command, cwd))) or None
            )

            with tempfile.TemporaryDirectory() as tmp:
                output_root = Path(tmp) / "test-blueprints"
                result = validate_test_blueprint_outputs(
                    PACKAGE_ROOT,
                    ("Runtime",),
                    [fixture],
                    output_root,
                    ["-k", "preview"],
                )

            self.assertEqual(result, 0)
            self.assertEqual(calls[0], ("generate", (output_root, [])))
            self.assertEqual(calls[1][0], "run")
            self.assertEqual(calls[1][1][0], "runtime-showcase panel regression")
            self.assertEqual(calls[2][0], "run")
            self.assertEqual(calls[2][1][0], "runtime-showcase browser tests")
            self.assertIn("-k", calls[2][1][1])
            self.assertIn("preview", calls[2][1][1])
        finally:
            test_blueprints_mod.generate_test_blueprint_outputs = originals["generate_test_blueprint_outputs"]
            validation_mod.run_capturing_failure = originals["run_capturing_failure"]

    def test_validate_test_blueprint_outputs_stops_on_first_failure(self) -> None:
        fixture = StandaloneTestBlueprint(
            slug="runtime-showcase",
            title="Runtime Showcase",
            category="Runtime",
            summary="Runtime summary",
            tags=(),
            project_root="tests/test_blueprints/runtime-showcase",
            build_command=None,
            generate_command=VBP_BUILD_OUTPUT_COMMAND,
            panel_regression_script="tests/harness/runtime/check.py",
            browser_tests_path="tests/browser",
        )
        originals = {
            "generate_test_blueprint_outputs": test_blueprints_mod.generate_test_blueprint_outputs,
            "run_capturing_failure": validation_mod.run_capturing_failure,
        }
        calls: list[str] = []
        try:
            test_blueprints_mod.generate_test_blueprint_outputs = lambda *_args: None
            validation_mod.run_capturing_failure = (
                lambda step, _command, cwd: calls.append(step) or StepFailure(step, "failed")
            )

            with tempfile.TemporaryDirectory() as tmp:
                result = validate_test_blueprint_outputs(
                    PACKAGE_ROOT,
                    ("Runtime",),
                    [fixture],
                    Path(tmp) / "test-blueprints",
                    [],
                    stop_on_first_failure=True,
                )

            self.assertEqual(result, 1)
            self.assertEqual(calls, ["runtime-showcase panel regression"])
        finally:
            test_blueprints_mod.generate_test_blueprint_outputs = originals["generate_test_blueprint_outputs"]
            validation_mod.run_capturing_failure = originals["run_capturing_failure"]


if __name__ == "__main__":
    unittest.main()
