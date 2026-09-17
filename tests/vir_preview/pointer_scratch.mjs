/* Research-only synchronous owned-constructor writers; no persistent views. */
const active = new WeakSet();
export function withPointerScratch(runtime, call) {
  if (active.has(runtime) || runtime.disposed || runtime.disposing) throw Error("invalid pointer scratch scope");
  const names = ["makeObjectCtorFromOwnedStack", "makeObjectArrayFromOwnedStack", "makeObjectArrayFromOwnedElements"];
  const descriptors = names.map(name => Object.getOwnPropertyDescriptor(runtime, name));
  let ptr = 0, capacity = 0;
  const write = (values, start, count) => {
    if (!count) return 0;
    if (count > capacity) {
      const nextCapacity = Math.max(64, count);
      const next = runtime.allocByteLength(nextCapacity * 4, "pointer scratch");
      if (ptr) runtime.freeBytes(ptr);
      ptr = next; capacity = nextCapacity;
    }
    const view = new DataView(runtime.exports.memory.buffer, ptr, count * 4);
    for (let i = 0; i < count; i++) view.setUint32(i * 4, values[start + i], true);
    return ptr;
  };
  runtime.makeObjectCtorFromOwnedStack = function(tag, stack, count, label) {
    if (this !== runtime) throw Error("pointer scratch receiver mismatch");
    const result = runtime.exports.vir_obj_ctor(tag, write(stack, stack.length - count, count), count);
    if (!result) throw Error(`${label} constructor allocation failed`);
    return result; // Caller transfers stack roots only after success.
  };
  runtime.makeObjectArrayFromOwnedElements = function(values, label) {
    if (this !== runtime) throw Error("pointer scratch receiver mismatch");
    const result = runtime.exports.vir_obj_array(write(values, 0, values.length), values.length);
    if (!result) throw Error(`${label} array allocation failed`);
    values.length = 0;
    return result;
  };
  runtime.makeObjectArrayFromOwnedStack = function(stack, count, label) {
    if (this !== runtime) throw Error("pointer scratch receiver mismatch");
    const result = runtime.exports.vir_obj_array(write(stack, stack.length - count, count), count);
    if (!result) throw Error(`${label} array allocation failed`);
    return result;
  };
  active.add(runtime);
  try {
    const result = call();
    if (result && typeof result.then === "function") throw Error("pointer scratch requires synchronous work");
    return result;
  } finally {
    names.forEach((name, i) => {
      if (descriptors[i]) Object.defineProperty(runtime, name, descriptors[i]);
      else delete runtime[name];
    });
    active.delete(runtime);
    if (ptr) runtime.freeBytes(ptr);
  }
}
