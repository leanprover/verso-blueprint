from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from scripts.blueprint_harness_projects import default_project_manifest, load_project_catalog


PACKAGE_ROOT = Path(__file__).resolve().parents[2]


class PrepareReferenceBlueprintPagesTests(unittest.TestCase):
    def write_minimal_inputs(self, root: Path) -> tuple[Path, Path]:
        reference_root = root / "reference-blueprints"
        test_root = root / "test-blueprints"

        (reference_root / "project-template" / "html-multi").mkdir(parents=True)
        (reference_root / "project-template" / "html-multi" / "index.html").write_text(
            "reference project template",
            encoding="utf-8",
        )
        (test_root / "preview_runtime_showcase" / "html-multi").mkdir(parents=True)
        (test_root / "preview_runtime_showcase" / "html-multi" / "index.html").write_text(
            "test showcase",
            encoding="utf-8",
        )
        return reference_root, test_root

    def run_helper(
        self,
        reference_root: Path,
        test_root: Path,
        output_root: Path,
        *,
        js_api_docs_root: Path | None = None,
    ) -> subprocess.CompletedProcess[str]:
        command = [
            sys.executable,
            "scripts/prepare_reference_blueprints_pages.py",
            "--reference-root",
            str(reference_root),
            "--test-root",
            str(test_root),
            "--output-root",
            str(output_root),
        ]
        if js_api_docs_root is not None:
            command.extend(["--js-api-docs-root", str(js_api_docs_root)])
        return subprocess.run(
            command,
            cwd=PACKAGE_ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_prepare_pages_stages_reference_and_test_blueprints(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            reference_root = tmp_path / "reference-blueprints"
            test_root = tmp_path / "test-blueprints"
            output_root = tmp_path / "_site"

            (reference_root / "project-template" / "html-multi").mkdir(parents=True)
            (reference_root / "project-template" / "html-multi" / "index.html").write_text(
                "reference project template",
                encoding="utf-8",
            )
            (reference_root / "noperthedron" / "html-multi").mkdir(parents=True)
            (reference_root / "noperthedron" / "html-multi" / "index.html").write_text(
                "reference noperthedron",
                encoding="utf-8",
            )

            (test_root / "preview_runtime_showcase" / "html-multi").mkdir(parents=True)
            (test_root / "preview_runtime_showcase" / "html-multi" / "index.html").write_text(
                "test showcase",
                encoding="utf-8",
            )
            (test_root / "summary-blockers" / "html-multi").mkdir(parents=True)
            (test_root / "summary-blockers" / "html-multi" / "index.html").write_text(
                "summary blockers",
                encoding="utf-8",
            )
            (test_root / "index.html").write_text("test index", encoding="utf-8")

            result = self.run_helper(reference_root, test_root, output_root)
            self.assertEqual(result.returncode, 0, msg=result.stderr)

            self.assertEqual(
                (output_root / "reference-blueprints" / "project-template" / "index.html").read_text(encoding="utf-8"),
                "reference project template",
            )
            self.assertEqual(
                (output_root / "test-blueprints" / "preview_runtime_showcase" / "html-multi" / "index.html").read_text(
                    encoding="utf-8"
                ),
                "test showcase",
            )
            self.assertEqual(
                (output_root / "test-blueprints" / "index.html").read_text(encoding="utf-8"),
                "test index",
            )

            landing_index = (output_root / "index.html").read_text(encoding="utf-8")
            self.assertIn("reference-blueprints/project-template/", landing_index)
            self.assertIn("reference-blueprints/noperthedron/", landing_index)
            self.assertIn("Open reference blueprint index", landing_index)
            self.assertIn("test-blueprints/", landing_index)
            self.assertIn("test-blueprints/preview_runtime_showcase/html-multi/", landing_index)

            reference_index = (output_root / "reference-blueprints" / "index.html").read_text(encoding="utf-8")
            self.assertIn('href="project-template/"', reference_index)
            self.assertIn('href="noperthedron/"', reference_index)
            self.assertNotIn("reference-blueprints/project-template/", reference_index)
            self.assertNotIn("js-api/", landing_index)

    def test_prepare_pages_stages_javascript_api_docs_when_requested(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            js_api_docs_root = tmp_path / "jsdoc-api"
            output_root = tmp_path / "_site"

            reference_root, test_root = self.write_minimal_inputs(tmp_path)
            js_api_docs_root.mkdir()
            (js_api_docs_root / "index.html").write_text("js api docs", encoding="utf-8")
            (js_api_docs_root / "module-blueprint-preview-api.html").write_text(
                "preview api",
                encoding="utf-8",
            )

            result = self.run_helper(
                reference_root,
                test_root,
                output_root,
                js_api_docs_root=js_api_docs_root,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)

            self.assertEqual(
                (output_root / "js-api" / "index.html").read_text(encoding="utf-8"),
                "js api docs",
            )
            self.assertEqual(
                (output_root / "js-api" / "module-blueprint-preview-api.html").read_text(encoding="utf-8"),
                "preview api",
            )
            landing_index = (output_root / "index.html").read_text(encoding="utf-8")
            self.assertIn("JavaScript API", landing_index)
            self.assertIn('href="js-api/"', landing_index)
            self.assertIn("JavaScript API docs assembled", landing_index)

    def test_prepare_pages_rejects_missing_javascript_api_docs_root(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            reference_root, test_root = self.write_minimal_inputs(tmp_path)
            output_root = tmp_path / "_site"

            result = self.run_helper(
                reference_root,
                test_root,
                output_root,
                js_api_docs_root=tmp_path / "missing-jsdoc-api",
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing JavaScript API docs root", result.stderr)

    def test_prepare_pages_rejects_javascript_api_docs_without_index(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            reference_root, test_root = self.write_minimal_inputs(tmp_path)
            js_api_docs_root = tmp_path / "jsdoc-api"
            output_root = tmp_path / "_site"
            js_api_docs_root.mkdir()

            result = self.run_helper(
                reference_root,
                test_root,
                output_root,
                js_api_docs_root=js_api_docs_root,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("JavaScript API docs root is missing index.html", result.stderr)

    def test_prepare_pages_stages_release_namespaced_reference_blueprints(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            reference_root = tmp_path / "reference-blueprints"
            test_root = tmp_path / "test-blueprints"
            output_root = tmp_path / "_site"

            (reference_root / "v4.28.0" / "project-template" / "html-multi").mkdir(parents=True)
            (reference_root / "v4.28.0" / "project-template" / "html-multi" / "index.html").write_text(
                "reference project template v4.28.0",
                encoding="utf-8",
            )
            (reference_root / "v4.29.0" / "project-template" / "html-multi").mkdir(parents=True)
            (reference_root / "v4.29.0" / "project-template" / "html-multi" / "index.html").write_text(
                "reference project template v4.29.0",
                encoding="utf-8",
            )
            (reference_root / "v4.29.0" / "noperthedron" / "html-multi").mkdir(parents=True)
            (reference_root / "v4.29.0" / "noperthedron" / "html-multi" / "index.html").write_text(
                "reference noperthedron v4.29.0",
                encoding="utf-8",
            )

            (test_root / "preview_runtime_showcase" / "html-multi").mkdir(parents=True)
            (test_root / "preview_runtime_showcase" / "html-multi" / "index.html").write_text(
                "test showcase",
                encoding="utf-8",
            )
            (test_root / "index.html").write_text("test index", encoding="utf-8")

            result = self.run_helper(reference_root, test_root, output_root)
            self.assertEqual(result.returncode, 0, msg=result.stderr)

            self.assertEqual(
                (
                    output_root
                    / "reference-blueprints"
                    / "v4.28.0"
                    / "project-template"
                    / "index.html"
                ).read_text(encoding="utf-8"),
                "reference project template v4.28.0",
            )
            self.assertEqual(
                (
                    output_root
                    / "reference-blueprints"
                    / "v4.29.0"
                    / "noperthedron"
                    / "index.html"
                ).read_text(encoding="utf-8"),
                "reference noperthedron v4.29.0",
            )

            release_index = (output_root / "reference-blueprints" / "index.html").read_text(encoding="utf-8")
            self.assertIn('href="v4.28.0/"', release_index)
            self.assertIn('href="v4.29.0/"', release_index)
            self.assertNotIn("reference-blueprints/v4.28.0/", release_index)
            self.assertFalse((output_root / "reference-blueprints" / "project-template").exists())

            release_project_index = (
                output_root / "reference-blueprints" / "v4.29.0" / "index.html"
            ).read_text(encoding="utf-8")
            self.assertIn('href="project-template/"', release_project_index)
            self.assertIn('href="noperthedron/"', release_project_index)
            self.assertNotIn("reference-blueprints/v4.29.0/noperthedron/", release_project_index)

            alias_index = (output_root / "reference-blueprints" / "noperthedron" / "index.html").read_text(
                encoding="utf-8"
            )
            self.assertIn("../v4.29.0/noperthedron/", alias_index)

            landing_index = (output_root / "index.html").read_text(encoding="utf-8")
            self.assertIn("reference-blueprints/v4.28.0/", landing_index)
            self.assertIn("reference-blueprints/v4.29.0/", landing_index)

    def test_readme_uses_release_namespaced_reference_links(self) -> None:
        readme = (PACKAGE_ROOT / "README.md").read_text(encoding="utf-8")
        catalog = load_project_catalog(default_project_manifest(PACKAGE_ROOT))

        for project in catalog.projects:
            self.assertNotIn(f"reference-blueprints/{project.project_id}/", readme)
            for target in project.targets:
                if target.publish_reference:
                    self.assertIn(f"reference-blueprints/{target.release}/{project.project_id}/", readme)

        self.assertNotIn("reference-blueprints/v4.31.0/project-template/", readme)
        self.assertNotIn("reference-blueprints/v4.32.0/project-template/", readme)

    def test_project_template_readme_does_not_link_unpublished_render(self) -> None:
        readme = (PACKAGE_ROOT / "project_template" / "README.md").read_text(encoding="utf-8")

        self.assertNotIn("reference-blueprints/project-template/", readme)
        self.assertIn("_out/site/html-multi/", readme)


if __name__ == "__main__":
    unittest.main()
