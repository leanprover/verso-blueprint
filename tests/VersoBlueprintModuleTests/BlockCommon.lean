/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Informal.Block.Assets
import VersoBlueprint.Informal.Block.Common
meta import VersoBlueprint.Informal.Block.Assets
meta import VersoBlueprint.Informal.Block.Common

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

/-- info: true -/
#guard_msgs in
#eval
  let header : String × Option String := codePanelHeaderContract
  let assetCounts : Nat × Nat × Nat := blockAssetCountsContract
  let statusHtml := BlockStatusMark.toHtml {
    status := .missing
    title := "Module status"
  } |>.asString
  header == ("Lean code for Lemma", some "2.4") &&
    assetCounts == (3, 7, 1) &&
    Informal.Block.Assets.css.contains ".bp_wrapper" &&
    externalRenderFailureSummaryText 1 == "render failed for 1 declaration" &&
    appendExternalRenderFailureSummary "Lean" 2 ==
      "Lean; render failed for 2 declarations" &&
    statusHtml.contains "bp_status_mark" && statusHtml.contains "Module status"

end VersoBlueprintModuleTests.BlockCommon
