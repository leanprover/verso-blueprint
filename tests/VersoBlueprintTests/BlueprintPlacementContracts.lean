/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintAttributeRendering
import VersoBlueprintTests.BlueprintNumbering.ChapterA
import VersoBlueprintTests.BlueprintNumbering.ChapterB
import VersoBlueprintTests.BlueprintImportedContributions.DocstringA
import VersoBlueprintTests.BlueprintImportedContributions.DocstringB

open Lean Verso Informal Verso.Genre.Manual
open Verso.VersoBlueprintTests.Blueprint.Support
open Verso.VersoBlueprintTests

namespace Verso.VersoBlueprintTests.BlueprintPlacementContracts

private def impls : ExtensionImpls := extension_impls%

#docs (Genre.Manual) contributorA "First contributor" :=
:::::::
{includeBlueprintModule VersoBlueprintTests.BlueprintImportedContributions.DocstringA}
:::::::

#docs (Genre.Manual) contributorB "Second contributor" :=
:::::::
{includeBlueprintModule VersoBlueprintTests.BlueprintImportedContributions.DocstringB}
:::::::

-- Selection is exact-module contribution, while rendering uses the merged node.
#eval show IO Unit from do
  for doc in #[contributorA, contributorB] do
    let html ← renderManualDocHtmlString impls doc
    unless hasSubstr html "docstringAttachmentA" && hasSubstr html "docstringAttachmentB" do
      throw <| IO.userError "Module inclusion lost a sibling's contribution"
  let html ← renderManualDocHtmlString impls contributorB
  unless !hasSubstr html "docstringAuthoredAttachment" do
    throw <| IO.userError "Module inclusion selected another module's distinct label"

set_option verso.blueprint.foldCodeBlocks true in
#docs (Genre.Manual) folded "Folded placement" :=
:::::::
{blueprint_node "attr.exported.theorem"}
:::::::

set_option verso.blueprint.foldCodeBlocks false in
#docs (Genre.Manual) expanded "Expanded placement" :=
:::::::
{blueprint_node "attr.exported.theorem"}
:::::::

#docs (Genre.Manual) compact "Compact placement" :=
:::::::
{blueprint_node "attr.exported.theorem" +compact}
:::::::

private def combine (docs : Array (Doc.VersoDoc Genre.Manual)) : Doc.VersoDoc Genre.Manual :=
  .mk (fun _ => { folded.toPart with content := #[], subParts := docs.map (·.toPart) }) "{}"

-- The advertised declaration link must name exactly one emitted row, including
-- compact-first placement. A compact-only document must not advertise a code row.
#eval show IO Unit from do
  let label := Name.mkSimple "attr.exported.theorem"
  let decl := ``BlueprintAttribute.Provider.exportedTheorem
  for doc in #[BlueprintAttributeRendering.placedAttributeDoc,
      BlueprintAttributeRendering.includedAttributeModuleDoc,
      combine #[folded, expanded], combine #[compact, expanded]] do
    let (html, state) ← renderManualDocHtmlStringAndState impls doc
    let some href := Resolve.resolveInformalDeclHref? state label decl
      | throw <| IO.userError "Missing declaration destination"
    let fragment := (href.splitOn "#").getLast!
    unless countSubstr html s!"id=\"{fragment}\"" == 1 do
      throw <| IO.userError s!"Declaration destination is missing or duplicated: {href}"
    let rows := (html.splitOn "bp_external_decl_item").length
    unless rows > 1 do throw <| IO.userError "Destination has no rendered code"
  let (_, state) ← renderManualDocHtmlStringAndState impls compact
  unless (Resolve.resolveRenderedExternalDeclHref? state label decl).isNone do
    throw <| IO.userError "Compact placement advertised code it does not render"

-- Each occurrence honors its own setting. The selected facet supplies the
-- exported default, independently of the second occurrence's override.
#eval show IO Unit from do
  for (docs, defaultFold) in #[(#[folded, expanded], true), (#[expanded, folded], false)] do
    let doc := combine docs
    let (html, state) ← renderManualDocHtmlStringAndState impls doc
    unless countSubstr html "class=\"bp_code_block bp_code_panel\"" == 2 &&
        countSubstr html "open=\"open\"" == 1 do
      throw <| IO.userError "Repeated placements lost occurrence-local folding"
    let files ← PreviewManifest.buildPreviewDataFiles impls (fun e => throw <| IO.userError e)
      (PreviewManifest.PreparedPreviewState.prepare state)
    let node := ({ label := "attr.exported.theorem" } : Graft.BlueprintNodeConfig).toNode
    let some entry := files.manifest.findEntry? node.key
      | throw <| IO.userError "Missing selected facet"
    let cached ← Graft.renderNodeFromManifestCache {}
      (Graft.RenderContext.ofPreviewData? (some files.manifest) (some files.htmlCache)) node
    unless entry.foldCodeBlock == defaultFold &&
        hasSubstr cached.asString "open=\"open\"" == !defaultFold do
      throw <| IO.userError "Cached presentation disagrees with the selected occurrence"

set_option verso.blueprint.foldProofBlocks false in
#docs (Genre.Manual) statement "Statement" :=
:::::::
:::theorem "presentation.facets"
Statement with an unfolded proof default.
:::
:::::::

set_option verso.blueprint.foldProofBlocks true in
#docs (Genre.Manual) proof "Proof" :=
:::::::
:::proof "presentation.facets"
Proof with its own folded presentation.
:::
:::::::

#docs (Genre.Manual) proofGraft "Proof reuse" :=
:::::::
{blueprint_node "presentation.facets" (facet := "proof")}
:::::::

#eval show IO Unit from do
  for docs in #[#[statement, proof, proofGraft], #[proof, statement, proofGraft]] do
    let doc := combine docs
    let (html, state) ← renderManualDocHtmlStringAndState impls doc
    unless !hasSubstr html "open=\"open\"" do
      throw <| IO.userError "Direct proof and proof graft disagree on folding"
    let files ← PreviewManifest.buildPreviewDataFiles impls (fun e => throw <| IO.userError e)
      (PreviewManifest.PreparedPreviewState.prepare state)
    let node := ({ label := "presentation.facets", facet := some "proof" } : Graft.BlueprintNodeConfig).toNode
    let some entry := files.manifest.findEntry? node.key | throw <| IO.userError "Missing proof cache"
    let cached ← Graft.renderNodeFromManifestCache {}
      (Graft.RenderContext.ofPreviewData? (some files.manifest) (some files.htmlCache)) node
    unless entry.foldProofBlock && !hasSubstr cached.asString "open=\"open\"" &&
        hasSubstr cached.asString "Proof with its own folded presentation." do
      throw <| IO.userError "Exported proof lost its facet-local presentation"

-- These chapters were elaborated independently, not fabricated as completed
-- occurrences. Reordering them or inserting an attribute placement cannot
-- change their positive local counts.
#eval show IO Unit from do
  let a := BlueprintNumbering.ChapterA.chapter
  let b := BlueprintNumbering.ChapterB.chapter
  for docs in #[#[a, b], #[b, a], #[a, expanded, b], #[b, expanded, a]] do
    let (_, state) ← renderManualDocHtmlStringAndState impls (combine docs)
    for chapterName in #["A", "B"] do
      for (suffix, expected) in #[("first", 1), ("second", 2)] do
        let label := Name.mkSimple s!"local.{chapterName}.{suffix}"
        let some data := TraversalIndex.Nodes.renderedData? state label
          | throw <| IO.userError "Missing numbered chapter"
        unless data.count == expected do
          throw <| IO.userError s!"Ordinary source-local count changed for {label}: {data.count}"
  let reordered := Doc.VersoDoc.mk
    (fun _ => { a.toPart with content := a.toPart.content.reverse }) "{}"
  let (_, state) ← renderManualDocHtmlStringAndState impls reordered
  unless (TraversalIndex.Nodes.renderedData? state (Name.mkSimple "local.A.first")).map (·.count) == some 1 do
    throw <| IO.userError "Reordered authored blocks were renumbered"

-- External witnesses change body selection, never the public statement key.
-- Start from both real placement paths and exercise the persisted-data consumer.
#eval show IO Unit from do
  let label := Name.mkSimple "attr.exported.undocumented"
  let node := ({ label := label.toString } : Graft.BlueprintNodeConfig).toNode
  for doc in #[BlueprintAttributeRendering.placedAttributeDoc,
      BlueprintAttributeRendering.includedAttributeModuleDoc] do
    let (blocks, baseline) ← traverseManualDocBlocksAndState impls doc
    for witness in #[none,
        some ({ language := .markdown, slot := "statement", raw := "**Witness marker**" } : Data.ExternalMarkup),
        some { language := .tex, slot := "statement", raw := "Witness marker" },
        some { language := .markdown, slot := "statement", raw := "   " }] do
      let state := match witness with
        | none => baseline
        | some markup => TraversalIndex.ExternalMarkup.saveData baseline label
            (toJson ({ label, markup := ({} : Data.ExternalMarkupSet).insert markup } : Data.ExternalMarkupData))
      let direct ← renderManualBlocksHtmlWithState blocks impls state
      for mode in #[ExternalMarkupRender.Mode.markdown, .none] do
        let files ← PreviewManifest.buildPreviewDataFiles impls (fun e => throw <| IO.userError e)
          (PreviewManifest.PreparedPreviewState.prepare state) { mode }
        let some entry := files.manifest.findEntry? node.key
          | throw <| IO.userError "External witness removed the standard statement key"
        let some _ := files.htmlCache.findHtml? node.key
          | throw <| IO.userError "External witness removed the standard statement body"
        let cached ← Graft.renderNodeFromManifestCache {}
          (Graft.RenderContext.ofPreviewData? (some files.manifest) (some files.htmlCache)) node
        unless hasSubstr cached.asString "exportedUndocumentedDefinition" &&
            !entry.leanCodePreviewKeys.isEmpty &&
            !hasSubstr cached.asString "Blueprint node not found" do
          throw <| IO.userError "Witness attachment broke exported graft reuse"
        if mode == .markdown then
          unless hasSubstr direct.asString "Witness marker" == hasSubstr cached.asString "Witness marker" do
            throw <| IO.userError "Direct and exported witness body availability disagree"

-- Persisted Manual blocks round-trip structurally, including an explicitly
-- empty body. Invalid serialized bodies are rejected at elaboration.
#eval show IO Unit from do
  for block in #[Verso.Doc.Block.para #[.bold #[.text "round trip"]], .concat #[]] do
    let json := toJson (block : Doc.Block Genre.Manual)
    let .ok restored := Graft.decodePersistedManualBlock json.compress
      | throw <| IO.userError "Persisted Manual body failed reconstruction"
    unless toJson restored == json do throw <| IO.userError "Persisted Manual body changed"

open Verso.Doc.Elab in
@[block_command]
meta def malformedPersistedBody : BlockCommandOf Graft.BlueprintNodeConfig
  | _ => Graft.persistedManualBlockTermFromJson "null"

/-- error: Blueprint persisted statement block could not be decoded: object expected -/
#guard_msgs in
#docs (Genre.Manual) rejectedPersistedBody "Rejected persisted body" :=
:::::::
{malformedPersistedBody "unused"}
:::::::

end Verso.VersoBlueprintTests.BlueprintPlacementContracts
