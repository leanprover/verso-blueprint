import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { createHash } from "node:crypto";

const directory = resolve(process.argv[2]);
const policy = process.argv[3] ?? "position";
assert.ok(["position", "structural"].includes(policy), "expected position or structural experiment");
const read = async path => JSON.parse(await readFile(resolve(directory, path), "utf8"));
const median = values => {
  const xs = [...values].sort((a, b) => a - b);
  return (xs[Math.floor((xs.length - 1) / 2)] + xs[Math.floor(xs.length / 2)]) / 2;
};
const summarize = rows => Object.fromEntries(["whole", "browserParsed"].map(mode => [mode,
  Object.fromEntries(["decodeMs", "renderToDomMs", "totalMs"].map(metric => [metric,
    { median: median(rows.map(row => row[mode][metric])),
      min: Math.min(...rows.map(row => row[mode][metric])),
      max: Math.max(...rows.map(row => row[mode][metric])) }]))]));
// Identity diagnostics necessarily change. Preserve all other DOM attributes,
// styles, text and structure in the equivalence check.
const identityAttributes = ["data-verso-render-id", "data-verso-identity-origin", "title"];
function presentation(node) {
  if (typeof node === "string") return node;
  const isBlock = node.attributes.some(([name]) => name === "data-verso-identity-origin");
  return { ...node, attributes: node.attributes.filter(([name]) => !isBlock || !identityAttributes.includes(name)),
    children: node.children.map(presentation) };
}
const names = ["before-a", "after-a", "after-b", "before-b"];
const runs = [], rows = { before: [], after: [] };
let firstIdentity, firstPresentation, firstText;
for (const name of names) {
  const report = await read(`${name}/result.json`), identity = await read(`${name}/identity.json`);
  firstIdentity ??= identity;
  assert.deepEqual(identity.sourceHashes, firstIdentity.sourceHashes);
  assert.equal(identity.virCommit, firstIdentity.virCommit);
  assert.equal(identity.cpuSamplingIntervalUs, null);
  assert.equal(identity.identityPhaseInstrumentation, false);
  const data = report.acceptance;
  assert.equal(data.rows.length, 16);
  assert.equal(data.retainedCheckbox, true);
  assert.equal(data.retainedParagraph, true);
  assert.deepEqual(data.warnings, []);
  const dom = JSON.stringify(presentation(data.renderedDom));
  firstPresentation ??= dom;
  firstText ??= data.renderedTextSha256;
  assert.equal(dom, firstPresentation, `${name}: presentation changed`);
  assert.equal(data.renderedTextSha256, firstText);
  rows[name.startsWith("before") ? "before" : "after"].push(...data.rows);
  runs.push({ name, ...summarize(data.rows) });
}
const before = summarize(rows.before), after = summarize(rows.after);
const changePercent = Object.fromEntries(Object.keys(before).map(mode => [mode,
  Object.fromEntries(Object.keys(before[mode]).map(metric => [metric,
    100 * (after[mode][metric].median / before[mode][metric].median - 1)]))]));
const baseline = await read("baseline/DecodeProbe.irpkg-set.json");
const candidate = await read("candidate/DecodeProbe.irpkg-set.json");
assert.deepEqual(baseline.packages.map(p => p.module), candidate.packages.map(p => p.module));
const summary = { order: names, observationsPerModePerPolicy: 32,
  runs, before, after, changePercent, presentationEqual: true, ignoredIdentityAttributes: identityAttributes,
  presentationSha256: createHash("sha256").update(firstPresentation).digest("hex"),
  packageBytes: { before: baseline.packages.reduce((n, p) => n + p.byteLength, 0),
    after: candidate.packages.reduce((n, p) => n + p.byteLength, 0) },
  changedPackageMembers: baseline.packages.filter((p, i) => p.sha256 !== candidate.packages[i].sha256).map(p => p.module),
  behavior: { before: (await read("behavior-before/result.json")).acceptance,
    after: (await read("behavior-after/result.json")).acceptance },
  policy,
  decision: policy === "position"
    ? "Reject positional fallback for adoption: measured control only; state transfers across unlabeled insert/delete."
    : "Retain session-owned structural fingerprints: exact equality resolves collisions; browser retention and presentation gates pass." };
await writeFile(resolve(directory, "summary.json"), JSON.stringify(summary, null, 2) + "\n");
console.log(JSON.stringify({ before, after, changePercent, presentationEqual: true }, null, 2));
