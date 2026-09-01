/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Slides.Node
meta import VersoBlueprint.Slides.Node

namespace VersoBlueprintModuleTests.SlidesNode

open Verso Doc Elab

meta example : Informal.Graft.BlueprintNodeConfig → DocElabM Lean.Term :=
  Informal.Slides.blueprintNodeBlock

/-- info: true -/
#guard_msgs in
#eval
  let node : Informal.Graft.BlueprintNode := {
    label := "module.slides"
    key := "module-slides--statement"
    compact := true
  }
  let attrs := Informal.Slides.blueprintNodeAttrs node
  let renderedAttrs := Informal.Slides.renderedBlueprintNodeAttrs node
  let sideBySide := Informal.Slides.sideBySideAttrs { boxed := true }
  let expectedClass :=
    "bp_graft_manifest_node bp_graft_manifest_node_compact " ++
      "bp_slide_node bp_slide_node_compact"
  attrs.contains ("class", expectedClass) &&
    renderedAttrs.contains ("class", expectedClass) &&
    sideBySide.contains
      ("class", "bp_graft_side_by_side bp_graft_side_by_side_boxed bp_slide_graft_side_by_side")

end VersoBlueprintModuleTests.SlidesNode
