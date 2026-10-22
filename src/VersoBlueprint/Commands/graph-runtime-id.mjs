import { getBlueprintProgram } from "./blueprint-vir-client.mjs";

// Lean strings contain Unicode scalar values; do not silently replace malformed
// JS UTF-16 when crossing the String boundary. Valid astral pairs match as one
// code point with /u, so only lone surrogate code units are rejected here.
export async function encodeGraphKey(key) {
  if (typeof key !== "string" || /[\uD800-\uDFFF]/u.test(key)) {
    throw new Error("Graph key must contain valid Unicode scalar values");
  }
  const {program, entries} = await getBlueprintProgram();
  const encoded = program.call(entries.htmlId, key);
  if (typeof encoded !== "string") throw new Error("VIR returned an invalid graph key");
  return encoded;
}
