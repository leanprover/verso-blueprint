// Same native React boundary for VIR and FIR. Runtime-local decoded values
// never cross backends. The Lean view owns controls, identity and presentation.
import { createElement, useMemo } from "react";

const badgeStyle = {
  position: "sticky", top: "4px", height: 0, zIndex: 20,
  display: "flex", justifyContent: "flex-end", pointerEvents: "none",
};
const labelStyle = {
  color: "var(--vscode-badge-foreground, #fff)",
  background: "var(--vscode-badge-background, #4d4d4d)",
  border: "1px solid var(--vscode-contrastBorder, transparent)",
  fontSize: "11px", fontWeight: 600, lineHeight: 1.4,
  letterSpacing: ".08em", padding: "2px 6px",
  borderRadius: "4px", alignSelf: "flex-start",
};

export function createMatchedDocumentComponent(decode, render, backend) {
  if (!["vir", "fir"].includes(backend)) throw Error("unknown preview backend");
  return function MatchedDocument({ document, requestedMs, receivedMs, notifiedMs }) {
    const value = useMemo(() => {
      let preview;
      try { preview = { ready: { document: JSON.parse(document) } }; }
      catch (error) { preview = { error: { message: String(error) } }; }
      return decode(preview);
    }, [document]);
    const decodedMs = useMemo(() => performance.now(), [value, requestedMs, receivedMs, notifiedMs]);
    return createElement("div", { "data-preview-backend": backend },
      createElement("div", { style: badgeStyle },
        createElement("span", { style: labelStyle, "aria-label": `${backend.toUpperCase()} renderer` },
          backend.toUpperCase())),
      render(value, { requestedMs, receivedMs, notifiedMs, decodedMs }));
  };
}
