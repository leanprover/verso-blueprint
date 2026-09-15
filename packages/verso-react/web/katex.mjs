import * as React from "react";

// React owns the empty span. KaTeX alone owns its descendants. Keep the
// component type stable: call this factory once, outside any render function.
export function createMathComponent(katex) {
  return function MathFormula({ source, ...attributes }) {
    const ref = React.useRef(null);
    const prelude = attributes["data-bp-tex-prelude"] ?? "";
    const displayMode = attributes["data-verso-math-mode"] === "display";
    React.useEffect(() => {
      const container = ref.current;
      katex.render(prelude ? `${prelude}\n${source}` : source, container, {
        displayMode, throwOnError: false, trust: false, macros: {},
      });
      return () => container.replaceChildren();
    }, [source, prelude, displayMode]);
    return React.createElement("span", { ...attributes, ref });
  };
}
