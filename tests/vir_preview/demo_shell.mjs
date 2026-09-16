/* Temporary edits to the pinned upstream shell, not a downstream widget shell.
 * Keep backend ownership explicit; fail rather than patch an ambiguous source. */
import assert from "node:assert/strict";

function replaceOnce(source, site, replacement) {
  assert.equal(source.split(site).length, 2, `upstream shell drift: ${site}`);
  return source.replace(site, replacement);
}

export function configureDemoShell(source, fir, { bridge, math, katex, mathCss }) {
  const bindingsSite = "  runtimeOptions.defaultHostBindings = () =>";
  if (fir) {
    source = 'import { openFirDemo } from "@fir-demo";\n' + source;
    source = replaceOnce(source, bindingsSite, `  const fir = await openFirDemo();
  runtimeOptions.hostBindings = {};
  runtimeOptions.hostBindings["previewDemo.componentFir"] = () => fir.Component;
${bindingsSite}`);
    source = replaceOnce(source, "    runtime: await createBundledVirRuntime(runtimeOptions),", `    fir,
    runtime: await createBundledVirRuntime(runtimeOptions).catch(error => { fir.dispose(); throw error; }),`);
    return replaceOnce(source, "    service.runtime.dispose?.();",
      "    try { service.runtime.dispose?.(); } finally { service.fir?.dispose(); }");
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
