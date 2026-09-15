// Usage: node tests/vir_preview/fir_renderer_smoke.mjs FIR_WORKTREE PREPARED_VBP OUTPUT
// Read-only producer consumption. No Lean build, dependency retarget, or live demo mutation.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { createServer } from "node:http";
import { resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

assert.equal(process.argv.length, 5, "expected FIR_WORKTREE PREPARED_VBP OUTPUT");
const [firRoot, prepared, output] = process.argv.slice(2).map(path => resolve(path));
const root = fileURLToPath(new URL("../../", import.meta.url));
const checkpoint = "0c2eaa623640067406099afa9cef33e242c4136b";
const expectedWasm = "8729a670b5ba9c4f233cb5c7ca27b05c5f0658c8e9a764cee4a524182caf11e7";
const hash = bytes => createHash("sha256").update(bytes).digest("hex");
const manifest = JSON.parse(await readFile(resolve(root, "lake-manifest.json"), "utf8"));
const virCommit = manifest.packages.find(p => p.name === "lean_vir").rev;
const virRoot = resolve(prepared, ".lake/packages/lean_vir");
const sdkRoot = resolve(prepared, ".lake/build/vir/sdk");
const sdk = JSON.parse(await readFile(resolve(sdkRoot, "lean-vir-artifact.json"), "utf8"));
assert.equal(sdk.gitCommit, virCommit);
assert.equal(sdk.gitDirty, false);
assert.equal(sdk.leanToolchain, (await readFile(resolve(root, "lean-toolchain"), "utf8")).trim());
assert.equal(execFileSync("git", ["-C", virRoot, "rev-parse", "HEAD"], { encoding: "utf8" }).trim(), virCommit);
// Verify the SDK JS actually consumed, including transitive helper modules.
for (const file of sdk.files.filter(file => file.path.startsWith("js/"))) {
  assert.equal(hash(await readFile(resolve(sdkRoot, file.path))), file.sha256, file.path);
}
const product = resolve(firRoot, ".deps/native-session-probe/host-prototype");
const wasm = await readFile(resolve(product, "renderer.wasm"));
assert.equal(hash(wasm), expectedWasm, "producer artifact changed; do not silently adopt a successor");
const manifestBytes = await readFile(resolve(product, "renderer.wasm.json"));
const hostManifest = { imports: JSON.parse(manifestBytes).imports };
const adapter = execFileSync("git", ["-C", firRoot, "show",
  `${checkpoint}:integration/vbp-native-session-probe/host-prototype.mjs`]);
await mkdir(output, { recursive: true });
await writeFile(resolve(output, "host-prototype.mjs"), adapter);
await writeFile(resolve(output, "renderer.wasm"), wasm);
await writeFile(resolve(output, "manifest.json"), JSON.stringify(hostManifest));
const { build } = await import(pathToFileURL(resolve(virRoot, "node_modules/esbuild/lib/main.js")));
const options = {
  bundle: true, write: false, nodePaths: [resolve(virRoot, "node_modules")],
  alias: {
    "@fir-host-prototype": resolve(output, "host-prototype.mjs"),
    "@vir-react-bindings": resolve(sdkRoot, "js/vir-react-host-bindings.js"),
    "@vir-collection-bindings": resolve(sdkRoot, "js/host/vir-js-collection-bindings.js"),
    "@vir-value-bindings": resolve(sdkRoot, "js/host/vir-js-value-bindings.js"),
  },
  define: { "process.env.NODE_ENV": '"development"' },
};
const entry = resolve(root, "tests/vir_preview/fir_renderer_entry.mjs");
const ssrBundle = await build({ ...options, entryPoints: [entry], platform: "node", format: "esm",
  banner: { js: 'import { createRequire } from "node:module"; const require = createRequire(import.meta.url);' } });
const ssrPath = resolve(output, "ssr.mjs");
await writeFile(ssrPath, ssrBundle.outputFiles[0].contents);
const { runSsr } = await import(pathToFileURL(ssrPath));
const ssr = await runSsr(await WebAssembly.compile(wasm), hostManifest);
console.log("FIR real React SSR passed");
const browserBundle = await build({ ...options, platform: "browser", format: "iife", target: "chrome120",
  stdin: { contents: `import { runBrowser } from ${JSON.stringify(entry)};
    globalThis.firAcceptance = runBrowser().then(value => ({ok:true,value}),
      error => ({ok:false,error:String(error.stack ?? error)}));`, resolveDir: root } });
const script = browserBundle.outputFiles[0].contents;
await writeFile(resolve(output, "probe.js"), script);
const html = '<!doctype html><meta charset="utf-8"><div id="app"></div><script src="/probe.js"></script>';
await writeFile(resolve(output, "index.html"), html);
const assets = new Map([["/", ["text/html", html]], ["/probe.js", ["text/javascript", script]],
  ["/renderer.wasm", ["application/wasm", wasm]],
  ["/manifest.json", ["application/json", JSON.stringify(hostManifest)]]]);
const { launchChromium, openChromiumPage, navigate, evaluate } = await import(pathToFileURL(
  resolve(virRoot, "tests/browser/harness.mjs")));
const { withCleanup } = await import(pathToFileURL(resolve(virRoot, "tests/infoview/rpc-test-support.js")));
let server, chrome, cdp, deadline;
const browser = await withCleanup(async () => {
  server = createServer((req, res) => {
    const asset = assets.get(req.url);
    res.writeHead(asset ? 200 : 404, { "content-type": asset?.[0] ?? "text/plain" });
    res.end(asset?.[1] ?? "not found");
  });
  await new Promise((ready, reject) => { server.once("error", reject); server.listen(0, "127.0.0.1", ready); });
  chrome = await launchChromium();
  cdp = await openChromiumPage(chrome);
  const result = await Promise.race([(async () => {
    await navigate(cdp, `http://127.0.0.1:${server.address().port}/`);
    return evaluate(cdp, "globalThis.firAcceptance");
  })(), new Promise((_, reject) => { deadline = setTimeout(() => reject(new Error("FIR browser timeout")), 60000); })]);
  assert.equal(result?.ok, true, JSON.stringify(result));
  return result.value;
}, [["deadline", () => clearTimeout(deadline)], ["CDP", () => cdp?.close()],
  ["Chromium", () => chrome?.close()],
  ["HTTP server", () => server?.listening && new Promise(done => server.close(done))]]);
const report = { checkpoint, wasmSha256: hash(wasm), wasmBytes: wasm.length,
  adapterSha256: hash(adapter), manifestSha256: hash(manifestBytes), virCommit,
  toolchain: sdk.leanToolchain, react: sdk.externalDependencies.react, ssr, browser,
  limitations: ["title-only Lean fixture", "no arbitrary Document/Options input",
    "no RPC or full preview controls", "no timing comparison", "host exception fix not adopted"] };
await writeFile(resolve(output, "acceptance.json"), JSON.stringify(report, null, 2) + "\n");
console.log(JSON.stringify(report, null, 2));
