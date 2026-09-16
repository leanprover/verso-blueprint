/*
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
*/

import { isLeanObjectHandle } from "@vir-object-values";

// Successful validation never needs a diagnostic string. Retain a linked path
// instead of repeatedly copying/escaping every ancestor for every child.
const fieldPath = (parent, key) => ({ parent, key });
function renderPath(path) {
  const keys = [];
  while (typeof path !== "string") { keys.push(path.key); path = path.parent; }
  return path + keys.reverse().map(key => `[${JSON.stringify(key)}]`).join("");
}
const diagnostics = new WeakMap();
const fail = (path, message) => {
  const text = `${renderPath(path)}: ${message}`;
  const error = new TypeError(text);
  diagnostics.set(error, text);
  throw error;
};

function stringCheck(value, path) {
  if (!value.isWellFormed()) fail(path, "unpaired UTF-16 surrogate");
}

// Validation walks children without constructing conversion views, tuple
// wrappers, or BigInts. Returns whether the node is a container.
function validateNode(value, path, visit) {
  if (value === null || typeof value === "boolean") return false;
  if (typeof value === "string") {
    stringCheck(value, path);
    return false;
  }
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value) || Object.is(value, -0))
      fail(path, "expected a safe integer (negative zero is unsupported)");
    return false;
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
  let childCount = 0;
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
      visit(descriptor.value, index);
    } else {
      visit(descriptor.value, key);
    }
    childCount++;
  }
  if (array && childCount !== value.length) fail(path, "sparse array");
  return true;
}

// Internal.inspect is private on the Lean side and called synchronously only
// after Internal.check accepts the entire graph. Accessors are rejected; proxies
// and mutation during conversion are outside the contract. No await or user
// callback occurs here. Do not repeat descriptor/prototype/string validation.
function inspectCheckedNode(value) {
  if (value === null) return { kind: "null" };
  switch (typeof value) {
    case "boolean": return { kind: "bool", value };
    case "string": return { kind: "string", value };
    case "number": return { kind: "integer", value: BigInt(value) };
    case "object":
      if (Array.isArray(value)) return { kind: "array", value };
      return { kind: "object", value: Object.keys(value).map(key => ({ fst: key, snd: value[key] })) };
    default: throw new TypeError("unchecked internal JSON node");
  }
}

function check(value) {
  const active = new WeakSet(), complete = new WeakSet();
  const stack = [{ value, path: "$" }];
  const visit = (value, key) => stack.push({ value, path: fieldPath(path, key) });
  let path = "$";
  try {
    while (stack.length) {
      const item = stack.pop();
      path = item.path;
      if (item.close) { active.delete(item.value); complete.add(item.value); continue; }
      const base = stack.length;
      if (item.value !== null && typeof item.value === "object")
        stack.push({ value: item.value, path, close: true });
      if (!validateNode(item.value, path, visit)) continue;
      if (active.has(item.value)) fail(path, "cyclic value");
      if (complete.has(item.value)) { stack.length = base; continue; }
      active.add(item.value);
    }
    return { kind: "ok", value: null };
  } catch (error) {
    // An external exception can itself be a proxy or a primitive. Do not
    // inspect it or invoke its coercion hooks to produce a diagnostic.
    return { kind: "error", value: diagnostics.get(error) ?? `${renderPath(path)}: object inspection failed` };
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
    "jsonValue.inspect": inspectCheckedNode,
    "jsonValue.build": build,
  };
}
