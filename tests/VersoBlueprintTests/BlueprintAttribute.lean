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

private def importedNodeHasLocalContributions (label : String) : CoreM Bool := do
  pure <| (← importedState).localContributions.contains (Name.mkSimple label)

private def isBlueprintAttrRef (expectedDecl : Name) (expectedKind : Informal.Data.NodeKind)
    (node : Informal.Data.Node) : Bool :=
  match node.externalRefs with
  | #[ref] =>
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
      theoremNode.hasAssociatedCode &&
      theoremNode.statement.isSome &&
      definitionNode.kind == .definition &&
      definitionNode.hasAssociatedCode &&
      definitionNode.statement.isSome &&
      inductiveNode.kind == .definition &&
      inductiveNode.hasAssociatedCode &&
      inductiveNode.statement.isSome &&
      undocumentedNode.kind == .definition &&
      undocumentedNode.hasAssociatedCode
    )

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    pure <|
      !(← importedNodeHasLocalContributions "attr.exported.theorem") &&
      !(← importedNodeHasLocalContributions "attr.exported.definition") &&
      !(← importedNodeHasLocalContributions "attr.exported.inductive") &&
      !(← importedNodeHasLocalContributions "attr.exported.undocumented")

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
