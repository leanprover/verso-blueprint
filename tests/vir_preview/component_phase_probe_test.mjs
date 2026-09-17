import assert from "node:assert/strict";
import { test } from "node:test";
import { createComponentPhaseProbe } from "./component_phase_probe.mjs";

const target = "js.value.function.unary";
const bindings = { [target]: callback => callback };

for (const count of [1, 2]) test(`exact ${count}-factory callback ownership`, () => {
  let clock = 0;
  const probe = createComponentPhaseProbe(bindings, () => clock++, count);
  const callbacks = Array.from({ length: count * 2 }, () => probe.bindings[target](x => x));
  probe.finishFactory();
  for (const [index, callback] of callbacks.entries()) assert.equal(callback(index), index);
  assert.deepEqual(probe.records.map(r => [r.phase, r.factory, r.ok, r.durationMs]),
    callbacks.map((_, index) => [index % 2 === 0 ? "decoded-document-to-elements" : "document-session",
      Math.floor(index / 2), true, 1]));
  probe.clear();
  const later = probe.bindings[target](x => x);
  assert.equal(later(42), 42);
  assert.equal(probe.records.length, 0, "post-factory callbacks must remain unwrapped");
});

test("factory drift and callback errors remain visible", () => {
  assert.throws(() => createComponentPhaseProbe(bindings, undefined, 0), /factory count/);
  const incomplete = createComponentPhaseProbe(bindings);
  assert.throws(() => incomplete.finishFactory(), /content then session/);
  const drift = createComponentPhaseProbe(bindings);
  drift.bindings[target](x => x);
  drift.bindings[target](x => x);
  assert.throws(() => drift.bindings[target](x => x), /unexpected unary/);
  assert.throws(() => drift.finishFactory(), /content then session/);
  const probe = createComponentPhaseProbe(bindings);
  const error = new Error("provider identity");
  const failing = probe.bindings[target](() => { throw error; });
  probe.bindings[target](x => x);
  probe.finishFactory();
  assert.throws(() => failing(), caught => caught === error);
  assert.equal(probe.records[0].ok, false);
});
