import { dataUrl as graphDataUrl } from "./blueprint-graph-core.mjs";

const version = 1;

export function dataUrl(filename, baseUrl) {
  return graphDataUrl(filename, baseUrl);
}

export function manifestUrl(baseUrl) {
  return dataUrl("blueprint-manifest.json", baseUrl);
}

export function htmlCacheUrl(baseUrl) {
  return dataUrl("blueprint-html-cache.json", baseUrl);
}

export function graphApiModuleUrl(baseUrl) {
  return dataUrl("api/graph.mjs", baseUrl);
}

export function dataApiModuleUrl(baseUrl) {
  return dataUrl("api/data.mjs", baseUrl);
}

export function previewApiModuleUrl(baseUrl) {
  return dataUrl("api/preview.mjs", baseUrl);
}

export function previewKey(label, facet) {
  const trimmedLabel = typeof label === "string" ? label.trim() : "";
  if (!trimmedLabel) return "";
  const trimmedFacet =
    typeof facet === "string" && facet.trim() ? facet.trim() : "statement";
  return trimmedLabel + "--" + trimmedFacet;
}

export function statementPreviewKey(label) {
  return previewKey(label, "statement");
}

export const previewCore = {
  version,
  dataUrl,
  manifestUrl,
  htmlCacheUrl,
  graphApiModuleUrl,
  dataApiModuleUrl,
  previewApiModuleUrl,
  previewKey,
  statementPreviewKey
};

export { version };

export default previewCore;
