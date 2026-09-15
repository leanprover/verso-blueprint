import assert from "node:assert/strict";
import test from "node:test";
import { createHostCallbackCensus, instrumentCallbackCensus } from "./host_callback_census.mjs";

test("census separates copied roots from newly tracked roots and freezes reports", () => {
  const census = createHostCallbackCensus();
  const entry = { target: "js.object.set", boundary: "fixture" }, arg = { type: { interfaceTag: 23 } };
  assert.equal(census.before(entry, arg, 10, 0), null);
  census.reset();
  census.after(census.before(entry, arg, 10, 0), 0);
  census.after(census.before(entry, arg, 12, 0), 1);
  const rows = census.finish();
  assert.deepEqual(rows, [{ target: "js.object.set", boundary: "fixture", tag: 23,
    arguments: 2, snapshotEntries: 22, maxLiveCallbacks: 12, newlyTracked: 1 }]);
  assert.equal(census.before(entry, arg, 20, 0), null);
  census.reset();
  assert.equal(census.finish().length, 0);
  assert.equal(rows[0].arguments, 2);
});

test("instrumentation rejects changed bridge anchors", () => {
  assert.throws(() => instrumentCallbackCensus(""), /pinned bridge drift/);
});
