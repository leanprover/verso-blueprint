import assert from "node:assert/strict";
import test from "node:test";
import { createResponsePhaseProbe, responsePhaseDurations } from "./response_phase_probe.mjs";

function fixture(throws = false) {
  let clock = 0;
  const probe = createResponsePhaseProbe(() => ++clock);
  const targets = ["js.string.fromAny", "js.string.value", "js.leanRef", "js.function.callVoid"];
  const prototype = { callObjects(slot) { assert.equal(this.hostImports[slot].target, targets[slot]); return slot; } };
  const hostState = Object.assign(Object.create(prototype), { hostImports: targets.map(target => ({ target })) });
  const root = { rootId: 1, type: "fixture", runtime: { hostState,
    callClosure(id, type, args) {
      assert.equal(id, 1); assert.equal(type, "fixture");
      for (let i = 0; i < targets.length; i++) assert.equal(hostState.callObjects(i, 0, 1), i);
      if (throws) throw Error("original failure");
      return args[0];
    },
  } };
  return { probe, root, hostState };
}
test("unarmed and unrelated callbacks pass through without samples", () => {
  const { probe, root } = fixture();
  assert.equal(probe.invoke(root, ["a"]), "a");
  probe.arm(4, "response");
  assert.equal(probe.invoke(root, ["other"]), "other");
  assert.equal(probe.samples.length, 0);
  assert.equal(probe.invoke(root, ["response"]), "response");
  assert.equal(probe.samples[0].id, 4);
});
test("records four calls, partitions duration, restores inherited dispatcher", () => {
  const { probe, root, hostState } = fixture();
  const original = hostState.callObjects;
  probe.arm(1, "response"); probe.invoke(root, ["response"]);
  assert.equal(Object.hasOwn(hostState, "callObjects"), false);
  assert.equal(hostState.callObjects, original);
  const phases = responsePhaseDurations(probe.samples[0]);
  const sum = Object.entries(phases).filter(([k]) => k !== "callbackTotalMs").reduce((n, [,v]) => n+v, 0);
  assert.equal(sum, phases.callbackTotalMs);
  probe.invoke(root, ["response"]);
  assert.equal(probe.samples.length, 1);
});
test("original exception and own dispatcher descriptor survive", () => {
  const { probe, root, hostState } = fixture(true);
  Object.defineProperty(hostState, "callObjects", { value: hostState.callObjects, writable: true, configurable: true });
  const descriptor = Object.getOwnPropertyDescriptor(hostState, "callObjects");
  probe.arm(1, "response");
  assert.throws(() => probe.invoke(root, ["response"]), /original failure/);
  assert.deepEqual(Object.getOwnPropertyDescriptor(hostState, "callObjects"), descriptor);
  assert.equal(probe.samples.length, 1);
});
test("unexpected host calls fail attribution rather than mislabel time", () => {
  assert.throws(() => responsePhaseDurations({ hosts: [], start: 0, end: 1 }), /sequence changed/);
});
