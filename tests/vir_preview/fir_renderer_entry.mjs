// Consumer acceptance of FIR's frozen renderer-only host prototype.
import * as React from "react";
import { createRoot } from "react-dom/client";
import { renderToStaticMarkup } from "react-dom/server";
import * as prototype from "@fir-host-prototype";
import { createBrowserReactHostBindings } from "@vir-react-bindings";
import { createJsCollectionHostBindings } from "@vir-collection-bindings";
import { createJsValueHostBindings } from "@vir-value-bindings";

const check = (value, message) => { if (!value) throw new Error(message); };
const title = 'FIR λ😀 <script>alert("escaped")</script> & title';
export const open = (module, manifest, overrides = {}) =>
  (WebAssembly.Module.imports(module).length === 13
    ? prototype.createCurrentRendererHostPrototype : prototype.createRendererHostPrototype)({ module, manifest,
  bindings: { ...createJsCollectionHostBindings(), ...createJsValueHostBindings(),
    ...createBrowserReactHostBindings(), ...overrides },
});

export async function checkErrorRecovery(module, manifest) {
  const react = createBrowserReactHostBindings();
  const marker = { reason: "provider failure after retaining callback" };
  let escaped;
  const session = await open(module, manifest, {
    "js.value.react.callback": (...args) => {
      escaped = react["js.value.react.callback"](...args);
      throw marker;
    },
  });
  try {
    let caught;
    try { session.retainedCallback("survives provider error"); } catch (error) { caught = error; }
    check(caught === marker, "provider error identity was lost");
    check(!session.stats().disposed, "ordinary provider error disposed session");
    const target = {};
    escaped(target);
    check(target.answer === "survives provider error", "escaped callback was revoked");
    check(React.isValidElement(session.renderDocument("After provider error")), "renderer did not recover");
    session.dispose();
    rejectsAfterDisposal(session, escaped);
  } finally { session.dispose(); }
}

function rejectsAfterDisposal(session, callback) {
  for (const call of [() => session.renderDocument("disposed"), () => callback({})]) {
    let rejected = false;
    try { call(); } catch (error) { rejected = /disposed/.test(error.message); }
    check(rejected, "call after disposal was not rejected");
  }
}

export async function runSsr(module, manifest) {
  await checkErrorRecovery(module, manifest);
  const session = await open(module, manifest);
  try {
    const node = session.renderDocument(title);
    check(React.isValidElement(node), "FIR did not return a real React element");
    const html = renderToStaticMarkup(node);
    for (const fragment of ['<article', 'data-verso-version="7"',
      'data-verso-correlation-id="fir-prototype"', 'FIR λ😀', '&lt;script&gt;', '&amp; title']) {
      check(html.includes(fragment), `missing SSR output: ${fragment}`);
    }
    check(!html.includes("<script>"), "unsafe unescaped title");
    const callback = session.retainedCallback("retained λ😀");
    for (let index = 0; index < 20; index++) {
      renderToStaticMarkup(session.renderDocument(`Update ${index}`));
      const target = {};
      callback(target);
      check(target.answer === "retained λ😀", "callback lost captured value");
    }
    session.dispose();
    rejectsAfterDisposal(session, callback);
    return { realReact: true, escapedTitle: true, metadata: true,
      updates: 20, retainedCallback: true, postDisposalRejected: true, errorRecovery: true, html };
  } finally { session.dispose(); }
}

export async function runBrowser() {
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  const module = await WebAssembly.compile(await (await fetch("/renderer.wasm")).arrayBuffer());
  const manifest = await (await fetch("/manifest.json")).json();
  await checkErrorRecovery(module, manifest);
  const session = await open(module, manifest);
  const warnings = [];
  const originalError = console.error, originalWarn = console.warn;
  console.error = console.warn = (...args) => warnings.push(args.map(String).join(" "));
  let root;
  try {
    const container = document.getElementById("app");
    root = createRoot(container);
    const render = value => React.act(() => root.render(
      React.createElement(React.StrictMode, null, session.renderDocument(value))));
    await render(title);
    const article = container.querySelector("article");
    const heading = article?.querySelector("h1, h2, h3, h4, h5, h6");
    check(article && heading, "missing actual renderer article/heading");
    check(heading.textContent === title && !container.querySelector("script"), "title was not escaped");
    check(article.dataset.versoVersion === "7" &&
      article.dataset.versoCorrelationId === "fir-prototype", "missing document metadata");
    const callback = session.retainedCallback("browser callback λ😀");
    for (let index = 0; index < 20; index++) {
      await render(`Update ${index}`);
      check(container.querySelector("article") === article, "update replaced article DOM");
      check(article.querySelector("h1, h2, h3, h4, h5, h6") === heading,
        "update replaced heading DOM");
      check(heading.textContent === `Update ${index}`, "title update was lost");
      const target = {};
      callback(target);
      check(target.answer === "browser callback λ😀", "retained callback failed after update");
    }
    await render("Update 19");
    check(article.isConnected && heading.isConnected, "unchanged render replaced DOM");
    await React.act(() => root.unmount());
    root = null;
    check(container.childNodes.length === 0, "React unmount did not finish");
    const finalTarget = {};
    callback(finalTarget);
    check(finalTarget.answer === "browser callback λ😀", "unmount prematurely disposed session");
    session.dispose();
    rejectsAfterDisposal(session, callback);
    check(warnings.length === 0, `React warnings: ${warnings.join("\n")}`);
    return { realReact: true, strictModeWrapper: true, updates: 20,
      retainedArticleAndHeading: true, escapedTitle: true, retainedCallback: true,
      unmountBeforeDispose: true, postDisposalRejected: true, noReactWarnings: true, errorRecovery: true,
      scope: "Lean-built title-only document; no body blocks, controls, RPC, or timing claim" };
  } finally {
    try { if (root) await React.act(() => root.unmount()); }
    finally { session.dispose(); console.error = originalError; console.warn = originalWarn; }
  }
}

// Interactive shell only: the preview nodes still come from compiled Lean.
// Runtime ownership is outside React; unmount completes before disposal.
export async function mountDemo() {
  const module = await WebAssembly.compile(await (await fetch("/renderer.wasm")).arrayBuffer());
  const manifest = await (await fetch("/manifest.json")).json();
  const session = await open(module, manifest);
  const initialTitle = "A small FIR preview — edit this title";
  let initialNode, callback, root;
  try {
    initialNode = session.renderDocument(initialTitle);
    callback = session.retainedCallback("The retained Lean callback is alive.");
    root = createRoot(document.getElementById("app"));
  } catch (error) { session.dispose(); throw error; }
  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    try { root.unmount(); } finally { session.dispose(); }
    window.removeEventListener("pagehide", close);
    document.getElementById("status").textContent = "Preview unmounted; FIR session disposed. Reload to reopen.";
  };
  function Demo() {
    const [view, setView] = React.useState({ title: initialTitle, node: initialNode, updates: 0, message: "" });
    const change = event => {
      const title = event.target.value;
      try {
        const node = session.renderDocument(title);
        setView(previous => ({ title, node, updates: previous.updates + 1, message: "" }));
      } catch (error) { setView(previous => ({ ...previous, message: String(error) })); }
    };
    const invoke = () => {
      try {
        const target = {};
        callback(target);
        setView(previous => ({ ...previous, message: target.answer }));
      } catch (error) { setView(previous => ({ ...previous, message: String(error) })); }
    };
    return React.createElement(React.Fragment, null,
      React.createElement("label", null, "Document title",
        React.createElement("input", { id: "fir-demo-title", value: view.title, onChange: change })),
      React.createElement("button", { id: "fir-demo-callback", onClick: invoke }, "Invoke retained callback"),
      React.createElement("button", { id: "fir-demo-close", onClick: close }, "Close preview"),
      React.createElement("p", { id: "fir-demo-state", role: "status" },
        `Updates in this session: ${view.updates}. ${view.message}`),
      React.createElement("div", { id: "fir-demo-preview" }, view.node));
  }
  window.addEventListener("pagehide", close);
  root.render(React.createElement(Demo));
  document.getElementById("status").textContent = "FIR 8ec770fd · Lean 4.34 rc2 · retained session · no timing instrumentation";
}
