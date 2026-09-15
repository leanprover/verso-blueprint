/* Experimental timing campaign: no instrumentation in shipped Lean/React code. */
import * as React from "react";
import { createRoot } from "react-dom/client";
import { RpcSessions } from "@leanprover/infoview-api";
import { EditorContext, EditorConnection } from "@leanprover/infoview";
import Widget from "@vir-embedded-shell";
import { createResponsePhaseProbe, responsePhaseDurations } from "./response_phase_probe.mjs";

const check = (ok, message) => { if (!ok) throw Error(message); };
async function post(path, body) {
  const value = await (await fetch(path, { method: "POST", body: JSON.stringify(body) })).json();
  if (value.error) throw Error(JSON.stringify(value.error));
  return value.result;
}
const previewMethod = JSON_BRIDGE_CANDIDATE
  ? "VersoBlueprintVirTests.NativeSession.LiveJson.Server.previewDocument"
  : PREVIEW_METHOD;
const panel = () => document.getElementById("vir-verso-preview");
// One observer per update, no polling and no document traversal in the timed path.
function committed(version) {
  return new Promise((resolve, reject) => {
    const finish = () => {
      const view = panel();
      const failure = document.querySelector('[data-vir-infoview-state="error"]');
      if (failure || view?.dataset.versoPreviewStatus === "error") {
        observer.disconnect(); clearTimeout(timer);
        reject(Error((failure ?? view).textContent));
      } else if (Number(view?.dataset.versoVersion) === version) {
        const time = performance.now();
        observer.disconnect(); clearTimeout(timer); resolve(time);
      }
    };
    const observer = new MutationObserver(finish);
    const timer = setTimeout(() => { observer.disconnect(); reject(Error(`version ${version} timeout`)); }, 90000);
    observer.observe(document.getElementById("app"), { subtree: true, childList: true, attributes: true });
    finish();
  });
}
function timingIn(value) {
  if (!value || typeof value !== "object") return;
  if (Object.hasOwn(value, "snapshotWaitNanos")) return value;
  for (const child of Object.values(value)) { const result = timingIn(child); if (result) return result; }
}
globalThis.rpcAcceptance = (async () => {
  const config = await (await fetch("/config")).json();
  const calls = [], handlers = new Set(), warnings = [], reactCommits = [];
  const responseProbe = RESPONSE_PHASES ? createResponsePhaseProbe() : null;
  if (RESPONSE_PHASES) globalThis.__vbpResponseProbe = responseProbe;
  let probeEnabled = false;
  const previousError = console.error;
  console.error = (...args) => { warnings.push(args.map(String).join(" ")); previousError(...args); };
  const editor = new EditorConnection({
    async subscribeClientNotifications() {}, async unsubscribeClientNotifications() {},
  }, { sentClientNotification: { on(handler) {
    handlers.add(handler); return { dispose() { handlers.delete(handler); } };
  } } });
  let nextId = 0;
  const sessions = new RpcSessions({
    async createRpcSession() { return (await post("/connect", {})).sessionId; },
    closeRpcSession(sessionId) { void post("/close", { sessionId }); },
    release(params) { void post("/release", params); },
    async call(params, options) {
      const record = { id: ++nextId, method: params.method, start: performance.now() };
      calls.push(record);
      const cancel = () => { void post("/cancel", { id: record.id }); };
      options?.abortSignal?.addEventListener("abort", cancel, { once: true });
      try {
        record.value = await post("/call", { id: record.id, params });
        record.reply = performance.now();
        if (probeEnabled && params.method === previewMethod) responseProbe.arm(record.id, record.value);
        return record.value;
      } finally { options?.abortSignal?.removeEventListener("abort", cancel); }
    },
  });
  const session = sessions.connect({ textDocument: { uri: config.uri }, position: config.a }, config.capabilities);
  globalThis.__vbpEmbeddedSession = session;
  const root = createRoot(document.getElementById("app"));
  try {
    const { widgets } = await session.call("Lean.Widget.getWidgets", config.a);
    const registered = widgets.find(w => w.id === WIDGET_ID);
    check(registered && registered.props.autoReloadMs === 0, "missing non-polling widget");
    const { sourcetext } = await session.call("Lean.Widget.getWidgetSource", { hash: registered.javascriptHash, pos: config.a });
    const hash = [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(sourcetext)))].map(b => b.toString(16).padStart(2, "0")).join("");
    check(hash === SHELL_HASH, "registered shell hash mismatch");
    const initial = committed(1), mountStart = performance.now();
    const tree = React.createElement(EditorContext.Provider, { value: editor },
      React.createElement(Widget, { ...registered.props, pos: { uri: config.uri, ...config.a } }));
    root.render(PROFILE ? React.createElement(React.Profiler, { id: "preview", onRender:
      (_id, phase, actualDuration, baseDuration, startTime, commitTime) => {
        reactCommits.push({ phase, actualDuration, baseDuration, startTime, commitTime });
      } }, tree) : tree);
    const mountEnd = await initial;
    const retained = document.getElementById("vir-verso-highlight-changes");
    check(retained && !retained.checked && !document.getElementById("vir-verso-debug").checked, "diagnostics must be off");
    const initialCalls = calls.map(({ method, start, reply }) => ({ method, elapsedMs: reply - start }));
    const rows = [];
    for (let trial = 0; trial < SAMPLES + 1; trial++) {
      probeEnabled = RESPONSE_PHASES && trial > 0 && [false, true, true, false][(trial - 1) % 4];
      if (SAMPLING && trial === 1) await post("/sampling/start", {});
      const version = trial + 2, before = calls.length;
      const done = committed(version), started = performance.now();
      const changed = await post("/edit", {});
      const forwarded = performance.now();
      for (const handler of [...handlers]) handler(["textDocument/didChange", changed]);
      const visible = await done;
      if (SAMPLING && trial === SAMPLES) await post("/sampling/browser-stop", {});
      // Verification and diagnostic parsing are deliberately after the timed endpoint.
      check(panel().textContent.includes(`Preview timing sample ${String(version).padStart(2, "0")}`), "stale document");
      check(document.getElementById("vir-verso-highlight-changes") === retained && !retained.checked, "control reset");
      const requests = calls.slice(before).filter(c => c.method === previewMethod);
      check(requests.length === 1, `expected one preview RPC, got ${requests.length}`);
      const request = requests[0];
      let responsePhases;
      if (RESPONSE_PHASES) {
        const samples = responseProbe.samples.filter(s => s.id === request.id);
        check(samples.length === (probeEnabled ? 1 : 0), "response callback attribution missing or repeated");
        if (probeEnabled) responsePhases = { ...responsePhaseDurations(samples[0]), raw: samples[0],
          replyToCallbackMs: samples[0].start - request.reply,
          callbackToDomMs: visible - samples[0].end };
      }
      const response = JSON_BRIDGE_CANDIDATE ? request.value : JSON.parse(request.value);
      const timing = timingIn(response);
      check(timing, "server timing absent");
      const snapshotMs = timing.snapshotWaitNanos / 1e6;
      const checkedMs = timing.checkedWaitNanos / 1e6;
      const evaluationMs = timing.evaluationNanos / 1e6;
      const diagnostics = await post("/diagnostics", {});
      if (SAMPLING && trial === SAMPLES) await post("/sampling/server-stop", {});
      rows.push({ trial, warmup: trial === 0, version, totalMs: visible - started,
        editBridgeMs: forwarded - started, notifyToRpcMs: request.start - forwarded,
        rpcMs: request.reply - request.start, replyToDomMs: visible - request.reply,
        snapshotMs, checkedMs, evaluationMs,
        rpcRemainderMs: request.reply - request.start - snapshotMs - checkedMs - evaluationMs,
        diagnosticsMs: diagnostics.ms, payloadChars: JSON_BRIDGE_CANDIDATE ? JSON.stringify(request.value).length : request.value.length,
        ...(RESPONSE_PHASES ? { probeEnabled, responsePhases } : {}),
        ...(PROFILE ? { reactCommits: reactCommits.filter(c => c.startTime >= started && c.commitTime <= visible) } : {}) });
    }
    check(calls.filter(c => c.method === "Lean.Vir.Infoview.buildIRPackage").length === 1, "client package rebuilt on edits");
    root.unmount();
    await new Promise(resolve => setTimeout(resolve, 20));
    check(warnings.length === 0, warnings.join("\n"));
    return { ok: true, value: { initialMountMs: mountEnd - mountStart, initialCalls, rows,
      clientPackage: calls.find(c => c.method === "Lean.Vir.Infoview.buildIRPackage").value,
      ...(CAPTURE_RESPONSE ? { capturedResponse: calls.filter(c => c.method === previewMethod).at(-1).value } : {}),
      ...(config.indexWaitMs !== undefined ? { indexWaitMs: config.indexWaitMs } : {}),
      warnings, clientPackages: 1, endpoint: "MutationObserver after accepted version DOM commit; not paint" } };
  } finally { sessions.dispose(); console.error = previousError; }
})().catch(error => ({ ok: false, error: String(error.stack ?? error) }));
