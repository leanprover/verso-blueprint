/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Informal.Block.Assets
import VersoBlueprint.Informal.Block.Common
import VersoBlueprint.Informal.MetadataView
meta import VersoBlueprint.Informal.Block.Assets
meta import VersoBlueprint.Informal.Block.Common
meta import VersoBlueprint.Informal.MetadataView

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

/-- info: true -/
#guard_msgs in
#eval
  let header : String × Option String := codePanelHeaderContract
  let assetCounts : Nat × Nat × Nat := blockAssetCountsContract
  let metadataContract : Bool × Array String × Array String := metadataPresentationContract
  let statusHtml := BlockStatusMark.toHtml {
    status := .missing
    title := "Module status"
  } |>.asString
  header == ("Lean code for Lemma", some "2.4") &&
    assetCounts == (3, 7, 1) &&
    Informal.Block.Assets.css.contains ".bp_wrapper" &&
    metadataContract == (true, #["owner: Ada", "priority: high", "tag: module"], #["PR"]) &&
    !MetadataPresentation.hasAny {} &&
    externalRenderFailureSummaryText 1 == "render failed for 1 declaration" &&
    appendExternalRenderFailureSummary "Lean" 2 ==
      "Lean; render failed for 2 declarations" &&
    statusHtml.contains "bp_status_mark" && statusHtml.contains "Module status"

end VersoBlueprintModuleTests.BlockCommon
