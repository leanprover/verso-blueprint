/* Temporary edits to the pinned upstream shell, not a downstream widget shell.
 * Keep backend ownership explicit; fail rather than patch an ambiguous source. */
import assert from "node:assert/strict";

function replaceOnce(source, site, replacement) {
  assert.equal(source.split(site).length, 2, `upstream shell drift: ${site}`);
  return source.replace(site, replacement);
}

// Reuse upstream RPC/editor/lifetime handling for either external native view.
export function configureNativeComponentShell(source, { module, open, binding, clock = false, styleText = "" }) {
  const site = "  runtimeOptions.defaultHostBindings = () =>";
  source = `import { ${open} as openNativePreview } from ${JSON.stringify(module)};\n` + source;
  if (styleText) {
    const styleSite = "    loaded?.configurationKey === configurationKey";
    source = replaceOnce(source, styleSite,
      `    e("style", { "data-verso-math-styles": true }, ${JSON.stringify(styleText)}),\n${styleSite}`);
  }
  source = replaceOnce(source, site, `  const nativePreview = await openNativePreview();
  runtimeOptions.hostBindings = {
    ${JSON.stringify(binding)}: () => nativePreview.Component,
    ${clock ? '"previewDemo.now": () => performance.now(),' : ""}
  };
${site}`);
  source = replaceOnce(source, "    runtime: await createBundledVirRuntime(runtimeOptions),", `    nativePreview,
    runtime: await createBundledVirRuntime(runtimeOptions).catch(error => { nativePreview.dispose(); throw error; }),`);
  return replaceOnce(source, "    service.runtime.dispose?.();",
    "    try { service.runtime.dispose?.(); } finally { service.nativePreview?.dispose(); }");
}

export function configureDemoShell(source, fir, { bridge, math, katex, mathCss }) {
  const bindingsSite = "  runtimeOptions.defaultHostBindings = () =>";
  if (fir) {
    return configureNativeComponentShell(source, {
      module: "@fir-demo", open: "openFirDemo", binding: "previewDemo.componentFir",
    });
  }
  const styleSite = "    loaded?.configurationKey === configurationKey";
  source = replaceOnce(source, styleSite,
    `    e("style", { "data-verso-math-styles": true }, ${JSON.stringify(mathCss)}),\n${styleSite}`);
  return `import { createJsonValueHostBindings } from ${JSON.stringify(bridge)};\n` +
    `import { createMathComponent } from ${JSON.stringify(math)};\n` +
    `import katex from ${JSON.stringify(katex)};\n` +
    `const PreviewMath = createMathComponent(katex);\n` +
    replaceOnce(source, bindingsSite, `  runtimeOptions.hostBindings = {
    ...createJsonValueHostBindings(),
    "previewDemo.now": () => performance.now(),
    "previewDemo.mathComponent": () => PreviewMath,
    "previewDemo.parse": source => {
      if (typeof source !== "string") throw new TypeError("Preview reply must be a String");
      return JSON.parse(source);
    },
  };\n${bindingsSite}`);
}
