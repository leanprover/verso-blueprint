/* Consumer experiment: remove temporary JS UTF-8 arrays, not Lean String copies. */
const active = new WeakSet();
const encoder = new TextEncoder();

export function withUtf8Scratch(runtime, call) {
  if (active.has(runtime)) throw Error("nested UTF-8 scratch scope");
  if (runtime.disposed || runtime.disposing) throw Error("disposed UTF-8 scratch runtime");
  const descriptor = Object.getOwnPropertyDescriptor(runtime, "makeObjectString");
  let ptr = 0, capacity = 0;
  runtime.makeObjectString = function(value, label) {
    if (this !== runtime || runtime.disposed || runtime.disposing) throw Error("invalid UTF-8 scratch runtime");
    if (typeof value !== "string") throw TypeError(`${label} must be a string`);
    const required = Math.max(1, value.length * 3);
    if (required > capacity) {
      const nextCapacity = Math.max(4096, required);
      const next = runtime.allocByteLength(nextCapacity, "UTF-8 scratch");
      if (ptr) runtime.freeBytes(ptr);
      ptr = next; capacity = nextCapacity;
    }
    // Acquire only after allocations; never retain a view across a Wasm call.
    const { read, written } = encoder.encodeInto(value,
      new Uint8Array(runtime.exports.memory.buffer, ptr, capacity));
    if (read !== value.length) throw Error("incomplete UTF-8 encoding");
    const result = runtime.exports.vir_obj_string(ptr, written);
    if (!result) throw Error(`${label} could not be lowered to a Lean string object`);
    return result;
  };
  active.add(runtime);
  try {
    const result = call();
    if (result && typeof result.then === "function") throw Error("UTF-8 scratch scope requires synchronous work");
    return result;
  } finally {
    if (descriptor) Object.defineProperty(runtime, "makeObjectString", descriptor);
    else delete runtime.makeObjectString;
    active.delete(runtime);
    if (ptr) runtime.freeBytes(ptr);
  }
}
