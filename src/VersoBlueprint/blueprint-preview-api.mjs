import { callDefaultApi, callDefaultApiSync, createDefaultApiHandle, createPreviewUrlApi, fallbackStoreStatus, optionsWithDefaultDataBaseUrl, version } from "./blueprint-api-common.mjs";
import { createPreviewRuntimeApi } from "./Commands/preview-runtime-api.mjs";

/**
 * Render-capable Blueprint preview API for custom browser clients.
 *
 * This module is emitted as `-verso-data/api/preview.mjs` in generated sites.
 * Import it when your client needs to display Blueprint content in the DOM.
 * It composes the data API with rendered-fragment insertion, canonical
 * generated-node loading, math rendering, hydration, and call-scoped
 * external-markup fallback renderers.
 *
 * The renderer returned by {@link createPreview} keeps its own manifest/cache
 * load state. Use it instead of reading `window.VersoBlueprint` or importing
 * private `Commands/*.mjs` chunks. Data-only clients should use
 * `api/data.mjs`; graph-only or graph-rendering clients should use
 * `api/graph.mjs` and pass an explicit preview renderer to graph render
 * helpers.
 *
 * Common rendering choices:
 *
 * - {@link renderPreviewInto} inserts only the cached preview body fragment,
 *   for clients that own their surrounding UI.
 * - {@link renderCanonicalPreviewInto} inserts the standard generated
 *   Blueprint node wrapper from the canonical generated page.
 * - {@link renderNode} starts from a Blueprint label and can fall back to
 *   call-scoped external Markdown, TeX, Verso, or source renderers when no
 *   native preview exists.
 * - {@link resolveSourceMetadata} resolves source-provenance metadata from the
 *   manifest for custom preview/source interfaces.
 * - {@link hydrate} runs Blueprint math and nested-preview behavior after a
 *   client has inserted cached HTML itself.
 *
 * @module blueprint-preview-api
 */

/** @import { BlueprintDataApiOptions, BlueprintLabelResolveOptions, BlueprintPreviewOptions, BlueprintPreviewApi, BlueprintStoreStatus, BlueprintManifestEntry, BlueprintSourceDocument, BlueprintHtmlCacheEntry, BlueprintResolveLabelResult, BlueprintResolveDeclarationResult, BlueprintPreviewResult, BlueprintCanonicalPreviewResult, BlueprintRenderNodeRequest, BlueprintRenderNodeResult, BlueprintSourceMetadataInput, BlueprintSourceMetadataResult } from "./blueprint-api-types.mjs" */

export { version };

const moduleUrl = import.meta.url;
const previewUrls = createPreviewUrlApi(moduleUrl);

/**
 * Create an isolated render-capable preview API instance.
 *
 * Prefer this entry point for custom browser clients. Pass `dataBaseUrl` or
 * `fetchJson` when the generated data files are not next to this module, and
 * pass `fetchText`, `loadDocument`, or `canonicalBaseUrl` when canonical node
 * rendering needs custom page loading.
 *
 * @param {BlueprintPreviewOptions} [options] Loader, hydration, and generated-data options.
 * @returns {BlueprintPreviewApi} Preview API instance.
 *
 * @example
 * // Import the render-capable API from the generated site.
 * import { createPreview } from "./-verso-data/api/preview.mjs";
 *
 * // Create one renderer for this custom client and register any client widgets
 * // that need to run after Blueprint content is inserted.
 * const preview = createPreview({
 *   hydrators: {
 *     audit(root) {
 *       root.querySelectorAll("[data-audit-target]").forEach(bindAuditWidget);
 *     }
 *   }
 * });
 *
 * // Render the same generated Blueprint node wrapper used by the site.
 * await preview.renderCanonicalPreviewInto(
 *   document.querySelector("#target"),
 *   preview.statementPreviewKey("Chapter2:Problem2.11.6")
 * );
 */
export function createPreview(options) {
  return createPreviewRuntimeApi(optionsWithDefaultDataBaseUrl(options, moduleUrl));
}

const defaultRenderHandle = createDefaultApiHandle(createPreview);

/**
 * Return the module-level preview API if it has already been created.
 *
 * @returns {BlueprintPreviewApi | null}
 */
export function currentRenderApi() {
  return defaultRenderHandle.currentApi();
}

/**
 * Return the module-level preview API, creating it on first use.
 *
 * @returns {Promise<BlueprintPreviewApi>}
 */
export function getRenderApi() {
  return defaultRenderHandle.getApi();
}

/**
 * Promise for the default preview API instance.
 *
 * @type {Promise<BlueprintPreviewApi>}
 */
export const ready = defaultRenderHandle.ready;

/**
 * Resolve a generated data filename under `-verso-data/`.
 *
 * @param {string} filename Generated data filename.
 * @param {string} [baseUrl] Base URL. Defaults to this module URL.
 * @returns {string}
 */
export function dataUrl(filename, baseUrl) {
  return previewUrls.dataUrl(filename, baseUrl);
}

/**
 * Resolve `blueprint-manifest.json`.
 *
 * @param {string} [baseUrl] Base URL. Defaults to this module URL.
 * @returns {string}
 */
export function manifestUrl(baseUrl) {
  return previewUrls.manifestUrl(baseUrl);
}

/**
 * Resolve `blueprint-html-cache.json`.
 *
 * @param {string} [baseUrl] Base URL. Defaults to this module URL.
 * @returns {string}
 */
export function htmlCacheUrl(baseUrl) {
  return previewUrls.htmlCacheUrl(baseUrl);
}

/**
 * Resolve the generated data API module URL.
 *
 * @param {string} [baseUrl] Base URL. Defaults to this module URL.
 * @returns {string}
 */
export function dataApiModuleUrl(baseUrl) {
  return previewUrls.dataApiModuleUrl(baseUrl);
}

/**
 * Resolve the generated preview API module URL.
 *
 * @param {string} [baseUrl] Base URL. Defaults to this module URL.
 * @returns {string}
 */
export function previewApiModuleUrl(baseUrl) {
  return previewUrls.previewApiModuleUrl(baseUrl);
}

/**
 * Resolve the generated graph API module URL.
 *
 * @param {string} [baseUrl] Base URL. Defaults to this module URL.
 * @returns {string}
 */
export function graphApiModuleUrl(baseUrl) {
  return previewUrls.graphApiModuleUrl(baseUrl);
}

/**
 * Build the preview key for a Blueprint label and facet.
 *
 * @param {string} label Blueprint label.
 * @param {string} [facet] Preview facet. Defaults to `statement`.
 * @returns {string}
 */
export function previewKey(label, facet) {
  return previewUrls.previewKey(label, facet);
}

/**
 * Build the statement preview key for a Blueprint label.
 *
 * @param {string} label Blueprint label.
 * @returns {string}
 */
export function statementPreviewKey(label) {
  return previewUrls.statementPreviewKey(label);
}

/**
 * Read cached manifest loader status without triggering a load.
 *
 * @returns {BlueprintStoreStatus}
 */
export function readManifestStatus() {
  return callDefaultApiSync(
    defaultRenderHandle.readDefaultApi,
    "readManifestStatus",
    function () { return fallbackStoreStatus(manifestUrl()); },
    []
  );
}

/**
 * Read cached HTML-cache loader status without triggering a load.
 *
 * @returns {BlueprintStoreStatus}
 */
export function readHtmlCacheStatus() {
  return callDefaultApiSync(
    defaultRenderHandle.readDefaultApi,
    "readHtmlCacheStatus",
    function () { return fallbackStoreStatus(htmlCacheUrl()); },
    []
  );
}

/**
 * Load and decode the Blueprint manifest.
 *
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<Map<string, BlueprintManifestEntry>>}
 */
export function loadManifest(options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "loadManifest", [options]);
}

/**
 * Load and decode the rendered HTML fragment cache.
 *
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<Map<string, BlueprintHtmlCacheEntry>>}
 */
export function loadHtmlCache(options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "loadHtmlCache", [options]);
}

/**
 * Load a single manifest entry by key.
 *
 * @param {string} key Manifest key.
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<BlueprintManifestEntry | null>}
 */
export function loadManifestEntry(key, options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "loadManifestEntry", [key, options]);
}

/**
 * Load source-document declarations from the Blueprint manifest.
 *
 * Use these records to resolve `entry.sources[*].document` ids to display
 * metadata such as the document title, PDF path, or extracted page roots.
 *
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<BlueprintSourceDocument[]>}
 */
export function loadSourceDocuments(options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "loadSourceDocuments", [options]);
}

/**
 * Load one source-document declaration by id.
 *
 * @param {string} id Source-document id.
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<BlueprintSourceDocument | null>}
 */
export function loadSourceDocument(id, options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "loadSourceDocument", [id, options]);
}

/**
 * Resolve a Blueprint block label to its manifest entry and source location.
 *
 * `sourceLocation` points to the authored Blueprint label/facet location. Use
 * `resolveSourceMetadata` when a client needs original-source provenance from
 * `entry.sources`.
 *
 * @param {string} label Blueprint block label.
 * @param {BlueprintLabelResolveOptions} [options] Optional facet and load overrides.
 * @returns {Promise<BlueprintResolveLabelResult>}
 *
 * @example
 * import { createPreview } from "./-verso-data/api/preview.mjs";
 *
 * const preview = createPreview();
 * const result = await preview.resolveLabel("main_theorem");
 * if (result.ok && result.sourceLocation.ok) {
 *   console.log(result.href, result.sourceLocation.location.path);
 * }
 */
export function resolveLabel(label, options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "resolveLabel", [label, options]);
}

/**
 * Resolve a Lean declaration name to a declaration-keyed manifest entry and
 * source location.
 *
 * `sourceLocation` points to the Lean declaration source. Use the returned
 * `manifestEntry` or `resolveSourceMetadata` for Blueprint provenance records.
 *
 * Inline code previews are keyed by the inline Blueprint code label, not by
 * each declaration in the code block. Load those previews through the explicit
 * key in the owning manifest entry's `leanCodePreviewKeys`.
 *
 * @param {string} declName Lean declaration name for a declaration-keyed preview.
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<BlueprintResolveDeclarationResult>}
 *
 * @example
 * import { resolveDeclaration } from "./-verso-data/api/preview.mjs";
 *
 * const result = await resolveDeclaration("Nat.add");
 * if (result.ok) {
 *   console.log(result.href, result.sourceLocation);
 * }
 */
export function resolveDeclaration(declName, options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "resolveDeclaration", [declName, options]);
}

/**
 * Load a single HTML-cache entry by key.
 *
 * @param {string} key HTML cache key.
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<BlueprintHtmlCacheEntry | null>}
 */
export function loadHtmlCacheEntry(key, options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "loadHtmlCacheEntry", [key, options]);
}

/**
 * Resolve a preview key against the manifest and HTML cache.
 *
 * This reads semantic data and rendered body HTML without writing to the DOM.
 * Use the returned `manifestEntry` for labels, facets, generated links,
 * external markup metadata, dependency metadata, and other semantic facts.
 *
 * @param {string} key Preview key such as `label--statement`.
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<BlueprintPreviewResult>}
 */
export function resolvePreview(key, options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "resolvePreview", [key, options]);
}

/**
 * Render a cached preview fragment into a target element.
 *
 * This writes the rendered body fragment from `blueprint-html-cache.json` into
 * your existing wrapper. Use this when your application owns the surrounding
 * card, panel, or component layout.
 *
 * @param {Element} element Target element to replace with the resolved fragment.
 * @param {string} key Preview key such as `label--statement`.
 * @param {BlueprintPreviewOptions} [options] Optional render and load overrides.
 * @returns {Promise<BlueprintPreviewResult>}
 *
 * @example
 * // Import the render-capable API from the generated site.
 * import { createPreview } from "./-verso-data/api/preview.mjs";
 *
 * // Create a renderer and choose the target element owned by your UI.
 * const preview = createPreview();
 * const body = document.querySelector("#preview-body");
 *
 * // Insert only the cached preview body fragment into that target.
 * await preview.renderPreviewInto(body, preview.statementPreviewKey("main_theorem"));
 */
export function renderPreviewInto(element, key, options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "renderPreviewInto", [element, key, options]);
}

/**
 * Resolve a preview key to its canonical generated-node shell.
 *
 * This loads the generated page referenced by the manifest entry and extracts
 * the same Blueprint node wrapper that appears in the generated site.
 *
 * @param {string} key Preview key such as `label--statement`.
 * @param {BlueprintPreviewOptions} [options] Optional render and load overrides.
 * @returns {Promise<BlueprintCanonicalPreviewResult>}
 */
export function resolveCanonicalPreview(key, options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "resolveCanonicalPreview", [key, options]);
}

/**
 * Render the canonical generated-node shell for a preview key into a target.
 *
 * Use this when the custom page should display normal Blueprint node visuals
 * instead of a client-owned wrapper around a body fragment.
 *
 * @param {Element} element Target element to replace with the canonical node.
 * @param {string} key Preview key such as `label--statement`.
 * @param {BlueprintPreviewOptions} [options] Optional render and load overrides.
 * @returns {Promise<BlueprintCanonicalPreviewResult>}
 */
export function renderCanonicalPreviewInto(element, key, options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "renderCanonicalPreviewInto", [element, key, options]);
}

/**
 * Render a Blueprint label, preferring the native rendered preview and falling
 * back to call-scoped external-markup renderers when needed.
 *
 * This is the highest-level display helper. It is useful for standalone pages
 * that know a Blueprint label but do not want to manually choose between native
 * previews, canonical generated-node insertion, and external markup fallback
 * rendering.
 *
 * @param {Element} element Target element to replace with the rendered node.
 * @param {string | BlueprintRenderNodeRequest} request Label or detailed render request.
 * @param {BlueprintPreviewOptions} [options] Optional render and load overrides.
 * @returns {Promise<BlueprintRenderNodeResult>}
 *
 * @example
 * // Import the render-capable API from the generated site.
 * import { createPreview } from "./-verso-data/api/preview.mjs";
 *
 * // Create one renderer for this standalone view.
 * const preview = createPreview();
 *
 * // Render by Blueprint label. Native generated content is preferred; external
 * // markup fallbacks are used only when the native preview is unavailable.
 * await preview.renderNode(document.querySelector("#target"), {
 *   label: "external_markdown_statement",
 *   externalMarkup: {
 *     prefer: [
 *       { language: "markdown", slot: "original", render: renderMarkdown },
 *       { display: "source" }
 *     ]
 *   }
 * });
 */
export function renderNode(element, request, options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "renderNode", [element, request, options]);
}

/**
 * Resolve source-provenance metadata for a preview key or manifest entry.
 *
 * The result joins `entry.sources` with the matching source-document records
 * from the manifest. Use this when a custom UI wants source metadata but owns
 * its own rendering.
 *
 * @param {BlueprintSourceMetadataInput} source Preview key, manifest entry, or render result.
 * @param {BlueprintPreviewOptions} [options] Optional render and load overrides.
 * @returns {Promise<BlueprintSourceMetadataResult>}
 */
export function resolveSourceMetadata(source, options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "resolveSourceMetadata", [source, options]);
}

/**
 * Hydrate Blueprint-specific behavior inside an already-rendered subtree.
 *
 * Call this after inserting Blueprint-rendered HTML yourself. It runs math,
 * descriptor-bound previews, registered Blueprint feature hydrators, and
 * caller-supplied hydrators according to the render options.
 *
 * @param {Element} element Root element to hydrate.
 * @param {BlueprintPreviewOptions} [options] Hydration options.
 * @returns {Promise<boolean>}
 */
export function hydrate(element, options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "hydrate", [element, options]);
}

const previewApi = {
  version,
  dataUrl,
  manifestUrl,
  htmlCacheUrl,
  dataApiModuleUrl,
  previewApiModuleUrl,
  graphApiModuleUrl,
  createPreview,
  currentRenderApi,
  getRenderApi,
  ready,
  loadManifest,
  readManifestStatus,
  loadManifestEntry,
  loadSourceDocuments,
  loadSourceDocument,
  loadHtmlCache,
  readHtmlCacheStatus,
  loadHtmlCacheEntry,
  previewKey,
  statementPreviewKey,
  resolveLabel,
  resolveDeclaration,
  resolvePreview,
  renderPreviewInto,
  resolveCanonicalPreview,
  renderCanonicalPreviewInto,
  renderNode,
  resolveSourceMetadata,
  hydrate
};

export default previewApi;
