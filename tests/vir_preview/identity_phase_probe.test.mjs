import assert from "node:assert/strict";
import { test } from "node:test";
import { createIdentityPhaseProbe } from "./identity_phase_probe.mjs";

const defaults = { "js.string": x => x, "js.nat": x => BigInt(x) };
test("JSON split adds a forced-tree boundary without charging its host body", () => {
  const stamps = [10, 20, 22, 30, 32, 40, 42, 50];
  const p = createIdentityPhaseProbe(defaults, () => stamps.shift());
  p.begin();
  p.bindings["js.string"]("__vbp_identity_json-blocks");
  for (let i = 0; i < 4; ++i) p.bindings["js.nat"](3);
  assert.deepEqual(p.finish(), [{ kind: "blocks", splitJson: true, start: 10,
    extensionEnd: 20, count: 3, hintsStart: 22, treeEnd: 30,
    serializationStart: 32, hintsEnd: 40, allocationStart: 42, allocationEnd: 50 }]);
  assert.equal(stamps.length, 0);
});
test("inactive/ordinary calls pass through without sampling", () => {
  const p = createIdentityPhaseProbe(defaults, () => { throw Error("unexpected timer"); });
  assert.equal(p.bindings["js.string"]("__vbp_identity_blocks"), "__vbp_identity_blocks");
  assert.equal(p.bindings["js.nat"](3), 3n);
  p.begin();
  assert.equal(p.bindings["js.string"]("paragraph"), "paragraph");
  assert.equal(p.bindings["js.nat"](2), 2n);
  assert.deepEqual(p.finish(), []);
});
test("separates extension resolution, fingerprints and allocation", () => {
  const stamps = [10, 20, 22, 30, 32, 40];
  const p = createIdentityPhaseProbe(defaults, () => stamps.shift());
  p.begin();
  p.bindings["js.string"]("__vbp_identity_blocks");
  p.bindings["js.nat"](3);
  p.bindings["js.nat"](3);
  p.bindings["js.nat"](3);
  assert.deepEqual(p.finish(), [{ kind: "blocks", start: 10, extensionEnd: 20,
    count: 3, hintsStart: 22, hintsEnd: 30, allocationStart: 32, allocationEnd: 40 }]);
  assert.equal(stamps.length, 0);
});
test("fails closed on incomplete, nested or mismatched groups", () => {
  for (const mode of ["incomplete", "nested", "mismatched"]) {
    const p = createIdentityPhaseProbe(defaults, () => 0);
    p.begin();
    p.bindings["js.string"]("__vbp_identity_parts");
    assert.throws(() => {
      if (mode === "nested") p.bindings["js.string"]("__vbp_identity_blocks");
      if (mode === "mismatched") {
        p.bindings["js.nat"](0); p.bindings["js.nat"](1); p.bindings["js.nat"](2);
      }
      p.finish();
    }, /identity phase probe/);
  }
});
test("outer renderer interval is independent from sibling intervals", () => {
  let clock = 0;
  const p = createIdentityPhaseProbe(defaults, () => ++clock);
  p.begin();
  p.bindings["js.string"]("__vbp_render_start");
  p.bindings["js.string"]("__vbp_identity_calibration");
  p.bindings["js.nat"](0); p.bindings["js.nat"](0);
  p.bindings["js.nat"](0);
  p.bindings["js.string"]("__vbp_render_end");
  const events = p.finish();
  assert.equal(events.length, 2);
  assert.deepEqual(events.at(-1), { kind: "render", start: 1, end: 8 });
});
