import Verso
import VersoManual
import VersoBlueprint

open Verso
open Verso.Genre
open Verso.Genre.Manual

namespace PreviewRuntimeShowcase.Chapters.CustomRenderClient

def customRenderClientCss : String := r##"
.bp_custom_render_client {
  margin: 1.5rem 0;
}

.bp_custom_render_client_header {
  align-items: baseline;
  border-bottom: 1px solid var(--bp-color-border-soft);
  display: flex;
  flex-wrap: wrap;
  gap: 0.6rem;
  justify-content: space-between;
  margin-bottom: 1rem;
  padding: 0 0 0.5rem;
}

.bp_custom_render_client_header h2 {
  font-size: 1rem;
  margin: 0;
}

.bp_custom_render_client_status {
  color: var(--bp-color-text-muted);
  font-size: 0.78rem;
  font-weight: 700;
  text-transform: uppercase;
}

.bp_custom_render_client_examples {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.bp_custom_render_client_example {
  min-width: 0;
}

.bp_custom_render_client_example h3 {
  font-size: 0.9rem;
  margin: 0 0 0.5rem;
}

.bp_custom_render_client_note {
  color: var(--bp-color-text-muted);
  font-size: 0.78rem;
  margin: 0 0 0.35rem;
}

.bp_custom_render_client_example[data-bp-custom-client-example="render-preview-into"],
.bp_custom_render_client_example[data-bp-custom-client-example="render-node"],
.bp_custom_render_client_example[data-bp-render-ok="false"] {
  background: var(--bp-color-surface);
  border: 1px solid var(--bp-color-border-soft);
  border-radius: var(--bp-radius-sm);
  padding: 0.9rem;
}

.bp_custom_render_client_preview_header {
  background: var(--bp-color-background);
  border: 1px solid var(--bp-color-border-soft);
  border-left: 0.24rem solid var(--bp-color-accent, var(--bp-color-border));
  border-radius: var(--bp-radius-sm);
  margin-bottom: 0.65rem;
  padding: 0.5rem 0.6rem;
}

.bp_custom_render_client_preview_title {
  color: var(--bp-color-text-strong);
  display: block;
  font-weight: 700;
  margin-bottom: 0.25rem;
}

.bp_custom_render_client_preview_meta {
  color: var(--bp-color-text-muted);
  display: flex;
  flex-wrap: wrap;
  font-size: 0.76rem;
  gap: 0.45rem;
}

.bp_custom_render_client_summary {
  background: var(--bp-color-background);
  border: 1px solid var(--bp-color-border-soft);
  border-radius: var(--bp-radius-sm);
  color: var(--bp-color-text-muted);
  font-size: 0.76rem;
  margin-bottom: 0.65rem;
  padding: 0.5rem;
}

.bp_custom_render_client_facts {
  display: flex;
  flex-wrap: wrap;
  gap: 0.35rem;
}

.bp_custom_render_client_fact {
  background: var(--bp-color-surface);
  border-radius: var(--bp-radius-sm);
  padding: 0.16rem 0.36rem;
}

.bp_custom_render_client_fact strong {
  color: var(--bp-color-text-strong);
}

.bp_custom_render_client_graph {
  background: var(--bp-color-surface);
  border: 1px solid var(--bp-color-border-soft);
  border-radius: var(--bp-radius-sm);
  padding: 0.9rem;
}

.bp_custom_render_client_graph h3 {
  font-size: 0.9rem;
  margin: 0 0 0.5rem;
}

.bp_custom_render_client_graph_nodes {
  display: flex;
  flex-wrap: wrap;
  gap: 0.35rem;
  margin-top: 0.65rem;
}

.bp_custom_render_client_graph_node {
  background: var(--bp-color-background);
  border: 1px solid var(--bp-color-border-soft);
  border-radius: var(--bp-radius-sm);
  color: var(--bp-color-text);
  padding: 0.18rem 0.4rem;
  text-decoration: none;
}

.bp_custom_render_client_graph_node:hover {
  border-color: var(--bp-color-accent, var(--bp-color-border));
}

.bp_custom_render_client_body {
  min-height: 8rem;
}

.bp_custom_render_client_body .bp_wrapper {
  max-width: 100%;
  overflow-wrap: anywhere;
}

.bp_custom_render_client_body .bp_heading {
  align-items: flex-start;
}

.bp_custom_render_client_body .bp_extras {
  display: flex;
  flex-wrap: wrap;
  gap: 0.3rem 0.55rem;
  justify-content: flex-start;
  margin-left: 0;
  width: 100%;
}

.bp_custom_render_client_body .bp_extra_slot {
  justify-content: flex-start;
}

.bp_custom_render_client_external {
  background: var(--bp-color-background);
  border: 1px solid var(--bp-color-border-soft);
  border-radius: var(--bp-radius-sm);
  padding: 0.75rem;
}

.bp_custom_render_client_external h4 {
  font-size: 0.95rem;
  margin: 0 0 0.45rem;
}

.bp_custom_render_client_external p {
  margin: 0.35rem 0;
}

.bp_custom_render_client_external_kicker {
  color: var(--bp-color-text-muted);
  font-size: 0.72rem;
  font-weight: 700;
  margin-bottom: 0.35rem;
  text-transform: uppercase;
}
"##

-- Keep this module rebuilt when the shared standalone preview API loader changes.
private def previewApiLoaderJs : String :=
  include_str "preview-api-loader.js"

-- Keep this module rebuilt when the standalone custom-client asset changes.
def customRenderClientJs : String :=
  previewApiLoaderJs ++ "\n" ++ include_str "custom-render-client.js"

-- Keep this module rebuilt when the standalone render-node Markdown example changes.
def standaloneRenderNodeMarkdownJs : String :=
  previewApiLoaderJs ++ "\n" ++ include_str "standalone-render-node-markdown.js"

private def clientText (text : String) : Verso.Output.Html :=
  VersoBlueprint.Html.text text

private def clientTag
    (tagName : String) (attrs : Array (String × String)) (body : Verso.Output.Html) :
    Verso.Output.Html :=
  Verso.Output.Html.tag tagName attrs body

private def clientExample
    (exampleName label facet title bodyKey note : String)
    (expectOk : Bool := true)
    (extras : Array Verso.Output.Html := #[]) :
    Verso.Output.Html :=
  let titleNode :=
    clientTag "h3" #[("data-bp-custom-client-title", "true")] (clientText title)
  let noteNode :=
    clientTag "p" #[("class", "bp_custom_render_client_note")] (clientText note)
  let summaryNode :=
    clientTag "div"
      #[("class", "bp_custom_render_client_summary"), ("data-bp-custom-client-summary", "true")]
      (clientText "Waiting for manifest data.")
  let previewHeaderNode :=
    clientTag "div"
      #[("class", "bp_custom_render_client_preview_header"),
        ("data-bp-custom-client-preview-header", "true")]
      (clientText "Waiting for preview header.")
  let bodyNode :=
    clientTag "div"
      #[("class", "bp_custom_render_client_body"), ("data-bp-custom-client-body", bodyKey)]
      .empty
  let expectedAttr := if expectOk then "true" else "false"
  clientTag "article"
    #[ ("class", "bp_custom_render_client_example"),
       ("data-bp-custom-client-example", exampleName),
       ("data-bp-preview-label", label),
       ("data-bp-preview-facet", facet),
       ("data-bp-expect-ok", expectedAttr) ]
    (Verso.Output.Html.seq
      (#[titleNode, noteNode, summaryNode] ++ extras ++ #[previewHeaderNode, bodyNode]))

private def graphDataExample : Verso.Output.Html :=
  let titleNode :=
    clientTag "h3" #[("data-bp-custom-client-title", "true")] (clientText "Graph manifest data")
  let noteNode :=
    clientTag "p" #[("class", "bp_custom_render_client_note")]
      (clientText "Standalone manifest access with api/graph.mjs loadGraphs; no rendered graph block is required on this page.")
  let summaryNode :=
    clientTag "div"
      #[("class", "bp_custom_render_client_summary"), ("data-bp-custom-client-graph-summary", "true")]
      (clientText "Waiting for graph data.")
  let nodeList :=
    clientTag "div"
      #[("class", "bp_custom_render_client_graph_nodes"), ("data-bp-custom-client-graph-nodes", "true")]
      .empty
  clientTag "article"
    #[ ("class", "bp_custom_render_client_graph"),
       ("data-bp-custom-client-graph", "true"),
       ("data-bp-graph-ok", "false") ]
    (Verso.Output.Html.seq #[titleNode, noteNode, summaryNode, nodeList])

private def previewModuleExample : Verso.Output.Html :=
  let titleNode :=
    clientTag "h3" #[("data-bp-custom-client-title", "true")] (clientText "Preview ESM import")
  let noteNode :=
    clientTag "p" #[("class", "bp_custom_render_client_note")]
      (clientText "ESM access with renderPreviewInto from -verso-data/api/preview.mjs.")
  let summaryNode :=
    clientTag "div"
      #[("class", "bp_custom_render_client_summary"), ("data-bp-preview-module-summary", "true")]
      (clientText "Waiting for preview module.")
  let bodyNode :=
    clientTag "div"
      #[("class", "bp_custom_render_client_body"), ("data-bp-preview-module-body", "true")]
      .empty
  clientTag "article"
    #[ ("class", "bp_custom_render_client_example"),
       ("data-bp-preview-module-example", "true"),
       ("data-bp-preview-module-ok", "false") ]
    (Verso.Output.Html.seq #[titleNode, noteNode, summaryNode, bodyNode])

private def previewModuleExampleScript : Verso.Output.Html :=
  clientTag "script" #[("type", "module")] <| Verso.Output.Html.text false r##"
const { loadPreviewApi } = createBlueprintPreviewApiLoader(window);

// Find the showcase card that will display this module-based result.
const card = document.querySelector("[data-bp-preview-module-example]");
if (card) {
  // Locate the text summary and preview body targets inside the card.
  const summary = card.querySelector("[data-bp-preview-module-summary]");
  const body = card.querySelector("[data-bp-preview-module-body]");
  try {
    // Import the generated preview/render ESM API for this output layout.
    const api = await loadPreviewApi();

    // Build the manifest/cache key for the statement facet.
    const key = api.previewKey("preview_facets", "statement");

    // Load the generated preview manifest through this renderer.
    const manifest = await api.loadManifest();

    // Resolve semantic manifest data and cached HTML for the key.
    const resolved = await api.resolvePreview(key);

    // Render the preview body fragment into the body target.
    if (body) await api.renderPreviewInto(body, key);

    // Store test-visible attributes that describe what the module resolved.
    card.dataset.bpPreviewModuleOk = resolved.ok ? "true" : "false";
    card.dataset.bpPreviewModuleKey = resolved.key || "";
    card.dataset.bpPreviewModuleTitle =
      resolved.manifestEntry && resolved.manifestEntry.title ? resolved.manifestEntry.title : "";
    card.dataset.bpPreviewModuleEntryCount =
      manifest instanceof Map ? String(manifest.size) : "0";
    card.dataset.bpPreviewModuleRenderApi =
      api && typeof api.renderPreviewInto === "function" ? "true" : "false";

    // Update the visible status text for humans inspecting the fixture.
    if (summary) summary.textContent = resolved.ok ? "Rendered through ESM" : resolved.reason;
  } catch (err) {
    // Preserve any import/load/render error for the browser regression test.
    card.dataset.bpPreviewModuleOk = "false";
    card.dataset.bpPreviewModuleError = err && err.message ? err.message : String(err);
    if (summary) summary.textContent = "Preview module error";
  }
}
"##

private def graphModuleExampleScript : Verso.Output.Html :=
  clientTag "script" #[("type", "module")] <| Verso.Output.Html.text false r##"
const { loadPreviewApi } = createBlueprintPreviewApiLoader(window);

// Find the showcase card that already displays graph manifest data.
const card = document.querySelector("[data-bp-custom-client-graph]");
if (card) {
  try {
    // Import the generated preview/render ESM API for this output layout.
    const api = await loadPreviewApi();
    const graphApiUrl =
      typeof api.graphApiModuleUrl === "function"
        ? api.graphApiModuleUrl()
        : api.dataUrl("api/graph.mjs");

    // Import the generated graph-data ESM API.
    const graphModule = await import(graphApiUrl);

    // Load every finalized graph record from blueprint-manifest.json.graphs.
    const graphs = await graphModule.loadGraphs();

    // Use the first graph in this small fixture.
    const graph = graphs[0] || null;

    // Store test-visible attributes that prove the ESM module loaded data.
    card.dataset.bpGraphModuleOk = graph ? "true" : "false";
    card.dataset.bpGraphModuleCount = String(graphs.length);
    card.dataset.bpGraphModuleKey = graph && graph.key ? graph.key : "";
  } catch (err) {
    // Preserve any import/load error for the browser regression test.
    card.dataset.bpGraphModuleOk = "false";
    card.dataset.bpGraphModuleError = err && err.message ? err.message : String(err);
  }
}
"##

private def standaloneRenderNodeMarkdownHtml : Verso.Output.Html :=
  clientTag "section"
    #[ ("id", "standalone-render-node-markdown-example"),
       ("data-bp-standalone-render-node-markdown", "true"),
       ("data-bp-label", "custom_client_external_markdown_metadata"),
       ("data-bp-facet", "statement") ]
    (clientTag "div" #[("data-bp-standalone-render-node-target", "true")] .empty)

def customRenderClientHtml : Verso.Output.Html :=
  let heading := clientTag "h2" #[] (clientText "Standalone Render Client")
  let status :=
    clientTag "div"
      #[("class", "bp_custom_render_client_status"), ("data-bp-custom-client-status-text", "true")]
      (clientText "Idle")
  let header :=
    clientTag "header"
      #[("class", "bp_custom_render_client_header")]
      (Verso.Output.Html.seq #[heading, status])
  let examples :=
    clientTag "div"
      #[("class", "bp_custom_render_client_examples")]
      (Verso.Output.Html.seq #[
        clientExample "render-preview-into" "preview_facets" "statement" "Body fragment"
          "statement"
          "Direct insertion with renderPreviewInto: useful for custom UIs, but intentionally body-only.",
        clientExample "render-node" "preview_facets" "statement" "Label native preview"
          "label-native"
          "Label-oriented renderNode call: native content uses the generated Blueprint node shell.",
        clientExample "render-canonical-preview-into" "preview_facets" "statement" "Canonical statement"
          "canonical-statement"
          "Canonical insertion with renderCanonicalPreviewInto; this reuses the generated Blueprint node wrapper.",
        clientExample "render-canonical-preview-into" "preview_facets" "proof" "Canonical proof"
          "proof"
          "Canonical proof-facet rendering, including the standard Blueprint heading.",
        clientExample "render-canonical-preview-into" "used_target" "statement" "Used-by and code"
          "used-target"
          "A definition with reverse dependencies, the standard used-by chip, and a Lean-code preview key.",
        clientExample "render-canonical-preview-into" "group_target" "statement" "Group header data"
          "group-target"
          "A grouped node with the standard group and used-by header extras.",
        clientExample "render-canonical-preview-into" "used_grouped_proof_panel" "statement" "Grouped theorem"
          "grouped-statement"
          "A theorem with group data, proof dependencies, used-by data, and an associated Lean preview key.",
        clientExample "render-canonical-preview-into" "used_grouped_proof_panel" "proof" "Proof dependencies"
          "grouped-proof"
          "The proof facet for the same theorem, showing proof-side uses and relation metadata.",
        clientExample "render-node" "custom_client_external_markdown_metadata" "statement" "External Markdown fallback"
          "external-markdown"
          "Label-oriented renderNode call: the generated Blueprint shell stays standard while Markdown fills the content slot.",
        clientExample "render-canonical-preview-into" "missing_custom_client_target" "statement" "Missing preview diagnostic"
          "missing"
          "An expected miss that demonstrates the runtime diagnostic branch for custom clients."
          false,
        previewModuleExample,
        graphDataExample
      ])
  let sectionBlock :=
    clientTag "section"
      #[ ("class", "bp_custom_render_client"),
         ("id", "custom-render-client-example"),
         ("data-bp-custom-render-client", "true"),
         ("data-bp-custom-client-status", "idle") ]
      (Verso.Output.Html.seq #[header, examples])
  Verso.Output.Html.seq #[
    sectionBlock,
    standaloneRenderNodeMarkdownHtml,
    previewModuleExampleScript,
    graphModuleExampleScript
  ]

def customRenderClientAssetBundle : Informal.Commands.BlueprintAssetBundle :=
  (Informal.Commands.blueprintCssAssetBundle [customRenderClientCss]).append
    ({ js := [
        customRenderClientJs,
        standaloneRenderNodeMarkdownJs
      ] } : Informal.Commands.BlueprintAssetBundle)

open Verso Doc Elab Genre Manual in
block_extension Block.customRenderClientExample where
  data := Lean.Json.null
  traverse _id _data _contents := pure none
  toTeX := none
  extraCss := customRenderClientAssetBundle.css
  extraJs := customRenderClientAssetBundle.js
  toHtml :=
    some <| fun _goI _goB _id _data _blocks => do
      pure customRenderClientHtml

open Verso Doc Elab in
@[block_command]
public meta def custom_render_client_example : BlockCommandOf Unit
  | () => ``(Block.other Block.customRenderClientExample #[])

end PreviewRuntimeShowcase.Chapters.CustomRenderClient

open PreviewRuntimeShowcase.Chapters.CustomRenderClient

#doc (Manual) "Custom Render Client" =>

This page carries a standalone browser client for the Blueprint render API.

{custom_render_client_example}

:::Informal.group "custom_client_external_metadata_group"
Custom render external metadata group.
:::

:::Informal.source_document "custom-client-paper"
%%%
title := "Representation Theory"
kind := .pdf
pdf := "source/paper.pdf"
pageRoot := "source/pages"
imageRoot := "source/pages/images"
%%%
:::

:::Informal.theorem "custom_client_external_markdown_metadata" (parent := "custom_client_external_metadata_group") (uses := "used_target") (tags := "external, markdown") (effort := "small") (priority := "medium")
%%%
source := {
  document := "custom-client-paper"
  spans := #[
    {
      page := "42"
      text := some {
        path := "source/pages/page-42.md"
        startLine := 10
        endLine := 12
      }
      pdf := some {
        path := "source/pages/page-42.pdf"
        image := "source/pages/images/page-42.png"
        box := some {
          scale := 2
          pageWidth := 1600
          pageHeight := 2200
          xMin := 120
          yMin := 240
          xMax := 980
          yMax := 520
        }
      }
    }
  ]
}
%%%
:::

:::Informal.lemma_ "custom_client_external_metadata_consumer" (uses := "custom_client_external_markdown_metadata")
Consumer node that gives the Markdown fallback target a used-by relation.
:::

```Informal.md "custom_client_external_markdown_metadata" (slot := original)
# External Markdown with metadata
This fallback keeps **manifest metadata** such as uses, used-by, group, tags, priority, and effort.
```

```Informal.md "custom_client_external_markdown" (slot := original)
# External Markdown source
This witness has **only Markdown** attached and no generated Blueprint node shell, so diagnostics can exercise source-only external markup.
```
