/**
 * Shared JSDoc typedefs for the browser-facing Blueprint ESM APIs.
 *
 * The runtime remains JavaScript. These declarations document the generated
 * data contract that custom clients consume from `-verso-data/api/*.mjs`.
 *
 * @module blueprint-api-types
 */

/**
 * Custom JSON loader used by standalone clients that cannot or do not want to
 * use the page's global `fetch`.
 *
 * @callback BlueprintFetchJson
 * @param {string} url URL to load.
 * @param {Record<string, unknown>} [options] The resolved load options.
 * @returns {unknown | Promise<unknown>} Parsed JSON data or a promise for it.
 */

/**
 * Common options accepted by the generated-data loaders.
 *
 * @typedef {Object} BlueprintDataApiOptions
 * @property {string} [dataBaseUrl] Base URL used to resolve files under `-verso-data/`.
 * @property {BlueprintFetchJson} [fetchJson] Per-API JSON loader override.
 * @property {RequestInit} [fetchOptions] Options forwarded to `fetch` when no custom loader is supplied.
 */

/**
 * Options accepted by label-resolution helpers.
 *
 * This duplicates the small generated-data loader option surface because the
 * JSDoc/TypeScript toolchain used for the public API does not accept typedef
 * intersections consistently.
 *
 * @typedef {Object} BlueprintLabelResolveOptions
 * @property {string} [facet] Preview facet to resolve. Defaults to `statement`.
 * @property {string} [dataBaseUrl] Base URL used to resolve files under `-verso-data/`.
 * @property {BlueprintFetchJson} [fetchJson] Per-API JSON loader override.
 * @property {RequestInit} [fetchOptions] Options forwarded to `fetch` when no custom loader is supplied.
 */

/**
 * Context passed to preview hydrators.
 *
 * @typedef {Object} BlueprintHydratorContext
 * @property {string} name Hydrator name when known.
 * @property {"registered" | "options" | string} source Where the hydrator came from.
 */

/**
 * Custom post-render hook for nested preview bindings, math, or client widgets.
 *
 * @callback BlueprintHydrator
 * @param {Element | Document} root Rendered root to hydrate.
 * @param {BlueprintHydratorContext} context Hydrator provenance.
 * @returns {void}
 */

/**
 * Named hydrator object accepted in preview options.
 *
 * @typedef {Object} BlueprintHydratorEntry
 * @property {string} [name] Optional hydrator name.
 * @property {BlueprintHydrator} [fn] Hydrator function.
 * @property {BlueprintHydrator} [hydrate] Hydrator method.
 */

/**
 * Hydrator collection accepted by preview render calls.
 *
 * @typedef {BlueprintHydrator | BlueprintHydratorEntry | Array<BlueprintHydrator | BlueprintHydratorEntry> | Map<string, BlueprintHydrator | BlueprintHydratorEntry> | Record<string, BlueprintHydrator | BlueprintHydratorEntry>} BlueprintHydrators
 */

/**
 * Custom binder for Lean-emitted preview templates in rendered fragments.
 *
 * @callback BlueprintTemplateBinder
 * @param {ParentNode | Element | Document | DocumentFragment} root Rendered root.
 * @param {BlueprintPreviewOptions} [options] Render options for this call.
 * @returns {unknown}
 */

/**
 * Custom text loader used by canonical generated-node rendering.
 *
 * @callback BlueprintFetchText
 * @param {string} url URL to load.
 * @param {BlueprintPreviewOptions} [options] Render options for this call.
 * @returns {string | Promise<string>} Loaded HTML text.
 */

/**
 * Payload passed to a custom canonical document loader.
 *
 * @typedef {Object} BlueprintLoadDocumentPayload
 * @property {string} url Canonical page URL without the hash.
 * @property {string} sourceUrl Canonical source URL including the requested hash.
 * @property {BlueprintPreviewOptions} options Render options for this call.
 */

/**
 * Custom canonical document loader.
 *
 * @callback BlueprintLoadDocument
 * @param {BlueprintLoadDocumentPayload} payload Canonical document load request.
 * @returns {Document | string | Promise<Document | string>} Loaded document or HTML source.
 */

/**
 * Options accepted by render-capable preview APIs.
 *
 * @typedef {Object} BlueprintPreviewOptions
 * @property {string} [dataBaseUrl] Base URL used to resolve files under `-verso-data/`.
 * @property {BlueprintFetchJson} [fetchJson] Per-API JSON loader override.
 * @property {RequestInit} [fetchOptions] Options forwarded to `fetch` when no custom loader is supplied.
 * @property {boolean} [hydrate] Set to `false` to skip preview-template and hydrator hooks.
 * @property {boolean} [renderMath] Set to `false` to skip KaTeX rendering.
 * @property {BlueprintHydrators} [hydrators] Per-render or per-preview hydrators.
 * @property {boolean} [inheritPageHydrators] Set to `false` to ignore registered page hydrators.
 * @property {BlueprintTemplateBinder} [templateBinder] Custom preview-template binder.
 * @property {BlueprintFetchText} [fetchText] Custom text loader for canonical generated pages.
 * @property {BlueprintLoadDocument} [loadDocument] Custom document loader for canonical generated pages.
 * @property {string} [canonicalBaseUrl] Base URL used to resolve canonical generated-page links.
 * @property {Map<string, Document | Promise<Document>>} [canonicalPreviewDocuments] Canonical page document cache.
 * @property {Map<string, string>} [canonicalPreviewHtmlByKey] Canonical generated-node HTML cache.
 */

/**
 * Loading status for a generated JSON store such as the manifest or HTML cache.
 *
 * @typedef {Object} BlueprintStoreStatus
 * @property {"idle" | "loading" | "ready" | "error" | string} state Current loader state.
 * @property {number} attempts Number of load attempts.
 * @property {string} url URL most recently used for the store.
 * @property {string} lastError Last error message, or an empty string.
 * @property {number} entryCount Number of decoded entries when ready.
 */

/**
 * Source file/range for a Blueprint manifest entry.
 *
 * Lines and characters use LSP zero-based UTF-16 coordinates.
 *
 * @typedef {Object} BlueprintSourceLocation
 * @property {string} path Source file path.
 * @property {{ start: { line: number, character: number }, end: { line: number, character: number } }} range Source range.
 */

/**
 * Result of looking up a source location for a manifest entry.
 *
 * @typedef {Object} BlueprintSourceLocationResult
 * @property {boolean} ok Whether a concrete source location is available.
 * @property {BlueprintSourceLocation | null} location Source location on success.
 * @property {string} error Diagnostic message when unavailable.
 */

/**
 * External source markup attached to a Blueprint label.
 *
 * @typedef {Object} BlueprintExternalMarkup
 * @property {string} language Source language, for example `markdown`, `tex`, or `verso`.
 * @property {string} slot Logical source slot, for example `statement` or `proof`.
 * @property {string} raw Raw source text.
 * @property {unknown} [location] Optional source provenance supplied by the generator.
 */

/**
 * Original source document declared by a Blueprint site.
 *
 * @typedef {Object} BlueprintSourceDocument
 * @property {string} id Stable source-document id.
 * @property {string} title Human-readable source title.
 * @property {"pdf" | "text" | string} kind Broad source-document kind.
 * @property {string} [pdf] Source PDF path, when the document is PDF-backed.
 * @property {string} [pageRoot] Optional root for extracted source pages.
 * @property {string} [imageRoot] Optional root for extracted page images.
 */

/**
 * Text source span for an original source reference.
 *
 * @typedef {Object} BlueprintSourceTextRange
 * @property {string} path Source text path.
 * @property {number} startLine One-based inclusive start line.
 * @property {number} endLine One-based inclusive end line.
 * @property {number} [startCharacter] Optional start character.
 * @property {number} [endCharacter] Optional end character.
 */

/**
 * Source PDF crop box in top-left page coordinates.
 *
 * @typedef {Object} BlueprintSourcePdfBox
 * @property {number} scale Coordinate scale used for the extracted page.
 * @property {number} pageWidth Scaled page width.
 * @property {number} pageHeight Scaled page height.
 * @property {number} xMin Left edge.
 * @property {number} yMin Top edge.
 * @property {number} xMax Right edge.
 * @property {number} yMax Bottom edge.
 */

/**
 * PDF/page-image source data for an original source span.
 *
 * @typedef {Object} BlueprintSourcePdfSpan
 * @property {string} path Source PDF page path.
 * @property {string} [image] Optional rendered page image path.
 * @property {BlueprintSourcePdfBox} [box] Optional crop box.
 */

/**
 * One original source span attached to a Blueprint node.
 *
 * @typedef {Object} BlueprintSourceSpan
 * @property {string} page Source-local page identifier.
 * @property {BlueprintSourceTextRange} [text] Text location for this span.
 * @property {BlueprintSourcePdfSpan} [pdf] PDF/page-image location for this span.
 */

/**
 * Original source provenance attached to a manifest entry.
 *
 * @typedef {Object} BlueprintSourceRef
 * @property {string} document Source-document id.
 * @property {BlueprintSourceSpan[]} spans Source spans within the document.
 */

/**
 * Semantic manifest entry emitted for a rendered Blueprint preview or an
 * source-backed external-markup node.
 *
 * @typedef {Object} BlueprintManifestEntry
 * @property {string} key Stable manifest key.
 * @property {string} [label] Canonical Blueprint node label when available.
 * @property {string} authoredLabel Authored/display label without Lean pretty-name quoting.
 * @property {string} [facet] Rendered facet such as `statement` or `proof`.
 * @property {string} [href] Link to the canonical generated node.
 * @property {BlueprintSourceLocationResult} [sourceLocation] Original source location lookup result for this entry.
 * @property {BlueprintExternalMarkup[]} [externalMarkup] Attached external source snippets.
 * @property {BlueprintSourceRef[]} [sources] Original source refs for this entry.
 */

/**
 * Rendered-fragment cache entry.
 *
 * @typedef {Object} BlueprintHtmlCacheEntry
 * @property {string} key Stable cache key.
 * @property {string} html Rendered HTML fragment.
 */

/**
 * Graph data exported by the Blueprint manifest or embedded in a graph page.
 *
 * @typedef {Object} BlueprintGraphData
 * @property {number} schemaVersion Graph payload schema version.
 * @property {string} key Variant key.
 * @property {unknown[]} nodes Graph node payloads.
 * @property {unknown[]} edges Graph edge payloads.
 * @property {unknown[]} groups Optional graph grouping payloads.
 * @property {BlueprintGraphVariant[]} [variants] Precomputed DOT variants for the bundled graph renderer.
 */

/**
 * Graph render variant emitted by Lean for the bundled graph renderer.
 *
 * @typedef {Object} BlueprintGraphVariant
 * @property {string} key Variant key.
 * @property {string} label Human-readable variant label.
 * @property {string} dot DOT source.
 * @property {Record<string, unknown>} [options] Rendering options emitted with the variant.
 * @property {unknown[]} [selectOnNodeId] Node IDs to select when the variant is active.
 * @property {unknown[]} [hoverOnNodeId] Node IDs to highlight on hover.
 * @property {unknown[]} [previewKeyByNodeId] SVG node ids mapped to Blueprint preview-cache keys.
 */

/**
 * Runtime dependency URLs accepted by graph rendering helpers.
 *
 * @typedef {Object} BlueprintGraphRuntimeLibraries
 * @property {string} [d3] URL for D3 when the page has not loaded it already.
 * @property {string} [graphviz] URL for d3-graphviz when the page has not loaded it already.
 */

/**
 * Options accepted by graph rendering helpers in `api/graph.mjs`.
 *
 * @typedef {Object} BlueprintGraphRenderOptions
 * @property {Record<string, unknown>} previewUtils Render-capable Blueprint preview API required by public `api/graph.mjs` render helpers.
 * @property {"page" | "block" | "fill" | string} [layout] Graph sizing mode.
 * @property {BlueprintGraphLayoutOptions} [graphOptions] Initial graph-control values for graph data rendered from manifest records.
 * @property {BlueprintGraphVariant[]} [variants] Optional precomputed DOT variants overriding `graphData.variants`;
 * required when rendering graph records that do not already carry Lean-emitted variants.
 * @property {"pinned" | "hover" | string} [previewMode] Initial graph node preview behavior for graph data rendered from manifest records.
 * @property {"docked" | "anchored" | string} [previewPlacement] Initial graph node preview placement for graph data rendered from manifest records.
 * @property {boolean} [replace] In `renderGraphData`, replace host children by default; set to `false` to append.
 * @property {boolean} [refresh] Re-render immediately after initialization.
 * @property {BlueprintGraphRuntimeLibraries} [libraries] Runtime dependency URL overrides.
 */

/**
 * Layout options accepted by graph controllers.
 *
 * @typedef {Object} BlueprintGraphLayoutOptions
 * @property {string} [direction] Graphviz rank direction.
 * @property {boolean} [pack] Enable or disable Graphviz packing.
 */

/**
 * Controller returned by graph rendering helpers.
 *
 * @typedef {Object} BlueprintGraphController
 * @property {function(): void} render Re-render the active graph view immediately.
 * @property {function(): void} scheduleRender Schedule a debounced render.
 * @property {function(string): void} setView Select a graph variant by key.
 * @property {function(BlueprintGraphLayoutOptions): void} setOptions Update graph layout options.
 * @property {function(string): void} setDirection Update the Graphviz rank direction.
 * @property {function(boolean): void} setPack Enable or disable Graphviz packing.
 * @property {function(string, string=): void} setPreviewBehavior Update graph preview behavior.
 */

/**
 * Result of resolving a preview key against the manifest and HTML cache.
 *
 * @typedef {Object} BlueprintPreviewResult
 * @property {boolean} ok Whether the rendered preview is available.
 * @property {string} key Requested preview key.
 * @property {string} reason Empty on success; diagnostic reason otherwise.
 * @property {BlueprintManifestEntry | null} manifestEntry Matching manifest entry.
 * @property {BlueprintHtmlCacheEntry | null} htmlCacheEntry Matching HTML cache entry.
 * @property {string} html Rendered fragment HTML on success.
 * @property {string} diagnosticHtml Diagnostic HTML when unavailable.
 */

/**
 * Result of resolving a canonical generated node for insertion into another
 * document.
 *
 * @typedef {Object} BlueprintCanonicalPreviewResult
 * @property {boolean} ok Whether the canonical node is available.
 * @property {string} key Requested preview key.
 * @property {string} reason Empty on success; diagnostic reason otherwise.
 * @property {BlueprintManifestEntry | null} manifestEntry Matching manifest entry.
 * @property {BlueprintHtmlCacheEntry | null} htmlCacheEntry Matching HTML cache entry.
 * @property {string} html Rendered fragment HTML on success.
 * @property {string} diagnosticHtml Diagnostic HTML when unavailable.
 * @property {string} [canonicalHtml] Full canonical generated-node HTML.
 * @property {string} [canonicalSourceHref] Source document URL for the canonical node.
 */

/**
 * Result of resolving a Blueprint block label.
 *
 * @typedef {Object} BlueprintResolveLabelResult
 * @property {boolean} ok Whether the label resolved to a manifest entry.
 * @property {string} label Requested Blueprint label.
 * @property {string} facet Requested or resolved facet.
 * @property {string} key Resolved preview key, or the requested key when missing.
 * @property {string} reason Empty on success; diagnostic reason otherwise.
 * @property {BlueprintManifestEntry | null} manifestEntry Matching manifest entry.
 * @property {string} href Generated-page href on success.
 * @property {BlueprintSourceLocationResult} sourceLocation Source location result for the label entry.
 */

/**
 * Result of resolving a Lean declaration name.
 *
 * @typedef {Object} BlueprintResolveDeclarationResult
 * @property {boolean} ok Whether the declaration resolved to a manifest entry.
 * @property {string} declaration Requested or resolved Lean declaration name.
 * @property {string} key Resolved preview key, or the requested key when missing.
 * @property {string} reason Empty on success; diagnostic reason otherwise.
 * @property {BlueprintManifestEntry | null} manifestEntry Matching manifest entry.
 * @property {string} href Generated-page href on success.
 * @property {BlueprintSourceLocationResult} sourceLocation Source location result for the declaration.
 */

/**
 * Payload supplied to a call-scoped external markup renderer.
 *
 * @typedef {Object} BlueprintExternalMarkupPayload
 * @property {string} raw Raw external source.
 * @property {string} language Selected source language.
 * @property {string} slot Selected source slot.
 * @property {unknown} location Source provenance when available.
 * @property {BlueprintManifestEntry | null} node Manifest node data.
 * @property {BlueprintManifestEntry | null} manifestEntry Manifest node data.
 * @property {string} label Requested Blueprint label.
 * @property {string} facet Requested rendered facet.
 * @property {BlueprintPreviewResult | null} nativePreview Native preview resolution result.
 * @property {BlueprintExternalMarkup} externalMarkup Selected external source entry.
 */

/**
 * Renders selected external markup into a target element.
 *
 * @callback BlueprintExternalMarkupRenderer
 * @param {BlueprintExternalMarkupPayload} payload VBP-owned source and provenance data.
 * @param {Element} target Element whose contents should be replaced or updated.
 * @returns {void | string | Node | Promise<void | string | Node>}
 */

/**
 * Preference used by `renderNode` when a native rendered preview is absent.
 *
 * @typedef {Object} BlueprintExternalMarkupPreference
 * @property {string} [language] Preferred language such as `markdown`, `tex`, or `verso`.
 * @property {string} [slot] Preferred source slot.
 * @property {"source" | string} [display] Use `source` to render the raw source without a custom renderer.
 * @property {BlueprintExternalMarkupRenderer} [render] Per-call renderer for this preference.
 */

/**
 * Ordered external-markup fallback preferences.
 *
 * @typedef {Object} BlueprintExternalMarkupPreferences
 * @property {BlueprintExternalMarkupPreference[]} prefer Ordered external-markup preferences.
 */

/**
 * Label-oriented render request.
 *
 * @typedef {Object} BlueprintRenderNodeRequest
 * @property {string} label Blueprint label to render.
 * @property {string} [facet="statement"] Rendered facet to prefer for native previews.
 * @property {BlueprintExternalMarkupPreference | BlueprintExternalMarkupPreference[] | BlueprintExternalMarkupPreferences} [externalMarkup] External-markup fallback preferences.
 * @property {BlueprintExternalMarkupPreference} [preferredExternalMarkup] Shorthand for a single external-markup preference.
 */

/**
 * Result returned by `renderNode`.
 *
 * @typedef {Object} BlueprintRenderNodeResult
 * @property {boolean} ok Whether rendering succeeded.
 * @property {string} key Requested preview key.
 * @property {string} reason Empty on success; diagnostic reason otherwise.
 * @property {BlueprintManifestEntry | null} manifestEntry Matching manifest entry.
 * @property {BlueprintHtmlCacheEntry | null} htmlCacheEntry Matching HTML cache entry.
 * @property {string} html Rendered fragment HTML when available.
 * @property {string} diagnosticHtml Diagnostic HTML when unavailable.
 * @property {"native" | "external-markup" | "diagnostic" | string} [renderMode] Rendering path used.
 * @property {string} [label] Requested Blueprint label.
 * @property {string} [facet] Requested rendered facet.
 * @property {BlueprintExternalMarkup | null} [externalMarkup] Selected external markup, if any.
 * @property {BlueprintPreviewResult | null} [nativePreview] Native preview lookup result.
 * @property {string} [canonicalHtml] Full canonical generated-node HTML.
 * @property {string} [canonicalSourceHref] Source document URL for the canonical node.
 */

/**
 * One source reference after resolving its source-document metadata.
 *
 * @typedef {Object} BlueprintResolvedSourceRef
 * @property {BlueprintSourceRef} sourceRef Original manifest source ref.
 * @property {string} documentId Source-document id from `sourceRef.document`.
 * @property {BlueprintSourceDocument | null} document Resolved source-document metadata, or `null` when missing.
 * @property {BlueprintSourceSpan[]} spans Source spans from the original source ref.
 */

/**
 * Input accepted by source-metadata helpers.
 *
 * @typedef {string | BlueprintManifestEntry | BlueprintPreviewResult | BlueprintCanonicalPreviewResult | BlueprintRenderNodeResult} BlueprintSourceMetadataInput
 */

/**
 * Result returned by source-metadata helpers.
 *
 * @typedef {Object} BlueprintSourceMetadataResult
 * @property {boolean} ok Whether source provenance was available.
 * @property {string} key Requested or resolved preview key.
 * @property {string} reason Empty on success; diagnostic reason otherwise.
 * @property {BlueprintManifestEntry | null} manifestEntry Matching manifest entry.
 * @property {BlueprintResolvedSourceRef[]} sources Resolved source references.
 */

/**
 * Data API returned by `createPreviewData`.
 *
 * @typedef {Object} BlueprintDataApi
 * @property {function(string): string} dataUrl
 * @property {function(): string} manifestUrl
 * @property {function(): string} htmlCacheUrl
 * @property {function(): string} dataApiModuleUrl
 * @property {function(): string} previewApiModuleUrl
 * @property {function(): string} graphApiModuleUrl
 * @property {function(string, string=): string} previewKey
 * @property {function(string): string} statementPreviewKey
 * @property {function(): BlueprintStoreStatus} readManifestStatus
 * @property {function(): BlueprintStoreStatus} readHtmlCacheStatus
 * @property {function(BlueprintDataApiOptions=): Promise<Map.<string, BlueprintManifestEntry>>} loadManifest
 * @property {function(BlueprintDataApiOptions=): Promise<Map.<string, BlueprintHtmlCacheEntry>>} loadHtmlCache
 * @property {function(string, BlueprintDataApiOptions=): Promise<(BlueprintManifestEntry | null)>} loadManifestEntry
 * @property {function(BlueprintDataApiOptions=): Promise<BlueprintSourceDocument[]>} loadSourceDocuments
 * @property {function(string, BlueprintDataApiOptions=): Promise<(BlueprintSourceDocument | null)>} loadSourceDocument
 * @property {function(string, BlueprintLabelResolveOptions=): Promise<BlueprintResolveLabelResult>} resolveLabel
 * @property {function(string, BlueprintDataApiOptions=): Promise<BlueprintResolveDeclarationResult>} resolveDeclaration
 * @property {function(BlueprintSourceMetadataInput, BlueprintDataApiOptions=): Promise<BlueprintSourceMetadataResult>} resolveSourceMetadata
 * @property {function(string, BlueprintDataApiOptions=): Promise<(BlueprintHtmlCacheEntry | null)>} loadHtmlCacheEntry
 */

/**
 * Preview API returned by `createPreview`.
 *
 * @typedef {Object} BlueprintPreviewApi
 * @property {function(string): string} dataUrl
 * @property {function(): string} manifestUrl
 * @property {function(): string} htmlCacheUrl
 * @property {function(): string} dataApiModuleUrl
 * @property {function(): string} previewApiModuleUrl
 * @property {function(): string} graphApiModuleUrl
 * @property {function(string, string=): string} previewKey
 * @property {function(string): string} statementPreviewKey
 * @property {function(): BlueprintStoreStatus} readManifestStatus
 * @property {function(): BlueprintStoreStatus} readHtmlCacheStatus
 * @property {function(BlueprintDataApiOptions=): Promise<Map.<string, BlueprintManifestEntry>>} loadManifest
 * @property {function(BlueprintDataApiOptions=): Promise<Map.<string, BlueprintHtmlCacheEntry>>} loadHtmlCache
 * @property {function(string, BlueprintDataApiOptions=): Promise<(BlueprintManifestEntry | null)>} loadManifestEntry
 * @property {function(BlueprintDataApiOptions=): Promise<BlueprintSourceDocument[]>} loadSourceDocuments
 * @property {function(string, BlueprintDataApiOptions=): Promise<(BlueprintSourceDocument | null)>} loadSourceDocument
 * @property {function(string, BlueprintDataApiOptions=): Promise<(BlueprintHtmlCacheEntry | null)>} loadHtmlCacheEntry
 * @property {function(string, BlueprintLabelResolveOptions=): Promise<BlueprintResolveLabelResult>} resolveLabel
 * @property {function(string, BlueprintDataApiOptions=): Promise<BlueprintResolveDeclarationResult>} resolveDeclaration
 * @property {function(string, BlueprintDataApiOptions=): Promise<BlueprintPreviewResult>} resolvePreview
 * @property {function(Element, string, BlueprintPreviewOptions=): Promise<BlueprintPreviewResult>} renderPreviewInto
 * @property {function(string, BlueprintPreviewOptions=): Promise<BlueprintCanonicalPreviewResult>} resolveCanonicalPreview
 * @property {function(Element, string, BlueprintPreviewOptions=): Promise<BlueprintCanonicalPreviewResult>} renderCanonicalPreviewInto
 * @property {function(Element, (string | BlueprintRenderNodeRequest), BlueprintPreviewOptions=): Promise<BlueprintRenderNodeResult>} renderNode
 * @property {function(BlueprintSourceMetadataInput, BlueprintPreviewOptions=): Promise<BlueprintSourceMetadataResult>} resolveSourceMetadata
 * @property {function(Element, BlueprintPreviewOptions=): boolean} hydrate
 * @property {function(BlueprintGraphData, BlueprintGraphRenderOptions=): Element | null} [createGraphBlock] Installed by the graph runtime when graph rendering is started.
 * @property {function(Element, BlueprintGraphData, BlueprintGraphRenderOptions=): Promise<BlueprintGraphController | null>} [renderGraphData] Installed by the graph runtime when graph rendering is started.
 */

export {};
