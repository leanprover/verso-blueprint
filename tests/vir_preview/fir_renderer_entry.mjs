// Consumer acceptance of FIR's frozen renderer-only host prototype.
import * as React from "react";
import { createRoot } from "react-dom/client";
import { renderToStaticMarkup } from "react-dom/server";
import { createRendererHostPrototype } from "@fir-host-prototype";
import { createBrowserReactHostBindings } from "@vir-react-bindings";
import { createJsCollectionHostBindings } from "@vir-collection-bindings";
import { createJsValueHostBindings } from "@vir-value-bindings";

const check = (value, message) => { if (!value) throw new Error(message); };
const title = 'FIR λ😀 <script>alert("escaped")</script> & title';
const open = (module, manifest) => createRendererHostPrototype({ module, manifest,
  bindings: { ...createJsCollectionHostBindings(), ...createJsValueHostBindings(),
    ...createBrowserReactHostBindings() },
});

function rejectsAfterDisposal(session, callback) {
  for (const call of [() => session.renderDocument("disposed"), () => callback({})]) {
    let rejected = false;
    try { call(); } catch (error) { rejected = /disposed/.test(error.message); }
    check(rejected, "call after disposal was not rejected");
  }
}

export async function runSsr(module, manifest) {
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
      updates: 20, retainedCallback: true, postDisposalRejected: true, html };
  } finally { session.dispose(); }
}

export async function runBrowser() {
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  const module = await WebAssembly.compile(await (await fetch("/renderer.wasm")).arrayBuffer());
  const manifest = await (await fetch("/manifest.json")).json();
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
      unmountBeforeDispose: true, postDisposalRejected: true, noReactWarnings: true,
      scope: "Lean-built title-only document; no body blocks, controls, RPC, or timing claim" };
  } finally {
    try { if (root) await React.act(() => root.unmount()); }
    finally { session.dispose(); console.error = originalError; console.warn = originalWarn; }
  }
}
