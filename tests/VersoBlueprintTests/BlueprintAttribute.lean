/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintAttribute.Reexport

open Lean
open Informal

namespace Verso.VersoBlueprintTests.BlueprintAttribute

private def importedState : CoreM Informal.Environment.State := do
  pure <| Informal.Environment.informalExt.getState (← getEnv)

private def importedNode? (label : String) : CoreM (Option Informal.Data.Node) := do
  pure <| (← importedState).data.get? (Name.mkSimple label)

private def importedNodeInLocalData (label : String) : CoreM Bool := do
  pure <| (← importedState).localData.contains (Name.mkSimple label)

private def isBlueprintAttrRef (expectedDecl : Name) (expectedKind : Informal.Data.NodeKind)
    (node : Informal.Data.Node) : Bool :=
  match node.code with
  | some (.external #[ref]) =>
    ref.origin == .blueprintAttr &&
      ref.present &&
      ref.written == expectedDecl &&
      ref.canonical == expectedDecl &&
      ref.kind == expectedKind
  | _ => false

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let some theoremNode ← importedNode? "attr.exported.theorem"
      | return false
    let some definitionNode ← importedNode? "attr.exported.definition"
      | return false
    let some inductiveNode ← importedNode? "attr.exported.inductive"
      | return false
    let some undocumentedNode ← importedNode? "attr.exported.undocumented"
      | return false
    pure (
      theoremNode.kind == .theorem &&
      theoremNode.code.isSome &&
      theoremNode.statement.isSome &&
      definitionNode.kind == .definition &&
      definitionNode.code.isSome &&
      definitionNode.statement.isSome &&
      inductiveNode.kind == .definition &&
      inductiveNode.code.isSome &&
      inductiveNode.statement.isSome &&
      undocumentedNode.kind == .definition &&
      undocumentedNode.code.isSome
    )

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    pure <|
      !(← importedNodeInLocalData "attr.exported.theorem") &&
      !(← importedNodeInLocalData "attr.exported.definition") &&
      !(← importedNodeInLocalData "attr.exported.inductive") &&
      !(← importedNodeInLocalData "attr.exported.undocumented")

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let some theoremNode ← importedNode? "attr.exported.theorem"
      | return false
    let some definitionNode ← importedNode? "attr.exported.definition"
      | return false
    let some inductiveNode ← importedNode? "attr.exported.inductive"
      | return false
    pure <|
      isBlueprintAttrRef `Verso.VersoBlueprintTests.BlueprintAttribute.Provider.exportedTheorem .theorem theoremNode &&
      isBlueprintAttrRef `Verso.VersoBlueprintTests.BlueprintAttribute.Provider.exportedDefinition .definition definitionNode &&
      isBlueprintAttrRef `Verso.VersoBlueprintTests.BlueprintAttribute.Provider.exportedInductive .definition inductiveNode

/-- Imported statement payloads should keep empty deps and at least one preview source. -/
private def importedStatementExportOk (node : Informal.Data.Node) : Bool :=
  match node.statement with
  | some st => st.deps.isEmpty && (!st.previewBlocks.isEmpty || !st.elabStx.isEmpty)
  | none => false

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let some theoremNode ← importedNode? "attr.exported.theorem"
      | return false
    let some definitionNode ← importedNode? "attr.exported.definition"
      | return false
    let some inductiveNode ← importedNode? "attr.exported.inductive"
      | return false
    let some undocumentedNode ← importedNode? "attr.exported.undocumented"
      | return false
    pure <|
      importedStatementExportOk theoremNode &&
      importedStatementExportOk definitionNode &&
      importedStatementExportOk inductiveNode &&
      undocumentedNode.statement.isNone

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let state ← importedState
    pure <|
      state.data.contains (Name.mkSimple "attr.exported.theorem") &&
      state.data.contains (Name.mkSimple "attr.exported.definition") &&
      state.data.contains (Name.mkSimple "attr.exported.inductive") &&
      state.data.contains (Name.mkSimple "attr.exported.undocumented")

end Verso.VersoBlueprintTests.BlueprintAttribute
