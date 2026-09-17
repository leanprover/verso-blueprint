import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { createDirectPreviewDecoder } from "./direct_typed_decoder.mjs";
import { withPointerScratch } from "./pointer_scratch.mjs";

// Ownership controls only; real type/value equivalence is checked in Chromium.
// Run the DirectCodecProbe build first to generate authoritative layouts.
const layouts = JSON.parse(readFileSync(new URL("../../.deps/direct-codec/layouts.json", import.meta.url)));
const bindings = { "jsonValue.check": () => ({ kind: "ok" }) };
const fixture = () => ({ ready: { document: { version: 1, correlationId: "", cursorToken: "", focus: null,
  serverTiming: null, document: { title: [{ text: "title" }], titleString: "title", metadata: null,
    content: [{ other: { container: { name: "Prototype.block", id: 7, data: { z: false, a: [1, "x", null] }, properties: {} },
      content: [{ para: [{ other: { container: { name: "Prototype.block", id: null, data: {} }, content: [] } }] }] } }],
    subParts: [] } } } });

function fakeRuntime() {
  let serial = 0;
  const heap = new Map();
  const allocate = (value, children = []) => {
    children.forEach(ptr => assert.ok(heap.has(ptr), "dangling child"));
    const ptr = ++serial;
    heap.set(ptr, { refs: 1, value, children: [...children] });
    return ptr;
  };
  const inc = ptr => { const obj = heap.get(ptr); assert.ok(obj, "retain freed pointer"); obj.refs++; };
  const dec = ptr => {
    const obj = heap.get(ptr); assert.ok(obj, "double release");
    if (--obj.refs === 0) { heap.delete(ptr); obj.children.forEach(dec); }
  };
  const runtime = {
    heap, exports: { vir_obj_inc: inc, vir_obj_dec: dec },
    makeObjectString: value => allocate(value),
    makeObjectScalar: value => allocate(value),
    makeObjectDecimal: (_ctor, value) => allocate(value),
    releaseOwnedObjects: objects => { objects.forEach(ptr => { if (ptr) dec(ptr); }); objects.length = 0; },
    makeObjectArrayFromOwnedElements(objects) {
      const ptr = allocate("array", objects); objects.length = 0; return ptr;
    },
    makeObjectCtorFromOwnedFields(tag, fields, name) {
      return runtime.makeObjectCtorFromOwnedLayout(tag,
        { objectFields: fields, scalarBytes: [] }, name);
    },
    makeObjectCtorFromOwnedLayout(tag, layout, name) {
      if (runtime.failAt === name) throw runtime.sentinel;
      const ptr = allocate({ tag, name, scalar: [...layout.scalarBytes] }, layout.objectFields);
      layout.objectFields.length = 0; return ptr;
    },
    makeLeanObjectHandleResource(ptr) { inc(ptr); return { ptr, live: true }; },
    leanObjectHandleCell(handle) { assert.ok(handle.live); return handle; },
    retainLeanObjectHandleValue(handle) { assert.ok(handle.live); inc(handle.ptr); return handle.ptr; },
    releaseLeanObjectHandleCell(handle) { assert.ok(handle.live); handle.live = false; dec(handle.ptr); },
    call(name, value) {
      if (name.endsWith(".finish")) {
        const child = runtime.retainLeanObjectHandleValue(value);
        const ptr = allocate("Except.ok", [child]);
        const handle = runtime.makeLeanObjectHandleResource(ptr); dec(ptr); return handle;
      }
      const ptr = allocate(name.endsWith(".name") ? value : "properties");
      const handle = runtime.makeLeanObjectHandleResource(ptr); dec(ptr); return handle;
    },
  };
  const memory = new WebAssembly.Memory({ initial: 1 });
  runtime.exports.memory = memory;
  runtime.allocByteLength = () => { memory.grow(0); return 32; };
  runtime.freeBytes = () => {};
  const native = (tag, ptr, count) => {
    if (runtime.failTag === tag) throw runtime.sentinel;
    const view = new DataView(memory.buffer);
    const children = Array.from({ length: count }, (_, i) => view.getUint32(ptr + i * 4, true));
    const result = allocate(tag, children);
    memory.grow(0);
    return result;
  };
  runtime.exports.vir_obj_ctor = native;
  runtime.exports.vir_obj_array = (ptr, count) => native("array", ptr, count);
  return runtime;
}

test("scoped constants release their roots while the result stays owned", () => {
  const runtime = fakeRuntime(), decode = createDirectPreviewDecoder(runtime, layouts, bindings);
  const result = decode(fixture());
  assert.ok(runtime.heap.size > 0);
  assert.ok(runtime.heap.has(result.ptr));
  runtime.releaseLeanObjectHandleCell(result);
  assert.equal(runtime.heap.size, 0);
});

test("partial construction and allocator failure clean up and preserve errors", () => {
  const runtime = fakeRuntime(), decode = createDirectPreviewDecoder(runtime, layouts, bindings);
  const bad = fixture(); delete bad.ready.document.document.titleString;
  assert.throws(() => decode(bad), /missing field/);
  assert.equal(runtime.heap.size, 0);
  runtime.sentinel = {};
  runtime.failAt = "Lean.Doc.Inline.other";
  assert.throws(() => decode(fixture()), error => error === runtime.sentinel);
  assert.equal(runtime.heap.size, 0);
  runtime.failAt = undefined;
  const result = decode(fixture()); runtime.releaseLeanObjectHandleCell(result);
  assert.equal(runtime.heap.size, 0);
});

test("disposed runtimes are rejected before allocation", () => {
  const runtime = fakeRuntime(), decode = createDirectPreviewDecoder(runtime, layouts, bindings);
  runtime.disposed = true;
  assert.throws(() => decode(fixture()), /disposed/);
  assert.equal(runtime.heap.size, 0);
});

test("whole-graph validation is opt-in", () => {
  let checks = 0;
  const checker = { "jsonValue.check": () => { checks++; return { kind: "ok" }; } };
  const runtime = fakeRuntime();
  for (const validate of [false, true]) {
    const decode = createDirectPreviewDecoder(runtime, layouts, checker, { validate });
    runtime.releaseLeanObjectHandleCell(decode(fixture()));
    assert.equal(runtime.heap.size, 0);
  }
  assert.equal(checks, 1);
});

test("small integers bypass decimal conversion, large integers retain it", () => {
  const runtime = fakeRuntime(), decimals = [];
  const original = runtime.makeObjectDecimal;
  runtime.makeObjectDecimal = (ctor, value) => { decimals.push([ctor, value]); return original(ctor, value); };
  const input = fixture();
  input.ready.document.document.content[0].other.container.data =
    [-1073741824, 1073741823, -1073741825, 1073741824];
  input.ready.document.version = 2147483647;
  const decode = createDirectPreviewDecoder(runtime, layouts, bindings);
  runtime.releaseLeanObjectHandleCell(decode(input));
  assert.deepEqual(decimals, [["vir_obj_int", "-1073741825"], ["vir_obj_int", "1073741824"]]);
  assert.equal(runtime.heap.size, 0);
});

test("scratch constructors preserve ownership and refresh views after native growth", () => {
  const runtime = fakeRuntime(), decode = createDirectPreviewDecoder(runtime, layouts, bindings);
  const result = withPointerScratch(runtime, () => decode(fixture()));
  runtime.releaseLeanObjectHandleCell(result);
  assert.equal(runtime.heap.size, 0);
  assert.equal(Object.hasOwn(runtime, "makeObjectCtorFromOwnedStack"), false);
  const bad = fixture(); delete bad.ready.document.document.titleString;
  assert.throws(() => withPointerScratch(runtime, () => decode(bad)), /missing field/);
  assert.equal(runtime.heap.size, 0);
  runtime.sentinel = {};
  runtime.failTag = "array";
  assert.throws(() => withPointerScratch(runtime, () => decode(fixture())), error => error === runtime.sentinel);
  assert.equal(runtime.heap.size, 0);
});

test("native property failure releases the typed input and permits recovery", () => {
  const runtime = fakeRuntime(), decode = createDirectPreviewDecoder(runtime, layouts, bindings);
  const call = runtime.call;
  const sentinel = {};
  runtime.call = (name, input) => {
    if (name.endsWith(".propertiesNative")) throw sentinel;
    return call(name, input);
  };
  assert.throws(() => withPointerScratch(runtime, () => decode(fixture())), error => error === sentinel);
  assert.equal(runtime.heap.size, 0);
  runtime.call = call;
  const result = withPointerScratch(runtime, () => decode(fixture()));
  runtime.releaseLeanObjectHandleCell(result);
  assert.equal(runtime.heap.size, 0);
});
