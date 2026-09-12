/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.Blueprint.Support

open Lean Verso Informal
open Verso.Genre Manual
open Verso.VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintSourceIdentity

def originalSource : Source.Ref := {
  document := "identity-paper"
  spans := #[{
    page := "12", anchor := "lem:original", citation := "Lemma 2.1(1)"
    text := some { path := "source/paper.tex", startLine := 41, endLine := 45 }
    pdf := some {
      path := "source/page-12.pdf", image := some "source/page-12.png"
      box := some {
        scale := 2, pageWidth := 1600, pageHeight := 2200
        xMin := 120, yMin := 240, xMax := 980, yMax := 520
      }
    }
  }]
}

set_option verso.blueprint.numbering "global" in
#docs (Manual) identityDoc "Independent source identities" :=
:::::::
:::source_document "identity-paper"
%%%
title := "Original paper"
pdf := "source/paper.pdf"
%%%
:::

:::source_document "identity-notes"
%%%
title := "Independent notes"
kind := .text
%%%
:::

:::lemma_ "source_identity_primary" (lean := "Nat.add_assoc")
%%%
source := originalSource
%%%
The first informal statement has its own Blueprint number.
:::

```md "source_identity_primary" (slot := statement)
An **informal representation**, not automatically an original excerpt.
```

:::lemma_ "source_identity_secondary" (lean := "Nat.add_assoc") (uses := "source_identity_primary")
%%%
source := { document := "identity-notes", spans := #[{
  anchor := "lem:original", citation := "Lemma 2.1(1)"
}] }
%%%
Another informal statement shares the Lean declaration, not the source identity.
:::

See {bpref "source_identity_primary"}[the first statement].

{blueprint_graph}
:::::::

private def model : RenderModel := blueprint_render_model%
private def impls : ExtensionImpls := extension_impls%

-- Edit only Level 1 before traversal. Keeping one authored AST fixes source-code
-- coordinates as well as the Level 2 bodies, labels, and Level 3 declarations.
private def withSource (source : Source.Ref) : IO (Doc.VersoDoc Manual) := do
  let rewrite (block : Doc.Block Manual) : Except String (Doc.Block Manual) :=
    block.rewriteOtherM
      (fun go container content => return .other container (← content.mapM go))
      (fun _ go container content => do
        let content ← content.mapM go
        if container.name == ``Informal.Block.informal then
          let occurrence ← fromJson? (α := BlockOccurrence) container.data
          if occurrence.label == `source_identity_primary then
            return .other { container with data := toJson { occurrence with sourceRef := some source } } content
        return .other container content)
  let .ok content := identityDoc.toPart.content.mapM rewrite
    | throw <| IO.userError "Could not replace fixture provenance"
  pure <| .mk (fun _ => { identityDoc.toPart with content }) "{}"

structure Snapshot where
  state : TraverseState
  files : PreviewManifest.Files
  html : String

def render (source : Source.Ref) : IO Snapshot := do
  let (html, state) ← renderManualDocHtmlStringAndState impls (← withSource source) (model := model)
  let files ← PreviewManifest.buildPreviewDataFiles impls
    (fun error => throw <| IO.userError error) (PreviewManifest.PreparedPreviewState.prepare state)
  pure { state, files, html }

def sourceCases : Array (String × Source.Ref) :=
  let span := originalSource.spans[0]!
  #[
    ("original", originalSource),
    ("anchor", { originalSource with spans := #[{ span with anchor := some "lem:revised" }] }),
    ("citation", { originalSource with spans := #[{ span with citation := some "Lemma 9.7" }] }),
    ("no-anchor", { originalSource with spans := #[{ span with anchor := none }] }),
    ("no-citation", { originalSource with spans := #[{ span with citation := none }] }),
    ("location", { originalSource with spans := #[{ span with
      page := none, text := some { path := "source/revised.tex", startLine := 80, endLine := 82 },
      pdf := none }] })
  ]

private def xrefTargets (state : TraverseState) : Except String Json := do
  let xref := PreviewManifest.buildPublicXrefJson state
  let domain ← xref.getObjVal? TraversalIndex.Nodes.domainName.toString
  let contents ← domain.getObjVal? "contents"
  return toJson (← #["source_identity_primary", "source_identity_secondary"].mapM fun label => do
    let targets ← contents.getObjValAs? (Array Json) label
    if targets.isEmpty then
      throw s!"Missing cross-reference destination for {label}"
    targets.mapM fun target => do
      return (← target.getObjValAs? String "address", ← target.getObjValAs? String "id"))

#eval show IO Unit from do
  let baseline ← render originalSource
  unless !baseline.files.manifest.graphs.isEmpty do
    throw <| IO.userError "Identity fixture must exercise a finalized graph"
  let some primary := baseline.files.manifest.findEntry? "source_identity_primary--statement"
    | throw <| IO.userError "Identity fixture has no primary statement"
  unless primary.title == "Lemma 1" && !primary.externalMarkup.isEmpty &&
      hasSubstr baseline.html "source: Lemma 2.1(1)" do
    throw <| IO.userError "Fixture must separate Blueprint numbering, source citation, and informal markup"
  let codeKey := TraversalIndex.LeanCodePreviews.lookupKey `Nat.add_assoc
  let baselineTargets ← IO.ofExcept (xrefTargets baseline.state)
  for (name, source) in sourceCases do
    let result ← render source
    -- All semantic entry fields except provenance must be invariant, including
    -- labels, facets, titles, hrefs, Lean keys, code facts, and Level 2 markup.
    let identities (snapshot : Snapshot) := toJson <|
      snapshot.files.manifest.previews.map fun entry => { entry with sources := #[] }
    let targets ← IO.ofExcept (xrefTargets result.state)
    unless identities result == identities baseline &&
        toJson result.files.manifest.graphs == toJson baseline.files.manifest.graphs &&
        targets == baselineTargets do
      throw <| IO.userError s!"{name}: provenance changed semantic identity, graph status, or cross-references"
    for label in #[`source_identity_primary, `source_identity_secondary] do
      let some before := TraversalIndex.Nodes.renderedData? baseline.state label
        | throw <| IO.userError "Missing baseline node"
      let some after := TraversalIndex.Nodes.renderedData? result.state label
        | throw <| IO.userError "Missing changed node"
      unless toJson { before with sourceRef := none } == toJson { after with sourceRef := none } do
        throw <| IO.userError s!"{name}: changed numbering, occurrence location, or declaration associations"
      let some entry := result.files.manifest.findEntry? (PreviewCache.statementKey label)
        | throw <| IO.userError "Missing statement"
      unless entry.leanCodePreviewKeys.contains codeKey do
        throw <| IO.userError "Both nodes must retain their shared Lean declaration"
    let some changed := result.files.manifest.findEntry? primary.key
      | throw <| IO.userError "Missing changed statement"
    let some code := result.files.manifest.findEntry? codeKey
      | throw <| IO.userError "Missing shared Lean preview"
    unless changed.sources == #[source] && code.sources.size == 2 &&
        code.sources.contains source && code.sources.any (·.document == "identity-notes") do
      throw <| IO.userError s!"{name}: lost provenance, document qualification, or shared-declaration aggregation"
    let expectedChip := source.spans[0]!.citation.map (s!"source: {·}") |>.getD "source 1"
    unless hasSubstr result.html s!">{expectedChip}<" &&
        (name == "original" || result.html != baseline.html) do
      throw <| IO.userError s!"{name}: provenance presentation did not change"

end Verso.VersoBlueprintTests.BlueprintSourceIdentity
