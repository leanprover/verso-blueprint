/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
module

public import VersoBlueprint.Graft.Node
public import VersoBlueprint.Informal.Block.Common
meta import VersoBlueprint.Graft.Node
meta import VersoBlueprint.Informal.Block.Common

public section

namespace Informal.Graft

open Lean Verso Doc Elab

/--
One visible placement. An optional statement occurrence materializes attribute
contributions; it is not a second, invisible source block. The placement's id
owns any emitted code destinations. Explicit folding options override the
selected facet's defaults, without changing that facet or the node's number.
-/
structure Placement where
  config : BlueprintNodeConfig
  statement : Option BlockOccurrence := none
  foldProofBlock : Option Bool := none
  foldCodeBlock : Option Bool := none
deriving ToJson, FromJson

meta instance : Quote Placement where
  quote placement := Syntax.mkCApp ``Placement.mk #[quote placement.config,
    quote placement.statement, quote placement.foldProofBlock, quote placement.foldCodeBlock]

def Placement.showsCode (placement : Placement) : Bool :=
  !placement.config.compact && placement.config.toNode.facet == "statement"

def nodeHasBlueprintAttributeAttachments (node : Data.Node) : Bool :=
  node.blueprintAttributeAttachments

/-- Decode the persisted Manual representation without disguising failure as prose. -/
def decodePersistedManualBlock (jsonText : String) :
    Except String (Doc.Block Genre.Manual) :=
  Json.parse jsonText >>= fromJson?

end Informal.Graft
