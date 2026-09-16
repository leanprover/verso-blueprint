// Diagnostic only: bracket callbacks, never individual host calls or values.
const check = (ok, message) => { if (!ok) throw new Error(message); };

/** The frozen createEncodedDocumentComponent factory creates content first,
 * then the outer document/session component. Validate that exact boundary
 * before mounting; a changed factory must fail rather than mislabel samples.
 * content includes props access, VDOM construction and effect registration.
 * outer includes decode/identity/shell work and is NOT a pure identity timer.
 */
export function createComponentPhaseProbe(bindings, now = () => performance.now()) {
  const target = 'js.value.function.unary';
  check(typeof bindings[target] === 'function', 'missing generic unary function provider');
  const records = [];
  let factoryOpen = true;
  let created = 0;
  const measuredBindings = { ...bindings, [target](callback) {
    const native = bindings[target](callback);
    if (!factoryOpen) return native;
    const index = created++;
    check(index < 2, 'frozen factory created an unexpected unary function');
    const phase = index === 0 ? 'decoded-document-to-elements' : 'document-session';
    return function (...args) {
      const startMs = now();
      let ok = false;
      try {
        const result = Reflect.apply(native, this, args);
        ok = true;
        return result;
      } finally {
        const endMs = now();
        records.push({ phase, startMs, endMs, durationMs: endMs - startMs, ok });
      }
    };
  } };
  return { bindings: measuredBindings, records,
    finishFactory() {
      check(factoryOpen, 'factory boundary already closed');
      check(created === 2, 'frozen factory must create content then session');
      factoryOpen = false;
    },
    clear() { records.length = 0; },
  };
}
