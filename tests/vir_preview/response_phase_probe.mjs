/* Diagnostic shell adapter: no producer writes, Lean probes, or per-node timers. */
export function measureHostCalls(host, call, sample, now = () => performance.now()) {
  sample.start = now();
  sample.hosts = [];
  const ownDescriptor = Object.getOwnPropertyDescriptor(host, "callObjects");
  const original = host.callObjects;
  host.callObjects = function(slot, argv, argc) {
    const event = { target: this.hostImports[slot]?.target, start: now() };
    sample.hosts.push(event);
    try { return original.call(this, slot, argv, argc); }
    finally { event.end = now(); }
  };
  try { return call(); }
  finally {
    sample.end = now();
    if (ownDescriptor) Object.defineProperty(host, "callObjects", ownDescriptor);
    else delete host.callObjects;
  }
}

export function createResponsePhaseProbe(now = () => performance.now()) {
  let pending = null;
  const samples = [];
  return {
    samples,
    arm(id, value) { pending = { id, value }; },
    invoke(root, args) {
      const call = () => root.runtime.callClosure(root.rootId, root.type, args);
      if (pending === null || args.length !== 1 || args[0] !== pending.value) return call();
      const sample = { id: pending.id };
      pending = null;
      // Install only for this synchronous response callback. Normal rendering
      // and all other callbacks use the original host dispatcher.
      try { return measureHostCalls(root.runtime.hostState, call, sample, now); }
      finally { samples.push(sample); }
    },
  };
}

export function responsePhaseDurations(sample) {
  const expected = ["js.string.fromAny", "js.string.value", "js.leanRef", "js.function.callVoid"];
  const targets = sample.hosts.map(h => h.target);
  if (JSON.stringify(targets) !== JSON.stringify(expected)) {
    throw Error(`response host sequence changed: ${JSON.stringify(targets)}`);
  }
  const [fromAny, toString, handle, setState] = sample.hosts;
  const boundaries = [sample.start, fromAny.start, toString.end, handle.start, setState.end, sample.end];
  if (boundaries.some((n, i) => !Number.isFinite(n) || (i && n < boundaries[i - 1]))) {
    throw Error("invalid response phase chronology");
  }
  return {
    callbackEntryMs: fromAny.start - sample.start,
    stringConversionMs: toString.end - fromAny.start,
    decodeIntervalMs: handle.start - toString.end,
    statePublicationMs: setState.end - handle.start,
    callbackTailMs: sample.end - setState.end,
    callbackTotalMs: sample.end - sample.start,
  };
}
