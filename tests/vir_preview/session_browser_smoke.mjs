/* Copyright (c) 2026 Lean FRO LLC. Released under Apache 2.0. */

import assert from "node:assert/strict";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = fileURLToPath(new URL("../../", import.meta.url));
const manifest = JSON.parse(await readFile(resolve(root, "lake-manifest.json"), "utf8"));
const dependency = manifest.packages.find(p => p.name === "lean_vir");
assert.equal(dependency?.type, "git");
const virRoot = resolve(root, manifest.packagesDir, "lean_vir");
const sdkRoot = resolve(root, ".lake/build/vir/sdk");
const sdk = JSON.parse(await readFile(resolve(sdkRoot, "lean-vir-artifact.json"), "utf8"));
assert.equal(sdk.gitCommit, dependency.rev);
assert.equal(sdk.gitDirty, false);
assert.equal(sdk.leanToolchain, (await readFile(resolve(root, "lean-toolchain"), "utf8")).trim());

// Reuse the pinned generic browser driver; no new CDP or LSP implementation.
const { launchChromium, openChromiumPage, navigate, evaluate } = await import(pathToFileURL(
  resolve(virRoot, "tests/browser/harness.mjs")));
const { withCleanup } = await import(pathToFileURL(
  resolve(virRoot, "tests/infoview/rpc-test-support.js")));
const { build } = await import(pathToFileURL(resolve(virRoot, "node_modules/esbuild/lib/main.js")));
const bundle = await build({
  entryPoints: [resolve(root, "tests/vir_preview/session_browser_entry.mjs")],
  bundle: true, format: "iife", platform: "browser", target: "chrome120", write: false,
  nodePaths: [resolve(virRoot, "node_modules")],
  alias: {
    "lean-vir": resolve(sdkRoot, "js/vir-runtime.js"),
    "lean-vir/host-bindings": resolve(sdkRoot, "js/vir-host-bindings.js"),
    "lean-vir/react-host-bindings": resolve(sdkRoot, "js/vir-react-host-bindings.js"),
    "@vir-test-support": resolve(virRoot, "tests/infoview/rpc-test-support.js"),
  },
  define: { "process.env.NODE_ENV": '"development"' },
});
const descriptorPath = resolve(root,
  ".lake/build/vir/module-sets/VersoBlueprintVirTests/NativeSession.irpkg-set.json");
const descriptorText = await readFile(descriptorPath, "utf8");
const descriptor = JSON.parse(descriptorText);
assert.equal(descriptor.version, 2);
const assets = new Map([
  ["/", ["text/html", '<!doctype html><div id="app"></div><script src="/probe.js"></script>']],
  ["/probe.js", ["text/javascript", bundle.outputFiles[0].contents]],
  ["/runtime.wasm", ["application/wasm", await readFile(resolve(sdkRoot, "wasm/vir-upstream.wasm"))]],
  ["/widget.irpkg-set.json", ["application/json", descriptorText]],
]);
for (const member of descriptor.packages) {
  assets.set(`/${member.path}`, ["application/octet-stream",
    await readFile(resolve(dirname(descriptorPath), member.path))]);
}
let server, chrome, cdp, deadline;
const acceptance = await withCleanup(async () => {
  server = createServer((req, res) => {
    const asset = req.method === "GET" && assets.get(req.url);
    res.writeHead(asset ? 200 : 404, { "content-type": asset?.[0] ?? "text/plain" });
    res.end(asset?.[1] ?? "not found");
  });
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  chrome = await launchChromium();
  cdp = await openChromiumPage(chrome);
  const result = await Promise.race([
    (async () => {
      await navigate(cdp, `http://127.0.0.1:${server.address().port}/`);
      return evaluate(cdp, "globalThis.sessionAcceptance");
    })(),
    new Promise((_, reject) => { deadline = setTimeout(() => reject(
      new Error("native session browser acceptance timed out")), 60000); }),
  ]);
  assert.equal(result?.ok, true, JSON.stringify(result));
  return result.value;
}, [
  ["deadline", () => clearTimeout(deadline)],
  ["CDP", () => cdp?.close()],
  ["Chromium", () => chrome?.close()],
  ["HTTP server", () => server && new Promise(resolve => server.close(resolve))],
]);
const report = { virCommit: dependency.rev, toolchain: sdk.leanToolchain,
  packageMembers: descriptor.packages.length, acceptance };
const output = resolve(process.env.VBP_NATIVE_SESSION_REPORT);
await mkdir(dirname(output), { recursive: true });
await writeFile(output, `${JSON.stringify(report, null, 2)}\n`);
console.log(JSON.stringify(report, null, 2));
