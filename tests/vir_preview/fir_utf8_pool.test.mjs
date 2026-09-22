import assert from "node:assert/strict";
import test from "node:test";
import { installFirUtf8Pool } from "./fir_utf8_pool.mjs";

const fixture = `  const encoder = new TextEncoder();
  const string = value => {
    check(typeof value === "string", "expected JS string");
    const bytes = encoder.encode(value), size = align(HEADER + bytes.length), p = allocate(size);
    writeHeader(p, 4, size, 1, bytes.length);
    new Uint8Array(memory.buffer, p + HEADER, bytes.length).set(bytes);
    return p;
  };`;

test("installs a reentrancy-safe UTF-8 buffer pool", () => {
  const result = installFirUtf8Pool(fixture);
  assert.match(result, /const scratchIndex = stringScratchDepth\+\+/);
  assert.match(result, /scratch = stringScratch\[scratchIndex\] = new Uint8Array\(capacity\)/);
  assert.match(result, /encoder\.encodeInto\(value, scratch\)/);
  assert.match(result, /p = allocate\(size\)/);
  assert.match(result, /new Uint8Array\(memory\.buffer, p \+ HEADER, length\)\.set/);
  assert.match(result, /finally \{\s*stringScratchDepth--/);
  assert.doesNotMatch(result, /encoder\.encode\(value\)/);
});

test("fails closed when either producer boundary drifts", () => {
  assert.throws(() => installFirUtf8Pool(fixture.replace("new TextEncoder", "new OtherEncoder")), /encoder boundary/);
  assert.throws(() => installFirUtf8Pool(fixture.replace("const string = value", "const string = input")), /String boundary/);
});
