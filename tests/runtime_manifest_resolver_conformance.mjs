import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";

import { createBlueprintDataApi, decodeBlueprintManifestFile } from "../src/VersoBlueprint/Commands/preview-runtime-data.mjs";

const fixtureUrl = new URL("./fixtures/runtime-manifest-resolver.json", import.meta.url);
const fixture = JSON.parse(await readFile(fixtureUrl, "utf8"));
const [nativeBinary, campaignFlag, ...extra] = process.argv.slice(2);
assert.ok(nativeBinary, "the campaign requires the native oracle path");
assert.equal(extra.length, 0, "unexpected arguments");
assert.ok(campaignFlag === undefined || campaignFlag === "--emit-campaign", "unexpected campaign flag");

function nativeLookup(manifest, request) {
  const run = spawnSync(nativeBinary, [], {
    input: JSON.stringify({ abiVersion: fixture.abiVersion, manifest, requests: [request] }) + "\n",
    encoding: "utf8", maxBuffer: 8 * 1024 * 1024, timeout: 30000,
  });
  assert.ifError(run.error);
  assert.equal(run.status, 0, run.stderr);
  const output = JSON.parse(run.stdout);
  assert.equal(output.ok, true, output.error);
  return output.results[0];
}

const createData = manifest => createBlueprintDataApi({
  fetchJson(url) {
    if (!url.endsWith("blueprint-manifest.json")) {
      throw new Error(`unexpected fixture URL: ${url}`);
    }
    return Promise.resolve(manifest);
  }
});

function unavailableSourceLocation(message) {
  return { ok: false, location: null, error: message };
}

async function resolveRequest(data, request, manifest = fixture.manifest) {
  const value = typeof request.value === "string" ? request.value.trim() : "";
  switch (request.kind) {
    case "preview": {
      const manifestEntry = value ? await data.loadManifestEntry(value) : null;
      return {
        ok: !!manifestEntry,
        key: value,
        reason: value ? (manifestEntry ? "" : "manifest-entry-missing") : "missing-key",
        manifestEntry,
        href: manifestEntry?.href || "",
        sourceLocation:
          manifestEntry?.sourceLocation || unavailableSourceLocation("preview key missing")
      };
    }
    case "label":
    case "declaration":
      // These policies now have one Lean authority. Static fixture expectations
      // guard semantics; Chromium compares the actual browser API to this oracle.
      return nativeLookup(manifest, request);
    case "group": {
      const group = value ? await data.loadGroup(value) : null;
      return {
        ok: !!group,
        key: value,
        reason: value ? (group ? "" : "group-entry-missing") : "missing-group",
        label: value,
        value: group,
        href: ""
      };
    }
    case "sourceDocument": {
      const document = value ? await data.loadSourceDocument(value) : null;
      return {
        ok: !!document,
        key: value,
        reason: value
          ? (document ? "" : "source-document-missing")
          : "missing-source-document",
        value: document,
        href: ""
      };
    }
    case "sourceMetadata":
      return nativeLookup(manifest, request);
    default:
      throw new Error(`unsupported fixture request kind: ${request.kind}`);
  }
}

function valueIdentity(kind, result) {
  switch (kind) {
    case "preview":
    case "label":
    case "declaration":
    case "sourceMetadata":
      return result.manifestEntry?.key || "";
    case "group":
      return result.value?.label || "";
    case "sourceDocument":
      return result.value?.id || "";
    default:
      return "";
  }
}

function snapshot(request, result) {
  const hasSourceLocation = request.kind !== "group" && request.kind !== "sourceDocument";
  const sourceLocation = result.sourceLocation || result.manifestEntry?.sourceLocation || null;
  return {
    id: request.id,
    kind: request.kind,
    ok: !!result.ok,
    key: result.key || "",
    reason: result.reason || "",
    label: Object.hasOwn(result, "label") ? result.label : null,
    facet: Object.hasOwn(result, "facet") ? result.facet : null,
    declaration: Object.hasOwn(result, "declaration") ? result.declaration : null,
    valueIdentity: valueIdentity(request.kind, result),
    href: result.href || "",
    sourceLocationOk: hasSourceLocation ? !!sourceLocation?.ok : null,
    sourceDocumentIds: Array.isArray(result.sources)
      ? result.sources.map(source => source.documentId)
      : []
  };
}

const actual = [];
const actualDomain = [];
const data = createData(fixture.manifest);
const nativeCases = [];
for (const request of fixture.requests) {
  const result = await resolveRequest(data, request);
  actualDomain.push(result);
  actual.push(snapshot(request, result));
}

assert.deepEqual(actual, fixture.expected);
nativeCases.push({ id: "baseline", manifest: fixture.manifest, requests: fixture.requests,
  expected: actual, domain: actualDomain });

for (const testCase of fixture.invalidCases) {
  const invalidData = createBlueprintDataApi({
    fetchJson() {
      return Promise.resolve(testCase.manifest);
    }
  });
  const manifest = await invalidData.loadManifest();
  const status = invalidData.readManifestStatus();
  assert.equal(manifest.size, 0, testCase.id);
  assert.equal(status.state, "error", testCase.id);
  assert.match(status.lastError, new RegExp(testCase.errorIncludes), testCase.id);
  nativeCases.push(testCase);
}

for (const testCase of fixture.parityCases) {
  if (testCase.errorIncludes) {
    assert.throws(() => decodeBlueprintManifestFile(testCase.manifest),
      error => error.message.includes(testCase.errorIncludes), testCase.id);
    nativeCases.push(testCase);
    continue;
  }
  decodeBlueprintManifestFile(testCase.manifest);
  const caseData = createData(testCase.manifest);
  const expected = [];
  const domain = [];
  for (const request of testCase.requests) {
    const result = await resolveRequest(caseData, request, testCase.manifest);
    domain.push(result);
    expected.push(snapshot(request, result));
  }
  assert.equal(expected.length, testCase.expected.length, testCase.id);
  for (let i = 0; i < expected.length; i++) {
    for (const [key, value] of Object.entries(testCase.expected[i])) {
      assert.deepEqual(expected[i][key], value, `${testCase.id}: ${key}`);
    }
  }
  nativeCases.push({ ...testCase, expected, domain });
}

// Source lookup also accepts entries and render results, not just preview keys.
// Use detached entries to prove that direct input wins over a manifest lookup.
const sourceRef = { document: " paper ", spans: [{ page: "42" }], extra: { keep: true } };
const detachedEntry = { key: " detached--statement ", facet: "statement", sources: [sourceRef] };
const sourceCases = [
  ["direct-entry", detachedEntry, { ok: true, key: "detached--statement", sourceDocumentIds: ["paper"] }],
  ["nested-entry", { key: "unsourced--statement", manifestEntry: detachedEntry },
    { ok: true, key: "detached--statement" }],
  ["same-key-nested-entry", { key: "same", facet: "statement", sources: [],
    manifestEntry: { key: "same", facet: "proof", sources: [sourceRef] } },
    { ok: true, key: "same", sourceDocumentIds: ["paper"] }],
  ["outer-entry-fallback", { ...detachedEntry, manifestEntry: { key: "ignored" } },
    { ok: true, key: "detached--statement" }],
  ["render-result", { ok: false, key: " alpha--statement " }, { ok: true, key: "alpha--statement" }],
  ["invalid-nested-entry", { key: "alpha--statement", manifestEntry: [] }, { ok: true }],
  ["key-only", { key: "alpha--statement" }, { ok: true }],
  ["key-only-missing", { key: "unknown" }, { ok: false, reason: "manifest-entry-missing" }],
  ["string", " alpha--statement ", { ok: true, key: "alpha--statement" }],
  ...[null, false, 17, [], {}, "", { key: "\u00a0" }].map((source, i) =>
    [`missing-key-${i}`, source, { ok: false, key: "", reason: "missing-key" }]),
  ...["authoredLabel", "targetKind", "facet"].map(field =>
    [`entry-marker-${field}`, { key: "detached", [field]: "" },
      { ok: false, key: "detached", reason: "source-missing" }]),
  ...["sources", "externalMarkup", "leanCodePreviewKeys"].map(field =>
    [`entry-marker-${field}`, { key: "detached", [field]: [] },
      { ok: false, key: "detached", reason: "source-missing" }]),
  ["wrong-marker-types", { key: "alpha--statement", authoredLabel: 1, targetKind: false,
    facet: [], sources: {}, externalMarkup: {}, leanCodePreviewKeys: "wrong" }, { ok: true }],
  ["non-array-sources", { key: "detached", facet: "statement", sources: {} },
    { ok: false, reason: "source-missing" }],
  ["mixed-source-refs", { key: "detached", sources: [sourceRef,
    { document: "unknown", spans: null }, { document: 17, spans: ["opaque"] },
    null, [], "invalid", { document: "paper", spans: [] }] },
    { ok: true, sourceDocumentIds: ["paper", "unknown", "", "", "", "", "paper"] }],
];
for (const [id, source, fields] of sourceCases) {
  const caseData = createData(fixture.manifest);
  const request = { id, kind: "sourceMetadata", value: source };
  const before = JSON.stringify(source);
  const result = await resolveRequest(caseData, request);
  const expected = snapshot(request, result);
  for (const [field, value] of Object.entries(fields)) {
    assert.deepEqual(expected[field], value, `${id}: ${field}`);
  }
  assert.equal(JSON.stringify(source), before, `${id}: input mutation`);
  // Native values must retain their complete content. Browser gates check identity.
  if (source?.manifestEntry === detachedEntry || source === detachedEntry || id === "outer-entry-fallback") {
    const direct = source?.manifestEntry === detachedEntry ? detachedEntry : source;
    assert.deepEqual(result.manifestEntry, direct, `${id}: entry content`);
    assert.deepEqual(result.sources[0].sourceRef, direct.sources[0], `${id}: source-ref content`);
    assert.deepEqual(result.sources[0].spans, direct.sources[0].spans, `${id}: spans content`);
    assert.deepEqual(result.sources[0].document, await caseData.loadSourceDocument("paper"),
      `${id}: document content`);
  }
  nativeCases.push({ id, manifest: fixture.manifest, requests: [request], expected: [expected], domain: [result] });
}

// An indexed entry's arbitrary nested metadata must not be selected again as input.
const nestedMetadataManifest = structuredClone(fixture.manifest);
nestedMetadataManifest.previews[0].manifestEntry = { key: "nested", sources: [] };
const nestedRequest = { id: "indexed-nested-metadata", kind: "sourceMetadata", value: "alpha--statement" };
const nestedResult = nativeLookup(nestedMetadataManifest, nestedRequest);
assert.equal(nestedResult.ok, true);
assert.equal(nestedResult.inputEntryIsNested, null);
assert.deepEqual(nestedResult.manifestEntry, nestedMetadataManifest.previews[0]);
nativeCases.push({ id: nestedRequest.id, manifest: nestedMetadataManifest, requests: [nestedRequest],
  expected: [snapshot(nestedRequest, nestedResult)], domain: [nestedResult] });

// Cover the complete ECMAScript trim set, plus characters trim must preserve.
const whitespace = [9, 10, 11, 12, 13, 32, 160, 5760,
  ...Array.from({ length: 11 }, (_, i) => 8192 + i), 8232, 8233, 8239, 8287, 12288, 65279];
for (const code of [...whitespace, 0, 133, 6158, 8203, 128512]) {
  const edge = String.fromCodePoint(code);
  const requests = [{ id: "label", kind: "label", value: edge + "alpha" + edge }];
  const expected = [snapshot(requests[0], await resolveRequest(data, requests[0]))];
  assert.equal(expected[0].ok, whitespace.includes(code), `trim U+${code.toString(16)}`);
  nativeCases.push({ id: `trim-${code}`, manifest: fixture.manifest, requests, expected });
}

let campaign;
if (nativeBinary) {
  const inputs = nativeCases.map(testCase => JSON.stringify({
    abiVersion: fixture.abiVersion, manifest: testCase.manifest, requests: testCase.requests || []
  }));
  inputs.push("not json", JSON.stringify({ abiVersion: fixture.abiVersion + 1,
    manifest: fixture.manifest, requests: [] }));
  const input = inputs.join("\n") + "\n";
  const run = spawnSync(nativeBinary, [], {
    input, encoding: "utf8", maxBuffer: 8 * 1024 * 1024, timeout: 30000
  });
  assert.ifError(run.error);
  assert.equal(run.status, 0, run.stderr);
  const outputs = run.stdout.trim().split("\n").map(line => JSON.parse(line));
  assert.equal(outputs.length, inputs.length);
  for (let i = 0; i < nativeCases.length; i++) {
    const testCase = nativeCases[i], output = outputs[i];
    assert.equal(output.abiVersion, fixture.abiVersion, testCase.id);
    if (testCase.errorIncludes) {
      assert.equal(output.ok, false, testCase.id);
      assert.ok(output.error.includes(testCase.errorIncludes), `${testCase.id}: ${output.error}`);
      assert.deepEqual(output.results, [], testCase.id);
    } else {
      assert.equal(output.ok, true, `${testCase.id}: ${output.error}`);
      assert.equal(output.error, "", testCase.id);
      assert.deepEqual(output.results.map((result, j) => snapshot(testCase.requests[j], result)),
        testCase.expected, testCase.id);
      for (let j = 0; j < (testCase.domain || []).length; j++) {
        for (const field of ["manifestEntry", "value", "sources"]) {
          if (Object.hasOwn(testCase.domain[j], field)) {
            assert.deepEqual(output.results[j][field], testCase.domain[j][field],
              `${testCase.id}: raw ${field}`);
          }
        }
      }
    }
  }
  for (const output of outputs.slice(nativeCases.length)) {
    assert.equal(output.ok, false);
    assert.ok(output.error.length > 0);
    assert.deepEqual(output.results, []);
  }
  assert.equal(outputs.at(-1).error, `unsupported manifest resolver ABI version ${fixture.abiVersion + 1}`);
  campaign = inputs.map((input, i) => ({
    id: nativeCases[i]?.id || `invalid-envelope-${i - nativeCases.length}`,
    input, expected: outputs[i]
  }));
}
console.log(campaignFlag ? JSON.stringify(campaign) :
  `manifest resolver reference campaign verified (${nativeCases.length} cases)`);
