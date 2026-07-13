from __future__ import annotations

from pathlib import Path
import unittest


PACKAGE_ROOT = Path(__file__).resolve().parents[2]
SKILL_ROOT = PACKAGE_ROOT / "skills" / "verso-blueprint"


class VersoBlueprintSkillTests(unittest.TestCase):
    def test_skill_frontmatter_and_references_are_present(self) -> None:
        skill = SKILL_ROOT / "SKILL.md"
        text = skill.read_text(encoding="utf-8")
        self.assertTrue(text.startswith("---\n"))
        self.assertIn("name: verso-blueprint", text)
        self.assertIn("description: Work with Verso Blueprint Lean projects.", text)
        self.assertIn("references/vbp.md", text)
        self.assertIn("references/authoring-patterns.md", text)
        self.assertIn("JSON shapes as unstable", text)
        self.assertNotIn("TODO", text)

    def test_vbp_reference_documents_public_surface(self) -> None:
        text = (SKILL_ROOT / "references" / "vbp.md").read_text(encoding="utf-8")
        self.assertIn("lake exe vbp build [--output <dir>] [--pdf] [--verbose] [--serve] [--port <n>]", text)
        self.assertIn("Pass `--pdf` to build `_out/site/pdf/main.pdf` from the generated TeX.", text)
        self.assertIn("`build --verbose` passes `--verbose` through to the generator run", text)
        self.assertIn("lake exe vbp query [--site <dir>] <selector>", text)
        self.assertIn("lake lean <GeneratorMain>.lean", text)
        self.assertIn("lake lean <GeneratorMain>.lean -- --run <GeneratorMain>.lean --output <output>", text)
        self.assertIn("selectors`: query selector forms", text)
        self.assertIn("does not require generated Blueprint data", text)
        self.assertIn("all <label>", text)
        self.assertIn("search <text>", text)
        self.assertIn("case-insensitively", text)
        self.assertIn("code <decl>", text)
        self.assertIn("stats", text)
        self.assertIn("used-by <label>", text)
        self.assertIn("Pass `--output <dir>` only", text)
        self.assertIn("Pass `--site <dir>`", text)
        self.assertIn("`--port` is accepted only with `--serve`", text)
        self.assertIn('"apiStability":"unstable"', text)
        self.assertIn("discoveryErrors", text)
        self.assertIn("Query reads the semantic manifest only", text)
        self.assertIn("topLevelBlueprintModuleGuess", text)
        self.assertIn("chapterCandidateGuesses", text)
        self.assertIn("fully unstable", text)
        self.assertIn("Fallback Without `vbp`", text)

    def test_vbp_reference_documents_build_check_boundary(self) -> None:
        text = (SKILL_ROOT / "references" / "vbp.md").read_text(encoding="utf-8")
        self.assertIn("post-build generated-data health check", text)
        self.assertIn("does not replace `build`", text)
        self.assertIn("Lean/Lake compilation", text)

    def test_vbp_reference_documents_adoption_boundary(self) -> None:
        text = (SKILL_ROOT / "references" / "vbp.md").read_text(encoding="utf-8")
        self.assertIn("lake exe vbp discover", text)
        self.assertIn("lake lean <GeneratorMain>.lean -- --run <GeneratorMain>.lean", text)
        self.assertIn("fully unstable", text)

    def test_readme_marks_vbp_json_unstable(self) -> None:
        text = (PACKAGE_ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("Treat `vbp` query JSON as an unstable", text)
        self.assertIn("not a public compatibility contract", " ".join(text.split()))

    def test_maintainer_guide_records_vbp_boundary(self) -> None:
        text = (PACKAGE_ROOT / "doc" / "MAINTAINER_GUIDE.md").read_text(encoding="utf-8")
        self.assertIn("Agent-Facing `vbp` Helper", text)
        self.assertIn("fully unstable", text)
        self.assertIn("lake exe vbp query selectors", text)

    def test_authoring_reference_records_dependency_guardrails(self) -> None:
        text = (SKILL_ROOT / "references" / "authoring-patterns.md").read_text(encoding="utf-8")
        self.assertIn('Use `{uses "target"}[]`', text)
        self.assertIn('Use `{bpref "target"}[]`', text)
        self.assertIn("Statement and proof dependencies are separate.", text)
        self.assertIn("Do not rename existing labels casually", text)

    def test_openai_metadata_matches_skill(self) -> None:
        text = (SKILL_ROOT / "agents" / "openai.yaml").read_text(encoding="utf-8")
        self.assertIn('display_name: "Verso Blueprint"', text)
        self.assertIn('short_description: "Work with Verso Blueprint projects"', text)
        self.assertIn('default_prompt: "Use $verso-blueprint', text)


if __name__ == "__main__":
    unittest.main()
