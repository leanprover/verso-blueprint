import {
  dataUrl as coreDataUrl,
  getGraphData as coreGetGraphData,
  getGraphVariants as coreGetGraphVariants,
  graphApiModuleUrl as coreGraphApiModuleUrl,
  loadManifestGraphs as coreLoadManifestGraphs,
  version as coreVersion
} from "./blueprint-graph-core.mjs";

/**
 * Graph-only Blueprint browser API.
 *
 * This module is emitted as `-verso-data/api/graph.mjs` in generated sites. It
 * exposes URL helpers, graph data readers, and graph-block render helpers.
 * Data-only calls do not load the interactive graph renderer; render helpers
 * lazy-load it when called.
 *
 * Use the data helpers when a dashboard needs finalized graph records from the
 * manifest or graph JSON embedded beside a rendered graph block. Use
 * {@link renderGraphData} to create the standard graph UI from a finalized
 * manifest graph record, or {@link renderGraphs} / {@link renderGraphBlock}
 * when the page already contains generated graph-block markup. Rendering graph
 * blocks requires an explicit preview renderer from `api/preview.mjs` so graph
 * popovers and nested previews use the same manifest/cache loader and hydration
 * path as the rest of the page.
 *
 * @module blueprint-graph-api
 */

/** @import { BlueprintDataApiOptions, BlueprintGraphController, BlueprintGraphData, BlueprintGraphRenderOptions, BlueprintGraphVariant } from "./blueprint-api-types.mjs" */

/** Graph API schema/runtime version. */
export const version = coreVersion;
const moduleUrl = import.meta.url;

/**
 * Resolve a generated data filename under `-verso-data/`.
 *
 * @param {string} filename Generated data filename.
 * @param {string} [baseUrl] Base URL. Defaults to this module URL.
 * @returns {string}
 */
export const dataUrl = (filename, baseUrl = moduleUrl) => coreDataUrl(filename, baseUrl);

/**
 * Resolve the generated graph API module URL.
 *
 * @param {string} [baseUrl] Base URL. Defaults to this module URL.
 * @returns {string}
 */
export const graphApiModuleUrl = (baseUrl = moduleUrl) => coreGraphApiModuleUrl(baseUrl);

/**
 * Read embedded graph data from the current graph page or supplied root.
 *
 * This is for pages that already contain generated graph-block markup. Use
 * {@link loadGraphs} when the current document does not contain the graph you
 * want to inspect.
 *
 * @param {ParentNode | Element | Document | DocumentFragment} [root] Search root.
 * @returns {BlueprintGraphData | null}
 */
export function getGraphData(root) {
  return coreGetGraphData(root);
}

/**
 * Read embedded graph variants from the current graph page or supplied root.
 *
 * @param {ParentNode | Element | Document | DocumentFragment} [root] Search root.
 * @returns {BlueprintGraphVariant[]}
 */
export function getGraphVariants(root) {
  return coreGetGraphVariants(root);
}

/**
 * Load finalized graph records from a manifest URL.
 *
 * @param {string} [url] Manifest URL. Defaults to this module's generated-data manifest.
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<BlueprintGraphData[]>}
 */
export const loadManifestGraphs = (url, options) => {
  const manifestUrl =
    typeof url === "string" && url.trim()
      ? url
      : coreDataUrl("blueprint-manifest.json", moduleUrl);
  return coreLoadManifestGraphs(manifestUrl, options);
};

/**
 * Load finalized graph records from this generated site's default manifest.
 *
 * This is the simplest graph-data entry point for dashboards and audits that
 * need graph records but do not need to render graph blocks.
 *
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<BlueprintGraphData[]>}
 *
 * @example
 * // Import graph data helpers when no graph rendering is needed.
 * import { loadGraphs } from "./-verso-data/api/graph.mjs";
 *
 * // Load finalized graph records from the generated manifest.
 * const graphs = await loadGraphs();
 * for (const graph of graphs) {
 *   console.log(graph.key, graph.nodes.length, graph.edges.length);
 * }
 */
export const loadGraphs = (options) =>
  coreLoadManifestGraphs(coreDataUrl("blueprint-manifest.json", moduleUrl), options);

let graphRuntimeModulePromise = null;

function graphRuntimeModuleUrl() {
  return new URL("./Commands/graph.mjs", moduleUrl).href;
}

function loadGraphRuntimeModule() {
  if (!graphRuntimeModulePromise) {
    graphRuntimeModulePromise = import(graphRuntimeModuleUrl()).catch(function (err) {
      graphRuntimeModulePromise = null;
      throw err;
    });
  }
  return graphRuntimeModulePromise;
}

function hasSearchRootShape(value) {
  return !!(
    value &&
    typeof value === "object" &&
    typeof value.querySelectorAll === "function"
  );
}

function readGraphRenderOptions(root, options) {
  if (options && typeof options === "object") return options;
  if (root && typeof root === "object" && !hasSearchRootShape(root)) return root;
  return {};
}

function requirePreviewUtils(options) {
  const opts = options && typeof options === "object" ? options : {};
  if (!opts.previewUtils || typeof opts.previewUtils !== "object") {
    throw new Error("Blueprint graph rendering requires options.previewUtils from createPreview().");
  }
  return opts;
}

/**
 * Render one standard `.bp_graph_fullwidth` graph block.
 *
 * The block must be generated Blueprint graph markup. Pass `previewUtils` from
 * `createPreview()` so node preview panels use the same renderer as the rest
 * of the client.
 *
 * @param {Element} graphBlock Standard graph block.
 * @param {BlueprintGraphRenderOptions} [options] Graph render options.
 * @returns {Promise<BlueprintGraphController | null>}
 *
 * @example
 * // Graph rendering needs a preview renderer for popovers and hydration.
 * import { createPreview } from "./-verso-data/api/preview.mjs";
 * import { renderGraphBlock } from "./-verso-data/api/graph.mjs";
 *
 * // Create one preview renderer for graph node previews.
 * const previewUtils = createPreview();
 *
 * // Initialize one generated graph block and force an immediate render.
 * await renderGraphBlock(document.querySelector(".bp_graph_fullwidth"), {
 *   previewUtils,
 *   refresh: true
 * });
 */
export async function renderGraphBlock(graphBlock, options) {
  const runtime = await loadGraphRuntimeModule();
  return runtime.renderGraphBlock(graphBlock, requirePreviewUtils(options));
}

/**
 * Render every standard graph block under a document, element, or fragment.
 *
 * This initializes the same interactive graph UI used by generated Blueprint
 * pages. It does not create graph markup from raw graph data; the root must
 * already contain generated `.bp_graph_fullwidth` blocks.
 *
 * @param {ParentNode | Element | Document | DocumentFragment} [root] Search root.
 * @param {BlueprintGraphRenderOptions} [options] Graph render options.
 * @returns {Promise<BlueprintGraphController[]>}
 *
 * @example
 * // Graph rendering needs a preview renderer for popovers and hydration.
 * import { createPreview } from "./-verso-data/api/preview.mjs";
 * import { renderGraphs } from "./-verso-data/api/graph.mjs";
 *
 * // Create one preview renderer and initialize every graph under a custom root.
 * const previewUtils = createPreview();
 * await renderGraphs(document.querySelector("#slide"), {
 *   previewUtils,
 *   layout: "fill",
 *   refresh: true
 * });
 */
export async function renderGraphs(root, options) {
  const runtime = await loadGraphRuntimeModule();
  const renderOptions = requirePreviewUtils(readGraphRenderOptions(root, options));
  if (!options && renderOptions === root) {
    return runtime.renderGraphs(renderOptions);
  }
  return runtime.renderGraphs(root, renderOptions);
}

/**
 * Create standard Blueprint graph-block markup from finalized graph data.
 *
 * This is useful when a custom browser client loaded graph records with
 * {@link loadGraphs} and wants to insert the same graph block shape used by
 * generated pages. The returned element is not rendered until it is inserted
 * and passed to {@link renderGraphBlock}, or until {@link renderGraphData} is
 * used. Returns `null` when the graph record does not contain precomputed
 * render variants and no `options.variants` override is supplied.
 *
 * @param {BlueprintGraphData} graphData Finalized graph record.
 * @param {BlueprintGraphRenderOptions} [options] Graph render options.
 * @returns {Promise<Element | null>} Standard graph block, or `null` when no
 * render variants are available.
 */
export async function createGraphBlock(graphData, options) {
  const runtime = await loadGraphRuntimeModule();
  return runtime.createGraphBlock(graphData, options);
}

/**
 * Render finalized graph data into a host element.
 *
 * This constructs the standard `.bp_graph_fullwidth` block, inserts it into
 * `host`, lazy-loads the graph renderer, and returns the same controller as
 * {@link renderGraphBlock}. Pass `replace: false` to append instead of replacing
 * the host's existing children. Returns `null` without changing `host` when the
 * graph record does not contain precomputed render variants and no
 * `options.variants` override is supplied.
 *
 * @param {Element} host Element that will contain the graph block.
 * @param {BlueprintGraphData} graphData Finalized graph record, typically from {@link loadGraphs}.
 * @param {BlueprintGraphRenderOptions} [options] Graph render options.
 * @returns {Promise<BlueprintGraphController | null>} Graph controller, or
 * `null` when no graph block can be built.
 *
 * @example
 * import { createPreview } from "./-verso-data/api/preview.mjs";
 * import { loadGraphs, renderGraphData } from "./-verso-data/api/graph.mjs";
 *
 * const previewUtils = createPreview();
 * const [graph] = await loadGraphs();
 * await renderGraphData(document.querySelector("#graph-host"), graph, {
 *   previewUtils,
 *   layout: "fill"
 * });
 */
export async function renderGraphData(host, graphData, options) {
  const runtime = await loadGraphRuntimeModule();
  return runtime.renderGraphData(host, graphData, requirePreviewUtils(options));
}

const graphApi = {
  version,
  dataUrl,
  graphApiModuleUrl,
  getGraphData,
  getGraphVariants,
  loadManifestGraphs,
  loadGraphs,
  createGraphBlock,
  renderGraphBlock,
  renderGraphs,
  renderGraphData
};

export default graphApi;
