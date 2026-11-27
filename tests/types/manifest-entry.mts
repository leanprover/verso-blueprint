import { createPreview } from "verso-blueprint";
import { loadGraphs } from "verso-blueprint/graph";
import type { BlueprintGraphNodeVisual, BlueprintManifestNode } from "verso-blueprint/types";

// Consume the generated public declarations through the package export.
const preview = createPreview();
const entry = await preview.loadManifestEntry("code-only--statement", undefined);
if (entry) {
  // @ts-expect-error The semantic assessment belongs to the manifest node row.
  void entry.assessment;
}
if (entry?.codeOnlyPreview) {
  const composed: boolean = entry.codeOnlyPreview;
  const keys: string[] = entry.leanCodePreviewKeys;
  keys.map((key: string) => preview.loadHtmlCacheEntry(key, undefined));

  // @ts-expect-error The composition flag is not a string or an untyped value.
  const invalidFlag: string = entry.codeOnlyPreview;
  // @ts-expect-error Lean preview keys are strings, not numbers.
  const invalidKeys: number[] = entry.leanCodePreviewKeys;
}


// Declaration evidence is typed independently of preview/loading status.
if (entry?.codeData) {
  for (const decl of entry.codeData.literateDeclarations.definedTheorems) {
    const status = decl.provedStatus;
    if (typeof status === "object") {
      const known = status.incomplete.knownSorry;
      const gaps = status.incomplete.unverified;
      gaps.forEach((gap) => {
        const axis: "statement" | "proof" | "unknown" = gap.location;
        const reason: "bodyUnavailable" | "declarationUnavailable" | "uncheckedExpression" = gap.reason;
        // @ts-expect-error Verification gaps are not observed source-reference counts.
        const refs: number = gap.refs;
        void [axis, reason, refs];
      });
      known.forEach((item) => {
        const origin: "direct" | "dependency" | "unknown" = item.origin;
        // @ts-expect-error Unknown origin cannot be treated as always direct.
        const direct: "direct" = item.origin;
        void [origin, direct];
      });
    }
  }
}

const visual: BlueprintGraphNodeVisual = {
  shape: "box", style: "filled", fillcolor: "#fff", color: "#000",
  penwidth: "1", fontcolor: "#000", peripheries: 1,
};
const row: BlueprintManifestNode = {
  label: "code-only", primaryKey: "code-only--statement", bodyless: null, assessment: null,
};
for (const graph of await loadGraphs()) {
  const schemaVersion: 7 = graph.schemaVersion;
  const legends: ("full" | "group")[] = graph.legends.map((legend) => legend.kind);
  const tooltip: string | null | undefined = graph.nodes[0]?.visual.tooltip;
  void [schemaVersion, legends, tooltip];
}
void [visual, row];
