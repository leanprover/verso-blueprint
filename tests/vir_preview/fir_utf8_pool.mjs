/* Consumer-only FIR adapter experiment. The producer package remains immutable. */
export function installFirUtf8Pool(source) {
  const encoderNeedle = "  const encoder = new TextEncoder();\n";
  const stringNeedle = `  const string = value => {
    check(typeof value === "string", "expected JS string");
    const bytes = encoder.encode(value), size = align(HEADER + bytes.length), p = allocate(size);
    writeHeader(p, 4, size, 1, bytes.length);
    new Uint8Array(memory.buffer, p + HEADER, bytes.length).set(bytes);
    return p;
  };`;
  if (source.split(encoderNeedle).length !== 2)
    throw new Error("FIR adapter encoder boundary drifted");
  if (source.split(stringNeedle).length !== 2)
    throw new Error("FIR adapter String boundary drifted");
  const pooled = `  const encoder = new TextEncoder();
  // A conversion keeps its slot leased while allocate runs. If allocation
  // reenters a host conversion, the nested call receives a distinct slot.
  const stringScratch = [];
  let stringScratchDepth = 0;
`;
  const string = `  const string = value => {
    check(typeof value === "string", "expected JS string");
    const scratchIndex = stringScratchDepth++;
    try {
      const capacity = Math.max(256, value.length * 3);
      let scratch = stringScratch[scratchIndex];
      if (scratch === undefined || scratch.length < capacity)
        scratch = stringScratch[scratchIndex] = new Uint8Array(capacity);
      const result = encoder.encodeInto(value, scratch);
      check(result.read === value.length, "incomplete UTF-8 encoding");
      const length = result.written, size = align(HEADER + length), p = allocate(size);
      writeHeader(p, 4, size, 1, length);
      // Obtain the Wasm view only after allocate: memory growth may detach an
      // earlier view, while a reentrant conversion cannot mutate this slot.
      new Uint8Array(memory.buffer, p + HEADER, length).set(scratch.subarray(0, length));
      return p;
    } finally {
      stringScratchDepth--;
    }
  };`;
  return source.replace(encoderNeedle, pooled).replace(stringNeedle, string);
}
