// Summarize retained diagnostic runs; never runs a benchmark or drops a row.
import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { createHash } from "node:crypto";

const [outputArg, ...captures] = process.argv.slice(2);
assert.ok(outputArg && captures.length, "usage: summarize_identity_phases.mjs OUTPUT_JSON CAPTURE_DIR...");
const sha = bytes => createHash("sha256").update(bytes).digest("hex");
const median = xs => {
  const sorted = xs.toSorted((a, b) => a - b);
  return (sorted[(sorted.length - 1) >> 1] + sorted[sorted.length >> 1]) / 2;
};
const sum = xs => xs.reduce((a, b) => a + b, 0);
const rows = [], sources = [];
for (const path of captures) {
  const bytes = await readFile(resolve(path, "result.json"));
  const identity = JSON.parse(await readFile(resolve(path, "identity.json")));
  assert.equal(identity.identityPhaseInstrumentation, true);
  assert.equal(identity.cpuSamplingIntervalUs, null);
  const { acceptance } = JSON.parse(bytes);
  assert.deepEqual(acceptance.warnings, []);
  assert.equal(acceptance.renderedDomSha256, "4d079cdcb7aace634a0fe78a1c130563a0f71acbf79ca84b7b9afefdac9c298d");
  sources.push({ path: resolve(path), resultSha256: sha(bytes), identity });
  for (const row of acceptance.rows) for (const mode of ["whole", "browserParsed"]) {
    const sample = row[mode], events = sample.identityEvents;
    const render = events.filter(e => e.kind === "render");
    const calibration = events.filter(e => e.kind === "calibration");
    const groups = events.filter(e => ["blocks", "parts"].includes(e.kind));
    const splitJson = groups[0]?.splitJson === true;
    assert.ok(groups.every(e => (e.splitJson === true) === splitJson), "mixed phase schemas");
    assert.equal(render.length, 1); assert.equal(calibration.length, 1);
    let previousEnd = render[0].start;
    for (const e of groups) {
      assert.ok(previousEnd <= e.start && e.start <= e.extensionEnd && e.extensionEnd <= e.hintsStart &&
        e.hintsStart <= e.hintsEnd && e.hintsEnd <= e.allocationStart && e.allocationStart <= e.allocationEnd &&
        e.allocationEnd <= render[0].end);
      previousEnd = e.allocationEnd;
      if (splitJson) assert.ok(e.hintsStart <= e.treeEnd && e.treeEnd <= e.serializationStart &&
        e.serializationStart <= e.hintsEnd);
    }
    const extensionMs = sum(groups.map(e => e.extensionEnd - e.start));
    const jsonTreeMs = splitJson ? sum(groups.map(e => e.treeEnd - e.hintsStart)) : undefined;
    const serializationMs = splitJson ? sum(groups.map(e => e.hintsEnd - e.serializationStart)) : undefined;
    const fingerprintMs = splitJson ? jsonTreeMs + serializationMs : sum(groups.map(e => e.hintsEnd - e.hintsStart));
    const keyAllocationMs = sum(groups.map(e => e.allocationEnd - e.allocationStart));
    const rendererMs = render[0].end - render[0].start;
    rows.push({ capture: resolve(path), pair: row.pair, order: row.order, mode,
      decodeMs: sample.decodeMs, renderToDomMs: sample.renderToDomMs, totalMs: sample.totalMs,
      extensionMs, fingerprintMs, keyAllocationMs,
      ...(splitJson ? { jsonTreeMs, serializationMs } : {}),
      otherRendererMs: rendererMs - extensionMs - fingerprintMs - keyAllocationMs,
      outsideRendererMs: sample.renderToDomMs - rendererMs,
      calibrationMs: calibration[0].allocationEnd - calibration[0].start,
      identityPercent: 100 * (extensionMs + fingerprintMs + keyAllocationMs) / sample.renderToDomMs,
      groups: groups.length, blocks: sum(groups.filter(e => e.kind === "blocks").map(e => e.count)),
      parts: sum(groups.filter(e => e.kind === "parts").map(e => e.count)) });
  }
}
for (const field of ["descriptorSha256", "sdkSha256", "wasmSha256", "responseSha256"])
  assert.equal(new Set(sources.map(s => s.identity[field])).size, 1, `incomparable ${field}`);
for (const source of sources.slice(1))
  assert.deepEqual(source.identity.sourceHashes, sources[0].identity.sourceHashes, "incomparable probe sources");
const metrics = Object.keys(rows[0]).filter(k => typeof rows[0][k] === "number" && k !== "pair");
const summarize = selected => Object.fromEntries(metrics.map(k => {
  const xs = selected.map(r => r[k]);
  return [k, { median: median(xs), mean: sum(xs) / xs.length, min: Math.min(...xs), max: Math.max(...xs) }];
}));
const report = { diagnosticOnly: true, sources, rows,
  summary: Object.fromEntries(["whole", "browserParsed"].map(mode => [mode,
    { observations: rows.filter(r => r.mode === mode).length, metrics: summarize(rows.filter(r => r.mode === mode)) }])) };
await writeFile(resolve(outputArg), JSON.stringify(report, null, 2));
console.log(JSON.stringify(report.summary, null, 2));
