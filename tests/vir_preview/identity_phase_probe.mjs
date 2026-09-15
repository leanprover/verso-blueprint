// Diagnostic-only boundaries emitted by identity-phases/instrumented/Renderer.lean.
// No per-node timers, graph copying, or document-content inspection.
export function createIdentityPhaseProbe(defaults, now = () => performance.now()) {
  let active = false, pending, renderStart, events = [];
  const fail = message => { throw Error(`identity phase probe: ${message}`); };
  const bindings = {
    "js.string": (...args) => {
      const value = defaults["js.string"](...args);
      if (active && value === "__vbp_render_start") {
        if (renderStart !== undefined) fail("nested renderer");
        renderStart = now();
      }
      if (active && value === "__vbp_render_end") {
        if (renderStart === undefined || pending) fail("unbalanced renderer");
        events.push({ kind: "render", start: renderStart, end: now() });
        renderStart = undefined;
      }
      if (active && value.startsWith("__vbp_identity_")) {
        if (pending) fail("nested identity group");
        const label = value.slice("__vbp_identity_".length);
        const splitJson = label.startsWith("json-");
        const kind = splitJson ? label.slice(5) : label;
        if (!["blocks", "parts", "calibration"].includes(kind)) fail(`unknown group ${kind}`);
        pending = { kind, ...(splitJson ? { splitJson: true } : {}), start: now() };
      }
      return value;
    },
    "js.nat": (...args) => {
      if (!active || !pending) return defaults["js.nat"](...args);
      const entered = now();
      const value = defaults["js.nat"](...args);
      if (typeof value !== "bigint" || value < 0n || value > BigInt(Number.MAX_SAFE_INTEGER))
        fail("invalid forced array size");
      const count = Number(value);
      if (pending.extensionEnd === undefined) {
        pending.extensionEnd = entered;
        pending.count = count;
        pending.hintsStart = now();
      } else if (pending.splitJson && pending.treeEnd === undefined) {
        if (pending.kind === "blocks" && count !== pending.count) fail("sibling count changed");
        pending.count = count;
        pending.treeEnd = entered;
        pending.serializationStart = now();
      } else if (pending.hintsEnd === undefined) {
        if ((pending.kind === "blocks" || pending.splitJson) && count !== pending.count) fail("sibling count changed");
        pending.count = count;
        pending.hintsEnd = entered;
        pending.allocationStart = now();
      } else {
        if (count !== pending.count) fail("sibling count changed");
        events.push({ ...pending, allocationEnd: entered });
        pending = undefined;
      }
      return value;
    },
  };
  return {
    bindings,
    begin() {
      if (active) fail("already active");
      active = true; pending = undefined; renderStart = undefined; events = [];
    },
    finish() {
      active = false;
      if (pending || renderStart !== undefined) fail("unfinished identity group or renderer");
      return events;
    },
  };
}
