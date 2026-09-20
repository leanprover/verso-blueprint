import assert from "node:assert/strict";
import test from "node:test";
import { createHostImportCensus, instrumentHostPrototypeSource } from "./host_import_census.mjs";

test("census reports only active calls and resets between phases", () => {
  const census = createHostImportCensus(2);
  const first = census.register("physical.one", "logical.one", "j_");
  const second = census.register("physical.two", "logical.two", "s_");
  census.counts[first]++;
  census.begin("content", 0);
  census.counts[first] += 3;
  census.counts[second]++;
  census.internal[0] = 4;
  census.internal[1] = 128;
  census.end("content", 0);
  assert.deepEqual(census.drain(), [{ phase: "content", factory: 0,
    imports: [
      { name: "physical.one", target: "logical.one", shape: "j_", calls: 3 },
      { name: "physical.two", target: "logical.two", shape: "s_", calls: 1 },
    ],
    internal: { allocateCalls: 4, allocatedBytes: 128, resourceCalls: 0, resolveCalls: 0,
      readStringCalls: 0, readStringBytes: 0, writeStringCalls: 0, writeStringBytes: 0 },
  }]);
  census.begin("session", 0);
  census.counts[second] = 2;
  census.end("session", 0);
  assert.equal(census.drain()[0].imports[0].calls, 2);
});

test("source instrumenter is fail-closed and inserts counter sites", () => {
  const fixture = `
  const allocate = bytes => {
    live();
    const size = align(bytes), p = exports.fir_heap_alloc(size) >>> 0;
  };
  const resource = value => {
    // Persistent *opaque wrappers*
  };
  const resolve = word => {
    const { p, kind, aux0 } = header(word);
  };
  const readString = word => {
    const { p, kind, aux0, aux1: length, extent } = header(word);
    check(kind === 4);
  };
  const string = value => {
    const bytes = encoder.encode(value), size = align(HEADER + bytes.length), p = allocate(size);
  };
  const importObject = {};
  for (const [name, [target, shape]] of Object.entries(inventory)) {
    importObject[name] = (...args) => guarded(() => {
  }`;
  const instrumented = instrumentHostPrototypeSource(fixture);
  for (const marker of ["__vbpFirHostImportCensus", "counts[vbpCensusIndex]++",
    "internal[0]++", "internal[2]++", "internal[3]++", "internal[4]++", "internal[6]++"])
    assert.ok(instrumented.includes(marker), marker);
  assert.throws(() => instrumentHostPrototypeSource(fixture.replace("  const importObject = {};", "")),
    /source drift/);
});
