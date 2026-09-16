// Same existing Document codec and default renderer on both engines. No timings.
import * as React from "react";
import { createRoot } from "react-dom/client";
import { renderToStaticMarkup } from "react-dom/server";
import { createVirRuntime } from "lean-vir";
import { createBrowserHostBindings } from "lean-vir/host-bindings";
import { createBrowserReactHostBindings } from "@vir-react-bindings";
import { open as openFir, checkErrorRecovery } from "./fir_renderer_entry.mjs";

const entry = "VersoBlueprintVirTests.Renderer";
const check = (ok, message) => { if (!ok) throw Error(message); };
const invalid = ["{", "{}", "null", '{"document":false}'];
const openVir = options => createVirRuntime({ ...options,
  defaultHostBindings: () => createBrowserHostBindings({ reactHostBindings: createBrowserReactHostBindings }),
});
const renderer = runtime => input => runtime.call(`${entry}.renderDocumentJson`, input);
function rejects(render) {
  for (const input of invalid) {
    let rejected = false;
    try { render(input); } catch { rejected = true; }
    check(rejected, `malformed Document accepted: ${input}`);
  }
}
function richOutput(html) {
  for (const fragment of ["retained proof body", 'data-verso-informal-label="independent"',
    'data-verso-informal-kind="Proof"', 'data-verso-external-markup-display="summary"',
    'data-verso-external-markup-display="source"', "&lt;script&gt;raw source&lt;/script&gt;",
    "[malformed informal block:", "[malformed external markup block:", "[malformed math extension:",
    "malformed child", "unsupported child", "Consumer.unsupported", 'data-bp-tex-prelude=',
    "bp_math", "<ul", "<ol", 'start="3"', "<dl", "<blockquote", "strong text", "λ😀"])
    check(html.includes(fragment), `missing rich output: ${fragment}`);
  check(!html.includes("<script>") && !html.includes("not rendered") &&
    !html.includes('data-verso-external-markup-display="hidden"'), "escaping/hidden markup regression");
}

export async function runSsr({ firModule, manifest, wasmBytes, irPackageSet, flt }) {
  const vir = await openVir({ wasmBytes, irPackageSet });
  let fir;
  try {
    fir = await openFir(firModule, manifest);
    const renderVir = renderer(vir), renderFir = input => fir.renderDocumentJson(input);
    // Actual Lean Document.encode generates shared fixture bytes, not a JS schema.
    const inputs = [vir.call(`${entry}.encoded`, false), vir.call(`${entry}.encoded`, true)];
    check(inputs.every(input => typeof input === "string"), "encoded export did not return Strings");
    const html = [];
    for (const [index, input] of [...inputs, ...flt].entries()) {
      console.log(`SSR document ${index + 1}: FIR`);
      const candidate = renderToStaticMarkup(renderFir(input));
      console.log(`SSR document ${index + 1}: VIR`);
      const control = renderToStaticMarkup(renderVir(input));
      check(candidate === control, `SSR differs for document ${index}`);
      if (index < 2) richOutput(candidate);
      html.push(candidate);
    }
    rejects(renderFir); rejects(renderVir);
    check(renderToStaticMarkup(renderFir(inputs[0])) === renderToStaticMarkup(renderVir(inputs[0])),
      "recovery after invalid input differs");
    await checkErrorRecovery(firModule, manifest);
    // The provider-error gate above covers escaping callback ownership. Exercise
    // the JSON renderer's own provider edge too, using one ordinary exception.
    const marker = { reason: "JSON renderer provider exception" };
    const bindings = createBrowserReactHostBindings();
    let fail = true;
    const broken = await openFir(firModule, manifest, {
      "react.node.createElement": (...args) => {
        if (fail) throw marker;
        return bindings["react.node.createElement"](...args);
      },
    });
    try {
      let caught;
      try { broken.renderDocumentJson(inputs[0]); } catch (error) { caught = error; }
      check(caught === marker && !broken.stats().disposed, "JSON provider error identity/session lost");
      fail = false;
      check(renderToStaticMarkup(broken.renderDocumentJson(inputs[0])) === html[0], "JSON provider recovery failed");
    } finally { broken.dispose(); }
    return { inputs, html, report: { matchedDocuments: html.length, exactSsrEquality: true,
      compiledDocumentCodec: true, malformedInputsPerBackend: invalid.length,
      postErrorRecovery: true, firProviderErrorIdentity: true, noTimings: true } };
  } finally { fir?.dispose(); vir.dispose(); }
}

export async function runBrowser() {
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  const [module, manifest, inputs, flt] = await Promise.all([
    fetch("/renderer.wasm").then(r => r.arrayBuffer()).then(WebAssembly.compile),
    fetch("/manifest.json").then(r => r.json()), fetch("/inputs.json").then(r => r.json()),
    Promise.all(["before", "after"].map(name => fetch(`/${name}.document.json`).then(r => r.text()))),
  ]);
  const warnings = [], original = console.error;
  console.error = (...args) => { warnings.push(args.map(String).join(" ")); original(...args); };
  const snapshots = {};
  try {
    for (const backend of ["fir", "vir"]) {
      const runtime = backend === "fir" ? await openFir(module, manifest)
        : await openVir({ wasmUrl: "/runtime.wasm", irPackageSet: "/control.irpkg-set.json" });
      const render = backend === "fir" ? input => runtime.renderDocumentJson(input) : renderer(runtime);
      let root;
      const container = document.getElementById("app");
      try {
        root = createRoot(container);
        const update = input => React.act(() => root.render(render(input)));
        update(inputs[0]);
        richOutput(container.innerHTML);
        const article = container.querySelector("article"), details = container.querySelector("details");
        check(article && details && !details.open, `${backend}: missing closed details`);
        details.querySelector("summary").click();
        check(details.open, `${backend}: summary did not open details`);
        const callback = backend === "fir" ? runtime.retainedCallback("retained through rich updates") : null;
        for (let i = 0; i < 6; i++) {
          update(inputs[(i + 1) % 2]);
          check(container.querySelector("article") === article &&
            container.querySelector("details") === details && details.open,
          `${backend}: update lost document/details identity or open state`);
          if (callback) { const target = {}; callback(target); check(target.answer === "retained through rich updates", "callback failed"); }
        }
        rejects(render);
        update(inputs[1]);
        check(details.isConnected && details.open, `${backend}: invalid inputs damaged retained details`);
        details.open = false;
        snapshots[backend] = [container.innerHTML];
        for (const input of flt) {
          update(input);
          check(container.querySelector("article") && container.textContent.includes("Fermat"), `${backend}: full FLT missing`);
          snapshots[backend].push(container.innerHTML);
        }
        await React.act(() => root.unmount()); root = null;
        check(container.childNodes.length === 0, `${backend}: unmount incomplete`);
        runtime.dispose();
        let rejected = false;
        try { render(inputs[0]); } catch { rejected = true; }
        check(rejected, `${backend}: post-disposal render accepted`);
        if (callback) {
          rejected = false; try { callback({}); } catch { rejected = true; }
          check(rejected, "FIR callback survived disposal");
        }
      } finally { if (root) await React.act(() => root.unmount()); runtime.dispose(); }
    }
    check(JSON.stringify(snapshots.fir) === JSON.stringify(snapshots.vir), "matched browser DOM differs");
    check(warnings.length === 0, `React warnings: ${warnings.join("\n")}`);
    return { exactDomEquality: true, richUpdatesPerBackend: 6, fullFltDocumentsPerBackend: 2,
      retainedDetails: true, retainedFirCallback: true, invalidInputRecovery: true,
      unmountBeforeDispose: true, postDisposalRejected: true, noReactWarnings: true, noTimings: true };
  } finally { console.error = original; }
}
