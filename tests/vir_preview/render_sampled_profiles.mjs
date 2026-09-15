/* Offline rendering of actual sampled stacks; never runs a benchmark. */
import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { gunzipSync, gzipSync } from "node:zlib";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";

const [captureArg, toolsArg] = process.argv.slice(2);
assert.ok(captureArg && toolsArg, "usage: render_sampled_profiles.mjs CAPTURE FLAMEGRAPH_TOOLS");
const capture = resolve(captureArg), tools = resolve(toolsArg);
const readJson = async name => JSON.parse(await readFile(resolve(capture, name), "utf8"));
const sha = data => createHash("sha256").update(data).digest("hex");
const clean = text => text.replaceAll(";", ":").replaceAll(/\s+/g, " ");
const add = (map, key, weight) => map.set(key, (map.get(key) ?? 0) + weight);
const foldedText = map => [...map].sort(([a], [b]) => a.localeCompare(b))
  .map(([stack, weight]) => `${stack} ${weight}\n`).join("");
const flamegraph = resolve(tools, "flamegraph.pl");
const result = await readJson("result.json"), row = result.result.rows.find(r => !r.warmup);
const events = await readJson("sampling-events.json");
assert.equal(result.result.rows.filter(r => !r.warmup).length, 1, "phase slicing requires one measured edit");
const editMs = Number(BigInt(events.filter(e => e.event === "edit:sent").at(-1).monotonicNanos)) / 1e6;
const diagnosticsMs = Number(BigInt(events.filter(e => e.event === "diagnostics:done").at(-1).monotonicNanos)) / 1e6;
// Server receipt precedes the browser's forwarding acknowledgment by an unknown
// fraction of editBridgeMs. These browser-derived boundaries are lower bounds.
const replyMs = editMs + row.notifyToRpcMs + row.rpcMs;
const domMs = replyMs + row.replyToDomMs;
const windows = [
  ["server-before-edit", "Before edit receipt", -Infinity, editMs],
  ["server-until-reply", "Edit → RPC reply (approximate)", editMs, replyMs],
  ["server-until-dom", "RPC reply → DOM (approximate)", replyMs, domMs],
  ["server-after-dom", "DOM → diagnostics (approximate)", domMs, diagnosticsMs],
  ["server-tail", "After diagnostics", diagnosticsMs, Infinity],
].map(([id, label, start, end]) => ({ id, label, start, end, stacks: new Map(),
  samples: 0, referenceExtraction: 0, moduleLookup: 0, referenceLoading: 0, compiler: 0, other: 0 }));
const perfText = await readFile(resolve(capture, "server.perf.script"), "utf8");
const perfTimes = new Map();
for (const match of perfText.matchAll(/^\S+\s+(\d+)\s+(\d+\.\d+):\s+\d+\s+cpu-clock:u:/gm)) {
  if (!perfTimes.has(match[1])) perfTimes.set(match[1], []);
  perfTimes.get(match[1]).push(Number(match[2]) * 1000);
}
let maxClockErrorMs = 0, boundarySensitiveSamples = 0;
async function render(name, stacks, title, units) {
  const folded = foldedText(stacks);
  await writeFile(resolve(capture, `${name}.folded`), folded);
  const result = spawnSync("perl", [flamegraph, "--title", title, "--countname", units,
    "--width", "1600", "--height", "16", "--inverted", "--hash", "--minwidth", name.startsWith("server") ? "1" : "0.2"],
  { input: folded, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  assert.equal(result.status, 0, result.stderr);
  await writeFile(resolve(capture, `${name}.svg`), result.stdout);
}

// Firefox stacks were unwound by samply/framehop, not perf's broken DWARF walk.
const nativeBytes = await readFile(resolve(capture, "server.firefox.json.gz"));
const native = JSON.parse(gunzipSync(nativeBytes));
const threads = native.threads.filter(t => t.samples.length);
const addresses = native.libs.map(() => new Set());
for (const t of threads) for (let f = 0; f < t.frameTable.length; f++) {
  const resource = t.funcTable.resource[t.frameTable.func[f]];
  const lib = t.resourceTable.lib[resource];
  if (lib != null && t.frameTable.address[f] >= 0) addresses[lib].add(t.frameTable.address[f]);
}
const symbols = new Map(), symbolEvidence = [];
for (let i = 0; i < native.libs.length; i++) {
  const lib = native.libs[i], input = [...addresses[i]];
  if (!input.length || lib.path.startsWith("[")) continue;
  const result = spawnSync("addr2line", ["-f", "-C", "-e", lib.path], {
    input: input.map(a => `0x${a.toString(16)}\n`).join(""),
    encoding: "utf8", maxBuffer: 64 * 1024 * 1024,
  });
  assert.equal(result.status, 0, result.stderr);
  const lines = result.stdout.trimEnd().split("\n");
  assert.equal(lines.length, input.length * 2);
  input.forEach((a, j) => {
    if (lines[j * 2] !== "??") symbols.set(`${i}:${a}`, lines[j * 2]);
  });
  symbolEvidence.push({ path: lib.path, sha256: sha(await readFile(lib.path)), addresses: input.length });
}
const nativeStacks = new Map(), nativeSelf = new Map(), nativePoints = [];
const quality = { samples: 0, unresolvedLeafSamples: 0, samplesWithUnresolvedFrame: 0, maxDepth: 0, threads: [] };
for (const t of threads) {
  const frameNames = t.frameTable.func.map((func, f) => {
    const lib = t.resourceTable.lib[t.funcTable.resource[func]];
    const address = t.frameTable.address[f];
    return symbols.get(`${lib}:${address}`) ?? t.stringArray[t.funcTable.name[func]];
  });
  // Preserve symbolicated raw stacks in a Firefox-compatible download too.
  const functionNames = new Map();
  t.frameTable.func.forEach((func, f) => { if (!functionNames.has(func)) functionNames.set(func, frameNames[f]); });
  for (const [func, name] of functionNames) {
    t.funcTable.name[func] = t.stringArray.length;
    t.stringArray.push(name);
  }
  let samples = 0;
  assert.equal(perfTimes.get(t.tid)?.length, t.samples.length, `perf/Firefox count differs for ${t.tid}`);
  for (const [sampleIndex, top] of t.samples.stack.entries()) {
    const time = t.samples.time[sampleIndex];
    const clockError = Math.abs(time - perfTimes.get(t.tid)[sampleIndex]);
    assert.ok(clockError < 0.0011, "Firefox times are not perf CLOCK_MONOTONIC milliseconds");
    maxClockErrorMs = Math.max(maxClockErrorMs, clockError);
    if (top == null) continue;
    const stack = [], seen = new Set();
    for (let s = top; s != null; s = t.stackTable.prefix[s]) {
      assert.ok(!seen.has(s), "cyclic stack table"); seen.add(s);
      stack.push(frameNames[t.stackTable.frame[s]]);
    }
    const unresolved = name => /^0x|\[unknown\]/.test(name);
    quality.samples++; samples++;
    if (unresolved(stack[0])) quality.unresolvedLeafSamples++;
    if (stack.some(unresolved)) quality.samplesWithUnresolvedFrame++;
    quality.maxDepth = Math.max(quality.maxDepth, stack.length);
    add(nativeSelf, stack[0], 1);
    // Process labels preserve the server/worker distinction; threads aggregate.
    const key = [`Lean process ${t.pid}`, ...stack.reverse()].map(clean).join(";");
    add(nativeStacks, key, 1);
    const window = windows.find(w => time >= w.start && time < w.end);
    assert.ok(window, "sample outside partition");
    window.samples++;
    add(window.stacks, key, 1);
    // Disjoint ownership buckets; moduleLookup is a separately reported subset.
    if (key.includes("getModuleContainingDecl")) window.moduleLookup++;
    const owner = key.includes("findModuleRefs") ? "referenceExtraction"
      : key.includes("startLoadingReferences") ? "referenceLoading"
      : /Lean_compileDecls|Lean_Compiler/.test(key) ? "compiler" : "other";
    window[owner]++;
    const detailOwner = owner !== "other" ? owner
      : key.includes("finishDoc") ? "finishDoc"
      : key.includes("retainElaboratedBlocks") ? "retainedBlocks"
      : /Informal_expanderImpl|Informal_Environment_withDirective/.test(key) ? "informal"
      : key.includes("runVersoBlock") ? "versoBlock" : owner;
    nativePoints.push({ timeMs: time - editMs, pid: t.pid, tid: t.tid, owner: detailOwner,
      leaf: stack.at(-1), moduleLookup: key.includes("getModuleContainingDecl") });
    if ([replyMs, domMs].some(b => time >= b && time <= b + row.editBridgeMs)) boundarySensitiveSamples++;
  }
  quality.threads.push({ pid: t.pid, tid: t.tid, name: t.name, samples });
}
await writeFile(resolve(capture, "server.symbolicated.firefox.json.gz"), gzipSync(JSON.stringify(native)));
await render("server", nativeStacks, "Lean server + document worker - sampled CPU, not wall time", "samples");
for (const window of windows.filter(w => w.samples)) {
  await render(window.id, window.stacks, `${window.label} - native sampled CPU`, "samples");
}

// Strip only custom sections when comparing: every executable byte and function
// index must match. Names come from the SDK's optimized unstripped companion.
function reader(bytes) {
  let offset = 0;
  return {
    get offset() { return offset; },
    uleb() {
      let value = 0, shift = 0, byte;
      do {
        assert.ok(offset < bytes.length && shift < 35, "invalid ULEB128");
        byte = bytes[offset++]; value += (byte & 127) * 2 ** shift; shift += 7;
      } while (byte & 128);
      return value;
    },
    take(length) {
      assert.ok(offset + length <= bytes.length, "truncated WASM section");
      const value = bytes.subarray(offset, offset + length); offset += length; return value;
    },
  };
}
function executableSections(bytes) {
  const r = reader(bytes), sections = [];
  assert.deepEqual(r.take(8), Buffer.from([0, 97, 115, 109, 1, 0, 0, 0]));
  while (r.offset < bytes.length) {
    const start = r.offset, id = r.take(1)[0]; r.take(r.uleb());
    if (id !== 0) sections.push(bytes.subarray(start, r.offset));
  }
  return Buffer.concat(sections);
}
const sdkRoot = resolve(result.root, ".lake/build/vir/sdk");
const sdkBytes = await readFile(resolve(sdkRoot, "lean-vir-artifact.json"));
const sdk = JSON.parse(sdkBytes);
assert.equal(sdk.gitCommit, result.virCommit);
assert.equal(sdk.leanToolchain, result.toolchain);
const wasmFiles = await Promise.all(["wasm/vir-upstream.wasm", "wasm/vir-upstream.dev.wasm"].map(async path => {
  const bytes = await readFile(resolve(sdkRoot, path));
  assert.equal(sha(bytes), sdk.files.find(f => f.path === path)?.sha256, `SDK checksum: ${path}`);
  return bytes;
}));
assert.deepEqual(executableSections(wasmFiles[0]), executableSections(wasmFiles[1]));
const wasmNames = new Map();
for (const section of WebAssembly.Module.customSections(new WebAssembly.Module(wasmFiles[1]), "name")) {
  const r = reader(Buffer.from(section));
  while (r.offset < section.byteLength) {
    const kind = r.take(1)[0], subsection = reader(r.take(r.uleb()));
    if (kind !== 1) continue;
    const count = subsection.uleb();
    for (let i = 0; i < count; i++) {
      const index = subsection.uleb(), name = subsection.take(subsection.uleb()).toString("utf8");
      assert.ok(!wasmNames.has(index), "duplicate function name"); wasmNames.set(index, name);
    }
  }
}
assert.ok(wasmNames.size > 0, "missing WASM function names");
const demangled = spawnSync("c++filt", [], {
  input: [...wasmNames.values()].join("\n") + "\n", encoding: "utf8", maxBuffer: 16 * 1024 * 1024,
});
assert.equal(demangled.status, 0, demangled.stderr);
const demangledNames = demangled.stdout.trimEnd().split("\n");
assert.equal(demangledNames.length, wasmNames.size);
[...wasmNames.keys()].forEach((index, i) => wasmNames.set(index, demangledNames[i]));
const wasmEvidence = { sdkManifestSha256: sha(sdkBytes), releaseSha256: sha(wasmFiles[0]),
  unstrippedSha256: sha(wasmFiles[1]), executableSectionsSha256: sha(executableSections(wasmFiles[0])),
  functionNames: wasmNames.size, resolvedFrames: 0, unresolvedFrames: 0 };

const browserBytes = await readFile(resolve(capture, "browser.cpuprofile"));
const browser = JSON.parse(browserBytes);
const wasmUrls = new Set(browser.nodes.filter(n => /^wasm-function\[/.test(n.callFrame.functionName)).map(n => n.callFrame.url));
assert.equal(wasmUrls.size, 1, "multiple WASM modules need separate symbol maps");
for (const node of browser.nodes) {
  const match = /^wasm-function\[(\d+)\]$/.exec(node.callFrame.functionName);
  if (!match) continue;
  const name = wasmNames.get(Number(match[1]));
  if (name) { node.callFrame.functionName = `${name} [wasm:${match[1]}]`; wasmEvidence.resolvedFrames++; }
  else wasmEvidence.unresolvedFrames++;
}
await writeFile(resolve(capture, "browser.symbolicated.cpuprofile"), JSON.stringify(browser));
await writeFile(resolve(capture, "wasm-symbols.json"), JSON.stringify({ ...wasmEvidence, names: Object.fromEntries(wasmNames) }, null, 2));
const nodes = new Map(browser.nodes.map(n => [n.id, n])), parents = new Map();
for (const n of browser.nodes) for (const child of n.children ?? []) parents.set(child, n.id);
const browserStacks = new Map(), activeStacks = new Map(), browserSelf = new Map();
const browserPoints = [];
let browserSampleMicros = browser.startTime;
const browserSummary = { samples: browser.samples.length, sampledMicroseconds: 0, idleMicroseconds: 0,
  programMicroseconds: 0, wasmLeafMicroseconds: 0, reactRenderMicroseconds: 0, callbackMicroseconds: 0,
  interpreterDispatchSelfMicroseconds: 0, symbolLookupSelfMicroseconds: 0 };
assert.equal(browser.samples.length, browser.timeDeltas.length);
browser.samples.forEach((id, i) => {
  const weight = browser.timeDeltas[i], stack = [], seen = new Set();
  for (let n = id; n != null; n = parents.get(n)) {
    assert.ok(!seen.has(n), "cyclic browser stack"); seen.add(n);
    stack.push(nodes.get(n).callFrame.functionName || "(anonymous)");
  }
  const leaf = stack[0];
  browserSampleMicros += weight;
  const owner = stack.includes("renderWithHooks") ? "react"
    : stack.includes("virCallback") ? "callback"
    : leaf === "(idle)" ? "idle" : "browserOther";
  browserPoints.push({ timeMs: browserSampleMicros / 1000 - editMs, owner, leaf });
  browserSummary.sampledMicroseconds += weight;
  if (leaf === "(idle)") browserSummary.idleMicroseconds += weight;
  if (leaf === "(program)") browserSummary.programMicroseconds += weight;
  if (/\[wasm:\d+\]$|^wasm-function/.test(leaf)) browserSummary.wasmLeafMicroseconds += weight;
  if (/interpreter::(?:call|eval_body|eval_expr)\(/.test(leaf)) browserSummary.interpreterDispatchSelfMicroseconds += weight;
  if (/interpreter::lookup_symbol\(|symbol_cache_entry.*::find</.test(leaf)) browserSummary.symbolLookupSelfMicroseconds += weight;
  if (stack.includes("renderWithHooks")) browserSummary.reactRenderMicroseconds += weight;
  else if (stack.includes("virCallback")) browserSummary.callbackMicroseconds += weight;
  add(browserSelf, leaf, weight);
  const key = stack.reverse().map(clean).join(";");
  add(browserStacks, key, weight);
  if (leaf !== "(idle)") add(activeStacks, key, weight);
});
await render("browser", browserStacks, "Browser main thread - includes idle waiting", "sampled microseconds");
await render("browser-active", activeStacks, "Browser main thread - idle samples excluded", "sampled microseconds");
assert.equal(windows.reduce((sum, w) => sum + w.samples, 0), quality.samples);
for (const w of windows) {
  assert.equal(w.referenceExtraction + w.referenceLoading + w.compiler + w.other, w.samples);
  assert.ok(w.moduleLookup <= w.referenceExtraction);
}
const summary = { nativeQuality: quality, browser: browserSummary,
  nativeTimeline: { clock: "perf CLOCK_MONOTONIC ms, checked sample-for-sample against perf script", maxClockErrorMs,
    browserBoundaryUncertaintyMs: row.editBridgeMs, boundarySensitiveSamples,
    windows: windows.map(({ stacks, start, end, ...w }) => ({ ...w,
      startRelativeMs: Number.isFinite(start) ? start - editMs : null,
      endRelativeMs: Number.isFinite(end) ? end - editMs : null })) },
  nativeSelf: [...nativeSelf].sort((a,b) => b[1]-a[1]).slice(0,25),
  browserSelf: [...browserSelf].sort((a,b) => b[1]-a[1]).slice(0,25),
  provenance: { nativeInputSha256: sha(nativeBytes), browserInputSha256: sha(browserBytes),
    flamegraphSha256: sha(await readFile(flamegraph)), symbolEvidence, wasmEvidence,
    scriptSha256: sha(await readFile(new URL(import.meta.url))) } };
await writeFile(resolve(capture, "profile-summary.json"), JSON.stringify(summary, null, 2));
const escape = text => String(text).replaceAll("&", "&amp;").replaceAll("<", "&lt;")
  .replaceAll(">", "&gt;").replaceAll('"', "&quot;");
const ownership = {
  react: ["React + VBP component execution through VIR", "#087f8c"],
  callback: ["VIR callback / response handling (decoder not isolated)", "#8456ad"],
  idle: ["Browser sampled idle", "#b5bec8"],
  browserOther: ["Other / unattributed browser work", "#546477"],
  referenceExtraction: ["Lean reference extraction", "#d57916"],
  referenceLoading: ["Lean background .ilean loading", "#b54f68"],
  compiler: ["Lean compiler", "#3d65b3"],
  other: ["Other Lean work (includes elaboration)", "#849653"],
  finishDoc: ["Verso finishDoc (excluding compiler bucket)", "#be5737"],
  retainedBlocks: ["VBP retain/evaluate directive bodies", "#4b9460"],
  informal: ["Other VBP informal-block processing", "#627e35"],
  versoBlock: ["Other Verso block processing", "#ad913e"],
};
const timelineEnd = diagnosticsMs - editMs;
const plotX = ms => 210 + ms / timelineEnd * 1150;
const tickMs = 10 ** Math.floor(Math.log10(timelineEnd / 5));
const tickStep = [1, 2, 5, 10].map(n => n * tickMs).find(n => timelineEnd / n <= 8);
function sampleLane(points, y) {
  return points.filter(p => p.timeMs >= 0 && p.timeMs <= timelineEnd).map(p =>
    `<line class="cpu-sample" x1="${plotX(p.timeMs)}" x2="${plotX(p.timeMs)}" y1="${y}" y2="${y + 14}" stroke="${ownership[p.owner][1]}" stroke-width="0.8"><title>${escape(`${p.timeMs.toFixed(2)} ms: ${ownership[p.owner][0]}\n${p.leaf}${p.moduleLookup ? "\nInside declaration-to-module lookup" : ""}`)}</title></line>`).join("");
}
const lanes = threads.map(t => ({ pid: t.pid, tid: t.tid,
  points: nativePoints.filter(p => p.pid === t.pid && p.tid === t.tid) }));
// Chromium's monotonic profile times are consistent with the local control
// brackets; no explicit browser↔Node clock calibration was recorded.
const browserStartAckMs = Number(BigInt(events.find(e => e.event === "browser:start").monotonicNanos)) / 1e6;
const browserStopAckMs = Number(BigInt(events.find(e => e.event === "browser:stop").monotonicNanos)) / 1e6;
assert.ok(browser.startTime / 1000 <= browserStartAckMs && browser.endTime / 1000 <= browserStopAckMs);
assert.ok(browser.endTime / 1000 >= domMs && browser.endTime / 1000 < domMs + 50);
const timelineHeight = 175 + lanes.length * 24;
const milestoneLines = [[replyMs - editMs, `RPC reply ≈${(replyMs - editMs).toFixed(0)} ms`],
  [domMs - editMs, `DOM ≈${(domMs - editMs).toFixed(0)} ms`]];
const timelineSvg = `<svg xmlns="http://www.w3.org/2000/svg" id="ownership-timeline" viewBox="0 0 1400 ${timelineHeight}" role="img" aria-label="Chronological preview timeline with subsystem ownership and separate native threads">
<style>text{font:12px system-ui,sans-serif;fill:#243346}.cpu-sample:hover{stroke:#000;stroke-width:3}</style>
<rect width="1400" height="${timelineHeight}" fill="white"/>
${Array.from({ length: Math.floor(timelineEnd / tickStep) + 1 }, (_, i) => i * tickStep).map(ms => `<line x1="${plotX(ms)}" x2="${plotX(ms)}" y1="30" y2="${timelineHeight - 15}" stroke="#e2e7ed"/><text x="${plotX(ms)}" y="20" text-anchor="middle">${ms} ms</text>`).join("")}
<text x="8" y="58">Preview RPC (wall interval)</text>
<rect x="${plotX(row.notifyToRpcMs)}" y="43" width="${row.rpcMs / timelineEnd * 1150}" height="22" fill="#326db8"><title>${row.rpcMs.toFixed(1)} ms RPC; internal phase start timestamps were not recorded. See the duration breakdown below.</title></rect>
<text x="${plotX(row.notifyToRpcMs + row.rpcMs / 2)}" text-anchor="middle" y="58" style="fill:white">RPC</text>
<rect x="${plotX(replyMs - editMs)}" y="43" width="${row.replyToDomMs / timelineEnd * 1150}" height="22" fill="#087f8c"/>
<text x="${plotX(replyMs - editMs + row.replyToDomMs / 2)}" text-anchor="middle" y="58" style="fill:white">Browser</text>
<text x="8" y="94">Browser CPU samples*</text>${sampleLane(browserPoints, 81)}
${milestoneLines.map(([ms, label], i) => `<line x1="${plotX(ms)}" x2="${plotX(ms)}" y1="38" y2="${timelineHeight - 15}" stroke="#263951" stroke-dasharray="4 4"/><text x="${plotX(ms) + 4}" y="${112 + i * 15}">${label}</text>`).join("")}
${lanes.map((lane, i) => `<text x="8" y="${157 + i * 24}">Lean ${escape(lane.pid)} / T${escape(lane.tid)}</text>${sampleLane(lane.points, 144 + i * 24)}`).join("")}
</svg>`;
await writeFile(resolve(capture, "timeline.svg"), timelineSvg);
await writeFile(resolve(capture, "timeline-data.json"), JSON.stringify({ origin: "server edit receipt; Linux monotonic milliseconds",
  browserAlignment: "same-host monotonic alignment inferred from control brackets, not explicitly calibrated",
  boundaryUncertaintyMs: row.editBridgeMs, ownership, milestones: { replyMs: replyMs - editMs, domMs: domMs - editMs, diagnosticsMs: timelineEnd },
  nativePoints, browserPoints }, null, 2));
const blame = [
  ["Before server receipt", `${row.editBridgeMs.toFixed(1)} ms bridge total`, "Harness / transport", "Includes request and acknowledgment; server receipt lies inside this interval."],
  [`≈0–${row.notifyToRpcMs.toFixed(0)} ms`, `${row.notifyToRpcMs.toFixed(1)} ms`, "VBP notification → React effect → RPC", "Widget reacts to the edit; browser acknowledgment alignment is approximate."],
  [`≈${row.notifyToRpcMs.toFixed(0)}–${(replyMs - editMs).toFixed(0)} ms: RPC`, `${row.rpcMs.toFixed(1)} ms`, "Lean worker + VBP server RPC", "Mostly waiting for the end snapshot, not continuous RPC computation."],
  ["↳ Snapshot wait", `${row.snapshotMs.toFixed(1)} ms`, "Lean / Verso document processing", "Measured wait. Elaboration, compilation, scheduling and contention are not individually timed."],
  ["↳ Checked-environment wait", `${row.checkedMs.toFixed(1)} ms`, "Lean asynchronous checking", "Wait remaining after the end snapshot; not all finalization CPU."],
  ["↳ Evaluate document / focus", `${row.evaluationMs.toFixed(1)} ms`, "VBP server preview preparation", "Existing measured server evaluation interval."],
  ["↳ RPC remainder", `${row.rpcRemainderMs.toFixed(1)} ms`, "Scheduling / encoding / transport / outer response parsing", "Computed residual; cannot assign it all to network or place it at one end of RPC."],
  [`≈${(replyMs - editMs).toFixed(0)}–${(domMs - editMs).toFixed(0)} ms`, `${row.replyToDomMs.toFixed(1)} ms`, "VBP response handling + VIR interpreter + React", `Samples show ≈${(browserSummary.callbackMicroseconds / 1000).toFixed(0)} ms in callbacks and ≈${(browserSummary.reactRenderMicroseconds / 1000).toFixed(0)} ms under React; these are sampled attribution, not exact subphase timers.`],
  [`≈${(domMs - editMs).toFixed(0)}–${timelineEnd.toFixed(0)} ms`, `${(timelineEnd - (domMs - editMs)).toFixed(1)} ms`, "Lean post-display work", "Preview already visible. See the reference/compiler/other sample counts below."],
];
const blameHtml = `<section class="panel" id="timeline"><h2>Chronological timeline and phase ownership</h2>
<p>Time zero is <strong>server edit receipt</strong>. Each vertical tick is one CPU sample at its recorded timestamp—not an invented function-duration span. Separate Lean rows preserve parallel threads; gaps do not prove idle time. Hover a tick for its owner and leaf function.</p>
<div style="overflow-x:auto">${timelineSvg.replace('viewBox=', 'style="min-width:1000px;width:100%" viewBox=')}</div>
<div class="legend">${Object.values(ownership).map(([label, color]) => `<span style="--color:${color}">${escape(label)}</span>`).join("")}</div>
<p><small>*Browser CPU samples use inferred same-host monotonic alignment consistent with capture-control brackets; no explicit cross-clock calibration was recorded. RPC/DOM milestones have up to ${row.editBridgeMs.toFixed(1)} ms bridge uncertainty. Native timestamps were checked against perf. The browser edit-start total is ${row.totalMs.toFixed(1)} ms; the server-origin DOM milestone is approximately ${(domMs - editMs).toFixed(1)} ms.</small></p>
<div style="overflow-x:auto"><table><thead><tr><th>When / phase</th><th>Duration</th><th>Owner</th><th>What the evidence supports</th></tr></thead><tbody>${blame.map(cells => `<tr>${cells.map(cell => `<td>${escape(cell)}</td>`).join("")}</tr>`).join("")}</tbody></table></div>
<p>Indented RPC rows break down the RPC total; do not add them again. Their durations are known, but their exact absolute start times are not, so they are not drawn as chronological subspans. CPU samples show who was running, not which task caused every millisecond of waiting.</p>
<p><a href="timeline.svg">Full-size timeline</a> · <a href="timeline-data.json">Timestamped samples and ownership data</a></p></section>`;
const phases = [
  ["Edit bridge", row.editBridgeMs, "#748094"],
  ["Notify → request", row.notifyToRpcMs, "#9b6cb8"],
  ["RPC", row.rpcMs, "#326db8"],
  ["Decode / render / DOM", row.replyToDomMs, "#23866b"],
];
const end = Math.max(row.totalMs, row.diagnosticsMs);
const bar = `<svg viewBox="0 0 1000 84" role="img" aria-label="Edit to preview timing, with diagnostics completion on a separate overlapping lane">${
  phases.map(([name, ms, color], i) => {
    const x = phases.slice(0, i).reduce((n, p) => n + p[1], 0) / end * 1000;
    return `<rect x="${x}" y="8" width="${ms / end * 1000}" height="26" fill="${color}"><title>${name}: ${ms.toFixed(1)} ms</title></rect>`;
  }).join("")
}<rect x="0" y="49" width="1000" height="8" fill="#d3d9e1"/><text x="0" y="79" font-size="13">0 ms</text><text x="1000" y="79" text-anchor="end" font-size="13">Diagnostics complete: ${row.diagnosticsMs.toFixed(0)} ms (overlapping)</text></svg>`;
const profileChoices = [
  ["server", "Lean server + document worker"],
  ...windows.filter(w => w.samples && !["server-before-edit", "server-tail"].includes(w.id)).map(w => [w.id, w.label]),
  ["browser-active", "Browser — idle excluded"], ["browser", "Browser — including idle"],
];
const objects = await Promise.all(profileChoices.map(async ([name]) => {
  const svg = await readFile(resolve(capture, `${name}.svg`), "utf8");
  const height = /<svg[^>]*height="([0-9.]+)"/.exec(svg)?.[1];
  assert.ok(height, "SVG dimensions missing");
  return `<div id="${name}" class="graph" ${name === "server" ? "" : "hidden"}><object data="${name}.svg" type="image/svg+xml" style="width:100%;aspect-ratio:1600/${height};display:block"></object></div>`;
}));
await writeFile(resolve(capture, "index.html"), `<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>FLT preview — sampled flamegraphs</title>
<style>
body{font:16px/1.5 system-ui,sans-serif;color:#192332;background:#f5f7fa;margin:0}main{max-width:1560px;margin:auto;padding:24px}
h1{margin:0;font-size:28px}h2{font-size:19px}p{max-width:100ch}a{color:#185baf}code{overflow-wrap:anywhere}
.panel{background:white;border:1px solid #d7dfe9;border-radius:8px;padding:18px;margin:18px 0}.legend{display:flex;gap:20px;flex-wrap:wrap}
.legend span::before{content:"";display:inline-block;width:12px;height:12px;background:var(--color);margin-right:6px}
.graph{max-height:660px;overflow:auto;border:1px solid #d7dfe9;background:#fff;margin-top:14px}.graph[hidden]{display:none}
select{font:inherit;padding:6px}small,.muted{color:#526174}li{margin:5px 0}table{border-collapse:collapse}td,th{text-align:left;padding:5px 16px 5px 0}
</style><main>
<h1>FLT preview: where the work runs</h1>
<p class="muted">Reductions chapter · one warm prose edit · checked JSON + retained fingerprints + KaTeX · highlighting/debug off</p>
<section class="panel"><h2>Observed timeline</h2>
<p><strong>${row.totalMs.toFixed(0)} ms to the updated DOM.</strong> Lean diagnostics completed at ${row.diagnosticsMs.toFixed(0)} ms.
This is one <em>sampled diagnostic run</em>, not a new latency benchmark. Initial loading and one warmup edit are excluded.</p>
${bar}<div class="legend">${phases.map(([name, ms, color]) => `<span style="--color:${color}">${name}: ${ms.toFixed(1)} ms</span>`).join("")}</div>
<p><small>The two lanes overlap. Browser and Lean run concurrently; their CPU costs must not be added to get elapsed time.
Endpoint: observed DOM commit, not VS Code paint. The thin diagnostics lane starts at server edit receipt, about ${row.editBridgeMs.toFixed(1)} ms after the browser's edit start; its display alignment is approximate.</small></p></section>
${blameHtml}
<section class="panel"><h2>Interactive flamegraphs</h2>
<label>Profile <select id="profile">${profileChoices.map(([id, label]) => `<option value="${id}">${escape(label)}</option>`).join("")}</select></label>
<p>Click a frame to zoom; use <strong>Search</strong> inside the graph to find a function. Scroll down to follow deep stacks.
Width represents aggregate sampled weight; <strong>left-to-right order is not chronological</strong>.</p>
<p><small>For readability, native frames narrower than one pixel are omitted from the SVG; the downloadable profile retains every sample.</small></p>
${objects.join("")}
<p>Open full size: <a href="server.svg">Lean server</a> · <a href="browser-active.svg">Browser active</a> · <a href="browser.svg">Browser including idle</a></p>
</section>
<section class="panel"><h2>Native work by timeline window</h2>
<p>Counts below are <strong>CPU samples across parallel threads, not wall-clock milliseconds</strong>.
Columns partition all samples; module-name lookup is a subset of reference extraction, not another additive cost.</p>
<div style="overflow-x:auto"><table><thead><tr><th>Window after server edit</th><th>Reference extraction</th><th>Background reference loading</th><th>Compiler</th><th>Other work</th><th>Total samples</th></tr></thead><tbody>
${summary.nativeTimeline.windows.filter(w => w.startRelativeMs != null && w.endRelativeMs != null).map(w => `<tr><td>${w.startRelativeMs.toFixed(0)}–${w.endRelativeMs.toFixed(0)} ms</td><td>${w.referenceExtraction} (${w.moduleLookup} module lookup)</td><td>${w.referenceLoading}</td><td>${w.compiler}</td><td>${w.other}</td><td>${w.samples}</td></tr>`).join("")}
</tbody></table></div>
<p><small>All ${quality.samples} Firefox sample timestamps match the original perf timestamps within ${(maxClockErrorMs * 1000).toFixed(2)} µs.
RPC/DOM boundary alignment has up to ${row.editBridgeMs.toFixed(1)} ms uncertainty from the HTTP edit bridge;
${boundarySensitiveSamples} samples may move to the preceding window. Another ${windows[0].samples + windows.at(-1).samples} samples fall outside edit→diagnostics.</small></p>
<p>The table preserves reference/indexing work before and after the reply separately.
Post-reply work can compete for CPU, but is not a prerequisite for publishing the reply.
${windows.some(w => w.referenceLoading) ? "The background loader is still reading reference indexes in this fresh server session." : "No startLoadingReferences samples occur in this capture."}</p></section>
<section class="panel"><h2>What is visible — and what is not</h2><ul>
<li>Native capture: ${quality.samples.toLocaleString()} samples across ${quality.threads.length} active threads.
Samply/framehop unwound the recorded stacks; local <code>addr2line</code> resolved their symbols.
${quality.samplesWithUnresolvedFrame} samples (${(100 * quality.samplesWithUnresolvedFrame / quality.samples).toFixed(2)}%) contain an unresolved frame. The original perf DWARF call chains were rejected.</li>
<li>Both Lean server processes are retained, including reference/indexing work and asynchronous tasks.
Reference-index gate: ${escape(result.referenceIndexGate ?? "none; early-session cohort")}. These samples are not all edited-block elaboration.</li>
<li>Browser: ${(browserSummary.idleMicroseconds / 1000).toFixed(0)} ms sampled idle; ${(browserSummary.reactRenderMicroseconds / 1000).toFixed(0)} ms under React rendering;
${(browserSummary.callbackMicroseconds / 1000).toFixed(0)} ms in VIR callbacks outside React rendering.
The callback bucket is consistent with response handling/decoding, but does not identify individual Lean decoder functions.</li>
<li>All ${wasmEvidence.resolvedFrames} WASM call-frame nodes resolve using the optimized unstripped SDK companion (${wasmEvidence.unresolvedFrames} unresolved).
Every non-custom WASM section matches the release binary byte-for-byte; no rebuild or runtime instrumentation was needed.
Original function indices remain in labels and the original raw profile is unchanged.</li>
<li>Interpreter <code>call</code>, <code>eval_body</code> and <code>eval_expr</code> account for ${(browserSummary.interpreterDispatchSelfMicroseconds / 1000).toFixed(0)} ms sampled self time;
<code>lookup_symbol</code> and symbol-cache lookup for another ${(browserSummary.symbolLookupSelfMicroseconds / 1000).toFixed(0)} ms.
These disjoint self-time buckets occur within the callback/render totals above and must not be added to them.
Symbols identify C++ interpreter functions, not the Lean declaration being interpreted. <code>(program)</code> remains unattributed.</li>
<li>Profiler start/stop overhead remains in the capture; sampled totals are not a replacement for the uninstrumented timing benchmark.</li>
<li>Browser sampling stops after the accepted DOM update, before harness verification. Native sampling continues through diagnostics completion.
This is the warm edit path, not startup, a full HTML build, or the entire FLT document.</li>
</ul></section>
<details class="panel"><summary>Raw profiles and reproduction</summary>
<p><a href="browser.symbolicated.cpuprofile">Symbolicated Chrome CPU profile</a> (load in DevTools) ·
<a href="browser.cpuprofile">Original Chrome CPU profile</a> · <a href="wasm-symbols.json">WASM names/provenance</a> ·
<a href="server.symbolicated.firefox.json.gz">Symbolicated Firefox profile</a> ·
<a href="server.perf.data">Original perf capture</a> · <a href="profile-summary.json">Summary/provenance</a> ·
<a href="result.json">Timing and identities</a> · <a href="sampling-events.json">Capture markers</a></p>
<p>Lean ${escape(result.toolchain)}; VIR <code>${escape(result.virCommit)}</code>.
VBP RPC source hash: <code>${escape(result.rpcSourceSha256)}</code>.</p>
<p>Capture with the existing latency driver using <code>VBP_LATENCY_SAMPLING=1 VBP_LATENCY_SAMPLES=1</code>.
Capture configuration: ${escape(result.cpuSampling)}.
Use <code>samply import --save-only</code>, then <code>tests/vir_preview/render_sampled_profiles.mjs CAPTURE FLAMEGRAPH_TOOLS</code>.
Graphs are rendered by <a href="https://github.com/brendangregg/FlameGraph">Brendan Gregg's FlameGraph</a>; local tool/binary hashes are recorded.</p>
</details></main><script>
document.getElementById("profile").addEventListener("change",event=>{for(const graph of document.querySelectorAll(".graph"))graph.hidden=graph.id!==event.target.value;});
</script></html>`);
console.log(JSON.stringify(summary, null, 2));
