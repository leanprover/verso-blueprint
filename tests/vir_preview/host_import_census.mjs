// Diagnostic-only counters for FIR's existing generic host dispatcher.
// The hot path performs integer increments only: timing remains the CDP
// sampler's responsibility.
const check = (condition, message) => { if (!condition) throw new Error(message); };
const equal = (actual, expected, message) => check(Object.is(actual, expected),
  message ?? `expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);

const internalNames = [
  "allocateCalls", "allocatedBytes", "resourceCalls", "resolveCalls",
  "readStringCalls", "readStringBytes", "writeStringCalls", "writeStringBytes",
];

export function createHostImportCensus(capacity = 128) {
  check(Number.isInteger(capacity) && capacity > 0, "invalid census capacity");
  const entries = [];
  const counts = new Float64Array(capacity);
  const internal = new Float64Array(internalNames.length);
  const reports = [];
  const census = {
    active: false,
    counts,
    internal,
    register(name, target, shape) {
      equal(census.active, false, "cannot register during a measured phase");
      check(entries.length < capacity, "host-import census capacity exceeded");
      check(!entries.some(entry => entry.name === name), `duplicate host import ${name}`);
      entries.push({ name, target, shape });
      return entries.length - 1;
    },
    begin(phase, factory) {
      equal(census.active, false, "nested host-import census phase");
      counts.fill(0);
      internal.fill(0);
      census.active = true;
      census.phase = phase;
      census.factory = factory;
    },
    end(phase, factory) {
      equal(census.active, true, "host-import census phase is not active");
      equal(census.phase, phase);
      equal(census.factory, factory);
      census.active = false;
      reports.push({ phase, factory,
        imports: entries.map((entry, index) => ({ ...entry, calls: counts[index] }))
          .filter(entry => entry.calls > 0),
        internal: Object.fromEntries(internalNames.map((name, index) => [name, internal[index]])),
      });
    },
    clear() {
      equal(census.active, false, "cannot clear an active host-import census");
      reports.length = 0;
    },
    drain() {
      equal(census.active, false, "cannot drain an active host-import census");
      return reports.splice(0, reports.length);
    },
  };
  return census;
}

function replaceOnce(source, before, after) {
  equal(source.split(before).length, 2, `FIR host census source drift: ${before}`);
  return source.replace(before, after);
}

export function instrumentHostPrototypeSource(original) {
  let source = original;
  source = replaceOnce(source,
    "  const importObject = {};",
    "  const vbpHostImportCensus = globalThis.__vbpFirHostImportCensus;\n  const importObject = {};");
  source = replaceOnce(source,
    "  for (const [name, [target, shape]] of Object.entries(inventory)) {\n    importObject[name] = (...args) => guarded(() => {",
    "  for (const [name, [target, shape]] of Object.entries(inventory)) {\n" +
    "    const vbpCensusIndex = vbpHostImportCensus?.register(name, target, shape);\n" +
    "    importObject[name] = (...args) => guarded(() => {\n" +
    "      if (vbpHostImportCensus?.active) vbpHostImportCensus.counts[vbpCensusIndex]++;");
  source = replaceOnce(source,
    "    const size = align(bytes), p = exports.fir_heap_alloc(size) >>> 0;",
    "    const size = align(bytes);\n" +
    "    if (vbpHostImportCensus?.active) { vbpHostImportCensus.internal[0]++; vbpHostImportCensus.internal[1] += size; }\n" +
    "    const p = exports.fir_heap_alloc(size) >>> 0;");
  source = replaceOnce(source,
    "  const resource = value => {\n    // Persistent *opaque wrappers*",
    "  const resource = value => {\n" +
    "    if (vbpHostImportCensus?.active) vbpHostImportCensus.internal[2]++;\n" +
    "    // Persistent *opaque wrappers*");
  source = replaceOnce(source,
    "  const resolve = word => {\n    const { p, kind, aux0 } = header(word);",
    "  const resolve = word => {\n" +
    "    if (vbpHostImportCensus?.active) vbpHostImportCensus.internal[3]++;\n" +
    "    const { p, kind, aux0 } = header(word);");
  source = replaceOnce(source,
    "    const { p, kind, aux0, aux1: length, extent } = header(word);\n    check(kind === 4",
    "    const { p, kind, aux0, aux1: length, extent } = header(word);\n" +
    "    if (vbpHostImportCensus?.active) { vbpHostImportCensus.internal[4]++; vbpHostImportCensus.internal[5] += length; }\n" +
    "    check(kind === 4");
  source = replaceOnce(source,
    "    const bytes = encoder.encode(value), size = align(HEADER + bytes.length), p = allocate(size);",
    "    const bytes = encoder.encode(value), size = align(HEADER + bytes.length);\n" +
    "    if (vbpHostImportCensus?.active) { vbpHostImportCensus.internal[6]++; vbpHostImportCensus.internal[7] += bytes.length; }\n" +
    "    const p = allocate(size);");
  return source;
}
