/* Copyright (c) 2026 Lean FRO LLC. Released under Apache 2.0. */

import * as React from "react";
import { createRoot } from "react-dom/client";
import { EditorContext } from "@leanprover/infoview";
import Widget from "@vir-embedded-shell";
import { describeError, withCleanup } from "@vir-test-support";

const check = (value, message) => { if (!value) throw new Error(message); };
const sha256 = async bytes => [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
  .map(x => x.toString(16).padStart(2, "0")).join("");

// The shared entry owns official RpcSessions and the real LSP transport. This
// campaign uses the exact generated shell embedded in Lean's Widget.Module.
export async function runEmbeddedAcceptance({ config, a, b, editor, emit, requests,
  warnings, subscriptions, listeners }) {
  const container = document.getElementById("app");
  const root = createRoot(container);
  const previewCalls = () => requests.filter(r =>
    r.method === "VersoBlueprint.Experimental.VirPreview.Server.previewDocument");
  const packageCalls = () => requests.filter(r => r.method === "Lean.Vir.Infoview.buildIRPackage");
  const panel = () => document.getElementById("vir-verso-preview");
  const checkbox = () => document.getElementById("vir-verso-highlight-changes");
  const version = () => Number(panel()?.dataset.versoVersion);
  const waitFor = async (label, predicate) => {
    // Every asynchronous wait is inside act; inspect the DOM after its flush.
    for (let attempt = 0; attempt < 2000; attempt++) {
      await React.act(async () => { await new Promise(resolve => setTimeout(resolve, 10)); });
      const error = container.querySelector('[data-vir-infoview-state="error"]');
      if (error) throw new Error(error.textContent);
      if (panel()?.dataset.versoPreviewStatus === "error")
        throw new Error(`${panel().textContent}: ${JSON.stringify(describeError(previewCalls().at(-1)?.error))}`);
      if (predicate()) return;
    }
    throw new Error(`Embedded preview condition timed out: ${label}`);
  };
  return withCleanup(async () => {
    // Read the actual panel registration, rather than duplicating its props here.
    const { widgets } = await a.call("Lean.Widget.getWidgets", config.a);
    const registered = widgets.find(w => w.id === "Lean.Vir.Infoview.widget");
    check(registered, "native show_panel_widgets registration missing");
    const { sourcetext } = await a.call("Lean.Widget.getWidgetSource", {
      hash: registered.javascriptHash, pos: config.a,
    });
    const hash = await sha256(new TextEncoder().encode(sourcetext));
    check(hash === VBP_EMBEDDED_SHELL_SHA256, "browser shell differs from registered Widget.Module");
    check(registered.props.autoReloadMs === 0, "fixture must not poll runtime assets");
    const render = (session, position) => {
      globalThis.__vbpEmbeddedSession = session;
      return React.act(async () => root.render(
        React.createElement(EditorContext.Provider, { value: editor },
          React.createElement(Widget, { ...registered.props, pos: { uri: config.uri, ...position } }))));
    };
    await render(a, config.a);
    await waitFor("embedded preview ready", () => version() === 1 &&
      container.querySelector('[data-vir-infoview-state="ready"]'));
    for (const content of ["A live Blueprint document", "An informal statement with inline math",
      "This proof body remains visible", "External Markdown markup (summary)"])
      check(panel().textContent.includes(content), `real Blueprint content missing: ${content}`);
    for (const kind of ["Statement", "Proof"])
      check(panel().querySelector(`[data-verso-informal-kind="${kind}"]`),
        `Blueprint statement/proof facet missing: ${kind}`);
    check(!panel().querySelector('[data-verso-kind="unsupported-extension"]'),
      "the real Blueprint fixture contains an unsupported or malformed block");
    check(packageCalls().length === 1, "shell did not build one live snapshot package");
    const asset = requests.find(r => r.method === "Lean.Vir.Infoview.readAsset")?.value;
    check(asset?.dataBase64, "shell did not read WASM through the asset RPC");
    const wasmHash = await sha256(Uint8Array.from(atob(asset.dataBase64), c => c.charCodeAt(0)));
    check(wasmHash === VBP_WASM_SHA256, "server-loaded WASM differs from the pinned SDK");
    const retained = checkbox();
    React.act(() => retained.click());
    React.act(() => document.getElementById("vir-verso-debug").click());
    React.act(() => document.getElementById("vir-verso-debug-disclosure").click());
    const beforeUnchanged = previewCalls().length;
    await render(a, config.a);
    await React.act(async () => { await new Promise(resolve => setTimeout(resolve, 30)); });
    check(previewCalls().length === beforeUnchanged, "unchanged shell render restarted the RPC");
    check(subscriptions() === 1 && listeners() === 1, "embedded editor bridge lacks one subscription");

    const changedResponse = await fetch("/edit", { method: "POST", body: "{}" });
    const { result: changed, error } = await changedResponse.json();
    if (error) throw error;
    React.act(() => emit("textDocument/didChange", changed));
    await waitFor("embedded same-position edit", () => version() === changed.textDocument.version);
    check(panel().textContent.includes(`browser edit ${changed.textDocument.version}`),
      "edited source text did not reach the preview document");
    check(checkbox() === retained && retained.checked,
      "embedded edit lost checkbox identity or state");
    check(document.getElementById("vir-verso-debug-disclosure").getAttribute("aria-expanded") === "true",
      "embedded edit lost disclosure state");
    check(packageCalls().length === 1, "document edit regenerated the client package");

    await render(b, config.b);
    await waitFor("embedded cursor refresh", () => panel()?.dataset.versoCorrelationId ===
      `${changed.textDocument.version}:${config.b.line}:${config.b.character}`);
    check(checkbox() === retained && retained.checked, "cursor movement remounted controls");
    check(packageCalls().length === 1, "cursor movement regenerated the client package");
    await React.act(async () => root.render(null));
    await waitFor("embedded unmount cleanup", () => subscriptions() === 0 && listeners() === 0);
    check(!panel(), "embedded unmount retained the preview DOM");
    return {
      registeredWidgetModule: true, shellSha256: hash, wasmSha256: wasmHash, liveSnapshotPackage: true,
      workspaceAssetRpc: true, editorContextBridge: true, samePositionEdit: true,
      liveBlueprintDocument: true, editedSourceRendered: true,
      retainedControls: true, cursorRefresh: true, unchangedInputNoRpc: true,
      clientPackageBuilds: packageCalls().length, previewRequests: previewCalls().length,
      unmountUnsubscribes: true, noReactWarnings: warnings.length === 0, warnings,
      scope: "standard embedded shell and real Lean RPC; test editor forwards edits after diagnostics, not VS Code",
    };
  }, [
    ["embedded React root", () => React.act(async () => root.unmount())],
    ["pending shell requests", () => waitFor("shell requests settled", () => requests.every(r => r.settled))],
  ]);
}
