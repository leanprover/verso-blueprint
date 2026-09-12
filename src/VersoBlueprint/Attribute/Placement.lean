/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Environment
import VersoBlueprint.Graft.Node
import VersoBlueprint.Informal.Block.Common

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
deriving ToJson, FromJson, Quote

def Placement.showsCode (placement : Placement) : Bool :=
  !placement.config.compact && placement.config.toNode.facet == "statement"

def nodeHasBlueprintAttributeAttachments (node : Data.Node) : Bool :=
  node.externalRefs.any fun ref => ref.origin == .blueprintAttr

/-- Decode the persisted Manual representation without disguising failure as prose. -/
def decodePersistedManualBlock (jsonText : String) :
    Except String (Doc.Block Genre.Manual) :=
  Json.parse jsonText >>= fromJson?

/-- Validate at the consuming elaboration boundary, before constructing a body term. -/
public meta def persistedManualBlockTermFromJson (jsonText : String) : DocElabM Term := do
  match decodePersistedManualBlock jsonText with
  | .error err => throwError "Blueprint persisted statement block could not be decoded: {err}"
  | .ok _ =>
    `((Informal.Graft.decodePersistedManualBlock $(quote jsonText)).toOption.get!)

private meta def attributeNodeOccurrence? (cfg : BlueprintNodeConfig) :
    DocElabM (Option (BlockOccurrence × Array Syntax)) := do
  if cfg.toNode.facet != "statement" then return none
  let label := LabelNameParsing.parse cfg.label
  let some node ← Environment.getNode? label | return none
  if !nodeHasBlueprintAttributeAttachments node then return none
  let statementStxs ←
    match node.statement with
    | none => pure #[]
    | some statement =>
      if statement.previewBlocks.isEmpty then
        pure statement.elabStx
      else
        statement.previewBlocks.mapM fun block =>
          return (← persistedManualBlockTermFromJson (toJson block).compress).raw
  let opts ← getOptions
  let sourceLocation :=
    match ← Data.SourceLocation.ofSyntax? (← getRef) with
    | some location => Data.SourceLocationResult.found location
    | none => Data.SourceLocationResult.unavailable s!"placement source location unavailable for {label}"
  let occurrence : BlockOccurrence := {
    label, sourceLocation
    foldProofBlock := verso.blueprint.foldProofBlocks.get opts
    foldCodeBlock := verso.blueprint.foldCodeBlocks.get opts
    count := 0
    numberingMode := Informal.numberingMode opts
    subNumberingPrefix := Informal.subNumberingPrefix opts
    subNumberingCounter := Informal.subNumberingCounter opts
  }
  return some (occurrence, statementStxs)

public meta def elaboratePlacement (config : BlueprintNodeConfig) :
    DocElabM (Placement × Array Term) := do
  let source ← attributeNodeOccurrence? config
  let opts ← getOptions
  return ({
    config
    statement := source.map (·.1)
    foldProofBlock := if opts.contains `verso.blueprint.foldProofBlocks then
      some (verso.blueprint.foldProofBlocks.get opts) else none
    foldCodeBlock := if opts.contains `verso.blueprint.foldCodeBlocks then
      some (verso.blueprint.foldCodeBlocks.get opts) else none
  }, source.map (·.2.map (⟨·⟩)) |>.getD #[])

end Informal.Graft
