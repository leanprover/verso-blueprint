import { createPreview } from "verso-blueprint";

// Consume the generated public declarations through the package export.
const preview = createPreview();
const entry = await preview.loadManifestEntry("code-only--statement", undefined);
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
