/* Reuse the existing session browser driver with a diagnostic package/payload. */
import assert from "node:assert/strict";
import { readFile, writeFile, mkdir, copyFile } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";

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
const hostImportCensus = process.env.VBP_REPLAY_HOST_IMPORT_CENSUS === "1";
const hostStringCensus = process.env.VBP_REPLAY_HOST_STRING_CENSUS === "1";
const hostImportCensusPath = fileURLToPath(new URL("./host_import_census.mjs", import.meta.url));
if (process.env.VBP_REPLAY_DIRECT_TYPED === "1") {
  assert.equal(process.env.VBP_REPLAY_TYPED_PACKAGE, "1", "direct decoder needs matched typed package");
  if (process.env.VBP_REPLAY_PROFILE === "1")
    assert.equal(process.env.VBP_REPLAY_RENDER, "1", "direct decoder sampling currently requires decode/render windows");
}
assert.ok(inputArg && outputArg, "usage: decode_browser_smoke.mjs CAPTURE_DIR OUTPUT_DIR");
const input = resolve(inputArg), output = resolve(outputArg);
const sha = value => createHash("sha256").update(value).digest("hex");
await mkdir(output, { recursive: false });
// Explicit local producer handoff; never alter the producer or live widget pin.
const firPackage = process.env.VBP_REPLAY_FIR_PACKAGE;
const timedView = process.env.VBP_REPLAY_TIMED_VIEW === "1";
const firDirect = process.env.VBP_REPLAY_FIR_DIRECT === "1";
const firDirectPackage = firDirect || process.env.VBP_REPLAY_FIR_DIRECT_PACKAGE === "1";
if (firDirectPackage) assert.ok(firPackage && timedView, "direct FIR package needs its timed view");
if (timedView) assert.equal(process.env.VBP_REPLAY_TYPED_PACKAGE, "1", "timed view needs DirectCodecProbe");
if (hostImportCensus) {
  assert.ok(firDirectPackage, "host-import census requires the direct FIR package");
  assert.notEqual(process.env.VBP_REPLAY_PROFILE, "1", "keep host-import census and CPU sampling separate");
  assert.notEqual(process.env.VBP_REPLAY_IDENTITY_PHASES, "1", "keep host-import and identity probes separate");
}
if (hostStringCensus) assert.ok(hostImportCensus, "string census requires host-import census");
let firIdentity;
if (firPackage) {
  assert.equal(process.env.VBP_REPLAY_RENDER, "1");
  assert.notEqual(process.env.VBP_REPLAY_DIRECT_TYPED, "1", "VIR's direct decoder cannot be used with FIR");
  const packageRoot = resolve(output, "fir");
  await mkdir(packageRoot);
  const sums = await readFile(resolve(firPackage, "SHA256SUMS"), "utf8");
  assert.equal(sha(sums), firDirectPackage
    ? "c5201068991185dfb7f9bd898d5357695dcac4094563da1f8e3accc5f6650672"
    : timedView ? "1ce76db7a0d7b356e2bd5b90a4ef546cefbf8e0e72f842f19ea927215c0a1a18"
    : "d6d33302cca5bd9aeba5bcbb19866d7f3bbe6f6648ec62c699833fce2a5aa122");
  for (const line of sums.trim().split("\n")) {
    const [, hash, file] = line.match(/^([a-f0-9]{64})  ([\w.-]+)$/) ?? [];
    assert.ok(file, "invalid package checksum entry");
    const bytes = await readFile(resolve(firPackage, file));
    assert.equal(sha(bytes), hash, file);
    await writeFile(resolve(packageRoot, file), bytes);
  }
  await copyFile(resolve(firPackage, "SHA256SUMS"), resolve(packageRoot, "SHA256SUMS"));
  const buildBytes = await readFile(resolve(packageRoot, "BUILD.json"));
  assert.equal(sha(buildBytes), firDirectPackage
    ? "a242881a6b4ae9ba8a41f2e2240e4aa5992cc833148a400abef5e3635ebc7385"
    : timedView ? "b1d17d869f264f58ea6c8b8a3ec5a33fc31fb062c90cca780598090c145a2342"
    : "7e1342ec1eb3d78cab666d32edf2e5fa43d70102e19bb2cc02f8d9f6e87e1434");
  firIdentity = { packageRoot, buildSha256: sha(buildBytes), build: JSON.parse(buildBytes) };
}
const response = await readFile(resolve(input, "response.json"));
const capture = JSON.parse(await readFile(resolve(input, "result.json"), "utf8"));
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
if (hostImportCensus) replace('import assert from "node:assert/strict";',
  `import { instrumentHostPrototypeSource } from ${JSON.stringify(pathToFileURL(hostImportCensusPath).href)};\nimport assert from "node:assert/strict";`);
// Always use this driver's browser fixture, also for the old control root.
replace('resolve(root, "tests/vir_preview/session_browser_entry.mjs")', JSON.stringify(fileURLToPath(new URL("./decode_browser_entry.mjs", import.meta.url))));
if (firIdentity) {
  replace(JSON.stringify(fileURLToPath(new URL("./decode_browser_entry.mjs", import.meta.url))),
    JSON.stringify(fileURLToPath(new URL("./fir_decode_browser_entry.mjs", import.meta.url))));
  replace('alias: {', `alias: {\n    "@fir-codec-bootstrap": ${JSON.stringify(resolve(firIdentity.packageRoot,
    firDirectPackage ? "direct-construction-session.mjs" : "codec-session-bootstrap.mjs"))},\n    "@fir-codec-providers": ${JSON.stringify(resolve(firIdentity.packageRoot, "providers.mjs"))},`);
  replace('const assets = new Map([', `const assets = new Map([\n${[
    "component.wasm", "component.wasm.json", "host-boundary.json", "callback-boundary.json", "entry-boundary.json",
    ...(firDirectPackage ? ["constructor-layouts.json"] : [])
  ].map(file => `  ["/${file}", [${JSON.stringify(file.endsWith("wasm") ? "application/wasm" : "application/json")}, await readFile(${JSON.stringify(resolve(firIdentity.packageRoot, file))})]],`).join("\n")}`);
  replace('packageMembers: descriptor.packages.length, acceptance', 'backend: "fir", packageMembers: 0, acceptance');
}
replace('resolve(root,\n  ".lake/build/vir/module-sets/VersoBlueprintVirTests/NativeSession.irpkg-set.json")', JSON.stringify(descriptorPath));
replace('"globalThis.sessionAcceptance"', '"globalThis.decodeAcceptance"');
replace('const output = resolve(process.env.VBP_NATIVE_SESSION_REPORT);', `const output = ${JSON.stringify(resolve(output, "result.json"))};`);
// Full-document replay includes warmups and repeated retained updates, unlike the
// small session acceptance fixture whose driver we reuse.
replace('60000); }),', '600000); }),');
replace('const assets = new Map([', `const assets = new Map([\n  ["/response.json", ["application/json", await readFile(${JSON.stringify(resolve(output, "response.json"))})]],`);
if (process.env.VBP_REPLAY_TYPED_PACKAGE === "1") {
  const layouts = await readFile(resolve(root, ".deps/direct-codec/layouts.json"));
  await writeFile(resolve(output, "direct-layouts.json"), layouts);
  replace('const assets = new Map([', `const assets = new Map([\n  ["/direct-layouts.json", ["application/json", await readFile(${JSON.stringify(resolve(output, "direct-layouts.json"))})]],`);
}
replace('"process.env.NODE_ENV": \'"development"\'', '"process.env.NODE_ENV": \'"production"\'');
const directDecoderPath = resolve(process.env.VBP_DIRECT_DECODER_FILE ?? resolve(root, "tests/vir_preview/direct_typed_decoder.mjs"));
replace('alias: {', `alias: {\n    "@vbp-direct-typed-decoder": ${JSON.stringify(directDecoderPath)},\n    "@vbp-json-value-bindings": ${JSON.stringify(codecBindingsPath)},\n    "@vir-object-values": ${JSON.stringify(objectValuesPath)},`);
replace('define: {', `plugins: [{ name: "upstream-json-brand-query", setup(plugin) {
    plugin.onLoad({ filter: /runtime\\/object-values\\.js$/ }, async ({ path }) => {
      assert.equal(path, ${JSON.stringify(objectValuesPath)});
      return { contents: (await readFile(path, "utf8")) + ${JSON.stringify(brandQuery)}, loader: "js" };
    });
  } }${hostImportCensus ? `, { name: "fir-host-import-census", setup(plugin) {
    plugin.onLoad({ filter: /host-prototype\\.mjs$/ }, async ({ path }) => {
      assert.equal(path, ${JSON.stringify(resolve(firIdentity.packageRoot, "host-prototype.mjs"))});
      return { contents: instrumentHostPrototypeSource(await readFile(path, "utf8")), loader: "js", resolveDir: dirname(path) };
    });
  } }` : ""}],\n  define: { "process.env.VBP_REPLAY_RENDER": ${JSON.stringify(JSON.stringify(process.env.VBP_REPLAY_RENDER ?? "0"))},`);
replace('define: { ', `define: { "process.env.VBP_REPLAY_PROFILE": ${JSON.stringify(JSON.stringify(process.env.VBP_REPLAY_PROFILE ?? "0"))}, `);
replace('define: { ', `define: { "process.env.VBP_REPLAY_HOST_IMPORT_CENSUS": ${JSON.stringify(JSON.stringify(hostImportCensus ? "1" : "0"))}, `);
replace('define: { ', `define: { "process.env.VBP_REPLAY_HOST_STRING_CENSUS": ${JSON.stringify(JSON.stringify(hostStringCensus ? "1" : "0"))}, `);
replace('define: { ', `define: { "process.env.VBP_REPLAY_TYPED_PACKAGE": ${JSON.stringify(JSON.stringify(process.env.VBP_REPLAY_TYPED_PACKAGE ?? "0"))}, `);
replace('define: { ', `define: { "process.env.VBP_REPLAY_TIMED_VIEW": ${JSON.stringify(JSON.stringify(timedView ? "1" : "0"))}, `);
replace('define: { ', `define: { "process.env.VBP_REPLAY_FIR_DIRECT": ${JSON.stringify(JSON.stringify(firDirect ? "1" : "0"))}, `);
replace('define: { ', `define: { "process.env.VBP_REPLAY_FIR_DIRECT_PACKAGE": ${JSON.stringify(JSON.stringify(firDirectPackage ? "1" : "0"))}, `);
replace('define: { ', `define: { "process.env.VBP_REPLAY_DIRECT_TYPED": ${JSON.stringify(JSON.stringify(process.env.VBP_REPLAY_DIRECT_TYPED ?? "0"))}, `);
replace('define: { ', `define: { "process.env.VBP_REPLAY_UTF8_SCRATCH": ${JSON.stringify(JSON.stringify(process.env.VBP_REPLAY_UTF8_SCRATCH ?? "0"))}, `);
replace('define: { ', `define: { "process.env.VBP_REPLAY_POINTER_SCRATCH": ${JSON.stringify(JSON.stringify(process.env.VBP_REPLAY_POINTER_SCRATCH ?? "0"))}, `);
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
  if (firIdentity) {
    replace('write: false,', `write: false, outfile: ${JSON.stringify(resolve(output, "probe.js"))}, sourcemap: "external",`);
    replace('bundle.outputFiles[0].contents', 'bundle.outputFiles.find(file => file.path.endsWith(".js")).contents');
    replace('const descriptorPath = ', `for (const file of bundle.outputFiles) await writeFile(file.path, file.contents);\nconst descriptorPath = `);
  }
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
  "src/VersoBlueprintVir/Preview/Component/Session.lean",
  "tests/vir_preview/decode_browser_smoke.mjs",
  "tests/vir_preview/decode_browser_entry.mjs", "tests/vir_preview/response_phase_probe.mjs",
  "tests/vir_preview/identity_phase_probe.mjs",
  "tests/vir_preview/identity_browser_cases.mjs",
  "tests/vir_preview/json_value_contract_cases.mjs",
  "tests/vir_preview/scoped_string_intern.mjs",
  "tests/vir_preview/direct_typed_decoder.mjs",
  "tests/vir_preview/utf8_scratch.mjs",
  "tests/vir_preview/pointer_scratch.mjs",
  "tests/vir_preview/matched_math_component.mjs",
  "tests/vir_preview/component_phase_probe.mjs",
  "tests/vir_preview/host_import_census.mjs",
  "tests/vir_preview/upstream-json-value-bindings.mjs",
  ...["Types", "Generated", "Codec", "Js"].map(name =>
    `tests/VersoBlueprintVirTests/NativeSession/UpstreamJson/${name}.lean`)];
if (firIdentity) sources.push("tests/vir_preview/fir_decode_browser_entry.mjs");
if (process.env.VBP_REPLAY_TYPED_PACKAGE === "1")
  sources.push("tests/VersoBlueprintVirTests/NativeSession/DirectCodecProbe.lean");
const sourceHashes = {};
for (const path of sources) {
  const bytes = await readFile(path.endsWith("direct_typed_decoder.mjs") ? directDecoderPath : path.endsWith(".mjs") ? fileURLToPath(new URL(path.split("/").at(-1), import.meta.url)) : resolve(root, path));
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
const git = args => execFileSync("git", args, { cwd: root, encoding: "utf8" });
await writeFile(resolve(output, "identity.json"), JSON.stringify({ sourceHashes, packageHashes,
  gitIdentity: { commit: git(["rev-parse", "HEAD"]).trim(),
    status: git(["status", "--short"]), trackedDiffSha256: sha(git(["diff", "HEAD"])) },
  backend: firIdentity ? "fir" : "vir", firIdentity,
  root, descriptorPath, virCommit: sdk.gitCommit, captureVirCommit: capture.virCommit,
  checkpointComparison: process.env.VBP_REPLAY_CHECKPOINT_COMPARISON === "1",
  replayUpdates,
  directTyped: process.env.VBP_REPLAY_DIRECT_TYPED === "1",
  directDecoderPath,
  utf8Scratch: process.env.VBP_REPLAY_UTF8_SCRATCH === "1",
  pointerScratch: process.env.VBP_REPLAY_POINTER_SCRATCH === "1",
  typedPackage: process.env.VBP_REPLAY_TYPED_PACKAGE === "1",
  timedView,
  firDirect,
  firDirectPackage,
  directLayoutsSha256: process.env.VBP_REPLAY_TYPED_PACKAGE === "1"
    ? sha(await readFile(resolve(output, "direct-layouts.json"))) : null,
  scopedStringIntern: process.env.VBP_REPLAY_STRING_INTERN === "1",
  stringInternControls: process.env.VBP_REPLAY_STRING_INTERN_CONTROLS === "1",
  validationOnly: process.env.VBP_REPLAY_VALIDATION_ONLY === "1",
  codecBindingsPath, codecBindingsSha256: sha(await readFile(codecBindingsPath)),
  cpuSamplingIntervalUs: process.env.VBP_REPLAY_PROFILE === "1" ? 1000 : null,
  hostImportCensus,
  hostStringCensus,
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
