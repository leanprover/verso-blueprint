import assert from "node:assert/strict";
import test from "node:test";
import { withScopedStringIntern } from "./scoped_string_intern.mjs";

function fixture() {
  let next = 1;
  const refs = new Map();
  const runtime = {
    makeObjectString(value) {
      if (typeof value !== "string") throw TypeError("string expected");
      const object = next++; refs.set(object, 1); return object;
    },
    exports: {
      vir_obj_inc(object) { assert(refs.get(object) > 0); refs.set(object, refs.get(object) + 1); },
      vir_obj_dec(object) { assert(refs.get(object) > 0); refs.set(object, refs.get(object) - 1); },
    },
  };
  return { runtime, refs };
}

test("interned strings have independent cache/result references, scoped and bounded", () => {
  const { runtime, refs } = fixture();
  const original = runtime.makeObjectString;
  const stats = {};
  const objects = withScopedStringIntern(runtime, () => {
    const a = runtime.makeObjectString("key");
    runtime.exports.vir_obj_dec(a); // Consumer can drop its reference immediately.
    const b = runtime.makeObjectString("key");
    const c = runtime.makeObjectString("other");
    assert.equal(a, b);
    return [b, c];
  }, stats, { maxEntries: 1, maxLength: 10 });
  assert.equal(runtime.makeObjectString, original);
  assert.deepEqual(stats, { hits: 1, misses: 2, bypasses: 0, rootsReleased: 1, entries: 1 });
  assert(objects.every(object => refs.get(object) === 1));
  objects.forEach(runtime.exports.vir_obj_dec);
  assert([...refs.values()].every(n => n === 0));
});

test("failure restores inherited converter and releases roots; nested scope fails closed", () => {
  const { runtime, refs } = fixture();
  const host = Object.create(runtime);
  const sentinel = {};
  assert.throws(() => withScopedStringIntern(host, () => {
    const object = host.makeObjectString("key");
    host.exports.vir_obj_dec(object);
    assert.throws(() => withScopedStringIntern(host, () => {}), /nested/);
    throw sentinel;
  }), error => error === sentinel);
  assert.equal(Object.hasOwn(host, "makeObjectString"), false);
  assert([...refs.values()].every(n => n === 0));
  assert.throws(() => withScopedStringIntern(host, () => host.makeObjectString(1)), /string expected/);
  assert.throws(() => withScopedStringIntern(host, () => Promise.resolve()), /synchronous/);
  assert.throws(() => withScopedStringIntern(host, () => {}, null, { maxEntries: 0 }), /limits/);
  const stats = {};
  withScopedStringIntern(host, () => {
    const object = host.makeObjectString("longer than the limit");
    host.exports.vir_obj_dec(object);
  }, stats, { maxLength: 1 });
  assert.equal(stats.bypasses, 1);
  assert.equal(stats.entries, 0);
  host.disposed = true;
  assert.throws(() => withScopedStringIntern(host, () => {}), /disposed/);
});
