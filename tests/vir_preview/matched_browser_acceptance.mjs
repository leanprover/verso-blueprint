import * as React from "react";
import { createRoot } from "react-dom/client";
import { EditorContext } from "@leanprover/infoview";
import Widget from "@vir-embedded-shell";
import { withCleanup } from "@vir-test-support";

const check = (ok, message) => { if (!ok) throw Error(message); };
export async function runEmbeddedAcceptance({ config, a, b, editor, emit, requests,
  warnings, subscriptions, listeners }) {
  const root = createRoot(document.getElementById("app"));
  const panel = () => document.getElementById("vir-verso-preview");
  const version = () => Number(panel()?.dataset.versoVersion);
  const calls = () => requests.filter(r => r.method === "MatchedPreview.Server.previewDocument");
  const wait = async predicate => {
    for (let i = 0; i < 2000; i++) {
      await React.act(async () => { await new Promise(resolve => setTimeout(resolve, 10)); });
      const error = document.querySelector('[data-vir-infoview-state="error"]');
      if (error) throw Error(error.textContent);
      if (predicate()) return;
    }
    throw Error(`matched preview timeout: calls=${JSON.stringify(calls().map(call => ({
      settled: call.settled, error: call.error,
    })))}, panel=${panel()?.outerHTML.slice(0, 500)}`);
  };
  return withCleanup(async () => {
    const { widgets } = await a.call("Lean.Widget.getWidgets", config.a);
    const registered = widgets.find(w => w.id === VBP_MATCHED_WIDGET_ID);
    check(registered, `matched panel registration missing (${VBP_MATCHED_WIDGET_ID}); available: ${widgets.map(w => w.id).join(", ")}`);
    const { sourcetext } = await a.call("Lean.Widget.getWidgetSource", {
      hash: registered.javascriptHash, pos: config.a });
    const hash = [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(sourcetext)))].map(x => x.toString(16).padStart(2, "0")).join("");
    check(hash === VBP_EMBEDDED_SHELL_SHA256, "wrong backend shell registration");
    const render = async (session, position) => {
      globalThis.__vbpEmbeddedSession = session;
      await React.act(async () => root.render(React.createElement(EditorContext.Provider, { value: editor },
        React.createElement(Widget, { ...registered.props, pos: { uri: config.uri, ...position } }))));
    };
    await render(a, config.a);
    await wait(() => version() === 1);
    const badge = document.querySelector("[data-preview-backend]");
    check(badge && badge.dataset.previewBackend === VBP_MATCHED_BACKEND,
      "renderer badge does not identify selected backend");
    for (const text of VBP_MATCHED_EXPECTED_TEXT ? [VBP_MATCHED_EXPECTED_TEXT]
      : ["A live Blueprint document", "An informal statement with inline math", "This proof body remains visible"])
      check(panel().textContent.includes(text), `missing ${text}`);
    const formula = document.querySelector(".katex");
    check(formula && document.querySelector("math"), "matched preview did not render KaTeX HTML/MathML");
    check(!document.querySelector(".katex-error"), "valid matched preview math produced a KaTeX error");
    const follow = document.getElementById("vir-verso-follow-cursor");
    if (VBP_NATIVE_DIRECT_TIMING) React.act(() => document.getElementById("vir-verso-debug").click());
    React.act(() => follow.click());
    const selected = follow.checked;
    const before = calls().length;
    await render(a, config.a);
    await React.act(async () => { await new Promise(resolve => setTimeout(resolve, 30)); });
    check(calls().length === before, "unchanged props restarted RPC");
    const edit = await (await fetch("/edit", { method: "POST", body: "{}" })).json();
    if (edit.error) throw edit.error;
    React.act(() => emit("textDocument/didChange", edit.result));
    await wait(() => version() === edit.result.textDocument.version);
    check(panel().textContent.includes(`browser edit ${version()}`), "edited text missing");
    check(document.querySelector(".katex") === formula,
      "unchanged formula was re-typeset or remounted during the document edit");
    let measurement;
    if (VBP_NATIVE_DIRECT_TIMING) {
      await wait(() => document.getElementById("vir-verso-measurement")?.dataset.versoMeasurementVersion === String(version()));
      const bar = document.getElementById("vir-verso-server-bar");
      measurement = { ...document.getElementById("vir-verso-measurement").dataset,
        totalNanos: bar.dataset.versoTotalNanos,
        phases: [...bar.children].map(s => ({ phase: s.dataset.versoPhase, nanos: Number(s.dataset.versoNanos) })) };
      check(bar.getAttribute("aria-label").startsWith("Edit notification → content effect"),
        "edit bar lacks the full notification-to-effect boundary");
      check(measurement.phases.length === 9, "edit bar is missing browser or server phases");
      check(measurement.phases.every(p => Number.isFinite(p.nanos) && p.nanos >= 0) &&
        Math.abs(measurement.phases.reduce((sum, p) => sum + p.nanos, 0) - Number(measurement.totalNanos)) <= 9,
        "edit phases do not account for the displayed total");
    }
    check(document.getElementById("vir-verso-follow-cursor") === follow && follow.checked === selected,
      "edit reset controls");
    await render(b, config.b);
    await wait(() => calls().at(-1)?.settled);
    check(document.getElementById("vir-verso-follow-cursor") === follow && follow.checked === selected,
      "cursor update reset controls");
    if (measurement) check(document.getElementById("vir-verso-server-bar").dataset.versoTotalNanos === measurement.totalNanos &&
      document.getElementById("vir-verso-measurement").dataset.versoMeasurementCorrelation === measurement.versoMeasurementCorrelation,
      "cursor reply replaced the edit bar");
    check(requests.filter(r => r.method === "Lean.Vir.Infoview.buildIRPackage").length === 1,
      "edit or cursor update rebuilt client package");
    return { registeredWidget: registered.id, shellSha256: hash, retainedControl: true, backendBadge: badge.dataset.previewBackend,
      measurement, retainedEditBar: Boolean(measurement),
      initialAndEditedDocument: true, previewRpcCalls: calls().length,
      subscriptions: subscriptions(), listeners: listeners(), warnings };
  }, [["unmount", () => React.act(() => root.unmount())]]);
}
