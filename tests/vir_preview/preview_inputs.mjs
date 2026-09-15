// Strip only Preview.ready's existing JSON envelope. Document bytes stay intact;
// decoding and interpretation belong to the existing Lean Document.decode.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { writeFile } from "node:fs/promises";
import { resolve } from "node:path";

export function readyDocumentJson(source) {
  assert.equal(typeof source, "string", "expected encoded Preview String");
  const prefix = '{"ready":{"document":';
  const suffix = '}}';
  assert.ok(source.startsWith(prefix) && source.endsWith(suffix), "expected compact Preview.ready envelope");
  const document = source.slice(prefix.length, -suffix.length);
  const value = JSON.parse(document);
  assert.ok(value && !Array.isArray(value) && typeof value === "object", "expected Document object");
  return document;
}

export async function writePreviewInputs(output, before, after) {
  const entries = [];
  for (const [name, preview] of [["before", before], ["after", after]]) {
    const document = readyDocumentJson(preview);
    const file = `${name}.document.json`;
    await writeFile(resolve(output, file), document, { flag: "wx" });
    entries.push({ name, file, bytes: Buffer.byteLength(document),
      sha256: createHash("sha256").update(document).digest("hex"),
      previewSha256: createHash("sha256").update(preview).digest("hex") });
  }
  assert.notEqual(entries[0].sha256, entries[1].sha256, "before/after inputs must differ");
  const manifest = { format: "existing Document.encode JSON; unchanged inner bytes from Preview.ready",
    sourceIdentity: "identity.json", endpoint: "initial accepted document and last accepted edit",
    scope: "input capture only, not benchmark results; Lean decoder acceptance still required", entries };
  await writeFile(resolve(output, "inputs.json"), JSON.stringify(manifest, null, 2), { flag: "wx" });
  return manifest;
}
