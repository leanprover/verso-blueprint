/*
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
*/

import { isLeanObjectHandle } from "@vir-object-values";

const fieldPath = (path, key) => `${path}[${JSON.stringify(key)}]`;
const diagnostics = new WeakMap();
const fail = (path, message) => {
  const text = `${path}: ${message}`;
  const error = new TypeError(text);
  diagnostics.set(error, text);
  throw error;
};

function stringCheck(value, path) {
  if (!value.isWellFormed()) fail(path, "unpaired UTF-16 surrogate");
}

function inspectNode(value, path) {
  if (value === null) return { kind: "null" };
  if (typeof value === "boolean") return { kind: "bool", value };
  if (typeof value === "string") {
    stringCheck(value, path);
    return { kind: "string", value };
  }
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value) || Object.is(value, -0))
      fail(path, "expected a safe integer (negative zero is unsupported)");
    return { kind: "integer", value: BigInt(value) };
  }
  if (typeof value !== "object") fail(path, `unsupported ${typeof value}`);
  if (isLeanObjectHandle(value)) fail(path, "Lean handles are not JSON values");
  const array = Array.isArray(value);
  const prototype = Object.getPrototypeOf(value);
  if (!array && prototype !== Object.prototype && prototype !== null)
    fail(path, "expected an ordinary object");
  if (array && prototype !== Array.prototype) fail(path, "expected an ordinary array");
  const descriptors = Object.getOwnPropertyDescriptors(value);
  const keys = Reflect.ownKeys(descriptors);
  if (keys.some((key) => typeof key !== "string")) fail(path, "symbol property");
  const children = [];
  for (const key of keys) {
    if (array && key === "length") continue;
    stringCheck(key, path);
    const descriptor = descriptors[key];
    if (!descriptor.enumerable || !Object.hasOwn(descriptor, "value"))
      fail(fieldPath(path, key), "non-enumerable property or accessor");
    if (array) {
      const index = Number(key);
      if (!Number.isInteger(index) || index < 0 || index >= value.length || String(index) !== key)
        fail(fieldPath(path, key), "non-index array property");
      children.push(descriptor.value);
    } else {
      children.push({ fst: key, snd: descriptor.value });
    }
  }
  if (array && children.length !== value.length) fail(path, "sparse array");
  return { kind: array ? "array" : "object", value: children };
}

function check(value) {
  const active = new WeakSet(), complete = new WeakSet();
  const stack = [{ value, path: "$" }];
  let path = "$";
  try {
    while (stack.length) {
      const item = stack.pop();
      path = item.path;
      if (item.close) { active.delete(item.value); complete.add(item.value); continue; }
      const node = inspectNode(item.value, path);
      if (node.kind !== "array" && node.kind !== "object") continue;
      if (active.has(item.value)) fail(path, "cyclic value");
      if (complete.has(item.value)) continue;
      active.add(item.value);
      stack.push({ ...item, close: true });
      node.value.forEach((child, index) => stack.push(node.kind === "array"
        ? { value: child, path: `${path}[${index}]` }
        : { value: child.snd, path: fieldPath(path, child.fst) }));
    }
    return { kind: "ok", value: null };
  } catch (error) {
    // An external exception can itself be a proxy or a primitive. Do not
    // inspect it or invoke its coercion hooks to produce a diagnostic.
    return { kind: "error", value: diagnostics.get(error) ?? `${path}: object inspection failed` };
  }
}

function build(node) {
  switch (node.kind) {
    case "null": return null;
    case "bool": case "string": return node.value;
    case "integer": {
      const value = BigInt(node.value);
      if (value < -9007199254740991n || value > 9007199254740991n)
        throw new RangeError("JSON integer exceeds the safe range");
      return Number(value);
    }
    case "array": return node.value;
    case "object": return Object.fromEntries(node.value.map(({ fst, snd }) => [fst, snd]));
    default: throw new TypeError("invalid internal JSON view");
  }
}

export function createJsonValueHostBindings() {
  return {
    "jsonValue.check": check,
    "jsonValue.inspect": (value) => inspectNode(value, "$"),
    "jsonValue.build": build,
  };
}
