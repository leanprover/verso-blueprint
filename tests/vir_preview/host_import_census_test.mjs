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
    return decoder.decode(new Uint8Array(memory.buffer, p + HEADER, length));
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

test("optional string census reports reuse without re-encoding", () => {
  const census = createHostImportCensus(1, true);
  census.register("physical.string", "js.string", "s_");
  census.begin("content", 0);
  census.recordString("same", 4);
  census.recordString("same", 4);
  census.recordString("λ", 2);
  census.end("content", 0);
  const strings = census.drain()[0].strings;
  assert.deepEqual({ calls: strings.calls, unique: strings.unique,
    repeatedCalls: strings.repeatedCalls, totalBytes: strings.totalBytes,
    uniqueBytes: strings.uniqueBytes, repeatedBytes: strings.repeatedBytes },
  { calls: 3, unique: 2, repeatedCalls: 1, totalBytes: 10, uniqueBytes: 6, repeatedBytes: 4 });
  assert.deepEqual(strings.topByCalls[0],
    { value: "same", calls: 2, bytes: 4, repeatedCalls: 1, repeatedBytes: 4 });
});
