// Browser-only extraction of the existing sampled-profile symbolication path.
// Usage: node summarize_replay_profile.mjs CAPTURE [FLAMEGRAPH_PL] [--live] [--out=DIR] [--fir-named-wasm=FILE]
// --live summarizes a single edit capture; default retains replay phase slicing.
import assert from "node:assert/strict";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { resolve, basename } from "node:path";
import { pathToFileURL } from "node:url";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
const capture = resolve(process.argv[2]);
const outputArg = process.argv.slice(3).find(arg => arg.startsWith("--out="));
const output = outputArg ? resolve(outputArg.slice("--out=".length)) : capture;
assert.ok(!outputArg || outputArg.length > "--out=".length, "empty output path");
const live = process.argv.includes("--live");
const component = process.argv.includes("--component");
const flamegraphPath = process.argv.slice(3).find(arg => !arg.startsWith("--"));
const identity = JSON.parse(await readFile(resolve(capture, "identity.json")));
const fir = identity.backend === "fir";
const namedArg = process.argv.slice(3).find(arg => arg.startsWith("--fir-named-wasm="));
assert.ok(!namedArg || (fir && namedArg.length > "--fir-named-wasm=".length),
  "--fir-named-wasm requires a FIR capture and a nonempty path");
assert.ok(!fir || (!component && !live), "FIR replay uses its own phase windows");
const report = JSON.parse(await readFile(resolve(capture, "result.json")));
const result = { ...report, root: identity.root,
  ...(component ? {virCommit:identity.virCommit,toolchain:identity.toolchain} : {}) };
const sha = x => createHash("sha256").update(x).digest("hex");
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
function functionNames(bytes) {
  const names = new Map();
  for (const section of WebAssembly.Module.customSections(new WebAssembly.Module(bytes), "name")) {
    const r = reader(Buffer.from(section));
    while (r.offset < section.byteLength) {
      const kind = r.take(1)[0], payload = r.take(r.uleb()), subsection = reader(payload);
      if (kind !== 1) continue;
      const count = subsection.uleb();
      for (let i = 0; i < count; i++) {
        const index = subsection.uleb(), name = subsection.take(subsection.uleb()).toString("utf8");
        assert.ok(!names.has(index), "duplicate function name"); names.set(index, name);
      }
      assert.equal(subsection.offset, payload.length, "trailing function-name bytes");
    }
  }
  return names;
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
const wasmNames = functionNames(wasmFiles[1]);
assert.ok(wasmNames.size > 0, "missing WASM function names");
const demangled = spawnSync("c++filt", [], {
  input: [...wasmNames.values()].join("\n") + "\n", encoding: "utf8", maxBuffer: 16 * 1024 * 1024,
});
assert.equal(demangled.status, 0, demangled.stderr);
const demangledNames = demangled.stdout.trimEnd().split("\n");
assert.equal(demangledNames.length, wasmNames.size);
[...wasmNames.keys()].forEach((index, i) => wasmNames.set(index, demangledNames[i]));
let wasmEvidence = { sdkManifestSha256: sha(sdkBytes), releaseSha256: sha(wasmFiles[0]),
  unstrippedSha256: sha(wasmFiles[1]), executableSectionsSha256: sha(executableSections(wasmFiles[0])),
  functionNames: wasmNames.size, resolvedFrames: 0, unresolvedFrames: 0 };
if (fir) {
  const bytes = await readFile(resolve(capture, "fir/component.wasm"));
  assert.equal(sha(bytes), identity.firIdentity.build.wasm.sha256);
  assert.equal(WebAssembly.Module.customSections(new WebAssembly.Module(bytes), "name").length, 0,
    "named FIR artifacts need an explicit symbol map");
  wasmNames.clear();
  wasmEvidence = { firWasmSha256: sha(bytes), functionNames: 0, resolvedFrames: 0, unresolvedFrames: 0 };
  if (namedArg) {
    assert.ok(outputArg, "FIR symbols require a separate --out directory");
    const namedPath = resolve(namedArg.slice("--fir-named-wasm=".length));
    const named = await readFile(namedPath);
    assert.ok(executableSections(bytes).equals(executableSections(named)),
      "FIR named Wasm does not match all captured non-custom sections");
    for (const [index, name] of functionNames(named)) wasmNames.set(index, name);
    assert.ok(wasmNames.size > 0, "missing FIR function names");
    Object.assign(wasmEvidence, { namedWasmPath: namedPath, namedWasmSha256: sha(named),
      executableSectionsSha256: sha(executableSections(bytes)), functionNames: wasmNames.size });
  }
}

const browserBytes = await readFile(resolve(capture, "browser.cpuprofile"));
const browser = JSON.parse(browserBytes);
const componentClock = component ? JSON.parse(await readFile(resolve(capture,"profile-clock.json"))) : null;
const componentWindows = component ? report.browser.samples.map(row => ({phase:row.backend+":content",
  start:(row.contentStartMs+componentClock.offsetMs)*1000,end:(row.contentEndMs+componentClock.offsetMs)*1000})) : [];
const nodes = new Map(browser.nodes.map(n => [n.id,n])), parents = new Map();
for (const n of browser.nodes) for (const child of n.children ?? []) parents.set(child,n.id);
const moduleOwners = new Map(), nodeCategories = new Map();
if (component || fir) {
  if (component) {
  let time = browser.startTime;
  for (let i=0;i<browser.samples.length;i++) {
    const from=time;time+=browser.timeDeltas[i];
    const window = componentWindows.find(w=>Math.min(time,w.end)>Math.max(from,w.start));
    if (!window) continue;
    for(let id=browser.samples[i];id!==undefined;id=parents.get(id)) {
      const frame=nodes.get(id).callFrame;
      // V8 can share js-to-wasm trampolines between modules of the same
      // signature; their attributed URL is not evidence of body ownership.
      if (!frame.url.startsWith('wasm://') || /^(js-to-wasm|wasm-to-js)/.test(frame.functionName)) continue;
      const owner=window.phase.split(':')[0];
      assert(!moduleOwners.has(frame.url)||moduleOwners.get(frame.url)===owner,'Wasm URL crosses backend content windows');
      moduleOwners.set(frame.url,owner);
    }
  }
  assert.deepEqual([...new Set(moduleOwners.values())].sort(),['fir','vir'],'both backend Wasm modules must be sampled');
  } else {
    const urls = new Set(browser.nodes.filter(n => /^wasm-function\[/.test(n.callFrame.functionName)).map(n => n.callFrame.url));
    assert.equal(urls.size, 1, "multiple FIR modules need explicit owner mapping");
    for (const url of urls) moduleOwners.set(url, "fir");
  }
  const mapBytes = await readFile(resolve(capture,'probe.js.map'));
  const sourceMapPath = resolve(result.root,'.lake/packages/lean_vir/node_modules/source-map-js/source-map.js');
  const mapping = await import(pathToFileURL(sourceMapPath));
  const consumer = new (mapping.SourceMapConsumer??mapping.default.SourceMapConsumer)(JSON.parse(mapBytes));
  wasmEvidence.componentModules=Object.fromEntries(moduleOwners);
  wasmEvidence.sourceMapSha256=sha(mapBytes);
  wasmEvidence.sourceMapToolSha256=sha(await readFile(sourceMapPath));
  for (const node of browser.nodes) {
    const frame=node.callFrame;
    if (!frame.url.includes('/probe.js') || frame.lineNumber<0) continue;
    const position=consumer.originalPositionFor({line:frame.lineNumber+1,column:frame.columnNumber});
    if (!position.source) continue;
    const source=position.source;
    nodeCategories.set(node.id, source.endsWith('/host-prototype.mjs') ? 'FIR JS adapter'
      : source.endsWith('/providers.mjs') ? 'Author provider bundle (JS)'
      : source.includes('node_modules/react-dom/') ? 'React hooks (JS)'
      : source.includes('node_modules/react/') ? 'React elements (JS)'
      : source.endsWith('vir-react-host-bindings.js') ? 'React host provider (JS)'
      : /vir-js-(collection|value)-bindings|vir-dom-host-bindings/.test(source) ? 'JS value/collection providers'
      : source.includes('/js/') || source.includes('/web/src/runtime/') ? 'VIR JS runtime/boundary'
      : 'Other JavaScript');
    frame.functionName=`${frame.functionName||position.name||'(anonymous)'} [${basename(source)}:${position.line}]`;
  }
  for (const node of browser.nodes) {
    if (node.callFrame.functionName!=='decode') continue;
    const parent=nodes.get(parents.get(node.id))?.callFrame.functionName??'';
    if (/^read(String|WasmString)/.test(parent)) nodeCategories.set(node.id,'Host UTF-8 conversion (JS builtin)');
  }
  consumer.destroy?.();
}
const wasmUrls = new Set(browser.nodes.filter(n => /^wasm-function\[/.test(n.callFrame.functionName)).map(n => n.callFrame.url));
if (!component) assert.equal(wasmUrls.size, 1, "multiple WASM modules need separate symbol maps");
for (const node of browser.nodes) {
  const match = /^wasm-function\[(\d+)\]$/.exec(node.callFrame.functionName);
  if (!match) continue;
  if ((component || fir) && moduleOwners.get(node.callFrame.url)!=='vir') {
    if (moduleOwners.get(node.callFrame.url)==='fir') {
      const name = fir ? wasmNames.get(Number(match[1])) : undefined;
      node.callFrame.functionName=name ? `${name} [fir-wasm:${match[1]}]` : `FIR wasm:function${match[1]} (stripped)`;
      nodeCategories.set(node.id, name ? 'FIR Wasm (named)' : 'FIR Wasm (internal symbols unavailable)');
      if (name) wasmEvidence.resolvedFrames++; else wasmEvidence.unresolvedFrames++;
    }
    continue;
  }
  const name = wasmNames.get(Number(match[1]));
  if (name) { node.callFrame.functionName = `${name} [wasm:${match[1]}]`; wasmEvidence.resolvedFrames++; }
  else wasmEvidence.unresolvedFrames++;
}
if (outputArg) await mkdir(output, { recursive: false });
await writeFile(resolve(output, "browser.symbolicated.cpuprofile"), JSON.stringify(browser));
await writeFile(resolve(output, "wasm-symbols.json"), JSON.stringify({ ...wasmEvidence, names: Object.fromEntries(wasmNames) }, null, 2));

const clock = live ? null : componentClock??JSON.parse(await readFile(resolve(capture, "profile-clock.json")));
if (clock) assert.ok(clock.uncertaintyMs < 5, "clock calibration too imprecise");
if (live) {
  assert.equal(report.samples, 1, "live profile must isolate one measured edit");
  assert.equal(report.result.rows.filter(row => !row.warmup).length, 1);
  assert.ok(report.cpuSampling, "live capture must enable sampling");
}
const windows = component ? componentWindows : live ? [{ phase: "live-edit", start: browser.startTime, end: browser.endTime }] : report.acceptance.rows.flatMap(row => ["whole","browserParsed"].flatMap(mode => {
  if (!row[mode]) return [];
  const {start, decodedAt, committedAt, parsedAt, convertedAt, end} = row[mode].raw;
  if (decodedAt === undefined) return [
    { phase: mode + ":parse", start: (start + clock.offsetMs) * 1000, end: (parsedAt + clock.offsetMs) * 1000 },
    { phase: mode + ":convert", start: (parsedAt + clock.offsetMs) * 1000, end: (convertedAt + clock.offsetMs) * 1000 },
    { phase: mode + ":reconstruct", start: (convertedAt + clock.offsetMs) * 1000, end: (end + clock.offsetMs) * 1000 },
  ];
  return [
    {phase: mode + ":decode", start:(start+clock.offsetMs)*1000, end:(decodedAt+clock.offsetMs)*1000},
    {phase: mode + ":render", start:(decodedAt+clock.offsetMs)*1000, end:(committedAt+clock.offsetMs)*1000},
  ];
}));
if (fir) for (const row of report.acceptance.rows) {
  const sample = row.browserParsed;
  const { start, parsedAt, decodedAt } = sample.raw;
  windows.push({ phase: "fir:parse", start: (start + clock.offsetMs) * 1000,
    end: (parsedAt + clock.offsetMs) * 1000 },
    { phase: "fir:checked-codec", start: (parsedAt + clock.offsetMs) * 1000,
      end: (decodedAt + clock.offsetMs) * 1000 });
  for (const event of sample.componentEvents ?? []) {
    assert.equal(event.factory, 1, "default view must own measured callbacks");
    windows.push({ phase: "fir:" + event.phase, start: (event.startMs + clock.offsetMs) * 1000,
      end: (event.endMs + clock.offsetMs) * 1000 });
  }
}
const summary = {};
let timestamp=browser.startTime;
assert.equal(browser.samples.length,browser.timeDeltas.length);
for (let i=0;i<browser.samples.length;i++) {
  const from=timestamp; timestamp+=browser.timeDeltas[i];
  const stack=[]; const seen=new Set();
  for(let id=browser.samples[i]; id!==undefined; id=parents.get(id)) {
    assert.ok(!seen.has(id)); seen.add(id);
    stack.push(nodes.get(id).callFrame.functionName || "(anonymous)");
  }
  for (const w of windows) {
    const weight=Math.min(timestamp,w.end)-Math.max(from,w.start);
    if(weight<=0)continue;
    // Caller groups are disjoint subdivisions of the live capture, not
    // chronological decode/render boundaries or additional elapsed time.
    const keys = [w.phase];
    if (live) keys.push(stack.includes("renderWithHooks") ? "react-render-callbacks"
      : stack.includes("virCallback") ? "other-lean-callbacks" : "outside-lean-callbacks");
    for (const key of keys) {
      const a=summary[key]??={us:0,samples:0,self:{},inclusive:{},folded:{},categories:{}};
      a.us+=weight; a.samples++;
      a.self[stack[0]]=(a.self[stack[0]]??0)+weight;
      if (component || fir) {
        const frame=nodes.get(browser.samples[i]).callFrame;
        const leaf=stack[0];
        const category=nodeCategories.get(browser.samples[i])??(leaf==='(garbage collector)' ? 'Browser GC'
          : /^(js-to-wasm|wasm-to-js)/.test(leaf) ? 'JS/Wasm transition (shared wrapper)'
          : moduleOwners.get(frame.url)==='vir' ? (/interpreter::(eval_body|eval_expr|call)\(/.test(leaf) ? 'VIR interpreter dispatch/evaluation'
            : /symbol_cache_entry|constant_cache_entry|interpreter::lookup_symbol|__hash.*find<lean::name>/.test(leaf) ? 'VIR symbol/constant/name lookup'
            : /^(dlmalloc|dlfree|lean_dec_ref_cold)|interpreter::alloc_ctor|vector<.*>::resize/.test(leaf) ? 'VIR allocation/refcount/vector storage'
            : 'Other VIR Wasm') : 'Unattributed/browser');
        a.categories[category]=(a.categories[category]??0)+weight;
      }
      for(const name of new Set(stack)) a.inclusive[name]=(a.inclusive[name]??0)+weight;
      const folded=stack.toReversed().join(";");
      a.folded[folded]=(a.folded[folded]??0)+weight;
    }
  }
}
const top=(xs,total)=>Object.entries(xs).sort((a,b)=>b[1]-a[1]).slice(0,30).map(([name,us])=>({name,ms:us/1000,percent:100*us/total}));
const compact={clock,wasmEvidence,rawProfileSha256:sha(browserBytes),
  capture,
  scope: component ? 'calibrated matched content callback windows; sampled attribution, not baseline wall timings; FIR internal symbols stripped'
    : live ? "capture surrounding one edit through accepted DOM; includes RPC idle and capture-control overhead; caller groups subdivide live-edit, not temporal phases"
    : fir ? `FIR calibrated replay; parse/codec subdivide decode; session/content subdivide render; overlapping windows must not be added; ${wasmNames.size ? "FIR names from matching non-custom sections" : "FIR internal symbols stripped"}`
    : "calibrated replay decode/render windows",
  phases:{}};
for(const [phase,a]of Object.entries(summary)) {
  const categories = component || fir ? a.categories : {};
  if (!component && !fir) for (const [leaf, us] of Object.entries(a.self)) {
    const category = leaf === "(idle)" ? "Idle"
      : /interpreter::(eval_body|eval_expr|call)\(/.test(leaf) ? "Interpreter dispatch/evaluation"
      : /symbol_cache_entry|constant_cache_entry|interpreter::lookup_symbol|__hash.*find<lean::name>/.test(leaf) ? "Symbol/constant/name lookup"
      : /^(dlmalloc|dlfree|lean_dec_ref_cold)|interpreter::alloc_ctor|vector<.*>::resize/.test(leaf) ? "Allocation/refcount/vector storage"
      : leaf.includes("[wasm:") ? "Other WASM" : "JavaScript/browser";
    categories[category] = (categories[category] ?? 0) + us;
  }
  compact.phases[phase]={samples:a.samples,sampledMs:a.us/1000,observations:component ? windows.filter(w=>w.phase===phase).length : live ? 1 : report.acceptance.rows.length,
    categories:top(categories,a.us),self:top(a.self,a.us),inclusive:top(a.inclusive,a.us),
    ...(component || fir ? {} : {hostBoundaryPercent:100*(a.inclusive.callObjectsImpl??0)/a.us,
    commitRootPercent:100*(a.inclusive.commitRoot??0)/a.us})};
  const folded = Object.entries(a.folded).map(([stack,us])=>stack+" "+Math.round(us)).join("\n")+"\n";
  await writeFile(resolve(output,phase.replace(":","-")+".folded"),folded);
  if (flamegraphPath) {
    const graph = spawnSync("perl", [resolve(flamegraphPath), "--title", phase + " - sampled CPU (not a timeline)",
      "--countname", "microseconds", "--width", "1600", "--hash"], {input:folded,encoding:"utf8",maxBuffer:32*1024*1024});
    assert.equal(graph.status,0,graph.stderr);
    await writeFile(resolve(output,phase.replace(":","-")+".svg"),graph.stdout);
    compact.flamegraphToolSha256 = sha(await readFile(resolve(flamegraphPath)));
  }
}
await writeFile(resolve(output,"profile-summary.json"),JSON.stringify(compact,null,2));
console.log(JSON.stringify(compact,null,2));
