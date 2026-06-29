import { access, readdir, readFile } from "node:fs/promises";
import path from "node:path";

const docsDir = path.resolve("_out/jsdoc-api");
const contractPath = path.resolve("tests/preview_runtime_api_contract.json");
const publicApiContract = JSON.parse(await readFile(contractPath, "utf8"));
const publicApiDocPages = [
  ...Object.values(publicApiContract.modules).map((entry) => entry.jsdocPage),
  publicApiContract.typesModule.jsdocPage
];
const publicApiTypeExports = Array.isArray(publicApiContract.typeExports)
  ? publicApiContract.typeExports
  : [];
const dataPage = publicApiContract.modules.data.jsdocPage;
const graphPage = publicApiContract.modules.graph.jsdocPage;
const previewPage = publicApiContract.modules.preview.jsdocPage;
const typesPage = publicApiContract.typesModule.jsdocPage;
const failures = [];
const textCache = new Map();

function fail(message) {
  failures.push(message);
}

async function requireReadableFile(relativePath) {
  const absolutePath = path.join(docsDir, relativePath);
  try {
    await access(absolutePath);
  } catch {
    fail(`missing generated docs file: ${relativePath}`);
    return "";
  }
  const text = await readFile(absolutePath, "utf8");
  textCache.set(relativePath, text);
  return text;
}

function requireIncludes(relativePath, text, needle, description) {
  if (!text.includes(needle)) {
    fail(`${relativePath}: missing ${description}`);
  }
}

function requireMatches(relativePath, text, pattern, description) {
  if (!pattern.test(text)) {
    fail(`${relativePath}: missing ${description}`);
  }
}

function quotedStringArray(relativePath, text, variableName) {
  const pattern = new RegExp(`(?:\\bvar\\s+|\\bglobalScope\\.)${variableName}\\s*=\\s*\\[([\\s\\S]*?)\\];`);
  const match = text.match(pattern);
  if (!match) {
    fail(`${relativePath}: missing ${variableName} string array`);
    return [];
  }
  return [...match[1].matchAll(/"([^"]+)"/g)].map((item) => item[1]);
}

function requireSameStringSet(description, actualNames, expectedNames) {
  const actual = new Set(actualNames);
  const expected = new Set(expectedNames);
  const duplicateActual = actualNames.filter((name, index) => actualNames.indexOf(name) !== index);
  const duplicateExpected = expectedNames.filter((name, index) => expectedNames.indexOf(name) !== index);
  const missing = [...expected].filter((name) => !actual.has(name)).sort();
  const extra = [...actual].filter((name) => !expected.has(name)).sort();

  if (
    duplicateActual.length > 0 ||
    duplicateExpected.length > 0 ||
    missing.length > 0 ||
    extra.length > 0
  ) {
    fail(
      `${description} mismatch` +
      `; missing=[${missing.join(", ")}] extra=[${extra.join(", ")}]` +
      ` duplicateActual=[${[...new Set(duplicateActual)].sort().join(", ")}]` +
      ` duplicateExpected=[${[...new Set(duplicateExpected)].sort().join(", ")}]`
    );
  }
}

async function listFiles(relativeDir = "") {
  const absoluteDir = path.join(docsDir, relativeDir);
  const entries = await readdir(absoluteDir, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const relativePath = path.join(relativeDir, entry.name);
    if (entry.isDirectory()) {
      files.push(...await listFiles(relativePath));
    } else if (entry.isFile()) {
      files.push(relativePath);
    }
  }
  return files;
}

function localHrefTarget(currentFile, href) {
  if (
    href === "" ||
    href.startsWith("http://") ||
    href.startsWith("https://") ||
    href.startsWith("mailto:") ||
    href.startsWith("javascript:") ||
    href.startsWith("data:")
  ) {
    return null;
  }

  const [filePart, hashPart] = href.split("#", 2);
  const targetFile = filePart === ""
    ? currentFile
    : path.normalize(path.join(path.dirname(currentFile), filePart));
  if (targetFile.startsWith("..") || path.isAbsolute(targetFile)) {
    return { file: targetFile, hash: hashPart || "", invalidPath: true };
  }
  return { file: targetFile, hash: hashPart || "", invalidPath: false };
}

function htmlHasAnchor(html, rawHash) {
  if (!rawHash) return true;

  let hash = rawHash;
  try {
    hash = decodeURIComponent(rawHash);
  } catch {
    hash = rawHash;
  }

  return (
    html.includes(`id="${hash}"`) ||
    html.includes(`id='${hash}'`) ||
    html.includes(`name="${hash}"`) ||
    html.includes(`name='${hash}'`)
  );
}

async function checkLocalLinks() {
  const files = await listFiles();
  const allFiles = new Set(files);
  const htmlFiles = files.filter((file) => file.endsWith(".html"));
  const hrefPattern = /\bhref=(["'])(.*?)\1/g;

  for (const htmlFile of htmlFiles) {
    const html = textCache.get(htmlFile) || await requireReadableFile(htmlFile);
    for (const match of html.matchAll(hrefPattern)) {
      const href = match[2].replaceAll("&amp;", "&");
      const target = localHrefTarget(htmlFile, href);
      if (!target) continue;
      if (target.invalidPath || !allFiles.has(target.file)) {
        fail(`${htmlFile}: broken local link to ${href}`);
        continue;
      }
      if (target.hash) {
        const targetHtml = textCache.get(target.file) || await requireReadableFile(target.file);
        if (!htmlHasAnchor(targetHtml, target.hash)) {
          fail(`${htmlFile}: broken local anchor ${href}`);
        }
      }
    }
  }
}

async function checkPublicModulePages() {
  const files = await listFiles();
  const expectedModulePages = new Set(publicApiDocPages);
  const modulePages = files.filter((file) => file.startsWith("module-") && file.endsWith(".html"));
  for (const modulePage of modulePages) {
    if (!expectedModulePages.has(modulePage)) {
      fail(`unexpected generated public module page: ${modulePage}`);
    }
  }
}

const pages = {
  "index.html": await requireReadableFile("index.html"),
  "jsdoc-type-names.js": await requireReadableFile("jsdoc-type-names.js"),
  "jsdoc-type-links.js": await requireReadableFile("jsdoc-type-links.js")
};

for (const page of publicApiDocPages) {
  pages[page] = await requireReadableFile(page);
}

requireSameStringSet(
  "public API type-link names",
  quotedStringArray("jsdoc-type-names.js", pages["jsdoc-type-names.js"], "blueprintJSDocTypeNames"),
  publicApiTypeExports
);

requireIncludes(
  "index.html",
  pages["index.html"],
  "Verso Blueprint JavaScript API",
  "landing-page title"
);
for (const entry of [...Object.values(publicApiContract.modules), publicApiContract.typesModule]) {
  requireIncludes("index.html", pages["index.html"], entry.jsdocPage, `${entry.jsdocPage} guide link`);
}
requireIncludes(
  "index.html",
  pages["index.html"],
  "Start from the kind of client you are writing",
  "client-selection guide"
);
requireIncludes(
  "index.html",
  pages["index.html"],
  "Rendering Paths",
  "rendering-path guide"
);

requireMatches(
  previewPage,
  pages[previewPage],
  /id="\.createPreview"[\s\S]*?&rarr; \{BlueprintPreviewApi\}/,
  "createPreview return type"
);
requireIncludes(
  previewPage,
  pages[previewPage],
  "Common rendering choices",
  "preview module rendering guidance"
);
requireIncludes(
  previewPage,
  pages[previewPage],
  "await preview.renderCanonicalPreviewInto",
  "createPreview example"
);
requireMatches(
  previewPage,
  pages[previewPage],
  /id="\.renderNode"[\s\S]*?&rarr; \{Promise\.&lt;BlueprintRenderNodeResult>\}/,
  "renderNode result type"
);
requireMatches(
  previewPage,
  pages[previewPage],
  /<script src="jsdoc-type-names\.js"><\/script>[\s\S]*?<script src="jsdoc-type-links\.js"><\/script>/,
  "typedef name and linking scripts"
);
requireMatches(
  previewPage,
  pages[previewPage],
  /<script src="jsdoc-type-links\.js"><\/script>/,
  "typedef-linking script"
);

requireMatches(
  dataPage,
  pages[dataPage],
  /id="\.createPreviewData"[\s\S]*?&rarr; \{BlueprintDataApi\}/,
  "createPreviewData return type"
);
requireIncludes(
  dataPage,
  pages[dataPage],
  "The manifest is the semantic data source",
  "data module manifest guidance"
);
requireMatches(
  graphPage,
  pages[graphPage],
  /id="\.loadGraphs"[\s\S]*?Load finalized graph records from this generated site's default manifest\./,
  "loadGraphs documentation"
);
requireIncludes(
  graphPage,
  pages[graphPage],
  "explicit preview renderer from <code>api/preview.mjs</code>",
  "graph module preview renderer guidance"
);

for (const typeName of publicApiTypeExports) {
  requireIncludes(
    typesPage,
    pages[typesPage],
    `id="~${typeName}"`,
    `${typeName} typedef anchor`
  );
  requireIncludes(
    "jsdoc-type-names.js",
    pages["jsdoc-type-names.js"],
    `"${typeName}"`,
    `${typeName} client-side link mapping`
  );
}

requireIncludes(
  "jsdoc-type-links.js",
  pages["jsdoc-type-links.js"],
  `${typesPage}#~`,
  "typedef target prefix"
);

await checkLocalLinks();
await checkPublicModulePages();

if (failures.length > 0) {
  console.error("JavaScript API docs smoke check failed:");
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log("JavaScript API docs smoke check passed.");
