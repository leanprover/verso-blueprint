/* Copyright (c) 2026 Lean FRO LLC. Released under Apache 2.0. */

import * as React from "react";
import { createRoot } from "react-dom/client";
import { RpcSessions } from "@leanprover/infoview-api";
import { EditorContext, EditorConnection, useClientNotificationEffect } from "@leanprover/infoview";
import { createVirRuntime } from "lean-vir";
import { createBrowserHostBindings } from "lean-vir/host-bindings";
import { createBrowserReactHostBindings } from "lean-vir/react-host-bindings";
import { describeError, until, withCleanup } from "@vir-test-support";

const stringPreview = VBP_STRING_PREVIEW;
const entry = `VersoBlueprintVirTests.${stringPreview ? "StringPreview" : "NativePreview"}`;
const check = (value, message) => { if (!value) throw new Error(message); };
async function post(path, body) {
  const response = await fetch(path, { method: "POST", body: JSON.stringify(body) });
  const value = await response.json();
  if (value.error) throw value.error;
  return value.result;
}

globalThis.IS_REACT_ACT_ENVIRONMENT = true;
globalThis.rpcAcceptance = run().then(
  value => ({ ok: true, value }), error => ({ ok: false, error: describeError(error) }));

async function run() {
  const config = await (await fetch("/config")).json();
  const requests = [];
  const notifications = new Set();
  const notificationHandlers = new Set();
  let subscriptions = 0;
  const editor = new EditorConnection({
    async subscribeClientNotifications(method) {
      check(method === "textDocument/didChange", "unexpected notification subscription");
      subscriptions++;
    },
    async unsubscribeClientNotifications() { subscriptions--; },
  }, {
    sentClientNotification: {
      on(handler) {
        notificationHandlers.add(handler);
        return { dispose() { notificationHandlers.delete(handler); } };
      },
    },
  });
  const emit = (method, params) => {
    for (const handler of [...notificationHandlers]) handler([method, params]);
  };
  // Delay one genuine edit response after receipt, to test cancellation races.
  const editGate = Promise.withResolvers();
  let holdNextEdit = false, heldEditId;
  const transportErrors = [];
  const warnings = [];
  const originalError = console.error, originalWarn = console.warn;
  console.error = (...args) => { warnings.push(args.map(String).join(" ")); originalError(...args); };
  console.warn = (...args) => { warnings.push(args.map(String).join(" ")); originalWarn(...args); };
  const notify = (path, body) => {
    const pending = post(path, body).catch(error => transportErrors.push(error));
    notifications.add(pending);
    void pending.then(() => notifications.delete(pending));
  };
  let sessions, runtime, root;
  let nextId = 0;
  const unmount = () => {
    if (root) React.act(() => root.unmount());
    root = null;
  };
  return withCleanup(async () => {
    // Only the test transport lives here. Official RpcSessions owns the protocol;
    // the Lean component, not a JavaScript parent, owns effects and request state.
    sessions = new RpcSessions({
      async createRpcSession() { return (await post("/connect", {})).sessionId; },
      closeRpcSession(sessionId) { notify("/close", { sessionId }); },
      release(params) { notify("/release", params); },
      async call(params, options) {
        const record = { id: ++nextId, method: params.method, params: params.params,
          message: params.params.message,
          settled: false, cancelled: false };
        requests.push(record);
        if (holdNextEdit) { heldEditId = record.id; holdNextEdit = false; }
        const pending = post("/call", { id: record.id, params });
        const cancel = () => {
          record.cancelled = true;
          notify("/cancel", { id: record.id });
        };
        options?.abortSignal?.addEventListener("abort", cancel, { once: true });
        if (options?.abortSignal?.aborted) cancel();
        try {
          record.value = await pending;
          return record.value;
        } catch (error) {
          record.error = error;
          throw error;
        } finally {
          record.received = true;
          if (record.id === heldEditId) await editGate.promise;
          options?.abortSignal?.removeEventListener("abort", cancel);
          record.settled = true;
        }
      },
    });
    const sessionAt = position => sessions.connect(
      { textDocument: { uri: config.uri }, position }, config.capabilities);
    const a = sessionAt(config.a), b = sessionAt(config.b);
    check(a === sessionAt(config.a) && a !== b, "official position-session identity");
    if (VBP_EMBEDDED_PREVIEW) {
      const { runEmbeddedAcceptance } = await import("./embedded_browser_acceptance.mjs");
      return await runEmbeddedAcceptance({ config, a, b, editor, emit, requests, warnings,
        subscriptions: () => subscriptions, listeners: () => notificationHandlers.size });
    }
    runtime = await createVirRuntime({
      wasmUrl: "/runtime.wasm", irPackageSet: "/widget.irpkg-set.json",
      defaultHostBindings: () => createBrowserHostBindings({
        reactHostBindings: createBrowserReactHostBindings,
        infoviewUseClientNotificationEffect: useClientNotificationEffect,
      }),
    });
    const method = stringPreview ? "StringPreviewServer.preview" : "RpcBrowserServer.create";
    let view = runtime.call(`${entry}.createComponent`, method);
    root = createRoot(document.getElementById("app"));
    // Keep native parameter identity stable for unchanged requests.
    const parameters = new Map();
    const render = (session, message, fail = false, revision = "0", waitForCancellation = false) => {
      const key = JSON.stringify([message, fail, waitForCancellation]);
      if (!parameters.has(key)) parameters.set(key, { message, fail, waitForCancellation });
      const input = stringPreview
        ? { session, params: parameters.get(key), uri: config.uri, revision }
        : { session, message, fail };
      React.act(() => root.render(React.createElement(React.StrictMode, null,
        React.createElement(EditorContext.Provider, { value: editor },
          runtime.call(`${entry}.render`, view, input)))));
    };
    const status = () => stringPreview
      ? document.getElementById("vir-verso-preview")?.dataset.versoPreviewStatus
      : document.querySelector("[data-preview-status]")?.dataset.previewStatus;
    const text = () => stringPreview
      ? document.getElementById("vir-verso-preview")?.dataset.versoCorrelationId
      : document.getElementById("native-preview-message")?.textContent;
    const checkbox = () => document.getElementById(
      stringPreview ? "vir-verso-highlight-changes" : "native-preview-checkbox");
    // Await transport inside act, then inspect DOM after React flushes. Polling
    // DOM across separate act windows can let response callbacks escape act.
    const settled = message => React.act(async () => {
      await until(`settled ${message}`, () => {
        const matching = requests.filter(r => r.message === message);
        return matching.length > 0 && matching.every(r => r.settled);
      });
    });
    const ready = async message => {
      await settled(message);
      check(status() === "ready" && text() === message, `not rendered: ${message}`);
    };
    const gate = (action, message) => post("/gate", { action, message });
    const gated = message => until(`gated ${message}`, () => gate("status", message));
    const release = message => React.act(async () => {
      await gate("open", message);
      await until(`settled ${message}`, () => requests
        .filter(r => r.message === message).every(r => r.settled));
    });

    render(a, "first preview");
    await ready("first preview");
    if (stringPreview) check(document.getElementById("vir-verso-preview")
      .textContent.includes("first preview"), "decoded Manual document did not render");
    check(requests.filter(r => r.message === "first preview").length === 2,
      "Strict Mode did not replay effect setup");
    const retainedCheckbox = checkbox();
    React.act(() => retainedCheckbox.click());
    check(checkbox().checked, "controlled checkbox did not update");
    const beforeUnchanged = requests.length;
    render(a, "first preview");
    check(requests.length === beforeUnchanged, "unchanged input or checkbox triggered RPC");
    if (stringPreview) {
      const beforeRevision = requests.length;
      render(a, "first preview", false, "1");
      await React.act(async () => {
        await until("explicit revision refresh", () => requests.length > beforeRevision &&
          requests.slice(beforeRevision).every(r => r.settled));
      });
      check(checkbox() === retainedCheckbox && checkbox().checked,
        "revision refresh lost control state");
      const beforeDebug = requests.length;
      React.act(() => document.getElementById("vir-verso-debug").click());
      React.act(() => document.getElementById("vir-verso-debug-disclosure").click());
      check(requests.length === beforeDebug, "debug controls triggered another RPC");

      check(subscriptions === 1 && notificationHandlers.size === 1,
        "Strict Mode leaked editor subscriptions");
      const beforeEdit = requests.length;
      React.act(() => emit("textDocument/didChange", {
        textDocument: { uri: "file:///another.lean", version: 2 }, contentChanges: [],
      }));
      React.act(() => emit("textDocument/didSave", { textDocument: { uri: config.uri } }));
      check(requests.length === beforeEdit, "unrelated notification triggered RPC");

      holdNextEdit = true;
      const changed = await post("/edit", {});
      React.act(() => emit("textDocument/didChange", changed));
      await React.act(async () => {
        await until("first edit response held", () => requests.length === beforeEdit + 1 &&
          requests.at(-1).received);
      });
      const firstEdit = requests.at(-1);
      const changedAgain = await post("/edit", {});
      React.act(() => emit("textDocument/didChange", changedAgain));
      await React.act(async () => {
        await until("second edit response settled", () => requests.length === beforeEdit + 2 &&
          requests.at(-1).settled);
      });
      const version = () => Number(document.getElementById("vir-verso-preview").dataset.versoVersion);
      check(version() === changedAgain.textDocument.version && status() === "ready",
        "same-position edit did not render the new server document version");
      await React.act(async () => {
        editGate.resolve();
        await until("obsolete edit delivered", () => firstEdit.settled);
      });
      check(firstEdit.cancelled && typeof firstEdit.value === "string" &&
        version() === changedAgain.textDocument.version,
        "cancelled edit response overwrote its successor");
      check(checkbox() === retainedCheckbox && checkbox().checked &&
        document.getElementById("vir-verso-debug-disclosure").getAttribute("aria-expanded") === "true",
        "editor refresh lost controls or disclosure state");

      render(a, "wait for cancellation", false, "0", true);
      await until("cancellable request started", () => post("/started", { message: "wait for cancellation" }));
      render(a, "after cancellation");
      await ready("after cancellation");
      await settled("wait for cancellation");
      const cancelled = requests.find(r => r.message === "wait for cancellation");
      check(cancelled?.cancelled && cancelled.error?.code === -32800 &&
        status() === "ready", "cleanup did not reach Lean's cancellation token");
    }

    render(a, "second preview");
    await ready("second preview");
    check(checkbox() === retainedCheckbox && checkbox().checked,
      "response update remounted checkbox or lost state");
    const beforeSession = requests.length;
    render(b, "second preview");
    await React.act(async () => {
      await until("session refresh settled", () => requests.length > beforeSession &&
        requests.slice(beforeSession).every(r => r.settled));
    });
    check(checkbox() === retainedCheckbox && checkbox().checked,
      "session change reset React state");

    render(b, "server rejection", true);
    await settled("server rejection");
    check(status() === "error", "missing visible RPC error");
    check((stringPreview || text() === "second preview") && checkbox().checked,
      "error lost expected response or checkbox state");
    if (stringPreview) {
      for (const malformed of ["malformed JSON", "wrong schema"]) {
        render(b, malformed);
        await settled(malformed);
        check(status() === "error" && document.getElementById("vir-verso-preview")
          .textContent.includes("Invalid preview response"), "missing visible decode error");
        check(checkbox() === retainedCheckbox && checkbox().checked,
          "decode error remounted controls");
        check(document.getElementById("vir-verso-debug-disclosure")
          .getAttribute("aria-expanded") === "true", "decode error reset disclosure");
      }
    }

    // Delay actual server outcomes after completion, not replacement mock replies.
    for (const [old, fail] of [["late success", false], ["late failure", true],
      ...(stringPreview ? [["malformed JSON", false]] : [])]) {
      const fresh = `newer than ${old}`;
      const previousText = text(), previousStatus = status();
      await gate("arm", old);
      render(a, old, fail);
      await gated(old);
      if (stringPreview) check(text() === previousText && status() === previousStatus,
        "pending refresh replaced the last accepted preview");
      render(a, fresh);
      await ready(fresh);
      await release(old);
      check(text() === fresh && status() === "ready" && checkbox().checked,
        `${old} overwrote the current preview`);
      if (stringPreview) check(requests.findLast(r => r.message === old).cancelled,
        `${old} was not aborted`);
    }

    await gate("arm", "unmounted request");
    render(a, "unmounted request");
    await gated("unmounted request");
    unmount();
    await release("unmounted request");
    check(!checkbox(), "late callback remounted an unmounted component");
    if (stringPreview) {
      check(requests.find(r => r.message === "unmounted request").cancelled,
        "unmount did not abort pending request");
      check(subscriptions === 0 && notificationHandlers.size === 0,
        "unmount leaked editor subscriptions");
    }
    root = createRoot(document.getElementById("app"));
    render(b, "new session lifetime");
    await ready("new session lifetime");
    check(!checkbox().checked, "intentional remount did not reset local state");
    if (stringPreview) {
      view = runtime.call(`${entry}.createComponent`, "StringPreviewServer.wrongType");
      render(b, "non-string response");
      await settled("non-string response");
      check(status() === "error", "missing checked string conversion error");
    }
    unmount();
    // Aborting does not settle every already-completed reply. Pending callbacks
    // must finish before explicit runtime disposal ends their Lean lifetime.
    await React.act(async () => {
      await until("all requests settled before runtime disposal",
        () => requests.every(r => r.settled));
    });
    runtime.dispose();
    let rejected = false;
    try { runtime.call(`${entry}.createComponent`, "RpcBrowserServer.create"); }
    catch { rejected = true; }
    check(rejected, "explicit runtime disposal allowed another call");
    runtime = null;
    check(warnings.length === 0, `React/browser warnings: ${warnings.join("\n")}`);
    return {
      requests: requests.length, strictModeReplay: true, unchangedInputNoRpc: true,
      retainedCheckbox: true, retainedDomIdentity: true, sessionRefresh: true,
      serverError: true, staleSuccessSuppressed: true, staleErrorSuppressed: true,
      lateUnmountSuppressed: true, intentionalRemountResets: true,
      postDisposalRejected: true,
      noReactWarnings: true,
      transportCancellation: stringPreview ? "Lean cancellation token observed (-32800)"
        : "not exercised: scalar baseline uses call",
      editorDidChange: stringPreview ? "two real LSP edits; server version rendered at unchanged cursor"
        : "not exercised: explicit input updates only",
      ...(stringPreview ? {
        fullPreviewStringRpc: true, invalidJson: true, invalidSchema: true,
        nonStringRejected: true, staleMalformedSuppressed: true, explicitRevisionRefresh: true,
        pendingRefreshRetainsPreview: true,
        unrelatedNotificationsIgnored: true, staleEditSuppressed: true,
        editorSubscriptionsCleaned: true, retainedControlsAcrossEdits: true,
      } : {}),
    };
  }, [
    ["edit response gate", () => editGate.resolve()],
    ["React root", unmount],
    ["VIR runtime", () => runtime?.dispose()],
    ["RPC sessions", () => sessions?.dispose()],
    ["RPC notifications", async () => {
      await Promise.all(notifications);
      check(transportErrors.length === 0, `transport errors: ${transportErrors.map(String)}`);
    }],
    ["console", () => { console.error = originalError; console.warn = originalWarn; }],
  ]);
}
