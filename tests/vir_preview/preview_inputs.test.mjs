import test from "node:test";
import assert from "node:assert/strict";
import { readyDocumentJson } from "./preview_inputs.mjs";

test("unwraps without reserializing numbers, strings or field order", () => {
  const document = '{"version":9007199254740993,"text":"λ\\\"}}","document":{}}';
  assert.equal(readyDocumentJson('{"ready":{"document":' + document + '}}'), document);
});
test("rejects unavailable, malformed, bare Document and ambiguous envelopes", () => {
  for (const input of [null, '{"loading":{"message":"wait"}}', '{"ready":',
    '{"document":{}}', '{"ready":{"document":null}}', '{"ready":{"document":[]}}',
    '{"ready":{"document":{},"extra":{}}}', '{"ready":{"document":{}},"extra":{}}',
    '{"ready":{"document":{},"document":{}}}']) {
    assert.throws(() => readyDocumentJson(input));
  }
});
