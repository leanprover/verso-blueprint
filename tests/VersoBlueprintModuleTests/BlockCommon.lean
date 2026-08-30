/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Informal.Block.Assets
import VersoBlueprint.Informal.Block.Common
import VersoBlueprint.Informal.Block.RelatedPanel
import VersoBlueprint.Informal.Block.Render
import VersoBlueprint.Informal.MetadataView
import VersoBlueprint.Informal.RustPanel
meta import VersoBlueprint.Informal.Block.Assets
meta import VersoBlueprint.Informal.Block.Common
meta import VersoBlueprint.Informal.Block.RelatedPanel
meta import VersoBlueprint.Informal.Block.Render
meta import VersoBlueprint.Informal.MetadataView
meta import VersoBlueprint.Informal.RustPanel

namespace VersoBlueprintModuleTests.BlockCommon

open Lean
open Informal

local macro "codePanelHeaderContract" : term => do
  let data : BlockData := {
    kind := .statement .lemma
    label := Name.mkSimple "module.block.common"
    count := 4
  }
  let header := codePanelHeader data "2.4"
  return quote (header.caption, header.number?)

local macro "blockAssetCountsContract" : term => do
  return quote (
    Informal.Block.Assets.codeAssetBundle.css.length,
    Informal.Block.Assets.blockAssetBundle.css.length,
    Informal.Block.Assets.blockAssetBundle.js.length)

local macro "metadataPresentationContract" : term => do
  let metadata : MetadataPresentation := {
    ownerText := some "Ada"
    priority := some "high"
    prUrl := some "https://example.test/pr/7"
    tags := #["module"]
  }
  let contract : Bool × Array String × Array String := (
    metadata.hasAny,
    metadata.summaryBadgeSpecs.map (·.text),
    metadata.summaryActionLinks.map (·.label))
  return quote contract

local macro "blockRenderContract" : term => do
  let style := BlockKindRenderStyle.ofInProgressKind (.statement .lemma)
  let customKind := HeaderExtraKind.custom (Name.mkSimple "contract")
  let contract : String × Bool × String × String :=
    (style.kindText, style.showLabel, style.wrapperCss, customKind.slotKey)
  return quote contract

local macro "relatedPanelContract" : term => do
  let cfg := RelatedPanel.usedByPanelConfig (some (Name.mkSimple "module.target"))
  let contract : String × String × String :=
    (cfg.chipText 2, cfg.chipTitle 2, cfg.panelTitle 2)
  return quote contract

local macro "rustPanelHeaderContract" : term => do
  let data : BlockData := {
    kind := .proof
    label := Name.mkSimple "module.rust.panel"
    count := 1
  }
  let header := Informal.Rust.codePanelHeader data "ignored"
  return quote (header.caption, header.number?)

/-- info: true -/
#guard_msgs in
#eval
  let header : String × Option String := codePanelHeaderContract
  let assetCounts : Nat × Nat × Nat := blockAssetCountsContract
  let metadataContract : Bool × Array String × Array String := metadataPresentationContract
  let renderContract : String × Bool × String × String := blockRenderContract
  let relationContract : String × String × String := relatedPanelContract
  let rustHeader : String × Option String := rustPanelHeaderContract
  let rustHtml := Informal.Rust.renderRawCodePanel
    { caption := "Rust code" } "Rust module panel" "fn main() {}" |>.asString
  let statusHtml := BlockStatusMark.toHtml {
    status := .missing
    title := "Module status"
  } |>.asString
  header == ("Lean code for Lemma", some "2.4") &&
    assetCounts == (3, 7, 1) &&
    Informal.Block.Assets.css.contains ".bp_wrapper" &&
    metadataContract == (true, #["owner: Ada", "priority: high", "tag: module"], #["PR"]) &&
    !MetadataPresentation.hasAny {} &&
    renderContract ==
      ("Lemma", true,
        "lemma_thmwrapper theorem-style-plain bp_kind_lemma bp_style_plain",
        "custom_contract") &&
    (renderBlockTitleRow (BlockKindRenderStyle.ofInProgressKind .proof)
      "proof.contract" "" "Proof").asString.contains "bp_kind_proof_caption" &&
    relationContract ==
      ("used by 2", "Reverse dependencies for «module.target»", "Used by 2") &&
    rustHeader == ("Rust code for proof", none) &&
    rustHtml.contains "bp_code_panel" && rustHtml.contains "bp_rust_kw" &&
    RelatedPanel.statementAxisBadgeCode == "s" && RelatedPanel.proofAxisBadgeCode == "p" &&
    externalRenderFailureSummaryText 1 == "render failed for 1 declaration" &&
    appendExternalRenderFailureSummary "Lean" 2 ==
      "Lean; render failed for 2 declarations" &&
    statusHtml.contains "bp_status_mark" && statusHtml.contains "Module status"

end VersoBlueprintModuleTests.BlockCommon
