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
    throw Error("matched preview timeout");
  };
  return withCleanup(async () => {
    const { widgets } = await a.call("Lean.Widget.getWidgets", config.a);
    const registered = widgets.find(w => w.id === (VBP_MATCHED_FLT_PREVIEW
      ? "FLTBlueprint.MatchedDemo.selectedWidget" : "MatchedPreview.Demo.selectedWidget"));
    check(registered, "matched panel registration missing");
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
    for (const text of VBP_MATCHED_FLT_PREVIEW ? ["Fermat's Last Theorem", "Diophantine"]
      : ["A live Blueprint document", "An informal statement with inline math", "This proof body remains visible"])
      check(panel().textContent.includes(text), `missing ${text}`);
    check(!document.querySelector(".katex"), "matched source-display mode unexpectedly uses KaTeX");
    const follow = document.getElementById("vir-verso-follow-cursor");
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
    check(document.getElementById("vir-verso-follow-cursor") === follow && follow.checked === selected,
      "edit reset controls");
    await render(b, config.b);
    await wait(() => calls().at(-1)?.settled);
    check(document.getElementById("vir-verso-follow-cursor") === follow && follow.checked === selected,
      "cursor update reset controls");
    check(requests.filter(r => r.method === "Lean.Vir.Infoview.buildIRPackage").length === 1,
      "edit or cursor update rebuilt client package");
    return { registeredWidget: registered.id, shellSha256: hash, retainedControl: true,
      initialAndEditedDocument: true, previewRpcCalls: calls().length,
      subscriptions: subscriptions(), listeners: listeners(), warnings };
  }, [["unmount", () => React.act(() => root.unmount())]]);
}
