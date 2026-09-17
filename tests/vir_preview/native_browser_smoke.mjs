/* Copyright (c) 2026 Lean FRO LLC. Released under Apache 2.0. */

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = fileURLToPath(new URL("../../", import.meta.url));
assert.ok(process.env.VBP_NATIVE_PREVIEW_REPORT, "Set VBP_NATIVE_PREVIEW_REPORT to a report file");
const output = resolve(process.env.VBP_NATIVE_PREVIEW_REPORT);
const encodedDocument = process.argv.includes("--encoded-document");
const stringPreview = process.argv.includes("--string-preview") || encodedDocument;
const embeddedPreview = process.argv.includes("--embedded-preview");
const matchedBackend = process.env.VBP_NATIVE_MATCHED_BACKEND;
if (matchedBackend) assert.ok(embeddedPreview && ["vir", "fir"].includes(matchedBackend));
const embeddedFixture = matchedBackend ? "MatchedPreviewServer" : "EmbeddedPreviewServer";
const embeddedSourcePath = resolve(process.env.VBP_NATIVE_MATCHED_SOURCE ??
  resolve(root, `tests/VersoBlueprintVirTests/${embeddedFixture}.lean`));
const matchedFlt = Boolean(process.env.VBP_NATIVE_MATCHED_SOURCE);
assert.ok(!matchedFlt || matchedBackend, "external matched source requires a backend");
const manifest = JSON.parse(await readFile(resolve(root, "lake-manifest.json"), "utf8"));
const dependency = manifest.packages.find(p => p.name === "lean_vir");
assert.equal(dependency?.type, "git");
const virRoot = resolve(root, manifest.packagesDir, "lean_vir");
const sdkRoot = resolve(root, ".lake/build/vir/sdk");
const sdk = JSON.parse(await readFile(resolve(sdkRoot, "lean-vir-artifact.json"), "utf8"));
assert.equal(sdk.gitCommit, dependency.rev, "SDK must match the pinned Lean package");
assert.equal(sdk.gitDirty, false, "acceptance requires a clean-source SDK");
assert.equal(sdk.leanToolchain, (await readFile(resolve(root, "lean-toolchain"), "utf8")).trim());

// Reuse VIR's real-server transport and browser lifecycle, without a second LSP harness.
// This pinned internal test entry is temporary pending a supported external entry.
const harnessPath = resolve(virRoot, "tests/infoview/rpc-browser-harness.mjs");
let harnessSource = await readFile(harnessPath, "utf8");
const rootSite = 'const root = fileURLToPath(new URL("../../", import.meta.url));';
assert.equal(harnessSource.split(rootSite).length, 2, "pinned harness root drift");
harnessSource = harnessSource.replace(rootSite,
  `const root = ${JSON.stringify(stringPreview || embeddedPreview ? root : virRoot)};`);
const require = createRequire(resolve(virRoot, "package.json"));
harnessSource = harnessSource.replace(/from "([^"\n]+)"/g, (match, specifier) => {
  if (specifier.startsWith("node:")) return match;
  const path = specifier.startsWith(".") ? resolve(dirname(harnessPath), specifier) : require.resolve(specifier);
  return `from ${JSON.stringify(pathToFileURL(path).href)}`;
});
const { runRpcBrowserAcceptance } = await import(`data:text/javascript;base64,${Buffer.from(harnessSource).toString("base64")}`);
const { build } = await import(pathToFileURL(resolve(virRoot, "node_modules/esbuild/lib/main.js")));
const shellPath = embeddedPreview ? resolve(root, matchedBackend ? `.lake/build/matched-${matchedBackend}-demo.js` : ".lake/build/checked-json-demo.js")
  : resolve(virRoot, "build/generated/infoview/vir-infoview-widget.js");
const shellHash = embeddedPreview
  ? createHash("sha256").update(await readFile(shellPath)).digest("hex") : "";
const bundle = await build({
  entryPoints: [resolve(root, "tests/vir_preview/native_browser_entry.mjs")],
  bundle: true, format: "iife", platform: "browser", target: "chrome120", write: false,
  nodePaths: [resolve(virRoot, "node_modules")],
  alias: {
    "lean-vir": resolve(sdkRoot, "js/vir-runtime.js"),
    "lean-vir/host-bindings": resolve(sdkRoot, "js/vir-host-bindings.js"),
    "lean-vir/react-host-bindings": resolve(sdkRoot, "js/vir-react-host-bindings.js"),
    "@vir-test-support": resolve(virRoot, "tests/infoview/rpc-test-support.js"),
    "@vir-embedded-shell": shellPath,
  },
  // Match VIR's shell test seam: only the context accessor is supplied here.
  // It returns an official position-specific RpcSession, not a mock session.
  plugins: embeddedPreview ? [{
    name: "embedded-editor-context",
    setup(builder) {
      builder.onResolve({ filter: /^@leanprover\/infoview$/ }, () => ({
        path: "infoview", namespace: "vbp-embedded-test",
      }));
      builder.onLoad({ filter: /.*/, namespace: "vbp-embedded-test" }, () => ({
        contents: `export { DocumentPosition, EditorConnection, EditorContext, useClientNotificationEffect }
          from ${JSON.stringify(createRequire(resolve(virRoot, "package.json")).resolve("@leanprover/infoview"))};
          export { TaggedText_stripTags }
          from ${JSON.stringify(createRequire(resolve(virRoot, "package.json")).resolve("@leanprover/infoview-api"))};
          export function useRpcSession() { return globalThis.__vbpEmbeddedSession; }`,
        loader: "js", resolveDir: virRoot,
      }));
    },
  }] : [],
  define: {
    "process.env.NODE_ENV": '"development"',
    VBP_STRING_PREVIEW: JSON.stringify(stringPreview),
    VBP_ENCODED_DOCUMENT: JSON.stringify(encodedDocument),
    VBP_EMBEDDED_PREVIEW: JSON.stringify(embeddedPreview),
    VBP_MATCHED_PREVIEW: JSON.stringify(Boolean(matchedBackend)),
    VBP_MATCHED_FLT_PREVIEW: JSON.stringify(matchedFlt),
    VBP_EMBEDDED_SHELL_SHA256: JSON.stringify(shellHash),
    VBP_WASM_SHA256: JSON.stringify(sdk.files.find(f => f.path === "wasm/vir-upstream.wasm").sha256),
  },
});
const assets = new Map([["/probe.js", ["text/javascript", bundle.outputFiles[0].contents]]]);
if (embeddedPreview) assets.set("/blueprint-source", ["text/plain", await readFile(
  embeddedSourcePath, "utf8")]);
let packageMembers;
if (!embeddedPreview) {
  const descriptorPath = resolve(root,
    `.lake/build/vir/module-sets/VersoBlueprintVirTests/${stringPreview ? "StringPreview" : "NativePreview"}.irpkg-set.json`);
  const descriptorText = await readFile(descriptorPath, "utf8");
  const descriptor = JSON.parse(descriptorText);
  assert.equal(descriptor.version, 2);
  packageMembers = descriptor.packages.length;
  assets.set("/runtime.wasm", ["application/wasm", await readFile(resolve(sdkRoot, "wasm/vir-upstream.wasm"))]);
  assets.set("/widget.irpkg-set.json", ["application/json", descriptorText]);
  for (const member of descriptor.packages) {
    assets.set(`/${member.path}`, ["application/octet-stream",
      await readFile(resolve(dirname(descriptorPath), member.path))]);
  }
}
const acceptance = await runRpcBrowserAcceptance({
  assets,
  ...(stringPreview || embeddedPreview ? {
    sourcePath: embeddedPreview ? embeddedSourcePath : resolve(root, "tests/VersoBlueprintVirTests/StringPreviewServer.lean"),
  } : {}),
  label: embeddedPreview ? "VBP native embedded preview" : stringPreview ? "VBP string RPC preview" : "VBP native preview first slice",
});
// Evidence collection is outside the widget runtime. These are the relevant
// consumer seams, not a claim to freeze the complete dependency closure.
const sourceHashes = {};
for (const path of [
  "src/VersoBlueprintVir/Preview/Component.lean",
  ...["Content", "Session", "Shell", "Style"].map(name =>
    `src/VersoBlueprintVir/Preview/Component/${name}.lean`),
  "src/VersoBlueprintVir/Preview/Rpc.lean",
  "src/VersoBlueprintVir/Preview/Widget.lean",
  "tests/VersoBlueprintVirTests/NativePreview.lean",
  "tests/VersoBlueprintVirTests/StringPreview.lean",
  "tests/vir_preview/native_browser_entry.mjs",
]) sourceHashes[path] = createHash("sha256").update(await readFile(resolve(root, path))).digest("hex");
const report = {
  virCommit: dependency.rev, toolchain: sdk.leanToolchain,
  wasmSha256: sdk.files.find(f => f.path === "wasm/vir-upstream.wasm").sha256,
  packageMembers,
  encodedDocument, embeddedPreview, matchedBackend, sourceHashes,
  ...(embeddedPreview ? { fixtureSourcePath: embeddedSourcePath,
    fixtureSourceSha256: createHash("sha256").update(await readFile(embeddedSourcePath)).digest("hex") } : {}),
  sdkManifestSha256: createHash("sha256").update(await readFile(
    resolve(sdkRoot, "lean-vir-artifact.json"))).digest("hex"),
  versoParserSha256: createHash("sha256").update(await readFile(resolve(root,
    manifest.packagesDir, "verso/src/verso/Verso/Parser.lean"))).digest("hex"),
  scope: matchedFlt ? "matched full FLT document through registered shell and real LSP in Chromium; not VS Code or a timing campaign"
    : embeddedPreview ? "registered native shell with live package/asset/preview RPC; not VS Code or FLT"
    : encodedDocument ? "shared document-String RPC adapter and native document session; real server and Chromium, not FIR or FLT" : stringPreview
    ? "full VBP preview decoded from VBP-owned String RPC fixture; server cwd is VBP, not FLT"
    : "native Lean component with real VIR fixture RPC; not the FLT renderer",
  acceptance,
};
await mkdir(dirname(output), { recursive: true });
await writeFile(output, `${JSON.stringify(report, null, 2)}\n`);
console.log(JSON.stringify(report, null, 2));
// Preserve functional evidence even when the strict embedded lifetime gate fails.
if (embeddedPreview) assert.deepEqual(acceptance.warnings, [], "embedded shell must be React-warning-free");
