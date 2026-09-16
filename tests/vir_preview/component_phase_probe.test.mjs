import assert from 'node:assert/strict';
import { createComponentPhaseProbe } from './component_phase_probe.mjs';

const target = 'js.value.function.unary';
const bindings = { [target]: callback => callback };
let ticks = 0;
const probe = createComponentPhaseProbe(bindings, () => ticks++);
const content = probe.bindings[target](function (props) { return [this, props]; });
const marker = { failure: true };
const session = probe.bindings[target](() => { throw marker; });
probe.finishFactory();
const props = {}, receiver = {};
assert.deepEqual(content.call(receiver, props), [receiver, props]);
assert.throws(session, error => error === marker);
assert.deepEqual(probe.records.map(({phase, durationMs, ok}) => ({phase, durationMs, ok})), [
  { phase: 'decoded-document-to-elements', durationMs: 1, ok: true },
  { phase: 'document-session', durationMs: 1, ok: false },
]);
const later = () => props;
assert.equal(probe.bindings[target](later), later);
assert.equal(ticks, 4); // Exactly two clock reads per measured callback.
probe.clear();
assert.equal(probe.records.length, 0);
assert.throws(() => probe.finishFactory());
assert.throws(() => createComponentPhaseProbe(bindings).finishFactory());
const unexpected = createComponentPhaseProbe(bindings);
unexpected.bindings[target](later);
unexpected.bindings[target](later);
assert.throws(() => unexpected.bindings[target](later));
console.log('PASS component phase boundaries, clock count, native identity and exception preservation');
