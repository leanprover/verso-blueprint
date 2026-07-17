import { access, readFile } from "node:fs/promises";
import path from "node:path";

const typesDir = path.resolve("dist/types/src/VersoBlueprint");
const contractPath = path.resolve("tests/preview_runtime_api_contract.json");
const publicApiContract = JSON.parse(await readFile(contractPath, "utf8"));
const publicApiTypeExports = Array.isArray(publicApiContract.typeExports)
  ? publicApiContract.typeExports
  : [];
const failures = [];

function fail(message) {
  failures.push(message);
}

async function requireDeclaration(relativePath) {
  const absolutePath = path.join(typesDir, relativePath);
  try {
    await access(absolutePath);
  } catch {
    fail(`missing generated declaration file: ${relativePath}`);
    return "";
  }
  return readFile(absolutePath, "utf8");
}

function requireMatches(relativePath, text, pattern, description) {
  if (!pattern.test(text)) {
    fail(`${relativePath}: missing ${description}`);
  }
}

function rejectMatches(relativePath, text, pattern, description) {
  if (pattern.test(text)) {
    fail(`${relativePath}: found ${description}`);
  }
}

function exportedValueNames(text) {
  const names = new Set();
  for (const match of text.matchAll(/^export function ([A-Za-z][A-Za-z0-9_]*)\b/gm)) {
    names.add(match[1]);
  }
  for (const match of text.matchAll(/^export const ([A-Za-z][A-Za-z0-9_]*)\b/gm)) {
    names.add(match[1]);
  }
  for (const match of text.matchAll(/^export \{ ([A-Za-z][A-Za-z0-9_]*) \};/gm)) {
    names.add(match[1]);
  }
  return names;
}

function exportedTypeNames(text) {
  const names = new Set();
  for (const match of text.matchAll(/^export type ([A-Za-z][A-Za-z0-9_]*)\b/gm)) {
    names.add(match[1]);
  }
  return names;
}

function requireExactNames(description, actualNames, expectedNames) {
  const expected = new Set(expectedNames);
  const missing = [...expected].filter((name) => !actualNames.has(name)).sort();
  const extra = [...actualNames].filter((name) => !expected.has(name)).sort();
  if (missing.length > 0 || extra.length > 0) {
    fail(`${description} mismatch; missing=[${missing.join(", ")}] extra=[${extra.join(", ")}]`);
  }
}

function requireExactExports(relativePath, text, expectedNames) {
  const actualNames = exportedValueNames(text);
  requireExactNames(`${relativePath}: public declaration exports`, actualNames, expectedNames);
}

function requireExactTypeExports(relativePath, text, expectedNames) {
  const actualNames = exportedTypeNames(text);
  requireExactNames(`${relativePath}: public type exports`, actualNames, expectedNames);
}

function requireTypeBlock(relativePath, text, typeName) {
  const pattern = new RegExp(`export type ${typeName} = \\{[\\s\\S]*?\\n\\};`);
  const match = text.match(pattern);
  if (!match) {
    fail(`${relativePath}: missing ${typeName} typedef`);
    return "";
  }
  return match[0];
}

function declarationFilename(entry) {
  return path.basename(entry.declaration);
}

const declarationEntries = [
  publicApiContract.typesModule,
  publicApiContract.modules.data,
  publicApiContract.modules.graph,
  publicApiContract.modules.preview
];
const declarations = Object.fromEntries(await Promise.all(
  declarationEntries.map(async (entry) => {
    const filename = declarationFilename(entry);
    return [filename, await requireDeclaration(filename)];
  })
));

const apiTypesDeclaration = declarationFilename(publicApiContract.typesModule);
const dataDeclaration = declarationFilename(publicApiContract.modules.data);
const graphDeclaration = declarationFilename(publicApiContract.modules.graph);
const previewDeclaration = declarationFilename(publicApiContract.modules.preview);
const apiTypes = declarations[apiTypesDeclaration];

for (const [relativePath, text] of Object.entries(declarations)) {
  rejectMatches(relativePath, text, /module:blueprint-api-types~/, "JSDoc longname leak");
  rejectMatches(relativePath, text, /(:|=>|<|,)\s*any\b/, "public API any type");
}

requireExactExports(
  dataDeclaration,
  declarations[dataDeclaration],
  publicApiContract.exports.data
);
requireExactExports(
  graphDeclaration,
  declarations[graphDeclaration],
  publicApiContract.exports.graph
);
requireExactExports(
  previewDeclaration,
  declarations[previewDeclaration],
  publicApiContract.exports.preview
);
requireExactTypeExports(
  apiTypesDeclaration,
  apiTypes,
  publicApiTypeExports
);

requireMatches(
  previewDeclaration,
  declarations[previewDeclaration],
  /export function createPreview\(options\?: BlueprintPreviewOptions\): BlueprintPreviewApi;/,
  "typed createPreview export"
);
requireMatches(
  previewDeclaration,
  declarations[previewDeclaration],
  /export function renderNode\(element: Element, request: string \| BlueprintRenderNodeRequest, options\?: BlueprintPreviewOptions\): Promise<BlueprintRenderNodeResult>;/,
  "typed module-level renderNode export"
);
requireMatches(
  previewDeclaration,
  declarations[previewDeclaration],
  /export function hydrate\(element: Element, options\?: BlueprintPreviewOptions\): Promise<boolean>;/,
  "async module-level hydrate export"
);

requireMatches(
  dataDeclaration,
  declarations[dataDeclaration],
  /export function createPreviewData\(options\?: BlueprintDataApiOptions\): BlueprintDataApi;/,
  "typed createPreviewData export"
);
requireMatches(
  dataDeclaration,
  declarations[dataDeclaration],
  /export function loadHtmlCacheEntry\(key: string, options\?: BlueprintDataApiOptions\): Promise<BlueprintHtmlCacheEntry \| null>;/,
  "typed data loadHtmlCacheEntry export"
);

requireMatches(
  graphDeclaration,
  declarations[graphDeclaration],
  /export function loadGraphs\(options\?: BlueprintDataApiOptions\): Promise<BlueprintGraphData\[]>;/,
  "typed graph loadGraphs export"
);
requireMatches(
  graphDeclaration,
  declarations[graphDeclaration],
  /export function renderGraphBlock\(graphBlock: Element, options\?: BlueprintGraphRenderOptions\): Promise<BlueprintGraphController \| null>;/,
  "typed graph renderGraphBlock export"
);

const graphApiNames = [
  "decodeGraphData",
  "graphsFromManifest",
  ...publicApiContract.exports.graph.filter(
    (name) => !["dataUrl", "graphApiModuleUrl", "renderGraphBlock", "renderGraphs", "version"].includes(name)
  )
];
const graphInternalApiNames = [
  "ensureGraphRuntimeLibraries",
  "getGraphRenderApi",
  "graphCanvasFor",
  "decodeGraphData",
  "graphsFromManifest",
  "initGraphBlock",
  "installGraphRenderApi",
  "loadJson",
  "readGraphJsonScript"
];

for (const apiName of graphApiNames) {
  rejectMatches(
    dataDeclaration,
    declarations[dataDeclaration],
    new RegExp(`export (?:function|const) ${apiName}\\b`),
    `${apiName} data API export`
  );
  rejectMatches(
    previewDeclaration,
    declarations[previewDeclaration],
    new RegExp(`export (?:function|const) ${apiName}\\b`),
    `${apiName} preview API export`
  );
}
for (const apiName of graphInternalApiNames) {
  rejectMatches(
    graphDeclaration,
    declarations[graphDeclaration],
    new RegExp(`export (?:function|const) ${apiName}\\b`),
    `${apiName} graph API export`
  );
}

const dataApiType = requireTypeBlock(
  apiTypesDeclaration,
  apiTypes,
  "BlueprintDataApi"
);
const previewApiType = requireTypeBlock(
  apiTypesDeclaration,
  apiTypes,
  "BlueprintPreviewApi"
);
requireMatches(
  apiTypesDeclaration,
  dataApiType,
  /dataUrl: \(arg0: string\) => string;[\s\S]*?loadManifest: \(arg0: BlueprintDataApiOptions \| undefined\) => Promise<Map<string, BlueprintManifestEntry>>;[\s\S]*?loadHtmlCacheEntry: \(arg0: string, arg1: BlueprintDataApiOptions \| undefined\) => Promise<\(?BlueprintHtmlCacheEntry \| null\)?>;/,
  "BlueprintDataApi manifest/cache object shape"
);
requireMatches(
  apiTypesDeclaration,
  previewApiType,
  /dataUrl: \(arg0: string\) => string;[\s\S]*?resolvePreview: \(arg0: string, arg1: BlueprintDataApiOptions \| undefined\) => Promise<BlueprintPreviewResult>;[\s\S]*?renderNode: \(arg0: Element, arg1: \(string \| BlueprintRenderNodeRequest\), arg2: BlueprintPreviewOptions \| undefined\) => Promise<BlueprintRenderNodeResult>;[\s\S]*?hydrate: \(arg0: Element, arg1: BlueprintPreviewOptions \| undefined\) => boolean;/,
  "BlueprintPreviewApi render object shape"
);
for (const apiName of graphApiNames) {
  rejectMatches(
    apiTypesDeclaration,
    dataApiType,
    new RegExp(`\\b${apiName}:`),
    `${apiName} on BlueprintDataApi`
  );
  rejectMatches(
    apiTypesDeclaration,
    previewApiType,
    new RegExp(`\\b${apiName}:`),
    `${apiName} on BlueprintPreviewApi`
  );
}
requireMatches(
  apiTypesDeclaration,
  apiTypes,
  /export type BlueprintExternalMarkupRenderer = \(payload: BlueprintExternalMarkupPayload, target: Element\) => void \| string \| Node \| Promise<void \| string \| Node>;/,
  "external-markup renderer callback"
);

if (failures.length > 0) {
  console.error("JavaScript API declaration check failed:");
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log("JavaScript API declaration check passed.");
