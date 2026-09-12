import assert from "node:assert/strict";
import { renderToStaticMarkup } from "react-dom/server";
import { createVirRuntime } from "lean-vir";
import { createBrowserHostBindings } from "lean-vir/host-bindings";
import { createBrowserReactHostBindings } from "lean-vir/react-host-bindings";
import { checkRenderer } from "../../packages/verso-react/tests/render-acceptance.mjs";

export async function run({ wasmBytes, genericPackages, blueprintPackages }) {
  async function withRuntime(packages, check) {
    const runtime = await createVirRuntime({ wasmBytes, irPackageSet: packages,
      defaultHostBindings: () => createBrowserHostBindings({
        reactHostBindings: createBrowserReactHostBindings,
      }),
    });
    try { return check(runtime); } finally { runtime.dispose(); }
  }
  const generic = await withRuntime(genericPackages, runtime =>
    checkRenderer(scenario => runtime.call("VersoReactTests.render", scenario)));
  const blueprint = await withRuntime(blueprintPackages, runtime => {
    const html = renderToStaticMarkup(runtime.call("VersoBlueprintVirTests.Renderer.render"));
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
    return { mathPrelude: true, informalBody: true, externalMarkupModes: true,
      malformedFallbacks: true, escapedSource: true, sessionMetadata: true };
  });
  return { generic, blueprint, scope: "VIR-generated React elements and React SSR; not live editor acceptance" };
}
