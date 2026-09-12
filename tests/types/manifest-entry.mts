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
