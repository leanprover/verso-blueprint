from __future__ import annotations

from pathlib import Path
import unittest

from tests.preview_runtime_api import (
    BLUEPRINT_SRC,
    RUNTIME_BOOTSTRAP_JS,
    blueprint_js_files,
    blueprint_js_source,
    documented_bundled_helper_methods,
    documented_stable_api_methods,
    esm_named_exports,
    js_object_keys,
    js_object_methods,
)

PACKAGE_ROOT = Path(__file__).resolve().parents[2]
API_DOC = PACKAGE_ROOT / "doc" / "API.md"
DESIGN_RATIONALE = PACKAGE_ROOT / "doc" / "DESIGN_RATIONALE.md"
INTERNAL_ONLY_HELPERS = {
    "bindCloseOnce",
    "bindDismissHandlers",
    "bindHoverablePanelLifetime",
    "bindPanelRepositioner",
    "bindTemplatePreview",
    "bindTemplatePreviewDescriptor",
    "bindTemplatePreviewDescriptors",
    "pointerWithinPanel",
    "positionAnchoredPanel",
    "readHtml",
    "readPanelBehavior",
    "readBlueprintManifestEntry",
    "readBlueprintHtmlCacheEntry",
    "renderHtmlInto",
    "resetPanelPosition",
    "shouldKeepOpen",
}
PREVIEW_ESM_EXTRA_EXPORTS = {
    "currentRenderApi",
    "getRenderApi",
    "normalizeGraphData",
    "onRenderReady",
    "ready",
    "version",
}
GRAPH_CORE_HELPERS = {
    "dataUrl",
    "graphCanvasFor",
    "readGraphJsonScript",
    "graphFallbackVariants",
    "normalizeGraphData",
    "graphsFromManifest",
    "getGraphData",
    "getGraphVariants",
    "loadJson",
    "loadManifestGraphs",
    "loadGraphs",
}
GRAPH_CORE_IMPLEMENTATION_HELPERS = {
    "dataUrl",
    "graphCanvasFor",
    "readGraphJsonScript",
    "graphFallbackVariants",
    "normalizeGraphData",
    "graphsFromManifest",
    "getGraphData",
    "getGraphVariants",
    "loadJson",
}


class PreviewRuntimeApiDocsTests(unittest.TestCase):
    def test_api_stable_api_table_matches_runtime_source(self) -> None:
        runtime = blueprint_js_source()
        api_doc = API_DOC.read_text(encoding="utf-8")

        source_methods = js_object_methods(runtime, "stableCustomClientApi")
        documented_methods = documented_stable_api_methods(api_doc)

        self.assertEqual(documented_methods, source_methods)
        self.assertIn("`window.VersoBlueprint.onRenderReady(callback)`", api_doc)
        self.assertIn("namespace.onRenderReady = onRenderReady", runtime)

    def test_api_stable_api_table_excludes_bundled_feature_helpers(self) -> None:
        runtime = blueprint_js_source()
        api_doc = API_DOC.read_text(encoding="utf-8")

        documented_methods = documented_stable_api_methods(api_doc)
        helper_methods = js_object_methods(runtime, "bundledFeatureRenderHelpers")

        self.assertFalse(documented_methods & helper_methods)

    def test_api_bundled_helper_table_matches_runtime_source(self) -> None:
        runtime = blueprint_js_source()
        api_doc = API_DOC.read_text(encoding="utf-8")

        helper_methods = js_object_methods(runtime, "bundledFeatureRenderHelpers")
        documented_methods = documented_bundled_helper_methods(api_doc)

        self.assertEqual(documented_methods, helper_methods)

    def test_runtime_api_tiers_remain_disjoint(self) -> None:
        runtime = blueprint_js_source()

        source_methods = js_object_methods(runtime, "stableCustomClientApi")
        helper_methods = js_object_methods(runtime, "bundledFeatureRenderHelpers")

        self.assertFalse(source_methods & helper_methods)

    def test_preview_esm_exports_stable_custom_client_api(self) -> None:
        runtime = blueprint_js_source()
        source = (BLUEPRINT_SRC / "blueprint-preview-api.mjs").read_text(encoding="utf-8")

        stable_methods = js_object_methods(runtime, "stableCustomClientApi")
        named_exports = esm_named_exports(source)
        default_methods = js_object_keys(source, "previewApi")
        helper_methods = js_object_methods(runtime, "bundledFeatureRenderHelpers")

        self.assertLessEqual(stable_methods, named_exports)
        self.assertLessEqual(stable_methods, default_methods)
        self.assertEqual(named_exports, stable_methods | PREVIEW_ESM_EXTRA_EXPORTS)
        self.assertEqual(default_methods, stable_methods | PREVIEW_ESM_EXTRA_EXPORTS)
        self.assertFalse(named_exports & helper_methods)
        self.assertFalse(default_methods & helper_methods)

    def test_internal_runtime_helpers_are_not_exported(self) -> None:
        runtime = blueprint_js_source()

        source_methods = js_object_methods(runtime, "stableCustomClientApi")
        helper_methods = js_object_methods(runtime, "bundledFeatureRenderHelpers")

        self.assertFalse(INTERNAL_ONLY_HELPERS & source_methods)
        self.assertFalse(INTERNAL_ONLY_HELPERS & helper_methods)

    def test_template_preview_descriptors_are_runtime_bound(self) -> None:
        runtime = blueprint_js_source()

        self.assertIn("function bindTemplatePreviewDescriptor(root)", runtime)
        self.assertIn("function bindTemplatePreviewDescriptors(root)", runtime)
        self.assertIn('const selector = "[data-bp-template-preview-root]";', runtime)
        self.assertIn("bindTemplatePreviewDescriptors(document);", runtime)
        self.assertNotIn("bindTemplatePreviewRoots", runtime)

    def test_preview_runtime_state_stays_runtime_local(self) -> None:
        runtime = blueprint_js_source()

        self.assertIn("const previewHydrators = new Map();", runtime)
        self.assertNotIn("window.bpPreviewHydrators", runtime)
        self.assertNotIn("window.bpPreviewTrace", runtime)

    def test_preview_runtime_component_boundaries_are_named(self) -> None:
        runtime = blueprint_js_source()

        for marker in (
            "Generated-data URL helpers and graph delegation.",
            "Manifest/cache status, loading, and diagnostics.",
            "Preview resolution joins semantic manifest entries with opaque body fragments.",
            "Canonical generated-node rendering.",
            "Bundled preview surface and lifecycle helpers.",
            "API assembly and readiness synchronization.",
        ):
            self.assertIn(marker, runtime)

    def test_design_rationale_explains_html_cache_boundary(self) -> None:
        design = DESIGN_RATIONALE.read_text(encoding="utf-8")

        self.assertIn("### Body Fragments vs Full Node Wrappers", design)
        self.assertIn(
            "The rendered-fragment cache should not grow into a second node-wrapper cache",
            design,
        )
        self.assertIn("renderCanonicalPreviewInto", design)
        self.assertIn("manifestEntry.href", design)

    def test_slide_runtime_uses_verso_blueprint_namespace(self) -> None:
        runtime = (BLUEPRINT_SRC / "Slides" / "blueprint-slides.js").read_text(
            encoding="utf-8"
        )

        self.assertIn("namespace.slides = slideRuntime", runtime)
        self.assertIn("slideRuntime.hydrate = hydrateWhenReady", runtime)
        self.assertNotIn("window.bpSlideNodeRuntime", runtime)
        self.assertNotIn("window.bpSlideNodeRuntimeConfig", runtime)

    def test_feature_js_uses_render_ready_instead_of_direct_runtime_reads(self) -> None:
        direct_runtime_reads: list[str] = []
        missing_ready_callbacks: list[str] = []

        for path in blueprint_js_files():
            relative_path = path.relative_to(BLUEPRINT_SRC)
            if relative_path in RUNTIME_BOOTSTRAP_JS:
                continue
            source = path.read_text(encoding="utf-8")
            display_path = relative_path.as_posix()
            if "window.VersoBlueprint.render" in source:
                direct_runtime_reads.append(display_path)
            if (
                "window.VersoBlueprint" in source
                and "window.VersoBlueprint.onRenderReady(" not in source
            ):
                missing_ready_callbacks.append(display_path)

        self.assertEqual([], direct_runtime_reads)
        self.assertEqual([], missing_ready_callbacks)

    def test_graph_helpers_are_owned_by_graph_core(self) -> None:
        core = (BLUEPRINT_SRC / "blueprint-graph-core.js").read_text(encoding="utf-8")
        graph_esm = (BLUEPRINT_SRC / "blueprint-graph-api.mjs").read_text(encoding="utf-8")
        runtime = (BLUEPRINT_SRC / "Commands" / "preview-runtime.js").read_text(
            encoding="utf-8"
        )

        self.assertIn('import "./blueprint-graph-core.js";', graph_esm)
        self.assertIn("callBlueprintGraphApi", runtime)
        for helper in GRAPH_CORE_HELPERS:
            self.assertIn(f"function {helper}", core)
            self.assertNotIn(f"function {helper}", graph_esm)
        for helper in GRAPH_CORE_IMPLEMENTATION_HELPERS:
            self.assertNotIn(f"function {helper}", runtime)


if __name__ == "__main__":
    unittest.main()
