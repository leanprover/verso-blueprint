const version = 1;

/** @import { BlueprintDataApiOptions, BlueprintGraphData, BlueprintGraphVariant } from "./blueprint-api-types.mjs" */

function defaultGlobalScope() {
  return typeof globalThis !== "undefined" ? globalThis : {};
}

function currentHref(globalScope = defaultGlobalScope()) {
  const windowObj = globalScope && globalScope.window;
  return windowObj && windowObj.location ? windowObj.location.href : "";
}

function currentDocument(globalScope = defaultGlobalScope()) {
  return globalScope && globalScope.document ? globalScope.document : null;
}

/**
 * @param {unknown} node
 * @param {Record<string, unknown>} [globalScope]
 * @returns {boolean}
 */
function isElement(node, globalScope = defaultGlobalScope()) {
  const ElementCtor = /** @type {Function | undefined} */ (
    globalScope && globalScope.Element
  );
  return typeof ElementCtor !== "undefined" && node instanceof ElementCtor;
}

/**
 * @param {unknown} node
 * @param {Record<string, unknown>} [globalScope]
 * @returns {boolean}
 */
function isDocumentLike(node, globalScope = defaultGlobalScope()) {
  const DocumentCtor = /** @type {Function | undefined} */ (
    globalScope && globalScope.Document
  );
  const DocumentFragmentCtor = /** @type {Function | undefined} */ (
    globalScope && globalScope.DocumentFragment
  );
  return (
    (typeof DocumentCtor !== "undefined" && node instanceof DocumentCtor) ||
    (typeof DocumentFragmentCtor !== "undefined" && node instanceof DocumentFragmentCtor)
  );
}

/**
 * @param {unknown} node
 * @returns {boolean}
 */
function isScriptElement(node) {
  const candidate = /** @type {Object.<string, unknown>} */ (
    node && typeof node === "object" ? node : {}
  );
  return typeof candidate.tagName === "string" && candidate.tagName.toLowerCase() === "script";
}

/**
 * Resolve a generated data filename under `-verso-data/`.
 *
 * @param {string} filename Generated data filename.
 * @param {string} [baseUrl] Base URL to resolve from. Defaults to the current page URL.
 * @returns {string}
 */
export function dataUrl(filename, baseUrl) {
  const safeFilename = String(filename || "").trim();
  const sourceUrl =
    typeof baseUrl === "string" && baseUrl.length > 0 ? baseUrl : currentHref();
  try {
    const url = new URL(sourceUrl);
    const dataMarker = "/-verso-data/";
    const dataIdx = url.pathname.indexOf(dataMarker);
    if (dataIdx >= 0) {
      const rootPath = url.pathname.slice(0, dataIdx + dataMarker.length);
      return rootPath + safeFilename;
    }
    const markers = ["/html-multi/", "/html-single/"];
    for (const marker of markers) {
      const idx = url.pathname.indexOf(marker);
      if (idx >= 0) {
        const rootPath = url.pathname.slice(0, idx + marker.length);
        return rootPath + "-verso-data/" + safeFilename;
      }
    }
  } catch (_err) {}
  return safeFilename ? "-verso-data/" + safeFilename : "-verso-data/";
}

/**
 * Resolve the generated graph API module URL.
 *
 * @param {string} [baseUrl] Base URL to resolve from.
 * @returns {string}
 */
export function graphApiModuleUrl(baseUrl) {
  return dataUrl("api/graph.mjs", baseUrl);
}

/**
 * Find the graph canvas associated with a root node.
 *
 * @param {ParentNode | Element | Document | DocumentFragment | null} [root] Search root. Defaults to `document`.
 * @returns {Element | null}
 */
export function graphCanvasFor(root) {
  const globalScope = defaultGlobalScope();
  const node = root || currentDocument(globalScope);
  if (!node) return null;
  if (isElement(node, globalScope)) {
    if (node.matches(".bp_graph_canvas")) return node;
    const ownCanvas = node.querySelector(".bp_graph_canvas");
    if (isElement(ownCanvas, globalScope)) return ownCanvas;
    const block = node.closest(".bp_graph_fullwidth");
    if (isElement(block, globalScope)) {
      const blockCanvas = block.querySelector(".bp_graph_canvas");
      if (isElement(blockCanvas, globalScope)) return blockCanvas;
    }
    return null;
  }
  if (isDocumentLike(node, globalScope)) {
    const canvas = node.querySelector(".bp_graph_canvas");
    return isElement(canvas, globalScope) ? canvas : null;
  }
  return null;
}

/**
 * Read and parse a graph JSON script embedded in a graph canvas.
 *
 * @param {ParentNode | Element | Document | DocumentFragment | null} root Search root.
 * @param {string} selector Script selector inside the graph canvas.
 * @returns {unknown | null}
 */
export function readGraphJsonScript(root, selector) {
  const container = graphCanvasFor(root);
  if (!container) return null;
  const payloadNode = container.querySelector(selector);
  if (!isScriptElement(payloadNode)) return null;
  const scriptNode = /** @type {HTMLScriptElement} */ (payloadNode);
  try {
    return JSON.parse((scriptNode.textContent || "").trim());
  } catch (_err) {
    return null;
  }
}

const graphDataSchemaVersion = 3;

/**
 * @param {unknown} value
 * @returns {boolean}
 */
function isRecord(value) {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

/**
 * @param {unknown} value
 * @returns {boolean}
 */
function isNonemptyString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

/**
 * @param {unknown} value
 * @returns {boolean}
 */
function isTrimmedNonemptyString(value) {
  return typeof value === "string" && value.length > 0 && value === value.trim();
}

/**
 * @param {unknown} value
 * @returns {boolean}
 */
function isGraphNodeIdPair(value) {
  return Array.isArray(value) && value.length === 2 && value.every(isTrimmedNonemptyString);
}

/**
 * @param {unknown} value
 * @returns {boolean}
 */
function areGraphNodeIdPairsValid(value) {
  if (!Array.isArray(value) || !value.every(isGraphNodeIdPair)) return false;
  const nodeIds = value.map(function (pair) { return pair[0]; });
  return new Set(nodeIds).size === nodeIds.length;
}

/**
 * @param {unknown} value
 * @returns {boolean}
 */
function isGraphLayoutOptions(value) {
  if (!isRecord(value)) return false;
  const options = /** @type {Record<string, unknown>} */ (value);
  return typeof options.direction === "string" &&
    ["TB", "LR", "RL", "BT"].includes(options.direction) &&
    typeof options.pack === "boolean";
}

/**
 * @param {unknown} value
 * @returns {boolean}
 */
function isGraphVariant(value) {
  if (!isRecord(value)) return false;
  const variant = /** @type {Record<string, unknown>} */ (value);
  return isTrimmedNonemptyString(variant.key) &&
    isTrimmedNonemptyString(variant.label) &&
    isNonemptyString(variant.dot) &&
    isGraphLayoutOptions(variant.options) &&
    areGraphNodeIdPairsValid(variant.selectOnNodeId) &&
    areGraphNodeIdPairsValid(variant.hoverOnNodeId) &&
    areGraphNodeIdPairsValid(variant.previewKeyByNodeId);
}

/**
 * @param {unknown[]} variants
 * @returns {boolean}
 */
function areGraphVariantsValid(variants) {
  if (variants.length === 0 || !variants.every(isGraphVariant)) return false;
  const records = variants.map(function (variant) {
    return /** @type {Record<string, unknown>} */ (variant);
  });
  const keys = records.map(function (variant) { return variant.key; });
  const keySet = new Set(keys);
  if (records[0].key !== "full" || keySet.size !== keys.length) return false;
  return records.every(function (variant) {
    return [variant.selectOnNodeId, variant.hoverOnNodeId].every(function (pairs) {
      return /** @type {unknown[][]} */ (pairs).every(function (pair) {
        return keySet.has(pair[1]);
      });
    });
  });
}

/**
 * Recognize the current finalized graph payload shape.
 *
 * Topology is finalized by Lean before serialization. Browser clients consume
 * that snapshot and do not carry a second implementation of graph finalization.
 * This boundary validates the schema, top-level collections, and render-variant
 * contract; it trusts Lean's producer boundary for semantic topology agreement.
 *
 * @param {unknown} rawData Parsed graph JSON.
 * @returns {BlueprintGraphData | null}
 */
export function decodeGraphData(rawData) {
  if (!isRecord(rawData)) return null;
  const data = /** @type {Record<string, unknown>} */ (rawData);
  if (data.schemaVersion !== graphDataSchemaVersion || !isTrimmedNonemptyString(data.key)) return null;
  if (!Array.isArray(data.nodes) || !Array.isArray(data.edges) ||
      !Array.isArray(data.groups) || !Array.isArray(data.variants)) return null;
  if (!areGraphVariantsValid(data.variants)) return null;
  return {
    schemaVersion: graphDataSchemaVersion,
    key: /** @type {string} */ (data.key),
    nodes: data.nodes,
    edges: data.edges,
    groups: data.groups,
    variants: data.variants
  };
}

/**
 * Extract graph records that pass the current schema, top-level collection,
 * and render-variant checks. Other records are omitted.
 *
 * @param {unknown} manifest Parsed manifest JSON.
 * @returns {BlueprintGraphData[]}
 */
export function graphsFromManifest(manifest) {
  const data =
    manifest && typeof manifest === "object"
      ? /** @type {Record<string, unknown>} */ (manifest)
      : null;
  if (!data || !Array.isArray(data.graphs)) {
    return [];
  }
  return data.graphs
    .map(decodeGraphData)
    .filter(function (graphData) { return !!graphData; });
}

/**
 * Read embedded graph data from a generated graph page, returning `null` when
 * the payload is missing or fails the current schema, top-level collection, or
 * render-variant checks.
 *
 * @param {ParentNode | Element | Document | DocumentFragment | null} [root] Search root. Defaults to `document`.
 * @returns {BlueprintGraphData | null}
 */
export function getGraphData(root) {
  return decodeGraphData(readGraphJsonScript(root || currentDocument(), "script.bp-graph-data"));
}

/**
 * Read the variants carried by graph data embedded in a generated graph page.
 * This is a convenience projection of {@link getGraphData}.
 *
 * @param {ParentNode | Element | Document | DocumentFragment | null} [root] Search root. Defaults to `document`.
 * @returns {BlueprintGraphVariant[]}
 */
export function getGraphVariants(root) {
  const data = getGraphData(root || currentDocument());
  return data ? data.variants : [];
}

/**
 * Load and parse JSON using `fetch` or a custom `fetchJson`.
 *
 * @param {string} url URL to load.
 * @param {BlueprintDataApiOptions} [options] Optional loader options.
 * @param {string} [errorPrefix] Prefix used for HTTP errors.
 * @returns {Promise<unknown>}
 */
export function loadJson(url, options, errorPrefix) {
  const opts = options && typeof options === "object" ? options : {};
  if (typeof opts.fetchJson === "function") {
    return Promise.resolve(opts.fetchJson(url, opts));
  }
  const globalScope = defaultGlobalScope();
  const fetchFn = globalScope && globalScope.fetch;
  if (typeof fetchFn !== "function") {
    return Promise.reject(new Error("Blueprint graph API requires fetch or options.fetchJson"));
  }
  const prefix =
    typeof errorPrefix === "string" && errorPrefix.length > 0
      ? errorPrefix
      : "Could not load Blueprint JSON";
  const fetchOptions =
    opts.fetchOptions && typeof opts.fetchOptions === "object" ? opts.fetchOptions : opts;
  return fetchFn.call(globalScope, url, fetchOptions).then(function (response) {
    if (!response.ok) {
      throw new Error(prefix + ": " + response.status);
    }
    return response.json();
  });
}

/**
 * Load graph records that pass the current schema, top-level collection, and
 * render-variant checks from a manifest URL. Other records are omitted.
 *
 * @param {string} [url] Manifest URL. Defaults to `blueprint-manifest.json`.
 * @param {BlueprintDataApiOptions} [options] Optional loader options.
 * @returns {Promise<BlueprintGraphData[]>}
 */
export function loadManifestGraphs(url, options) {
  const manifestUrl =
    typeof url === "string" && url.trim() ? url : dataUrl("blueprint-manifest.json");
  return loadJson(
    manifestUrl,
    options,
    "Could not load Blueprint graph manifest"
  ).then(graphsFromManifest);
}

/**
 * Load graph records that pass the current schema, top-level collection, and
 * render-variant checks from the default manifest. Other records are omitted.
 *
 * @param {BlueprintDataApiOptions} [options] Optional loader options.
 * @returns {Promise<BlueprintGraphData[]>}
 */
export function loadGraphs(options) {
  return loadManifestGraphs(dataUrl("blueprint-manifest.json"), options);
}

export const graphCore = {
  version,
  dataUrl,
  graphApiModuleUrl,
  graphCanvasFor,
  readGraphJsonScript,
  decodeGraphData,
  graphsFromManifest,
  getGraphData,
  getGraphVariants,
  loadJson,
  loadManifestGraphs,
  loadGraphs
};

export { version };

export default graphCore;
