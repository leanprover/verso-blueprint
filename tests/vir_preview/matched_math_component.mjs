import katex from "../../.lake/packages/verso/vendored-js/katex/katex.mjs";
import { createMathComponent } from "../../packages/verso-react/web/katex.mjs";

// One component type for every matched VIR/FIR consumer.  Constructing this at
// module scope keeps React identity stable across retained document updates.
export const PreviewMath = createMathComponent(katex);
