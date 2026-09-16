/* Research-only use of the existing VIR object runtime. No SDK source patch. */
const active = new WeakSet();

export function withScopedStringIntern(runtime, call, stats = null,
    { maxEntries = 256, maxLength = 64 } = {}) {
  if (active.has(runtime)) throw Error("nested string-intern scope on one runtime");
  if (runtime.disposed || runtime.disposing) throw Error("string-intern scope on disposed runtime");
  if (!Number.isInteger(maxEntries) || maxEntries < 1 ||
      !Number.isInteger(maxLength) || maxLength < 0) throw Error("invalid string-intern limits");
  const original = runtime.makeObjectString;
  const descriptor = Object.getOwnPropertyDescriptor(runtime, "makeObjectString");
  const { vir_obj_inc: retain, vir_obj_dec: release } = runtime.exports;
  if (typeof original !== "function" || typeof retain !== "function" || typeof release !== "function")
    throw Error("string-intern experiment requires existing object ownership exports");
  const strings = new Map();
  if (stats) Object.assign(stats, { hits: 0, misses: 0, bypasses: 0, rootsReleased: 0 });
  runtime.makeObjectString = function(value, label) {
    if (this !== runtime) throw Error("string-intern converter belongs to another runtime");
    // Preserve normal input validation for nonstrings/large strings.
    if (typeof value !== "string" || value.length > maxLength) {
      if (stats) stats.bypasses++;
      return original.call(this, value, label);
    }
    const cached = strings.get(value);
    if (cached !== undefined) {
      retain(cached); // One owned reference for the normal result consumer.
      if (stats) stats.hits++;
      return cached;
    }
    const object = original.call(this, value, label);
    if (stats) stats.misses++;
    if (strings.size < maxEntries) {
      retain(object); // Separate root owned only by this scope.
      try { strings.set(value, object); }
      catch (error) { release(object); release(object); throw error; }
    }
    return object;
  };
  active.add(runtime);
  try {
    const result = call();
    if (result && typeof result.then === "function")
      throw Error("string-intern scope requires a synchronous call");
    return result;
  } finally {
    if (descriptor) Object.defineProperty(runtime, "makeObjectString", descriptor);
    else delete runtime.makeObjectString;
    active.delete(runtime);
    for (const object of strings.values()) {
      release(object);
      if (stats) stats.rootsReleased++;
    }
    if (stats) stats.entries = strings.size;
    strings.clear();
  }
}
