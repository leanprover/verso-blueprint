/* Reuse the existing session browser driver with a diagnostic package/payload. */
import assert from "node:assert/strict";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createHash } from "node:crypto";

// An explicit root lets the same driver compare two source/SDK checkpoints.
const root = resolve(process.env.VBP_REPLAY_ROOT ?? fileURLToPath(new URL("../../", import.meta.url)));
// A retained package set permits order-balanced source comparisons on one SDK.
const descriptorPath = resolve(process.env.VBP_REPLAY_PACKAGE_SET ?? resolve(root,
  ".lake/build/vir/module-sets/VersoBlueprintVirTests/NativeSession/DecodeProbe.irpkg-set.json"));
const [inputArg, outputArg] = process.argv.slice(2);
const replayUpdates = Number(process.env.VBP_REPLAY_UPDATES ?? "16");
assert.ok(Number.isInteger(replayUpdates) && replayUpdates >= 2,
  "VBP_REPLAY_UPDATES must be an integer of at least two");
const codecBindingsPath = resolve(process.env.VBP_JSON_BINDINGS_FILE ??
  fileURLToPath(new URL("./upstream-json-value-bindings.mjs", import.meta.url)));
assert.ok(inputArg && outputArg, "usage: decode_browser_smoke.mjs CAPTURE_DIR OUTPUT_DIR");
const input = resolve(inputArg), output = resolve(outputArg);
await mkdir(output, { recursive: false });
const response = await readFile(resolve(input, "response.json"));
const capture = JSON.parse(await readFile(resolve(input, "result.json"), "utf8"));
const sha = value => createHash("sha256").update(value).digest("hex");
const bridgeRevision = "5953a7aef6fe9ec83481e313fb045fc27f7a1a9e";
const objectValuesPath = resolve(root, ".lake/build/vir/sdk/js/runtime/object-values.js");
const objectValues = await readFile(objectValuesPath, "utf8");
assert.ok(objectValues.includes("const leanObjectHandleStates = new WeakMap();"));
assert.ok(!objectValues.includes("export function isLeanObjectHandle"));
// Diagnostic-only source backport of the upstream brand query. The module is
// the SDK's actual owner of the WeakMap, not a second copy or a duck-type check.
const brandQuery = "\nexport function isLeanObjectHandle(value) { return leanObjectHandleStates.has(value); }\n";
assert.equal(sha(response), capture.result.capturedResponseSha256);
const sdk = JSON.parse(await readFile(resolve(root, ".lake/build/vir/sdk/lean-vir-artifact.json"), "utf8"));
const manifest = JSON.parse(await readFile(resolve(root, "lake-manifest.json"), "utf8"));
assert.equal(sdk.gitCommit, manifest.packages.find(p => p.name === "lean_vir").rev);
assert.equal(sdk.leanToolchain, capture.toolchain);
if (process.env.VBP_REPLAY_CHECKPOINT_COMPARISON !== "1") {
  assert.equal(sdk.gitCommit, capture.virCommit);
  assert.equal(sha(await readFile(resolve(root, "src/VersoBlueprintVir/Preview/Rpc.lean"))), capture.rpcSourceSha256);
}
await writeFile(resolve(output, "response.json"), response);
let driver = await readFile(resolve(root, "tests/vir_preview/session_browser_smoke.mjs"), "utf8");
function replace(before, after) {
  assert.equal(driver.split(before).length, 2, `browser driver drift: ${before}`);
  driver = driver.replace(before, after);
}
replace('const root = fileURLToPath(new URL("../../", import.meta.url));', `const root = ${JSON.stringify(root)};`);
// Always use this driver's browser fixture, also for the old control root.
replace('resolve(root, "tests/vir_preview/session_browser_entry.mjs")', JSON.stringify(fileURLToPath(new URL("./decode_browser_entry.mjs", import.meta.url))));
replace('resolve(root,\n  ".lake/build/vir/module-sets/VersoBlueprintVirTests/NativeSession.irpkg-set.json")', JSON.stringify(descriptorPath));
replace('"globalThis.sessionAcceptance"', '"globalThis.decodeAcceptance"');
replace('const output = resolve(process.env.VBP_NATIVE_SESSION_REPORT);', `const output = ${JSON.stringify(resolve(output, "result.json"))};`);
// Full-document replay includes warmups and repeated retained updates, unlike the
// small session acceptance fixture whose driver we reuse.
replace('60000); }),', '600000); }),');
replace('const assets = new Map([', `const assets = new Map([\n  ["/response.json", ["application/json", await readFile(${JSON.stringify(resolve(output, "response.json"))})]],`);
replace('"process.env.NODE_ENV": \'"development"\'', '"process.env.NODE_ENV": \'"production"\'');
replace('alias: {', `alias: {\n    "@vbp-json-value-bindings": ${JSON.stringify(codecBindingsPath)},\n    "@vir-object-values": ${JSON.stringify(objectValuesPath)},`);
replace('define: {', `plugins: [{ name: "upstream-json-brand-query", setup(plugin) {
    plugin.onLoad({ filter: /runtime\\/object-values\\.js$/ }, async ({ path }) => {
      assert.equal(path, ${JSON.stringify(objectValuesPath)});
      return { contents: (await readFile(path, "utf8")) + ${JSON.stringify(brandQuery)}, loader: "js" };
    });
  } }],\n  define: { "process.env.VBP_REPLAY_RENDER": ${JSON.stringify(JSON.stringify(process.env.VBP_REPLAY_RENDER ?? "0"))},`);
replace('define: { ', `define: { "process.env.VBP_REPLAY_PROFILE": ${JSON.stringify(JSON.stringify(process.env.VBP_REPLAY_PROFILE ?? "0"))}, `);
replace('define: { ', `define: { "process.env.VBP_REPLAY_UPDATES": ${JSON.stringify(JSON.stringify(replayUpdates))}, `);
replace('define: { ', `define: { "process.env.VBP_REPLAY_STRING_INTERN": ${JSON.stringify(JSON.stringify(process.env.VBP_REPLAY_STRING_INTERN ?? "0"))}, `);
replace('define: { ', `define: { "process.env.VBP_REPLAY_STRING_INTERN_CONTROLS": ${JSON.stringify(JSON.stringify(process.env.VBP_REPLAY_STRING_INTERN_CONTROLS ?? "0"))}, `);
replace('define: { ', `define: { "process.env.VBP_REPLAY_VALIDATION_ONLY": ${JSON.stringify(JSON.stringify(process.env.VBP_REPLAY_VALIDATION_ONLY ?? "0"))}, `);
replace('define: { ', `define: { "process.env.VBP_REPLAY_COMPRESSION_CHECK": ${JSON.stringify(JSON.stringify(process.env.VBP_REPLAY_COMPRESSION_CHECK ?? "0"))}, `);
replace('define: { ', `define: { "process.env.VBP_REPLAY_IDENTITY_TEST": ${JSON.stringify(JSON.stringify(process.env.VBP_REPLAY_IDENTITY_TEST ?? ""))}, `);
replace('define: { ', `define: { "process.env.VBP_REPLAY_FINGERPRINT_CHECK": ${JSON.stringify(JSON.stringify(process.env.VBP_REPLAY_FINGERPRINT_CHECK ?? "0"))}, `);
replace('define: { ', `define: { "process.env.VBP_REPLAY_IDENTITY_PHASES": ${JSON.stringify(JSON.stringify(process.env.VBP_REPLAY_IDENTITY_PHASES ?? "0"))}, `);
if (process.env.VBP_REPLAY_IDENTITY_PHASES === "1") {
  assert.equal(process.env.VBP_REPLAY_RENDER, "1");
  assert.notEqual(process.env.VBP_REPLAY_PROFILE, "1", "keep identity and CPU-sampling probes separate");
}
if (process.env.VBP_REPLAY_PROFILE === "1") {
  assert.notEqual(process.env.VBP_REPLAY_VALIDATION_ONLY, "1",
    "profile the complete decoder or renderer; keep focused validation separate");
  replace('server = createServer((req, res) => {', `server = createServer(async (req, res) => {
    if (req.url === "/profile/start" || req.url === "/profile/stop") {
      try {
        if (req.url === "/profile/start") {
          await cdp.send("Performance.enable");
          const stamp = async () => (await cdp.send("Performance.getMetrics")).metrics.find(m => m.name === "Timestamp").value * 1000;
          const trials = [];
          for (let trial = 0; trial < 5; trial++) {
            const before = await stamp();
            const browserNow = await evaluate(cdp, "performance.now()");
            const after = await stamp();
            trials.push({ before, browserNow, after,
              offsetMs: (before + after) / 2 - browserNow, uncertaintyMs: (after - before) / 2 });
          }
          const best = trials.reduce((a, b) => a.uncertaintyMs < b.uncertaintyMs ? a : b);
          await writeFile(${JSON.stringify(resolve(output, "profile-clock.json"))}, JSON.stringify({ ...best, trials }));
          assert.ok(best.uncertaintyMs < 5, "clock calibration too imprecise");
          await cdp.send("Profiler.enable");
          await cdp.send("Profiler.setSamplingInterval", { interval: 1000 });
          await cdp.send("Profiler.start");
        } else {
          const { profile } = await cdp.send("Profiler.stop");
          await writeFile(${JSON.stringify(resolve(output, "browser.cpuprofile"))}, JSON.stringify(profile));
        }
        res.writeHead(200); res.end("ok");
      } catch (error) { res.writeHead(500); res.end(String(error)); }
      return;
    }`);
}
await writeFile(resolve(output, "driver.mjs"), driver);
const sources = ["tests/VersoBlueprintVirTests/NativeSession/DecodeProbe.lean",
  "tests/vir_preview/decode_browser_smoke.mjs",
  "tests/vir_preview/decode_browser_entry.mjs", "tests/vir_preview/response_phase_probe.mjs",
  "tests/vir_preview/identity_phase_probe.mjs",
  "tests/vir_preview/identity_browser_cases.mjs",
  "tests/vir_preview/json_value_contract_cases.mjs",
  "tests/vir_preview/scoped_string_intern.mjs",
  "tests/vir_preview/upstream-json-value-bindings.mjs",
  ...["Types", "Generated", "Codec", "Js"].map(name =>
    `tests/VersoBlueprintVirTests/NativeSession/UpstreamJson/${name}.lean`)];
const sourceHashes = {};
for (const path of sources) {
  const bytes = await readFile(path.endsWith(".mjs") ? fileURLToPath(new URL(path.split("/").at(-1), import.meta.url)) : resolve(root, path));
  sourceHashes[path] = sha(bytes);
  await writeFile(resolve(output, path.split("/").at(-1)), bytes);
}
const descriptorBytes = await readFile(descriptorPath);
const descriptor = JSON.parse(descriptorBytes);
const packageHashes = await Promise.all(descriptor.packages.map(async member => {
  const bytes = await readFile(resolve(dirname(descriptorPath), member.path));
  assert.equal(bytes.length, member.byteLength, `package size mismatch: ${member.path}`);
  const sha256 = sha(bytes);
  assert.equal(sha256, member.sha256, `package hash mismatch: ${member.path}`);
  return { path: member.path, sha256 };
}));
await writeFile(resolve(output, "identity.json"), JSON.stringify({ sourceHashes, packageHashes,
  root, descriptorPath, virCommit: sdk.gitCommit, captureVirCommit: capture.virCommit,
  checkpointComparison: process.env.VBP_REPLAY_CHECKPOINT_COMPARISON === "1",
  replayUpdates,
  scopedStringIntern: process.env.VBP_REPLAY_STRING_INTERN === "1",
  stringInternControls: process.env.VBP_REPLAY_STRING_INTERN_CONTROLS === "1",
  validationOnly: process.env.VBP_REPLAY_VALIDATION_ONLY === "1",
  codecBindingsPath, codecBindingsSha256: sha(await readFile(codecBindingsPath)),
  cpuSamplingIntervalUs: process.env.VBP_REPLAY_PROFILE === "1" ? 1000 : null,
  identityPhaseInstrumentation: process.env.VBP_REPLAY_IDENTITY_PHASES === "1",
  compressionCheck: process.env.VBP_REPLAY_COMPRESSION_CHECK === "1",
  identityTest: process.env.VBP_REPLAY_IDENTITY_TEST ?? null,
  rpcSourceSha256: sha(await readFile(resolve(root, "src/VersoBlueprintVir/Preview/Rpc.lean"))),
  bridgeRevision, objectValuesSha256: sha(objectValues), brandQuery,
  diagnosticObjectValuesSha256: sha(objectValues + brandQuery),
  browserJson: true,
  responseSha256: sha(response), sdkSha256: sha(await readFile(resolve(root, ".lake/build/vir/sdk/lean-vir-artifact.json"))),
  wasmSha256: sha(await readFile(resolve(root, ".lake/build/vir/sdk/wasm/vir-upstream.wasm"))),
  descriptorSha256: sha(descriptorBytes), driverSha256: sha(driver), input }, null, 2));
await import(pathToFileURL(resolve(output, "driver.mjs")));
