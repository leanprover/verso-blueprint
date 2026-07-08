import { callDefaultApi, callDefaultApiSync, createDefaultApiHandle, createPreviewUrlApi, fallbackStoreStatus, optionsWithDefaultDataBaseUrl, version } from "./blueprint-api-common.mjs";
import { createBlueprintDataApi } from "./Commands/preview-runtime-data.mjs";

/**
 * Generated-data API for custom Blueprint clients.
 *
 * This module is emitted as `-verso-data/api/data.mjs` in generated sites. It
 * exposes manifest, HTML cache, preview-key, and URL helpers without importing
 * DOM rendering code or installing any page-global render hook.
 *
 * Use this module for audits, dashboards, migration tools, or Node-like clients
 * that own their UI and only need generated data. The manifest is the semantic
 * contract: labels, facets, generated links, external markup metadata,
 * dependency metadata, status metadata, and graph records. The HTML cache is
 * rendered presentation data; do not parse it to recover semantics.
 *
 * Browser clients that need to insert Blueprint content should use
 * `api/preview.mjs` instead. Graph dashboards may use this module for manifest
 * data, but graph-specific helpers are collected in `api/graph.mjs`.
 *
 * @module blueprint-data-api
 */

/** @import { BlueprintDataApiOptions, BlueprintLabelResolveOptions, BlueprintDataApi, BlueprintStoreStatus, BlueprintManifestEntry, BlueprintSourceDocument, BlueprintHtmlCacheEntry, BlueprintResolveLabelResult, BlueprintResolveDeclarationResult, BlueprintSourceMetadataInput, BlueprintSourceMetadataResult } from "./blueprint-api-types.mjs" */

export { version };

const moduleUrl = import.meta.url;
const previewUrls = createPreviewUrlApi(moduleUrl);

/**
 * Create an isolated data API instance.
 *
 * Use this when a custom client wants explicit loaders and cache state instead
 * of the module-level default singleton.
 *
 * @param {BlueprintDataApiOptions} [options] Loader and generated-data base URL options.
 * @returns {BlueprintDataApi} Data API instance.
 *
 * @example
 * // Import the data-only API when no DOM rendering is needed.
 * import { createPreviewData } from "./-verso-data/api/data.mjs";
 *
 * // Create an isolated data loader for this client.
 * const data = createPreviewData();
 *
 * // Build the same manifest/cache key Blueprint uses for statement previews.
 * const key = data.statementPreviewKey("main_theorem");
 *
 * // Read one semantic manifest entry by key.
 * const entry = await data.loadManifestEntry(key);
 *
 * if (entry) {
 *   console.log(entry.href, entry.label, entry.facet);
 * }
 */
export function createPreviewData(options) {
  return createBlueprintDataApi(optionsWithDefaultDataBaseUrl(options, moduleUrl));
}

const defaultDataHandle = createDefaultApiHandle(createPreviewData);

/**
 * Return the module-level data API if it has already been created.
 *
 * @returns {BlueprintDataApi | null}
 */
export function currentDataApi() {
  return defaultDataHandle.currentApi();
}

/**
 * Return the module-level data API, creating it on first use.
 *
 * @returns {Promise<BlueprintDataApi>}
 */
export function getDataApi() {
  return defaultDataHandle.getApi();
}

/**
 * Promise for the default data API instance.
 *
 * @type {Promise<BlueprintDataApi>}
 */
export const ready = defaultDataHandle.ready;

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
    defaultDataHandle.readDefaultApi,
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
    defaultDataHandle.readDefaultApi,
    "readHtmlCacheStatus",
    function () { return fallbackStoreStatus(htmlCacheUrl()); },
    []
  );
}

/**
 * Load and decode the Blueprint manifest.
 *
 * The manifest is the semantic data source for generated Blueprint sites. Use
 * it for labels, generated links, external markup metadata, graph records, and
 * other structured facts.
 *
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<Map<string, BlueprintManifestEntry>>}
 */
export function loadManifest(options) {
  return callDefaultApi(defaultDataHandle.readDefaultApi, "data", "loadManifest", [options]);
}

/**
 * Load and decode the rendered HTML fragment cache.
 *
 * The cache contains rendered presentation fragments keyed like the manifest.
 * Insert or display these fragments as HTML; do not parse them to rediscover
 * semantic data that already lives in the manifest.
 *
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<Map<string, BlueprintHtmlCacheEntry>>}
 */
export function loadHtmlCache(options) {
  return callDefaultApi(defaultDataHandle.readDefaultApi, "data", "loadHtmlCache", [options]);
}

/**
 * Load a single manifest entry by key.
 *
 * @param {string} key Manifest key.
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<BlueprintManifestEntry | null>}
 */
export function loadManifestEntry(key, options) {
  return callDefaultApi(defaultDataHandle.readDefaultApi, "data", "loadManifestEntry", [key, options]);
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
  return callDefaultApi(defaultDataHandle.readDefaultApi, "data", "loadSourceDocuments", [options]);
}

/**
 * Load one source-document declaration by id.
 *
 * @param {string} id Source-document id.
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<BlueprintSourceDocument | null>}
 */
export function loadSourceDocument(id, options) {
  return callDefaultApi(defaultDataHandle.readDefaultApi, "data", "loadSourceDocument", [id, options]);
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
 * import { resolveLabel } from "./-verso-data/api/data.mjs";
 *
 * const result = await resolveLabel("main_theorem", { facet: "statement" });
 * if (result.ok && result.sourceLocation.ok) {
 *   console.log(result.href, result.sourceLocation.location.path);
 * }
 */
export function resolveLabel(label, options) {
  return callDefaultApi(defaultDataHandle.readDefaultApi, "data", "resolveLabel", [label, options]);
}

/**
 * Resolve a Lean declaration name to a declaration-keyed manifest entry and
 * source location.
 *
 * Inline code previews are keyed by the inline Blueprint code label, not by
 * each declaration in the code block. Load those previews through the explicit
 * key in the owning manifest entry's `leanCodePreviewKeys`.
 *
 * `sourceLocation` points to the Lean declaration source. Use the returned
 * `manifestEntry` or `resolveSourceMetadata` for Blueprint provenance records.
 *
 * @param {string} declName Lean declaration name.
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<BlueprintResolveDeclarationResult>}
 *
 * @example
 * import { resolveDeclaration } from "./-verso-data/api/data.mjs";
 *
 * const result = await resolveDeclaration("Nat.add");
 * if (result.ok) {
 *   console.log(result.key, result.sourceLocation);
 * }
 */
export function resolveDeclaration(declName, options) {
  return callDefaultApi(defaultDataHandle.readDefaultApi, "data", "resolveDeclaration", [declName, options]);
}

/**
 * Resolve original-source provenance for a preview key or manifest entry.
 *
 * This joins `entry.sources` with declared source-document metadata. It returns
 * structured metadata only; callers own PDF/text loading and presentation.
 *
 * @param {BlueprintSourceMetadataInput} source Preview key, manifest entry, or render result.
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<BlueprintSourceMetadataResult>}
 */
export function resolveSourceMetadata(source, options) {
  return callDefaultApi(defaultDataHandle.readDefaultApi, "data", "resolveSourceMetadata", [source, options]);
}

/**
 * Load a single HTML-cache entry by key.
 *
 * @param {string} key HTML cache key.
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<BlueprintHtmlCacheEntry | null>}
 */
export function loadHtmlCacheEntry(key, options) {
  return callDefaultApi(defaultDataHandle.readDefaultApi, "data", "loadHtmlCacheEntry", [key, options]);
}

const dataApi = {
  version,
  dataUrl,
  manifestUrl,
  htmlCacheUrl,
  dataApiModuleUrl,
  previewApiModuleUrl,
  graphApiModuleUrl,
  createPreviewData,
  currentDataApi,
  getDataApi,
  ready,
  loadManifest,
  readManifestStatus,
  loadManifestEntry,
  loadSourceDocuments,
  loadSourceDocument,
  resolveLabel,
  resolveDeclaration,
  resolveSourceMetadata,
  loadHtmlCache,
  readHtmlCacheStatus,
  loadHtmlCacheEntry,
  previewKey,
  statementPreviewKey
};

export default dataApi;
