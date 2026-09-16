/* Reuse the pinned VIR transport; adapt only its workspace, edit, and timing gates. */
import assert from "node:assert/strict";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import { dirname, resolve } from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import os from "node:os";
import { instrumentCallbackCensus } from "./host_callback_census.mjs";
import { writePreviewInputs } from "./preview_inputs.mjs";
const root = resolve(process.env.VBP_LATENCY_PROJECT);
const sourcePath = resolve(root, process.env.VBP_LATENCY_SOURCE ?? "FLTBlueprint/Chapters/Reductions.lean");
const output = resolve(process.env.VBP_LATENCY_OUTPUT);
await mkdir(output, { recursive: false }); // Do not overwrite a previous campaign.
const manifestText = await readFile(resolve(root, "lake-manifest.json"), "utf8");
const manifest = JSON.parse(manifestText), virRoot = resolve(root, manifest.packagesDir, "lean_vir");
const sdkRoot = resolve(root, ".lake/build/vir/sdk");
const sdk = JSON.parse(await readFile(resolve(sdkRoot, "lean-vir-artifact.json"), "utf8"));
assert.equal(sdk.gitCommit, manifest.packages.find(p => p.name === "lean_vir").rev);
assert.equal(sdk.gitDirty, false);
const jsonBridge = process.env.VBP_LATENCY_JSON_BRIDGE ?? "off";
assert.ok(["off", "control", "candidate"].includes(jsonBridge));
const diskSource = await readFile(sourcePath, "utf8");
let source = diskSource;
// Opt-in local fixture selection without changing an editor-owned demo file.
const firRegistration = process.env.VBP_LATENCY_FIR_REGISTRATION === "1";
if (firRegistration) {
  assert.equal(process.env.VBP_LATENCY_BACKEND, "fir");
  assert.equal(jsonBridge, "off");
  const virPanel = 'show_panel_widgets [local Lean.Vir.Infoview.widget with FLTBlueprint.Preview.panelProps]';
  const firPanel = '-- show_panel_widgets [local FirJsonPreview.widget with FLTBlueprint.FirPreview.panelProps]';
  assert.equal(source.split(virPanel).length, 2, "FLT VIR registration drift");
  assert.equal(source.split(firPanel).length, 2, "FLT FIR registration drift");
  source = source.replace(virPanel, `-- ${virPanel}`).replace(firPanel, firPanel.slice(3));
  await writeFile(resolve(output, "effective-source.lean"), source);
}
if (jsonBridge !== "off") {
  const imports = "meta import FLTBlueprint.Preview";
  assert.equal(source.split(imports).length, 2, "FLT preview import drift");
  source = source.replace(imports, imports + "\nimport VersoBlueprintVirTests.NativeSession.LiveJson\nmeta import VersoBlueprintVirTests.NativeSession.LiveJson");
  if (jsonBridge === "candidate") {
    assert.equal(source.split("with FLTBlueprint.Preview.panelProps]").length, 2, "FLT panel registration drift");
    source = source.replace("with FLTBlueprint.Preview.panelProps]", "with VersoBlueprintVirTests.NativeSession.LiveJson.panelProps]");
  }
  await writeFile(resolve(output, "effective-source.lean"), source);
}
const anchor = process.env.VBP_LATENCY_ANCHOR ?? "The goal of this chapter is to reduce FLT to a deep theorem of Mazur and a deep\ntheorem of Wiles about a Galois representation.";
assert.equal(source.split(anchor).length, 2, "unique prose edit anchor required");
const position = { line: source.slice(0, source.indexOf(anchor)).split("\n").length - 1, character: 3 };
const sha = value => createHash("sha256").update(value).digest("hex");
const { build } = await import(pathToFileURL(resolve(virRoot, "node_modules/esbuild/lib/main.js")));
const require = createRequire(resolve(virRoot, "package.json"));
const profile = process.env.VBP_LATENCY_PROFILE === "1";
const sampling = process.env.VBP_LATENCY_SAMPLING === "1";
const responsePhases = process.env.VBP_LATENCY_RESPONSE_PHASES === "1";
const captureResponse = process.env.VBP_LATENCY_CAPTURE_RESPONSE === "1";
const debugTiming = process.env.VBP_LATENCY_DEBUG === "1";
const firRenderer = process.env.VBP_LATENCY_BACKEND === "fir";
const firMode = process.env.VBP_LATENCY_FIR_MODE ?? "correctness";
assert.ok(["correctness", "timing"].includes(firMode), "Use component_campaign_smoke for isolated FIR phases");
assert.ok(firRenderer || firMode === "correctness", "FIR mode requires the FIR backend");
assert.ok(!firRenderer || (!debugTiming && !sampling && !profile && !responsePhases && !captureResponse && jsonBridge === "off"),
  "FIR measurements do not enable VIR-specific probes or options");
const hostCensus = process.env.VBP_LATENCY_HOST_CENSUS === "1";
assert.ok(!firRenderer || !hostCensus, "FIR measurements do not use callback census");
const waitForILeans = process.env.VBP_LATENCY_WAIT_ILEANS === "1";
const stackBytes = Number(process.env.VBP_LATENCY_STACK_BYTES ?? 16384);
assert.ok([16384, 65528].includes(stackBytes), "supported perf stack sizes: 16384 or 65528");
assert.ok(!sampling || !profile, "CPU sampling and React profiling are separate experiments");
assert.ok(!responsePhases || (!sampling && !profile), "response probes are a separate diagnostic campaign");
assert.ok(!debugTiming || (!sampling && !profile && !responsePhases), "live bar validation is a separate diagnostic campaign");
assert.ok(!hostCensus || (!sampling && !profile && !responsePhases && !debugTiming && jsonBridge === "off"), "callback census is a separate diagnostic campaign");
assert.ok(jsonBridge === "off" || (!responsePhases && !captureResponse), "JSON bridge uses ordinary timing, not the string-only response probe");
const shellPath = resolve(process.env.VBP_LATENCY_SHELL ?? resolve(virRoot, "build/generated/infoview/vir-infoview-widget.js"));
const shellHash = sha(await readFile(shellPath));
let diagnosticShell = null;
const shellOverride = process.env.VBP_LATENCY_SHELL_OVERRIDE;
let shellOverrideIdentity = null;
if (shellOverride) {
  assert.ok(jsonBridge === "off" && !responsePhases && !hostCensus, "shell qualification must not stack source adapters");
  diagnosticShell = await readFile(shellOverride, "utf8");
  shellOverrideIdentity = JSON.parse(await readFile(shellOverride + ".identity.json", "utf8"));
  assert.equal(shellOverrideIdentity.bundleSha256, sha(diagnosticShell));
  assert.equal(shellOverrideIdentity.virCommit, sdk.gitCommit);
  assert.equal(shellOverrideIdentity.toolchain, sdk.leanToolchain);
  assert.equal(shellOverrideIdentity.sdkManifestSha256, sha(await readFile(resolve(sdkRoot, "lean-vir-artifact.json"))));
  await writeFile(resolve(output, "qualified-shell.js"), diagnosticShell);
  await writeFile(resolve(output, "qualified-shell.identity.json"), JSON.stringify(shellOverrideIdentity, null, 2));
}
let jsonHostSource = null;
if (jsonBridge !== "off") {
  const shell = await readFile(shellPath, "utf8");
  const site = "    ...createJsValueHostBindings(),";
  assert.equal(shell.split(site).length, 2, "pinned host provider drift");
  assert.equal(shell.split("var leanObjectHandleStates =").length, 2, "pinned handle registry drift");
  jsonHostSource = await readFile(fileURLToPath(new URL("./upstream-json-value-bindings.mjs", import.meta.url)), "utf8");
  const hostCode = jsonHostSource.replace('import { isLeanObjectHandle } from "@vir-object-values";',
    "function isLeanObjectHandle(value) { return leanObjectHandleStates.has(value); }")
    .replace("export function createJsonValueHostBindings", "function createJsonValueHostBindings");
  diagnosticShell = shell.replace(site, site + "\n    ...vbpUpstreamJsonBindings,") +
    "\nconst vbpUpstreamJsonBindings = (() => {\n" + hostCode + "\nreturn createJsonValueHostBindings();\n})();\n";
  await writeFile(resolve(output, "diagnostic-shell.js"), diagnosticShell);
  await writeFile(resolve(output, "upstream-json-value-bindings.mjs"), jsonHostSource);
}
if (responsePhases) {
  const shell = await readFile(shellPath, "utf8");
  const call = "return root.runtime.callClosure(root.rootId, root.type, args);";
  assert.equal(shell.split(call).length, 2, "pinned callback boundary drift");
  diagnosticShell = shell.replace(call, "return globalThis.__vbpResponseProbe.invoke(root, args);");
  await writeFile(resolve(output, "diagnostic-shell.js"), diagnosticShell);
  await writeFile(resolve(output, "response_phase_probe.mjs"),
    await readFile(fileURLToPath(new URL("./response_phase_probe.mjs", import.meta.url))));
}
const clientEntry = fileURLToPath(new URL("./latency_browser_entry.mjs", import.meta.url));
if (firRenderer && firMode !== "timing") {
  // Correctness-only probe: the live demo has neither counters nor this guard.
  const site = 'runtimeOptions.hostBindings["previewDemo.componentFir"] = () => fir.Component;';
  diagnosticShell ??= await readFile(shellPath, "utf8");
  assert.equal(diagnosticShell.split(site).length, 2, "FIR entry drift");
  diagnosticShell = diagnosticShell.replace(site, `
  runtimeOptions.hostBindings["previewDemo.parse"] = () => { throw new Error("FIR must not decode Preview in the shell"); };
  runtimeOptions.hostBindings["previewDemo.componentFir"] = () => {
    globalThis.__vbpFirFactories = (globalThis.__vbpFirFactories ?? 0) + 1;
    return function FirDocumentProbe(props) {
      if (globalThis.__vbpFirInput !== props.document) {
        globalThis.__vbpFirRenders = (globalThis.__vbpFirRenders ?? 0) + 1;
        globalThis.__vbpFirInput = props.document;
      }
      return e(fir.Component, props);
    };
  };`);
  await writeFile(resolve(output, "diagnostic-shell.js"), diagnosticShell);
}
if (hostCensus) {
  diagnosticShell = "globalThis.__vbpHostCensusEnabled = true;\n" + instrumentCallbackCensus(await readFile(shellPath, "utf8"));
  await writeFile(resolve(output, "diagnostic-shell.js"), diagnosticShell);
  await writeFile(resolve(output, "host_callback_census.mjs"),
    await readFile(fileURLToPath(new URL("./host_callback_census.mjs", import.meta.url))));
}
const clientSource = await readFile(clientEntry);
const driverSource = await readFile(fileURLToPath(import.meta.url));
const bundle = await build({ entryPoints: [clientEntry], bundle: true, format: "iife", platform: "browser", write: false,
  nodePaths: [resolve(virRoot, "node_modules")], alias: { "@vir-embedded-shell": shellPath,
    ...(profile ? { "react-dom/client": require.resolve("react-dom/profiling") } : {}) },
  plugins: [{ name: "widget-backend", setup(builder) {
    builder.onLoad({ filter: /latency_browser_entry\.mjs$/ }, async ({ path }) => ({
      contents: `const FIR_RENDERER = ${JSON.stringify(firRenderer)};\nconst FIR_MODE = ${JSON.stringify(firMode)};\n` + await readFile(path, "utf8"), loader: "js", resolveDir: dirname(path) }));
  } }, ...(diagnosticShell ? [{ name: "diagnostic-shell", setup(builder) {
    builder.onLoad({ filter: /(?:vir-infoview-widget|checked-json-demo|fir-json-demo)\.js$/ }, args => {
      assert.equal(args.path, shellPath);
      return { contents: diagnosticShell, loader: "js", resolveDir: dirname(shellPath) };
    });
  } }] : []), { name: "official-infoview-context", setup(builder) {
    builder.onResolve({ filter: /^@leanprover\/infoview$/ }, () => ({ path: "infoview", namespace: "latency-context" }));
    builder.onLoad({ filter: /.*/, namespace: "latency-context" }, () => ({
      contents: `export { DocumentPosition, EditorConnection, EditorContext, useClientNotificationEffect } from ${JSON.stringify(require.resolve("@leanprover/infoview"))};
        export { TaggedText_stripTags } from ${JSON.stringify(require.resolve("@leanprover/infoview-api"))};
        export function useRpcSession() { return globalThis.__vbpEmbeddedSession; }`, loader: "js", resolveDir: virRoot,
    }));
  } }], define: { "process.env.NODE_ENV": '"production"', SHELL_HASH: JSON.stringify(shellHash), PREVIEW_METHOD: JSON.stringify(process.env.VBP_LATENCY_METHOD ?? (firRenderer ? "FirJsonPreview.Server.previewDocument" : "VersoBlueprint.Experimental.VirPreview.Server.previewDocument")), WIDGET_ID: JSON.stringify(process.env.VBP_LATENCY_WIDGET ?? (firRenderer ? "FirJsonPreview.widget" : "Lean.Vir.Infoview.widget")), SAMPLES: process.env.VBP_LATENCY_SAMPLES ?? "9", DEBUG_TIMING: JSON.stringify(debugTiming), PROFILE: JSON.stringify(profile), SAMPLING: JSON.stringify(sampling), RESPONSE_PHASES: JSON.stringify(responsePhases), CAPTURE_RESPONSE: JSON.stringify(captureResponse), JSON_BRIDGE_CANDIDATE: JSON.stringify(jsonBridge === "candidate") },
});
const harnessPath = resolve(virRoot, "tests/infoview/rpc-browser-harness.mjs");
const original = await readFile(harnessPath, "utf8");
let harness = original;
function replaceOnce(before, after) {
  assert.equal(harness.split(before).length, 2, `pinned harness drift: ${before.slice(0, 65)}`);
  harness = harness.replace(before, () => after);
}
replaceOnce('const root = fileURLToPath(new URL("../../", import.meta.url));', `const root = ${JSON.stringify(root)};`);
if (source !== diskSource) replaceOnce('const source = await readFile(sourcePath, "utf8");',
  `const source = await readFile(${JSON.stringify(resolve(output, "effective-source.lean"))}, "utf8");`);
replaceOnce('a: fixturePosition(source, "rpc-position-a"),\n    b: fixturePosition(source, "rpc-position-b"),', `a: ${JSON.stringify(position)}, b: ${JSON.stringify(position)},`);
replaceOnce('let documentVersion = 1;', 'let documentVersion = 1; let diagnosticsDone;');
replaceOnce('120000,', firRenderer && firMode !== "correctness" ? '900000,' : '300000,');
if (waitForILeans) {
  replaceOnce('    const config = {', `    const indexWaitStarted = performance.now();
    await Promise.race([connection.sendRequest("$/lean/waitForILeans", {}), timedOut]);
    const indexWaitMs = performance.now() - indexWaitStarted;
    const config = { indexWaitMs,`);
}
replaceOnce('contentChanges: [{ text: `${source}\\n-- browser edit ${documentVersion}\\n` }],',
  `contentChanges: [{ text: source.replace(${JSON.stringify(anchor)}, ${JSON.stringify(anchor)} + " Preview timing sample " + String(documentVersion).padStart(2, "0") + ".") }],`);
replaceOnce(`          await connection.sendNotification("textDocument/didChange", params);
          await connection.sendRequest("textDocument/waitForDiagnostics", {
            uri, version: documentVersion,
          });`, `          const sent = performance.now();
          await connection.sendNotification("textDocument/didChange", params);
          diagnosticsDone = connection.sendRequest("textDocument/waitForDiagnostics", {
            uri, version: documentVersion,
          }).then(() => ({ ms: performance.now() - sent }));`);
replaceOnce('        } else if (req.url === "/call") {',
  '        } else if (req.url === "/diagnostics") {\n          result = await diagnosticsDone;\n        } else if (req.url === "/call") {');
if (sampling) {
  replaceOnce('import { readFile } from "node:fs/promises";', 'import { readFile, writeFile } from "node:fs/promises";');
  replaceOnce('  let child, connection, server, chrome, cdp;', `  let child, connection, server, chrome, cdp;
  const samplingOutput = ${JSON.stringify(output)};
  const samplingEvents = [];
  const mark = event => samplingEvents.push({ event, monotonicNanos: String(process.hrtime.bigint()) });
  async function controlPerf(command) {
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => { child.stdio[4].off("data", acknowledged); reject(Error("perf control timeout")); }, 5000);
      const acknowledged = chunk => {
        if (!chunk.toString().includes("ack")) return;
        clearTimeout(timer); child.stdio[4].off("data", acknowledged); resolve();
      };
      child.stdio[4].on("data", acknowledged);
      child.stdio[3].write(command + "\\n");
    });
    mark("perf:" + command);
  }`);
  replaceOnce('    child = spawn("lake", ["serve", "--", "-DstderrAsMessages=false"], {\n      cwd: root,\n      stdio: ["pipe", "pipe", "pipe"],\n    });', `    child = spawn("perf", ["record", "-N", "-e", "cpu-clock:u", "-F", "997",
      "--call-graph", "dwarf,${stackBytes}", "--clockid", "mono", "--delay=-1", "--control=fd:3,4",
      "-o", join(samplingOutput, "server.perf.data"), "--",
      "lake", "serve", "--", "-DstderrAsMessages=false"], {
      cwd: root, stdio: ["pipe", "pipe", "pipe", "pipe", "pipe"],
    });`);
  replaceOnce('        } else if (req.url === "/call") {', `        } else if (req.url === "/sampling/start") {
          await cdp.send("Profiler.enable");
          await cdp.send("Profiler.setSamplingInterval", { interval: 1000 });
          await cdp.send("Profiler.start");
          mark("browser:start");
          await controlPerf("enable");
          result = true;
        } else if (req.url === "/sampling/browser-stop") {
          const { profile } = await cdp.send("Profiler.stop");
          mark("browser:stop");
          await writeFile(join(samplingOutput, "browser.cpuprofile"), JSON.stringify(profile));
          result = true;
        } else if (req.url === "/sampling/server-stop") {
          await controlPerf("disable");
          await writeFile(join(samplingOutput, "sampling-events.json"), JSON.stringify(samplingEvents, null, 2));
          result = true;
        } else if (req.url === "/call") {`);
  replaceOnce('          const sent = performance.now();', '          mark("edit:sent");\n          const sent = performance.now();');
  replaceOnce('          }).then(() => ({ ms: performance.now() - sent }));', '          }).then(() => { mark("diagnostics:done"); return { ms: performance.now() - sent }; });');
}
// Resolve the adapted module's imports against the unmodified producer harness.
harness = harness.replace(/from "([^"\n]+)"/g, (match, specifier) => {
  if (specifier.startsWith("node:")) return match;
  const path = specifier.startsWith(".") ? resolve(dirname(harnessPath), specifier) : require.resolve(specifier);
  return `from ${JSON.stringify(pathToFileURL(path).href)}`;
});
await writeFile(resolve(output, "adapted-harness.mjs"), harness);
await writeFile(resolve(output, "client.mjs"), clientSource);
await writeFile(resolve(output, "driver.mjs"), driverSource);
await writeFile(resolve(output, "probe.js"), bundle.outputFiles[0].contents);
const vbp = manifest.packages.find(p => p.name === "VersoBlueprint")?.dir;
const git = (cwd, ...args) => execFileSync("git", args, { cwd, encoding: "utf8" });
const rpcSource = vbp ? await readFile(resolve(vbp, "src/VersoBlueprintVir/Preview/Rpc.lean")) : null;
if (rpcSource) await writeFile(resolve(output, "Rpc.lean"), rpcSource);
let firIdentity = null;
if (firRenderer) {
  assert.ok(vbp, "FIR demo requires the VBP path dependency");
  const shellIdentity = JSON.parse(await readFile(shellPath + ".identity.json", "utf8"));
  assert.equal(shellIdentity.bundleSha256, shellHash, "FIR shell identity drift");
  const sources = {};
  for (const path of [resolve(vbp, "tests/FirJsonPreview.lean"),
    resolve(vbp, "tests/FirJsonPreview/Server.lean"), resolve(root, "FLTBlueprint/FirPreview.lean"),
    resolve(vbp, "src/VersoBlueprintVir/Preview/Server.lean"), resolve(vbp, "src/VersoBlueprintVir/Preview/Widget.lean")]) {
    const bytes = await readFile(path);
    sources[path] = sha(bytes);
    await writeFile(resolve(output, `source-${Object.keys(sources).length}.lean`), bytes);
  }
  firIdentity = { shellIdentity, sources };
}
const jsonLeanSources = {};
if (jsonBridge !== "off") {
  assert.ok(vbp, "VBP path dependency required");
  const paths = ["tests/VersoBlueprintVirTests/NativeSession/LiveJson.lean",
    ...["Rpc", "Widget", "Server"].map(name => `tests/VersoBlueprintVirTests/NativeSession/LiveJson/${name}.lean`),
    ...["Types", "Generated", "Codec", "Js"].map(name => `tests/VersoBlueprintVirTests/NativeSession/UpstreamJson/${name}.lean`),
    ...["Rpc", "Widget", "Server", "Model"].map(name => `src/VersoBlueprintVir/Preview/${name}.lean`)];
  for (const path of paths) {
    const bytes = await readFile(resolve(vbp, path));
    jsonLeanSources[path] = sha(bytes);
    await writeFile(resolve(output, path.replaceAll("/", "__")), bytes);
  }
}
const identity = { root, sourcePath, anchor, position, virCommit: sdk.gitCommit,
  widgetBackend: firRenderer ? `fir (${firMode})` : "vir",
  firIdentity, firRegistration,
  firProbe: firRenderer && firMode !== "timing" ? {
    mode: firMode, diagnosticShellSha256: sha(diagnosticShell),
    scope: "correctness-only component factory/input guards; no timing claims",
  } : false,
  sdkManifestSha256: sha(await readFile(resolve(sdkRoot, "lean-vir-artifact.json"))),
  wasmSha256: sha(await readFile(resolve(sdkRoot, "wasm/vir-upstream.wasm"))),
  vbpCommit: vbp ? git(vbp, "rev-parse", "HEAD").trim() : null,
  vbpDiffSha256: vbp ? sha(git(vbp, "diff", "HEAD")) : null,
  rpcSourceSha256: rpcSource ? sha(rpcSource) : null,
  sourceSha256: sha(diskSource), sourceBytes: Buffer.byteLength(diskSource), effectiveSourceSha256: sha(source), manifestSha256: sha(manifestText),
  toolchain: sdk.leanToolchain, shellSha256: shellHash, originalHarnessSha256: sha(original),
  adaptedHarnessSha256: sha(harness), clientHarnessSha256: sha(clientSource),
  driverSha256: sha(driverSource), bundleSha256: sha(bundle.outputFiles[0].contents),
  projectHead: git(root, "rev-parse", "HEAD").trim(), projectDiffSha256: sha(git(root, "diff", "HEAD")),
  cpu: os.cpus()[0].model, cpuCount: os.cpus().length, loadBefore: os.loadavg(),
  startedAt: new Date().toISOString(), browserMode: `React production; highlighting off; debug ${debugTiming ? "on" : "off"}`, reactProfiler: profile,
  responsePhases: responsePhases ? { order: "off/on/on/off repeated, excluding one off warmup",
    diagnosticShellSha256: sha(diagnosticShell),
    probeSha256: sha(await readFile(resolve(output, "response_phase_probe.mjs"))),
    scope: "four existing host calls in the matching synchronous response callback only" } : false,
  captureResponse,
  shellOverride: shellOverrideIdentity,
  hostCensus: hostCensus ? { diagnosticShellSha256: sha(diagnosticShell),
    probeSha256: sha(await readFile(resolve(output, "host_callback_census.mjs"))),
    scope: "argument/root census only; original tracking retained; elapsed time is instrumented" } : false,
  jsonBridge: jsonBridge === "off" ? false : { variant: jsonBridge,
    bridgeRevision: "5953a7aef6fe9ec83481e313fb045fc27f7a1a9e",
    leanSourceHashes: jsonLeanSources,
    diagnosticShellSha256: sha(diagnosticShell), hostSourceSha256: sha(jsonHostSource),
    sourceAdaptation: "same test imports in both variants; candidate selects checked ordinary-JSON RPC/widget; disk source unchanged" },
  cpuSampling: sampling ? `Lean descendants/threads: cpu-clock:u 997 Hz DWARF ${stackBytes} bytes; browser: CDP 1 ms; exclude startup/warmup` : false,
  samples: Number(process.env.VBP_LATENCY_SAMPLES ?? 9), warmups: 1,
  referenceIndexGate: waitForILeans ? "$/lean/waitForILeans before browser startup" : "none; early-session cohort",
  cache: "warm built dependencies; own fresh LSP worker/browser; edits in memory only",
  scope: "test HTTP bridge forwards edits immediately; native notification effect; DOM commit, not VS Code paint",
};
await writeFile(resolve(output, "identity.json"), JSON.stringify(identity, null, 2));
const { runRpcBrowserAcceptance } = await import(pathToFileURL(resolve(output, "adapted-harness.mjs")));
try {
  const result = await runRpcBrowserAcceptance({ sourcePath,
    assets: new Map([["/probe.js", ["text/javascript", bundle.outputFiles[0].contents]]]),
    label: "FLT preview latency", });
  if (result.clientPackage) {
    const { dataBase64, report, ...metadata } = result.clientPackage;
    const bytes = Buffer.from(dataBase64, "base64");
    await writeFile(resolve(output, "client.irpkg"), bytes);
    await writeFile(resolve(output, "client-package-report.md"), report);
    result.clientPackage = { ...metadata, sha256: sha(bytes), reportSha256: sha(report) };
  }
  if (captureResponse) {
    assert.equal(typeof result.capturedResponse, "string");
    await writeFile(resolve(output, "response.json"), result.capturedResponse);
    await writeFile(resolve(output, "initial-response.json"), result.capturedInitialResponse);
    result.capturedInputs = await writePreviewInputs(output, result.capturedInitialResponse, result.capturedResponse);
    result.capturedResponseSha256 = sha(result.capturedResponse);
    delete result.capturedInitialResponse;
    delete result.capturedResponse;
  }
  assert.equal(sha(await readFile(sourcePath)), identity.sourceSha256, "source changed during campaign");
  await writeFile(resolve(output, "result.json"), JSON.stringify({ ...identity, loadAfter: os.loadavg(), result }, null, 2));
  console.log(JSON.stringify(result, null, 2));
} catch (error) {
  await writeFile(resolve(output, "failure.txt"), String(error.stack ?? error));
  throw error;
}
