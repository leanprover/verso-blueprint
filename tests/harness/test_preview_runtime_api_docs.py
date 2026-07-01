from __future__ import annotations

import json
from pathlib import Path
import re
import unittest

from tests.preview_runtime_api import (
    BLUEPRINT_SRC,
    PACKAGE_ROOT,
    PUBLIC_API_JSDOC_SOURCES,
    PUBLIC_API_MODULES,
    PUBLIC_API_PACKAGE_EXPORTS,
    PUBLIC_API_TYPE_EXPORTS,
    PUBLIC_DATA_API_EXPORTS,
    PUBLIC_GENERATED_API_MODULES,
    PUBLIC_GRAPH_API_EXPORTS,
    PUBLIC_PREVIEW_API_EXPORTS,
    RUNTIME_BOOTSTRAP_JS,
    blueprint_js_files,
    blueprint_js_source,
    documented_bundled_helper_methods,
    documented_stable_api_methods,
    esm_named_exports,
    js_object_keys,
    js_object_methods,
)

API_DOC = PACKAGE_ROOT / "doc" / "API.md"
DESIGN_RATIONALE = PACKAGE_ROOT / "doc" / "DESIGN_RATIONALE.md"
JSDOC_CONFIG = PACKAGE_ROOT / "jsdoc.json"
JSDOC_TYPE_NAMES = PACKAGE_ROOT / "doc" / "jsdoc-static" / "jsdoc-type-names.js"
PACKAGE_JSON = PACKAGE_ROOT / "package.json"
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
GRAPH_CORE_HELPERS = {
    "dataUrl",
    "graphCanvasFor",
    "readGraphJsonScript",
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
    "normalizeGraphData",
    "graphsFromManifest",
    "getGraphData",
    "getGraphVariants",
    "loadJson",
}
PREVIEW_CORE_HELPERS = {
    "dataUrl",
    "manifestUrl",
    "htmlCacheUrl",
    "dataApiModuleUrl",
    "graphApiModuleUrl",
    "previewApiModuleUrl",
    "previewKey",
    "statementPreviewKey",
}
GRAPH_RUNTIME_CORE_HELPERS = {
    "debounce",
    "normalizeGraphOptions",
    "graphPackAttr",
    "graphOptionsKey",
    "graphLayoutMode",
    "readPreviewBehaviorDefaults",
    "layoutGraphCanvas",
    "load",
    "graphNodeLabel",
    "graphNodeId",
    "ensureGraphBlockState",
    "rememberGraphLayoutMeasurements",
    "resizeRenderedGraphToCanvas",
    "resetGraphvizForVariant",
    "makeGroupPanelPositioner",
}


class PreviewRuntimeApiDocsTests(unittest.TestCase):
    def test_package_json_exports_only_public_js_api_modules(self) -> None:
        package = json.loads(PACKAGE_JSON.read_text(encoding="utf-8"))

        preview_entry = PUBLIC_API_MODULES["preview"]
        self.assertEqual(package["type"], "module")
        self.assertEqual(package["main"], f"./{preview_entry['source']}")
        self.assertEqual(package["module"], f"./{preview_entry['source']}")
        self.assertEqual(package["types"], f"./{preview_entry['declaration']}")
        self.assertEqual(set(package["exports"]), set(PUBLIC_API_PACKAGE_EXPORTS))
        for export_name, entry in PUBLIC_API_PACKAGE_EXPORTS.items():
            self.assertEqual(
                package["exports"][export_name],
                {
                    "types": f"./{entry['declaration']}",
                    "import": f"./{entry['source']}",
                },
            )

    def test_jsdoc_documents_only_public_js_api_modules(self) -> None:
        jsdoc_config = json.loads(JSDOC_CONFIG.read_text(encoding="utf-8"))
        source_includes = set(jsdoc_config["source"]["include"])

        self.assertEqual(source_includes, PUBLIC_API_JSDOC_SOURCES)
        self.assertEqual(
            jsdoc_config["docdash"]["scripts"],
            ["jsdoc-type-names.js", "jsdoc-type-links.js"],
        )
        self.assertFalse(any("/Commands/" in source for source in source_includes))
        self.assertFalse(any(source.endswith("-core.mjs") for source in source_includes))
        self.assertFalse(any(source.endswith("-common.mjs") for source in source_includes))

    def test_jsdoc_type_linker_matches_public_type_contract(self) -> None:
        source = JSDOC_TYPE_NAMES.read_text(encoding="utf-8")
        match = re.search(r"\bglobalScope\.blueprintJSDocTypeNames\s*=\s*\[([\s\S]*?)\];", source)

        self.assertIsNotNone(match)
        type_names = set(re.findall(r'"([^"]+)"', match.group(1)))
        self.assertEqual(type_names, PUBLIC_API_TYPE_EXPORTS)

    def test_api_doc_module_table_matches_public_generated_modules(self) -> None:
        api_doc = API_DOC.read_text(encoding="utf-8")
        js_api_docs = (PACKAGE_ROOT / "doc" / "JS_API_DOCS.md").read_text(
            encoding="utf-8"
        )

        documented_modules = set(
            re.findall(r"\| `(api/[A-Za-z][A-Za-z0-9_-]*\.mjs)` \|", api_doc)
        )
        self.assertEqual(documented_modules, PUBLIC_GENERATED_API_MODULES)
        self.assertIn("Only the files listed in this table are public", api_doc)
        for entry in PUBLIC_API_MODULES.values():
            self.assertIn(entry["jsdoc_page"], js_api_docs)
        self.assertIn("Start from the kind of client you are writing", js_api_docs)
        self.assertIn("## Rendering Paths", js_api_docs)
        self.assertIn("api/preview.mjs", js_api_docs)
        self.assertIn("api/data.mjs", js_api_docs)
        self.assertIn("api/graph.mjs", js_api_docs)

    def test_api_stable_api_table_matches_runtime_source(self) -> None:
        runtime = blueprint_js_source()
        api_doc = API_DOC.read_text(encoding="utf-8")

        source_methods = js_object_methods(runtime, "stableCustomClientApi")
        documented_methods = documented_stable_api_methods(api_doc)

        self.assertEqual(documented_methods, source_methods)
        self.assertIn("`createPreview()`", api_doc)
        self.assertNotIn("namespace.onRenderReady = onRenderReady", runtime)

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

        self.assertLessEqual(stable_methods, PUBLIC_PREVIEW_API_EXPORTS)
        self.assertEqual(named_exports, PUBLIC_PREVIEW_API_EXPORTS)
        self.assertEqual(default_methods, PUBLIC_PREVIEW_API_EXPORTS)
        self.assertFalse(named_exports & helper_methods)
        self.assertFalse(default_methods & helper_methods)

    def test_data_esm_exports_data_only_api(self) -> None:
        source = (BLUEPRINT_SRC / "blueprint-data-api.mjs").read_text(encoding="utf-8")

        named_exports = esm_named_exports(source)
        default_methods = js_object_keys(source, "dataApi")

        self.assertEqual(named_exports, PUBLIC_DATA_API_EXPORTS)
        self.assertEqual(default_methods, PUBLIC_DATA_API_EXPORTS)
        for render_name in (
            "renderPreviewInto",
            "renderCanonicalPreviewInto",
            "renderNode",
            "hydrate",
        ):
            self.assertNotIn(render_name, named_exports)
            self.assertNotIn(render_name, default_methods)
        self.assertIn('from "./Commands/preview-runtime-data.mjs";', source)
        self.assertNotIn('from "./Commands/preview-runtime-render.mjs";', source)

    def test_internal_runtime_helpers_are_not_exported(self) -> None:
        runtime = blueprint_js_source()

        source_methods = js_object_methods(runtime, "stableCustomClientApi")
        helper_methods = js_object_methods(runtime, "bundledFeatureRenderHelpers")

        self.assertFalse(INTERNAL_ONLY_HELPERS & source_methods)
        self.assertFalse(INTERNAL_ONLY_HELPERS & helper_methods)

    def test_template_preview_descriptors_are_runtime_bound(self) -> None:
        runtime = blueprint_js_source()

        self.assertIn("function bindTemplatePreviewDescriptor(root, options)", runtime)
        self.assertIn("function bindTemplatePreviewDescriptors(root, options)", runtime)
        self.assertIn('const selector = "[data-bp-template-preview-root]";', runtime)
        self.assertIn("bindTemplatePreviewDescriptors(root, opts);", runtime)
        self.assertNotIn("bindTemplatePreviewRoots", runtime)

    def test_preview_runtime_state_stays_runtime_local(self) -> None:
        runtime = blueprint_js_source()

        self.assertIn("const localPreviewHydrators = new Map();", runtime)
        self.assertIn("function activePreviewHydrators()", runtime)
        self.assertNotIn("window.bpPreviewHydrators", runtime)
        self.assertNotIn("window.bpPreviewTrace", runtime)

    def test_preview_runtime_component_boundaries_are_named(self) -> None:
        runtime = blueprint_js_source()

        for marker in (
            "Runtime-local diagnostics and page-local template capture.",
            "Generated-data URL helpers.",
            "Manifest/cache status, loading, and diagnostics.",
            "Preview resolution joins semantic manifest entries with opaque body fragments.",
            "Canonical generated-node rendering.",
            "Bundled preview lifecycle helpers.",
            "Bundled preview surface, panel, and content helpers.",
            "Template preview binding adapts the shared helpers to concrete surfaces.",
            "API assembly and readiness synchronization.",
        ):
            self.assertIn(marker, runtime)

    def test_preview_runtime_helpers_live_in_private_chunks(self) -> None:
        common = (BLUEPRINT_SRC / "Commands" / "Common.lean").read_text(
            encoding="utf-8"
        )
        slide_assets = (BLUEPRINT_SRC / "Slides" / "Assets.lean").read_text(
            encoding="utf-8"
        )
        base = (BLUEPRINT_SRC / "Commands" / "preview-runtime-base.mjs").read_text(
            encoding="utf-8"
        )
        data = (BLUEPRINT_SRC / "Commands" / "preview-runtime-data.mjs").read_text(
            encoding="utf-8"
        )
        render = (BLUEPRINT_SRC / "Commands" / "preview-runtime-render.mjs").read_text(
            encoding="utf-8"
        )
        source_metadata = (
            BLUEPRINT_SRC / "Commands" / "preview-runtime-source-metadata.mjs"
        ).read_text(encoding="utf-8")
        hydration = (
            BLUEPRINT_SRC / "Commands" / "preview-runtime-hydration.mjs"
        ).read_text(encoding="utf-8")
        lifecycle = (
            BLUEPRINT_SRC / "Commands" / "preview-runtime-lifecycle.mjs"
        ).read_text(encoding="utf-8")
        surface = (BLUEPRINT_SRC / "Commands" / "preview-runtime-surface.mjs").read_text(
            encoding="utf-8"
        )
        template = (
            BLUEPRINT_SRC / "Commands" / "preview-runtime-template.mjs"
        ).read_text(encoding="utf-8")
        api = (BLUEPRINT_SRC / "Commands" / "preview-runtime-api.mjs").read_text(
            encoding="utf-8"
        )

        for old_common_include_path in (
            "preview-runtime-base.mjs",
            "preview-runtime-data.mjs",
            "preview-runtime-render.mjs",
            "preview-runtime-source-metadata.mjs",
            "preview-runtime-hydration.mjs",
            "preview-runtime-lifecycle.mjs",
            "preview-runtime-surface.mjs",
            "preview-runtime-template.mjs",
            "preview-runtime-api.mjs",
            "blueprint-graph-core.mjs",
            "blueprint-preview-core.mjs",
            "inline-preview.mjs",
        ):
            self.assertNotIn(f'include_str "{old_common_include_path}"', common)
        self.assertIn('include_str "blueprint-slide-runtime.mjs"', slide_assets)
        self.assertIn('include_str "blueprint-slides.mjs"', slide_assets)
        self.assertNotIn("ClassicPreviewAdapter", slide_assets)
        self.assertNotIn("import VersoBlueprint.BrowserAsset", common)
        self.assertNotIn("BrowserAsset", slide_assets)
        self.assertIn("function collectPreviewTemplates(root, selector, keyAttr)", base)
        self.assertIn("function readHtml(entry)", base)
        self.assertIn("function escapeHtml(text)", base)
        self.assertIn("export const previewRuntimeBase = {", base)
        self.assertIn("export function createBlueprintDataApi(options)", data)
        self.assertIn("function loadBlueprintStoreForApi(store, options)", data)
        self.assertIn("function setBlueprintFetchJsonForApi(fetchJson)", data)
        self.assertIn("function previewKey(label, facet)", data)
        self.assertNotIn("function blueprintGraphApi()", data)
        self.assertNotIn("function callBlueprintGraphCore(name, args, fallback)", data)
        self.assertNotIn("function callRuntimeGraphCore(name, args, fallback)", common)
        self.assertIn("export const previewRuntimeData = {", data)
        self.assertIn("function readBlueprintManifestStatusForApi()", data)
        self.assertNotIn("function loadBlueprintStore(store, options)", data)
        self.assertNotIn("function setBlueprintFetchJson(fetchJson)", data)
        self.assertNotIn("function readBlueprintManifestStatus()", data)
        self.assertIn("async function resolveBlueprintPreview(previewKey, options)", render)
        self.assertIn("function renderHtmlInto(target, html, options)", render)
        self.assertIn("async function resolveCanonicalBlueprintPreview(previewKey, options)", render)
        self.assertIn("export const previewRuntimeRender = {", render)
        self.assertIn("async function resolveSourceMetadata(source, options)", source_metadata)
        self.assertNotIn("function renderSourceMetadataInto", source_metadata)
        self.assertNotIn("function sourceMetadataHtml", source_metadata)
        self.assertIn("export const previewRuntimeSourceMetadata = {", source_metadata)
        self.assertNotIn("function sourceMetadataHtml(result, options)", render)
        self.assertIn("function hydrateRenderedPreview(root, options)", hydration)
        self.assertIn("function renderBlueprintMath(root)", hydration)
        self.assertIn("function registerPreviewHydrator(name, fn)", hydration)
        self.assertIn("function setTemplatePreviewDescriptorBinder(fn)", hydration)
        self.assertIn("export const previewRuntimeHydration = {", hydration)
        self.assertIn("function bindDismissHandlers(options)", lifecycle)
        self.assertIn("function bindPreviewTriggers(options)", lifecycle)
        self.assertIn("function bindAnchoredPopover(options)", lifecycle)
        self.assertIn('from "./preview-runtime-base.mjs";', lifecycle)
        self.assertNotIn('from "./preview-runtime-surface.mjs";', lifecycle)
        self.assertIn("export const previewRuntimeLifecycle = {", lifecycle)
        self.assertIn("function createPreviewSurface(options)", surface)
        self.assertIn("async function renderPreviewIntoSurface(surface, previewKey, options)", surface)
        self.assertIn("function previewMessageHtml(options)", surface)
        self.assertIn("export const previewRuntimeSurface = {", surface)
        self.assertIn("async function renderBlueprintNodeInto(target, request, options)", render)
        self.assertIn("function externalMarkupRendererPayload", render)
        self.assertIn("function bindTemplatePreview(options)", template)
        self.assertIn("function bindTemplatePreviewDescriptor(root, options)", template)
        self.assertIn("export const previewRuntimeTemplate = {", template)
        self.assertIn(
            "setTemplatePreviewDescriptorBinder(bindTemplatePreviewDescriptors)",
            template,
        )
        self.assertIn("const stableCustomClientApi = {", api)
        self.assertIn("export function createPreviewRuntimeApi(options)", api)
        self.assertNotIn("export function installPreviewRuntimeApi(options)", api)
        self.assertNotIn("function onRenderReady(fn)", api)
        self.assertIn("renderNode: previewRenderApi.renderNode", api)
        for helper in (
            "function loadBlueprintStoreForApi(store, options)",
            "function previewKey(label, facet)",
            "async function resolveBlueprintPreview(previewKey, options)",
            "function renderBlueprintMath(root)",
            "function createPreviewSurface(options)",
            "function bindTemplatePreview(options)",
        ):
            self.assertNotIn(helper, api)

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
        runtime = (BLUEPRINT_SRC / "Slides" / "blueprint-slides.mjs").read_text(
            encoding="utf-8"
        )

        self.assertIn("namespace.slides = slideRuntime", runtime)
        self.assertIn("runtime.hydrate = function (root)", runtime)
        self.assertIn("export function installBlueprintSlides(previewUtils", runtime)
        self.assertNotIn("window.VersoBlueprint.onRenderReady", runtime)
        self.assertNotIn("window.bpSlideNodeRuntime", runtime)
        self.assertNotIn("window.bpSlideNodeRuntimeConfig", runtime)

    def test_graph_runtime_uses_structured_variants_only(self) -> None:
        runtime = (BLUEPRINT_SRC / "Commands" / "graph.mjs").read_text(
            encoding="utf-8"
        )

        self.assertIn("readPublicGraphVariants(graphBlock)", runtime)
        self.assertIn("coreGetGraphVariants(root)", runtime)
        self.assertIn("export function startGraphRuntime(previewUtils, options)", runtime)
        self.assertNotIn("legacyGraphVariants", runtime)

    def test_regular_page_feature_js_uses_page_runtime_instead_of_window_bridge(self) -> None:
        direct_runtime_reads: list[str] = []
        regular_feature_window_reads: list[str] = []

        for path in blueprint_js_files():
            relative_path = path.relative_to(BLUEPRINT_SRC)
            if relative_path in RUNTIME_BOOTSTRAP_JS or relative_path == Path("Slides/blueprint-slides.mjs"):
                continue
            source = path.read_text(encoding="utf-8")
            display_path = relative_path.as_posix()
            if "window.VersoBlueprint.render" in source:
                direct_runtime_reads.append(display_path)
            if "window.VersoBlueprint" in source:
                regular_feature_window_reads.append(display_path)

        self.assertEqual([], direct_runtime_reads)
        self.assertEqual([], regular_feature_window_reads)

        page_runtime = (BLUEPRINT_SRC / "blueprint-page-runtime.mjs").read_text(
            encoding="utf-8"
        )
        self.assertIn('from "./api/preview.mjs";', page_runtime)
        self.assertIn('from "./Commands/inline-preview.mjs";', page_runtime)
        self.assertIn('from "./Commands/graph.mjs";', page_runtime)
        self.assertIn('from "./Informal/Block/relation-panel.mjs";', page_runtime)
        self.assertNotIn("window.VersoBlueprint", page_runtime)

    def test_graph_helpers_are_owned_by_graph_core(self) -> None:
        core = (BLUEPRINT_SRC / "blueprint-graph-core.mjs").read_text(encoding="utf-8")
        graph_esm = (BLUEPRINT_SRC / "blueprint-graph-api.mjs").read_text(encoding="utf-8")
        graph_runtime = (BLUEPRINT_SRC / "Commands" / "graph.mjs").read_text(
            encoding="utf-8"
        )
        runtime_data = (
            BLUEPRINT_SRC / "Commands" / "preview-runtime-data.mjs"
        ).read_text(encoding="utf-8")
        common = (BLUEPRINT_SRC / "Commands" / "Common.lean").read_text(
            encoding="utf-8"
        )
        runtime = (BLUEPRINT_SRC / "Commands" / "preview-runtime-api.mjs").read_text(
            encoding="utf-8"
        )

        self.assertIn('from "./blueprint-graph-core.mjs";', graph_esm)
        self.assertIn('from "../blueprint-graph-core.mjs";', graph_runtime)
        self.assertEqual(esm_named_exports(graph_esm), PUBLIC_GRAPH_API_EXPORTS)
        self.assertIn(
            'throw new Error("Blueprint graph rendering requires options.previewUtils from createPreview().");',
            graph_esm,
        )
        self.assertNotIn("callRuntimeGraphCore", common)
        self.assertNotIn("VersoBlueprint.__private", common)
        self.assertNotIn("VersoBlueprintGraphCore", common)
        self.assertNotIn("namespace.graphCore = existingCore", core)
        self.assertNotIn("VersoBlueprint.__private", core)
        self.assertNotIn("VersoBlueprintGraphCore", core)
        self.assertNotIn("callBlueprintGraphCore", runtime_data)
        self.assertNotIn("callBlueprintGraphApi", runtime_data)
        self.assertNotIn("window.bpGraphApi", runtime_data)
        for helper in GRAPH_CORE_HELPERS:
            self.assertIn(f"function {helper}", core)
        for helper in GRAPH_CORE_HELPERS - {"getGraphData", "getGraphVariants"}:
            self.assertNotIn(f"function {helper}", graph_esm)
        for helper in GRAPH_CORE_IMPLEMENTATION_HELPERS:
            self.assertNotIn(f"function {helper}", graph_runtime)
            self.assertNotIn(f"function {helper}", runtime)

    def test_preview_helpers_are_owned_by_preview_core(self) -> None:
        core = (BLUEPRINT_SRC / "blueprint-preview-core.mjs").read_text(encoding="utf-8")
        api_common = (BLUEPRINT_SRC / "blueprint-api-common.mjs").read_text(
            encoding="utf-8"
        )
        data_esm = (BLUEPRINT_SRC / "blueprint-data-api.mjs").read_text(
            encoding="utf-8"
        )
        preview_esm = (BLUEPRINT_SRC / "blueprint-preview-api.mjs").read_text(
            encoding="utf-8"
        )
        runtime_data = (BLUEPRINT_SRC / "Commands" / "preview-runtime-data.mjs").read_text(
            encoding="utf-8"
        )
        preview_manifest = (BLUEPRINT_SRC / "PreviewManifest.lean").read_text(
            encoding="utf-8"
        )

        self.assertIn('from "./blueprint-preview-core.mjs";', api_common)
        self.assertIn('from "./blueprint-api-common.mjs";', data_esm)
        self.assertIn('from "./blueprint-api-common.mjs";', preview_esm)
        self.assertIn('from "./Commands/preview-runtime-data.mjs";', data_esm)
        self.assertIn('from "./Commands/preview-runtime-api.mjs";', preview_esm)
        self.assertIn('from "../blueprint-preview-core.mjs";', runtime_data)
        self.assertIn('include_str "blueprint-api-common.mjs"', preview_manifest)
        self.assertIn('include_str "blueprint-data-api.mjs"', preview_manifest)
        self.assertIn('include_str "blueprint-preview-core.mjs"', preview_manifest)
        self.assertIn('include_str "blueprint-page-runtime.mjs"', preview_manifest)
        self.assertIn('include_str "Commands/inline-preview.mjs"', preview_manifest)
        self.assertIn('include_str "Commands/graph.mjs"', preview_manifest)
        self.assertIn('include_str "Informal/Block/relation-panel.mjs"', preview_manifest)
        self.assertIn('include_str "Commands/preview-runtime-api.mjs"', preview_manifest)
        self.assertIn("IO.FS.writeFile (dataDir / previewCoreModuleFilename)", preview_manifest)
        self.assertIn("IO.FS.writeFile (dataDir / apiCommonModuleFilename)", preview_manifest)
        self.assertIn("IO.FS.writeFile (dataDir / dataApiModuleFilename)", preview_manifest)
        self.assertIn("IO.FS.writeFile (apiDir / dataApiModuleAliasFilename)", preview_manifest)
        self.assertIn("writePageRuntimeModules dataDir", preview_manifest)
        self.assertIn("writePreviewRuntimeModules dataDir", preview_manifest)
        for helper in PREVIEW_CORE_HELPERS:
            self.assertIn(f"function {helper}", core)
        for helper in (
            "optionsWithDefaultDataBaseUrl",
            "createDefaultApiHandle",
            "createPreviewUrlApi",
            "fallbackStoreStatus",
            "callDefaultApiSync",
            "callDefaultApi",
        ):
            self.assertIn(f"function {helper}", api_common)
            self.assertNotIn(f"function {helper}", data_esm)
            self.assertNotIn(f"function {helper}", preview_esm)
        self.assertNotIn("const trimmedLabel = typeof label", data_esm)
        self.assertNotIn("const trimmedLabel = typeof label", preview_esm)
        self.assertNotIn("const trimmedLabel = typeof label", runtime_data)
        self.assertNotIn("namespace.previewCore = existingCore", core)
        self.assertNotIn("VersoBlueprint.__private", core)
        self.assertNotIn("VersoBlueprintPreviewCore", core)

    def test_graph_runtime_helpers_live_in_private_graph_chunk(self) -> None:
        graph_core = (BLUEPRINT_SRC / "Commands" / "graph-runtime-core.mjs").read_text(
            encoding="utf-8"
        )
        graph_runtime = (BLUEPRINT_SRC / "Commands" / "graph.mjs").read_text(
            encoding="utf-8"
        )
        graph_lean = (BLUEPRINT_SRC / "Commands" / "Graph.lean").read_text(
            encoding="utf-8"
        )
        preview_manifest = (BLUEPRINT_SRC / "PreviewManifest.lean").read_text(
            encoding="utf-8"
        )

        self.assertNotIn('include_str "graph-runtime-core.mjs"', graph_lean)
        self.assertNotIn('include_str "graph.mjs"', graph_lean)
        self.assertIn('include_str "Commands/graph-runtime-core.mjs"', preview_manifest)
        self.assertIn('include_str "Commands/graph.mjs"', preview_manifest)
        self.assertIn("export function startGraphRuntime(previewUtils, options)", graph_runtime)
        self.assertIn("installGraphRenderApi(previewUtils, options);", graph_runtime)
        self.assertIn("export const graphRuntimeCore = {", graph_core)
        self.assertNotIn("globalScope.VersoBlueprintGraphRuntimeCore", graph_core)
        self.assertNotIn("globalScope.VersoBlueprintGraphRuntimeCore", graph_lean)
        self.assertNotIn("privateNamespace.graphRuntimeCore = existingCore", graph_lean)
        self.assertIn('from "./graph-runtime-core.mjs";', graph_runtime)
        for helper in GRAPH_RUNTIME_CORE_HELPERS:
            self.assertIn(f"function {helper}", graph_core)
            self.assertNotIn(f"function {helper}", graph_runtime)
        self.assertNotIn("VersoBlueprintGraphRuntimeCore", graph_runtime)


if __name__ == "__main__":
    unittest.main()
