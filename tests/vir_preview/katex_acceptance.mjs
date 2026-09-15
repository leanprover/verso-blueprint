import * as React from "react";
import { createRoot } from "react-dom/client";
import katex from "../../.lake/packages/verso/vendored-js/katex/katex.mjs";
import { createMathComponent } from "../../packages/verso-react/web/katex.mjs";

export function checkMathLifecycle() {
  const check = (ok, message) => { if (!ok) throw Error(message); };
  let calls = 0;
  const Formula = createMathComponent({ render(...args) { calls++; katex.render(...args); } });
  const host = document.createElement("div");
  document.body.append(host);
  const root = createRoot(host);
  const render = (source, prelude = "", display = false) => React.act(() => root.render(
    React.createElement(React.StrictMode, null, React.createElement(Formula, {
      source, "data-bp-tex-prelude": prelude,
      "data-verso-math-mode": display ? "display" : "inline",
    }))));
  try {
    render("x + 1");
    const container = host.firstChild, formula = host.querySelector(".katex");
    check(formula && host.querySelector("math"), "KaTeX HTML/MathML missing");
    const mountedCalls = calls;
    render("x + 1");
    check(calls === mountedCalls && host.firstChild === container &&
      host.querySelector(".katex") === formula, "unchanged formula was re-typeset or remounted");
    render("x + 2");
    check(calls === mountedCalls + 1 && host.firstChild === container, "formula edit not retained");
    render("\\demo", "\\newcommand{\\demo}{y}");
    check(!host.querySelector(".katex-error"), "TeX prelude not applied");
    render("\\demo", "\\newcommand{\\demo}{z}", true);
    check(host.querySelector(".katex-display"), "display mode dependency ignored");
    render("\\frac{1");
    check(host.querySelector(".katex-error")?.textContent.includes("frac"),
      "invalid TeX must remain visibly diagnosable");
    render("\\href{https://example.org}{link}");
    check(!host.querySelector("a"), "KaTeX trust must stay disabled");
    React.act(() => root.unmount());
    check(container.childNodes.length === 0, "math effect did not clean owned descendants");
    return { strictMode: true, unchangedNoTypeset: true, sourcePreludeModeUpdates: true,
      visibleErrors: true, trustDisabled: true, cleanup: true };
  } finally { React.act(() => root.unmount()); host.remove(); }
}
