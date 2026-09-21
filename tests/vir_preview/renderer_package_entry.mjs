import assert from "node:assert/strict";
import { renderToStaticMarkup } from "react-dom/server";
import { createVirRuntime } from "lean-vir";
import { createBrowserHostBindings } from "lean-vir/host-bindings";
import { createBrowserReactHostBindings } from "lean-vir/react-host-bindings";
import { checkRenderer } from "../../packages/verso-react/tests/render-acceptance.mjs";

export async function run({ wasmBytes, genericPackages, blueprintPackages }) {
  async function withRuntime(packages, check, onString) {
    const runtime = await createVirRuntime({ wasmBytes, irPackageSet: packages,
      defaultHostBindings: () => {
        const bindings = createBrowserHostBindings({ reactHostBindings: createBrowserReactHostBindings });
        if (onString) {
          const original = bindings["js.string"];
          assert.equal(typeof original, "function");
          bindings["js.string"] = (...args) => { onString(args[0]); return original(...args); };
        }
        return bindings;
      },
    });
    try { return check(runtime); } finally { runtime.dispose(); }
  }
  const generic = await withRuntime(genericPackages, runtime =>
    checkRenderer(scenario => runtime.call("VersoReactTests.render", scenario)));
  const preludeConversions = new Map();
  let nestedRuntime, triggerNested = false, nestedRendered = false;
  const blueprint = await withRuntime(blueprintPackages, runtime => {
    nestedRuntime = runtime;
    const html = renderToStaticMarkup(runtime.call("VersoBlueprintVirTests.Renderer.render"));
    assert.equal((html.match(/data-bp-tex-prelude=/g) ?? []).length, 4,
      "empty prelude must have no attribute");
    for (const fragment of ['data-bp-tex-prelude=', "bp_math", "retained proof body",
      'data-verso-informal-label="independent"', 'data-verso-informal-kind="Proof"',
      'data-verso-external-markup-display="summary"',
      'data-verso-external-markup-display="source"', "&lt;script&gt;raw source&lt;/script&gt;",
      "[malformed informal block:", "[malformed external markup block:",
      "[malformed math extension:", "malformed child", 'data-verso-version="7"',
      'data-verso-correlation-id="renderer-package-7"']) {
      assert.ok(html.includes(fragment), `missing Blueprint output ${fragment}`);
    }
    assert.ok(!html.includes("<script>") && !html.includes("not rendered"));
    assert.ok(!html.includes('data-verso-external-markup-display="hidden"'));
    assert.equal(preludeConversions.get("\\newcommand{\\RR}{R}"), 1);
    assert.equal(preludeConversions.get("\\newcommand{\\AA}{A}"), 1);
    renderToStaticMarkup(runtime.call("VersoBlueprintVirTests.Renderer.render"));
    assert.equal(preludeConversions.get("\\newcommand{\\RR}{R}"), 2,
      "a retained runtime must create a fresh render-local table");
    assert.equal(preludeConversions.get("\\newcommand{\\AA}{A}"), 2);
    triggerNested = true;
    renderToStaticMarkup(runtime.call("VersoBlueprintVirTests.Renderer.render"));
    assert.ok(nestedRendered, "nested render did not complete");
    return { mathPrelude: true, informalBody: true, externalMarkupModes: true,
      malformedFallbacks: true, escapedSource: true, sessionMetadata: true,
      perRenderPreludeSharing: true, nestedRender: true };
  }, value => {
    if (value === "\\newcommand{\\RR}{R}" || value === "\\newcommand{\\AA}{A}")
      preludeConversions.set(value, (preludeConversions.get(value) ?? 0) + 1);
    if (triggerNested && value === "\\newcommand{\\RR}{R}") {
      triggerNested = false;
      renderToStaticMarkup(nestedRuntime.call("VersoBlueprintVirTests.Renderer.render"));
      nestedRendered = true;
    }
  });
  return { generic, blueprint, scope: "VIR-generated React elements and React SSR; not live editor acceptance" };
}
