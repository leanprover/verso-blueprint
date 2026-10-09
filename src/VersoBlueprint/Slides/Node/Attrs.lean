/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoBlueprint.Graft.Node

public section

namespace Informal.Slides

private def blueprintNodeClassName (node : Informal.Graft.BlueprintNode) : String :=
  if node.compact then
    "bp_slide_node bp_slide_node_compact"
  else
    "bp_slide_node"

def blueprintNodeAttrs (node : Informal.Graft.BlueprintNode) :
    Array (String × String) :=
  Informal.Graft.appendClassAttr node.toAttrs (blueprintNodeClassName node)

def renderedBlueprintNodeAttrs (node : Informal.Graft.BlueprintNode) :
    Array (String × String) :=
  node.renderedAttrsWithClass (blueprintNodeClassName node)

def sideBySideAttrs (cfg : Informal.Graft.SideBySideConfig) :
    Array (String × String) :=
  #[("class", cfg.className ++ " bp_slide_graft_side_by_side")]

end Informal.Slides
