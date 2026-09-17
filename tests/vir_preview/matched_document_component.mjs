// Same native React boundary for VIR and FIR. Runtime-local decoded values
// never cross backends. The Lean view owns controls, identity and presentation.
import { useMemo } from "react";

export function createMatchedDocumentComponent(decode, render) {
  return function MatchedDocument({ document }) {
    const value = useMemo(() => {
      let preview;
      try { preview = { ready: { document: JSON.parse(document) } }; }
      catch (error) { preview = { error: { message: String(error) } }; }
      return decode(preview);
    }, [document]);
    return render(value);
  };
}
