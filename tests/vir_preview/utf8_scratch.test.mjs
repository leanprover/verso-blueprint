import assert from "node:assert/strict";
import test from "node:test";
import { withUtf8Scratch } from "./utf8_scratch.mjs";

test("UTF-8 scratch survives buffer replacement and restores its scoped override", () => {
  const memory = new WebAssembly.Memory({ initial: 2 });
  const original = () => { throw Error("original converter"); };
  const freed = [], strings = [];
  let allocations = 0;
  const runtime = { makeObjectString: original, exports: { memory,
    vir_obj_string(ptr, size) {
      strings.push(new TextDecoder().decode(new Uint8Array(memory.buffer, ptr, size)));
      memory.grow(0); // A native call may replace the buffer without increasing size.
      return 1;
    } },
    allocByteLength() { allocations++; memory.grow(1); return 32; },
    freeBytes(ptr) { freed.push(ptr); },
  };
  withUtf8Scratch(runtime, () => {
    for (const value of ["", "α😀\0", "z".repeat(5000), "again"])
      runtime.makeObjectString(value, "test");
    assert.throws(() => withUtf8Scratch(runtime, () => {}), /nested/);
  });
  assert.deepEqual(strings, ["", "α😀\0", "z".repeat(5000), "again"]);
  assert.equal(allocations, 2);
  assert.equal(freed.length, 2);
  assert.equal(runtime.makeObjectString, original);
  assert.throws(() => withUtf8Scratch(runtime, () => { throw Error("failure"); }), /failure/);
  assert.equal(runtime.makeObjectString, original);
});
