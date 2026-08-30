/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Graft.Node
meta import VersoBlueprint.Graft.Node

namespace VersoBlueprintModuleTests.GraftNode

open Lean
open Verso Doc Elab ArgParse

meta example : FromArgs Informal.Graft.BlueprintNodeConfig DocElabM := inferInstance
meta example : FromArgs Informal.Graft.SideBySideConfig DocElabM := inferInstance

local macro "graftNodeConfigContract" : term => do
  let cfg : Informal.Graft.BlueprintNodeConfig := {
    label := "modulegraft"
    facet := "proof"
    displayLabel := "Module Graft"
    compact := true
    showHeader := false
    siteBase := "/module-site"
  }
  return quote cfg

/-- info: true -/
#guard_msgs in
#eval
  let cfg : Informal.Graft.BlueprintNodeConfig := graftNodeConfigContract
  let node := cfg.toNode
  let attrs := node.toAttrs
  node.key == "modulegraft--proof" &&
    node.displayLabel? == some "Module Graft" &&
    node.compact && !node.showHeader &&
    node.siteBase? == some "/module-site" &&
    Informal.Graft.BlueprintNode.fromAttrs? attrs == some node &&
    (node.renderedAttrsWithClass "module-contract").contains
      ("class", "bp_graft_manifest_node bp_graft_manifest_node_compact module-contract") &&
    ({ boxed := true } : Informal.Graft.SideBySideConfig).className ==
      "bp_graft_side_by_side bp_graft_side_by_side_boxed"

end VersoBlueprintModuleTests.GraftNode
