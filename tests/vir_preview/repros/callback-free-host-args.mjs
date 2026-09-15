// Usage: node callback-free-host-args.mjs VIR_WEB_SRC_OR_SDK_JS [--bench]
// Unmodified VIR dispatcher and argument lifting; only Wasm memory/exports are mocked.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

assert.ok(process.argv[2], "supply VIR web/src or SDK js directory");
const root = resolve(process.argv[2]);
const load = name => import(pathToFileURL(resolve(root, "runtime", name)));
const { VirHostState } = await load("host-state.js");
const { ObjectValueRuntime } = await load("object-values.js");
const { INTERFACE_TAG } = await load("interface-tags.js");
const { HOST_IMPORT_BOUNDARY } = await load("interface-manifest.js");

class CountedSet extends Set {
  passes = 0;
  visits = 0;
  *[Symbol.iterator]() {
    this.passes++;
    for (const value of super.values()) { this.visits++; yield value; }
  }
}

function fixture(rootCount, counted = false) {
  const object = {};
  const resources = new Map([[1, object], [2, "answer"], [3, 42]]);
  const buffer = new ArrayBuffer(16);
  new Uint32Array(buffer).set([0, 1, 2, 3]); // argv begins at non-null offset 4
  const exports = {
    memory: { buffer },
    vir_obj_resource_is_valid: pointer => Number(resources.has(pointer)),
    vir_obj_resource_externref: pointer => resources.get(pointer),
    vir_obj_scalar: value => { assert.equal(value, 0); return 1; },
    vir_obj_closure_root: () => { throw Error("resource lifting must not create a callback"); },
  };
  const runtime = new ObjectValueRuntime();
  runtime.exports = exports;
  const roots = Array.from({ length: rootCount }, () => ({}));
  runtime.liveCallbacks = counted ? new CountedSet(roots) : new Set(roots);
  const host = new VirHostState({ defaultHostBindings: {}, hostBindings: {
    "example.set": (object, key, value) => { object[key] = value; },
  } });
  host.attach(exports);
  host.attachRuntime(runtime);
  const type = { interfaceTag: INTERFACE_TAG.RESOURCE, kind: "resource", name: "Lean.Vir.Js" };
  host.setManifest({ hostImports: [{ target: "example.set", boundary: HOST_IMPORT_BOUNDARY.HOST_RESOURCE,
    args: ["object", "key", "value"].map(name => ({ name, type })),
    result: { interfaceTag: INTERFACE_TAG.UNIT } }] });
  return { host, runtime, object };
}

const witness = fixture(56, true);
assert.equal(witness.host.callObjectsImpl(0, 4, 3), 1);
assert.equal(witness.object.answer, 42);
assert.equal(witness.runtime.liveCallbacks.size, 56);
const output = { scope: "Node dispatcher reproducer; real VIR lifting, mock Wasm exports; not widget latency",
  node: process.version, v8: process.versions.v8, source: root,
  witness: { arguments: 3, retainedRoots: 56, callbacksCreated: 0,
    registryPasses: witness.runtime.liveCallbacks.passes, registryEntriesVisited: witness.runtime.liveCallbacks.visits },
  hashes: {} };
for (const name of ["host-state.js", "object-values.js", "object-abi.js", "interface-tags.js"]) {
  output.hashes[name] = createHash("sha256").update(await readFile(resolve(root, "runtime", name))).digest("hex");
}

if (process.argv.includes("--bench")) {
  const calls = 20000;
  const fixtures = [fixture(0), fixture(56)]; // ordinary Sets; no counting overhead
  const run = fixture => {
    let sum = 0;
    const start = performance.now();
    for (let i = 0; i < calls; i++) sum += fixture.host.callObjectsImpl(0, 4, 3);
    const ms = performance.now() - start;
    assert.equal(sum, calls);
    assert.equal(fixture.object.answer, 42);
    return ms;
  };
  for (let i = 0; i < 3; i++) for (const fixture of fixtures) run(fixture);
  const rows = [];
  for (let pair = 0; pair < 6; pair++) {
    const order = pair % 2 ? [1, 0] : [0, 1];
    const ms = {};
    for (const index of order) ms[index ? 56 : 0] = run(fixtures[index]);
    rows.push({ pair, order: order.map(index => index ? 56 : 0), ms, deltaMs: ms[56] - ms[0] });
  }
  output.benchmark = { calls, warmupsPerConfiguration: 3, rows };
}
console.log(JSON.stringify(output, null, 2));
