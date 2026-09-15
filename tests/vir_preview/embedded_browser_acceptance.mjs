/* Copyright (c) 2026 Lean FRO LLC. Released under Apache 2.0. */

import * as React from "react";
import { checkMathLifecycle } from "./katex_acceptance.mjs";
import { createRoot } from "react-dom/client";
import { EditorContext } from "@leanprover/infoview";
import Widget from "@vir-embedded-shell";
import { describeError, withCleanup } from "@vir-test-support";

const check = (value, message) => { if (!value) throw new Error(message); };
const sha256 = async bytes => [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
  .map(x => x.toString(16).padStart(2, "0")).join("");

// The shared entry owns official RpcSessions and the real LSP transport. This
// campaign uses the exact generated shell embedded in Lean's Widget.Module.
export async function runEmbeddedAcceptance({ config, a, b, sessionAt, editor, emit, requests,
  warnings, subscriptions, listeners }) {
  const container = document.getElementById("app");
  const root = createRoot(container);
  const previewCalls = () => requests.filter(r =>
    r.method === "CheckedJsonPreview.Server.previewDocument");
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
    const registered = widgets.find(w => w.id === "CheckedJsonPreview.widget");
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
    check(!document.getElementById("vir-verso-server-timings") &&
      !document.getElementById("vir-verso-debug").checked,
      "live server timing must stay hidden outside debug mode");
    const retained = checkbox();
    React.act(() => retained.click());
    React.act(() => document.getElementById("vir-verso-debug").click());
    const measuredBar = () => {
      const bar = document.getElementById("vir-verso-server-bar");
      check(bar, "live server response has no timing bar");
      const phases = [...bar.querySelectorAll("[data-verso-phase]")];
      const total = Number(bar.dataset.versoTotalNanos);
      check([3, 8, 9].includes(phases.length) && total > 0 && phases.reduce((sum, phase) =>
        sum + Number(phase.dataset.versoNanos), 0) === total,
      "live server phases do not partition preparation time");
      return total;
    };
    const initialTotal = measuredBar();
    const beforeScale = previewCalls().length;
    React.act(() => {
      const scale = document.getElementById("vir-verso-timing-scale");
      scale.value = "100";
      scale.dispatchEvent(new Event("change", { bubbles: true }));
    });
    check(previewCalls().length === beforeScale && measuredBar() === initialTotal &&
      document.getElementById("vir-verso-server-bar").dataset.versoTickMs === "100",
      "time scale change must reuse the measured response without an RPC");
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
    check(document.getElementById("vir-verso-debug").checked,
      "embedded edit lost debug option");
    measuredBar();
    check(document.querySelectorAll('#vir-verso-server-bar [data-verso-phase]').length === 9,
      "accepted edit did not publish the full server/browser timing partition");
    check(document.getElementById("vir-verso-server-timings").textContent.includes("Edit notification → content effect"),
      "accepted edit timing omitted its notification boundary");
    check(document.getElementById("vir-verso-timing-scale").value === "100",
      "document edit reset timing scale");
    check(packageCalls().length === 1, "document edit regenerated the client package");

    await render(b, config.b);
    await waitFor("embedded cursor refresh", () => panel()?.dataset.versoCorrelationId ===
      `${changed.textDocument.version}:${config.b.line}:${config.b.character}`);
    check(checkbox() === retained && retained.checked, "cursor movement remounted controls");
    await waitFor("cursor-only timing", () => document.getElementById("vir-verso-server-timings")?.textContent.includes("RPC → content effect"));
    check(!document.querySelector('#vir-verso-server-bar [data-verso-phase="dispatch"]'),
      "cursor-only RPC reused an earlier edit notification timestamp");
    check(packageCalls().length === 1, "cursor movement regenerated the client package");

    // Move through real source blocks using the same official position-specific
    // sessions as the infoview. No synthetic focus field or replacement RPC.
    const source = await (await fetch("/blueprint-source")).text();
    const positionOf = text => {
      const offset = source.indexOf(text);
      check(offset >= 0, `source anchor missing: ${text}`);
      const before = source.slice(0, offset).split("\n");
      return { line: before.length - 1, character: before.at(-1).length };
    };
    const focused = () => [...panel().querySelectorAll('[data-verso-focus="cursor"]')];
    const listRegistrations = [];
    for (const anchor of ["* A preview list item", "A preview list item", "* A nested preview",
      "A nested preview", "1. An ordered preview", "An ordered preview"]) {
      const position = positionOf(anchor);
      const found = await sessionAt(position).call("Lean.Widget.getWidgets", position);
      listRegistrations.push({ anchor, present: found.widgets.some(w => w.id === "CheckedJsonPreview.widget") });
    }
    check(listRegistrations.every(x => x.present), `list registrations: ${JSON.stringify(listRegistrations)}`);
    const moveTo = async position => {
      await render(sessionAt(position), position);
      await waitFor("source focus refresh", () => panel()?.dataset.versoCorrelationId ===
        `${changed.textDocument.version}:${position.line}:${position.character}`);
    };
    check(focused().length === 0, "Lean code before #doc must not focus a document block");
    for (const { anchor } of listRegistrations) {
      await moveTo(positionOf(anchor));
      check(panel() && checkbox() === retained && retained.checked && packageCalls().length === 1,
        `list cursor move lost the retained preview: ${anchor}`);
    }
    const statement = positionOf("An informal statement with inline math");
    const proof = positionOf("This proof body remains visible");
    const atStatement = await sessionAt(statement).call("Lean.Widget.getWidgets", statement);
    check(atStatement.widgets.some(w => w.id === "CheckedJsonPreview.widget"),
      "panel registration is unavailable inside the real Blueprint statement");
    await moveTo(statement);
    check(focused().length === 1 && focused()[0].textContent.includes("An informal statement"),
      `statement source position did not select the rendered statement: ${JSON.stringify({
        panel: panel().dataset, focused: focused().map(node => ({
          path: node.dataset.versoBlock, text: node.textContent.slice(0, 120),
        })),
      })}`);
    const statementPath = focused()[0].dataset.versoBlock;
    await moveTo(proof);
    check(focused().length === 1 && focused()[0].textContent.includes("This proof body"),
      "proof source position did not select the rendered proof");
    check(focused()[0].dataset.versoBlock !== statementPath, "focus did not change blocks");
    const follow = document.getElementById("vir-verso-follow-cursor");
    React.act(() => follow.click());
    check(!follow.checked && focused().length === 0, "disabled follow retained focus");
    await moveTo(statement);
    check(document.getElementById("vir-verso-follow-cursor") === follow &&
      !follow.checked && focused().length === 0, "cursor movement reset disabled follow");
    const beforeFollow = previewCalls().length;
    React.act(() => follow.click());
    check(follow.checked && focused().length === 1 &&
      focused()[0].dataset.versoBlock === statementPath, "reenabling follow missed latest cursor");
    check(previewCalls().length === beforeFollow, "follow toggle restarted RPC");
    await moveTo(positionOf("# A live Blueprint document"));
    check(focused().length === 1 && focused()[0].textContent.includes("A live Blueprint document"),
      "heading source position did not select the rendered heading");
    await moveTo(config.a);
    check(focused().length === 0, "leaving the document retained stale focus");
    check(checkbox() === retained && retained.checked && packageCalls().length === 1,
      "source navigation remounted controls or regenerated the client package");
    check(panel().querySelector(".katex math"), "live Blueprint math was not typeset");
    const math = checkMathLifecycle();
    await React.act(async () => root.render(null));
    await waitFor("embedded unmount cleanup", () => subscriptions() === 0 && listeners() === 0);
    check(!panel(), "embedded unmount retained the preview DOM");
    return {
      registeredWidgetModule: true, shellSha256: hash, wasmSha256: wasmHash, liveSnapshotPackage: true,
      listRegistrations, math, fullChainTimingBar: true,
      workspaceAssetRpc: true, editorContextBridge: true, samePositionEdit: true,
      liveBlueprintDocument: true, editedSourceRendered: true, measuredServerTimingBar: true,
      debugOnlyTiming: true, scaleChangeNoRpc: true, retainedScale: true,
      retainedControls: true, cursorRefresh: true, unchangedInputNoRpc: true,
      realSourceFocus: true, sourceHeadingFocus: true, outsideDocumentClearsFocus: true,
      disabledFollowRetained: true, reenabledFollowUsesLatestCursor: true,
      automaticScrolling: "pending a public VIR DOM scrolling binding",
      clientPackageBuilds: packageCalls().length, previewRequests: previewCalls().length,
      unmountUnsubscribes: true, noReactWarnings: warnings.length === 0, warnings,
      scope: "standard embedded shell and real Lean RPC; test editor forwards edits after diagnostics, not VS Code",
    };
  }, [
    ["embedded React root", () => React.act(async () => root.unmount())],
    ["pending shell requests", () => waitFor("shell requests settled", () => requests.every(r => r.settled))],
  ]);
}
