import { createPreview } from "verso-blueprint";
import type { BlueprintSourceSpan } from "verso-blueprint/types";

// Source-native identity does not require a page, text file, or PDF.
const pageLessSpan: BlueprintSourceSpan = {
  page: null,
  anchor: "lem:original",
  citation: "Lemma 2.1",
  text: null,
  pdf: null,
};

const preview = createPreview();
const entry = await preview.loadManifestEntry("sourced--statement", undefined);
for (const source of entry?.sources ?? []) {
  for (const span of source.spans) {
    const identity: (string | null)[] = [span.page, span.anchor, span.citation];
    // @ts-expect-error Consumers must handle page-less spans.
    const requiredPage: string = span.page;
    // @ts-expect-error Missing source-native identity is null, not undefined.
    const optionalAnchor: string | undefined = span.anchor;
    // @ts-expect-error Citations are text, not generated numeric node counters.
    const numericCitation: number | null = span.citation;
  }
}

// @ts-expect-error Serialized fields are required even when their values are null.
const omittedFields: BlueprintSourceSpan = {};
