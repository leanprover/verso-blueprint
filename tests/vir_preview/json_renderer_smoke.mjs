// Immutable FIR + frozen VIR control, existing shared Document inputs; no timings.
// Usage: node json_renderer_smoke.mjs FIR_ROOT PREPARED_VBP CONSUMER INPUTS NEW_OUTPUT
import assert from "node:assert/strict";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { createServer } from "node:http";
import { resolve, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
assert.equal(process.argv.length, 7);
const [firRoot, prepared, consumer, inputsDir, output] = process.argv.slice(2).map(p => resolve(p));
const root = fileURLToPath(new URL("../../", import.meta.url));
const sha = bytes => createHash("sha256").update(bytes).digest("hex");
const current = process.env.VBP_MATCHED_CURRENT === "1";
const checkpoint = current ? "4776f86edae9177f352feb4a4af1b5110f239fa3" : "a48bbb4a30b3f06604149cde95d39173439bbbbd";
const virCommit = current ? "36d26bc224f0c2a52cd586587b2c3e1b1ade70d6" : "9fafe9cfd594213ee39dc8205b08084c31101816";
const sdkRoot = resolve(prepared, ".lake/build/vir/sdk"), virRoot = resolve(prepared, ".lake/packages/lean_vir");
const sdkBytes = await readFile(resolve(sdkRoot, "lean-vir-artifact.json"));
const sdk = JSON.parse(sdkBytes);
assert.equal(sdk.gitCommit, virCommit); assert.equal(sdk.gitDirty, false);
assert.equal(sdk.leanToolchain, "leanprover/lean4:v4.34.0-rc2");
for (const file of sdk.files) assert.equal(sha(await readFile(resolve(sdkRoot, file.path))), file.sha256, file.path);
const product = resolve(firRoot, current ? ".deps/native-session-probe/retarget-92db6325-36d26bc2/lower" : ".deps/native-session-probe/host-prototype-json-resident");
const wasm = await readFile(resolve(product, "renderer.wasm"));
assert.equal(sha(wasm), current ? "c040db3abbe40b34f0fe22fcfbe1c14c997f6ea7753be678ec5f439846272024" : "d654a4aca5281905d213ac0951b526bb21d16c22f2d2d51d841c455fee978526");
const manifestBytes = await readFile(resolve(product, "renderer.wasm.json"));
const manifest = { imports: JSON.parse(manifestBytes).imports };
const adapter = execFileSync("git", ["-C", firRoot, "show", `${checkpoint}:integration/vbp-native-session-probe/host-prototype.mjs`]);
assert.equal(sha(adapter), current ? "83f2199006e8d4ac69709c52107e7dbff159cd5e2da30faeb183e00209b7d287" : "05573ac23720446e7516637587b6cccc7b55bb80725829bb5bd70bd097c5a1de");
await mkdir(output, { recursive: false });
await writeFile(resolve(output, "host-prototype.mjs"), adapter);
if (current) {
  const abi = execFileSync("git", ["-C", firRoot, "show", `${checkpoint}:integration/vbp-native-session-probe/host-bool-abi.mjs`]);
  assert.equal(sha(abi), "c6ff62981528f8957e47b657f14c8c84ca36f318443d782149f3b194d94cdb5e");
  await writeFile(resolve(output, "host-bool-abi.mjs"), abi);
}
const descriptorPath = resolve(consumer, ".lake/build/vir/module-sets/MatchedRenderer.irpkg-set.json");
const descriptor = JSON.parse(await readFile(descriptorPath));
const packages = await Promise.all(descriptor.packages.map(p => readFile(resolve(dirname(descriptorPath), p.path))));
const flt = await Promise.all(["before", "after"].map(name => readFile(resolve(inputsDir, `${name}.document.json`), "utf8")));
const inputInventory = JSON.parse(await readFile(resolve(inputsDir, "inputs.json")));
const identity = { checkpoint, virCommit, wasmSha256: sha(wasm), manifestSha256: sha(manifestBytes),
  adapterSha256: sha(adapter), sdkManifestSha256: sha(sdkBytes), toolchain: sdk.leanToolchain,
  consumer: JSON.parse(await readFile(resolve(consumer, "identity.json"))),
  controlPackages: packages.map(sha), flt: flt.map(input => ({ bytes: Buffer.byteLength(input), sha256: sha(input) })),
  capturedInputInventory: inputInventory, noTimings: true };
await writeFile(resolve(output, "identity.json"), JSON.stringify(identity, null, 2));
const { build } = await import(pathToFileURL(resolve(virRoot, "node_modules/esbuild/lib/main.js")));
const entry = resolve(root, "tests/vir_preview/json_renderer_entry.mjs");
const options = { bundle: true, write: false, nodePaths: [resolve(virRoot, "node_modules")],
  alias: { "@fir-host-prototype": resolve(output, "host-prototype.mjs"),
    "lean-vir": resolve(sdkRoot, "js/vir-runtime.js"),
    "lean-vir/host-bindings": resolve(sdkRoot, "js/vir-host-bindings.js"),
    "@vir-react-bindings": resolve(sdkRoot, "js/vir-react-host-bindings.js"),
    "@vir-collection-bindings": resolve(sdkRoot, "js/host/vir-js-collection-bindings.js"),
    "@vir-value-bindings": resolve(sdkRoot, "js/host/vir-js-value-bindings.js") },
  define: { "process.env.NODE_ENV": '"development"' } };
const ssrBundle = await build({ ...options, entryPoints: [entry], platform: "node", format: "esm",
  banner: { js: 'import { createRequire } from "node:module"; const require = createRequire(import.meta.url);' } });
await writeFile(resolve(output, "ssr.mjs"), ssrBundle.outputFiles[0].contents);
const { runSsr } = await import(pathToFileURL(resolve(output, "ssr.mjs")));
const ssr = await runSsr({ firModule: await WebAssembly.compile(wasm), manifest,
  wasmBytes: await readFile(resolve(sdkRoot, "wasm/vir-upstream.wasm")), irPackageSet: packages, flt });
await writeFile(resolve(output, "ssr.json"), JSON.stringify(ssr.report, null, 2));
await writeFile(resolve(output, "inputs.json"), JSON.stringify(ssr.inputs));
for (const [i, html] of ssr.html.entries()) await writeFile(resolve(output, `document-${i}.html`), html);
const bundle = await build({ ...options, platform: "browser", format: "iife", target: "chrome120",
  stdin: { contents: `import { runBrowser } from ${JSON.stringify(entry)};
    globalThis.acceptance = runBrowser().then(value => ({ok:true,value}), error => ({ok:false,error:String(error.stack ?? error)}));`, resolveDir: root } });
const assets = new Map([["/", ["text/html", '<!doctype html><meta charset="utf-8"><div id="app"></div><script src="/probe.js"></script>']],
  ["/probe.js", ["text/javascript", bundle.outputFiles[0].contents]],
  ["/renderer.wasm", ["application/wasm", wasm]], ["/manifest.json", ["application/json", JSON.stringify(manifest)]],
  ["/inputs.json", ["application/json", JSON.stringify(ssr.inputs)]],
  ["/runtime.wasm", ["application/wasm", await readFile(resolve(sdkRoot, "wasm/vir-upstream.wasm"))]],
  ["/control.irpkg-set.json", ["application/json", JSON.stringify({ ...descriptor,
    packages: descriptor.packages.map((p, i) => ({ ...p, path: `control-${i}.irpkg` })) })]]]);
for (const [i, bytes] of packages.entries()) assets.set(`/control-${i}.irpkg`, ["application/octet-stream", bytes]);
for (const [i, name] of ["before", "after"].entries()) assets.set(`/${name}.document.json`, ["application/json", flt[i]]);
const { launchChromium, openChromiumPage, navigate, evaluate } = await import(pathToFileURL(resolve(virRoot, "tests/browser/harness.mjs")));
let server, chrome, cdp, deadline;
try {
  server = createServer((req, res) => { const asset = assets.get(req.url);
    res.writeHead(asset ? 200 : 404, { "content-type": asset?.[0] ?? "text/plain" }); res.end(asset?.[1] ?? "not found"); });
  await new Promise((done, reject) => { server.once("error", reject); server.listen(0, "127.0.0.1", done); });
  chrome = await launchChromium(); cdp = await openChromiumPage(chrome);
  await navigate(cdp, `http://127.0.0.1:${server.address().port}/`);
  const browser = await Promise.race([evaluate(cdp, "globalThis.acceptance"),
    new Promise((_, reject) => { deadline = setTimeout(() => reject(Error("browser acceptance timeout")), 180000); })]);
  await writeFile(resolve(output, "browser.json"), JSON.stringify(browser, null, 2));
  assert.equal(browser?.ok, true, JSON.stringify(browser));
  console.log(JSON.stringify({ ssr: ssr.report, browser: browser.value }, null, 2));
} finally {
  clearTimeout(deadline); await cdp?.close(); await chrome?.close();
  if (server?.listening) await new Promise(done => server.close(done));
}
