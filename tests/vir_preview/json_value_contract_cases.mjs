const expect = (actual, expected) => {
  if (JSON.stringify(actual) !== JSON.stringify(expected))
    throw Error(`JSON value contract mismatch: ${JSON.stringify(actual)}`);
};

// Exercise the real selected provider, including its SDK-owned handle brand.
// No getters/coercion hooks may execute merely to reject a value.
export function jsonValueContractCases(bindings, leanHandle) {
  const check = bindings["jsonValue.check"];
  const shared = { text: "λ😀", integer: 42 };
  const valid = [null, false, "λ😀", -9007199254740991, 9007199254740991,
    [null, shared, shared], Object.assign(Object.create(null), { value: shared })];
  for (const value of valid) expect(check(value), { kind: "ok", value: null });

  let effects = 0;
  const accessor = Object.defineProperty({}, "x", { enumerable: true,
    get() { effects++; throw Error("getter executed"); } });
  const externalError = { toString() { effects++; throw Error("coercion executed"); } };
  const proxy = new Proxy({}, { ownKeys() { throw externalError; } });
  const cycle = {}; cycle.self = cycle;
  const hidden = Object.defineProperty({}, "x", { value: 1 });
  const symbol = { [Symbol("x")]: 1 };
  const arrayProperty = []; arrayProperty.extra = 1;
  const invalid = [undefined, 0.5, -0, 9007199254740992, "\ud800", [,],
    cycle, accessor, hidden, symbol, arrayProperty, new Date(), proxy, leanHandle];
  for (const value of invalid) {
    const result = check(value);
    expect(result.kind, "error");
    expect(/^\$.*: /.test(result.value), true);
  }
  expect(effects, 0);
  expect(check({ "a\"b": [undefined] }), {
    kind: "error", value: '$["a\\\"b"][0]: unsupported undefined',
  });
  expect(check(cycle), { kind: "error", value: '$["self"]: cyclic value' });
  expect(check(proxy), { kind: "error", value: '$: object inspection failed' });

  // Validation is iterative and path creation must not copy every ancestor.
  let deep = null;
  for (let depth = 0; depth < 2000; depth++) deep = [deep];
  expect(check(deep), { kind: "ok", value: null });
  expect(bindings["jsonValue.inspect"]({ "2": false, x: shared }), {
    kind: "object", value: [{ fst: "2", snd: false }, { fst: "x", snd: shared }],
  });
  return { valid: valid.length, invalid: invalid.length, deepValidationDepth: 2000,
    diagnostics: 3, getterOrCoercionCalls: effects, sdkHandleRejected: true };
}
