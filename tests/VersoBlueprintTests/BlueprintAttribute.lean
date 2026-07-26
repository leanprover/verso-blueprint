/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintAttribute.Reexport
import VersoBlueprintTests.BlueprintAttribute.HybridProvider
import VersoBlueprintTests.BlueprintAttribute.DefaultLabelProvider

open Lean
open Informal

namespace Verso.VersoBlueprintTests.BlueprintAttribute

/-
`uses` is a Manual role, not a Lean `doc.verso` role. Keep the diagnostic
explicit so documentation cannot drift back toward describing it as a flattened
docstring extension.
-/
/--
error: `uses : Doc.Elab.RoleExpanderOf UsesConfig` is not registered as a role
-/
#guard_msgs in
set_option doc.verso true in
/--
A declaration docstring containing {uses "attr.exported.theorem"}[].
-/
@[blueprint "attr.docstring.rejected_uses"]
def rejectedDocstringUsesRole : Nat := 0

private def importedState : CoreM Informal.Environment.State := do
  pure <| Informal.Environment.informalExt.getState (← getEnv)

private def importedNode? (label : String) : CoreM (Option Informal.Data.Node) := do
  pure <| (← importedState).data.get? (Name.mkSimple label)

private def importedNodeByName? (label : Name) : CoreM (Option Informal.Data.Node) := do
  pure <| (← importedState).data.get? label

private def importedNodeInLocalData (label : String) : CoreM Bool := do
  pure <| (← importedState).localData.contains (Name.mkSimple label)

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
      !(← importedNodeInLocalData "attr.exported.theorem") &&
      !(← importedNodeInLocalData "attr.exported.definition") &&
      !(← importedNodeInLocalData "attr.exported.inductive") &&
      !(← importedNodeInLocalData "attr.exported.undocumented")

/- Imported module catalogs retain direct attribute ownership and source order. -/
/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let providerLabels ← Informal.Environment.blueprintAttributeLabelsForModule
      `VersoBlueprintTests.BlueprintAttribute.Provider
    let reexportLabels ← Informal.Environment.blueprintAttributeLabelsForModule
      `VersoBlueprintTests.BlueprintAttribute.Reexport
    let hybridLabels ← Informal.Environment.blueprintAttributeLabelsForModule
      `VersoBlueprintTests.BlueprintAttribute.HybridProvider
    let defaultLabelProviderLabels ← Informal.Environment.blueprintAttributeLabelsForModule
      `VersoBlueprintTests.BlueprintAttribute.DefaultLabelProvider
    pure <|
      providerLabels == #[
        Name.mkSimple "attr.exported.theorem",
        Name.mkSimple "attr.exported.definition",
        Name.mkSimple "attr.exported.inductive",
        Name.mkSimple "attr.exported.undocumented"
      ] &&
      hybridLabels == #[
        Name.mkSimple "attr.hybrid.body",
        Name.mkSimple "attr.hybrid.verso_docstring",
        Name.mkSimple "attr.hybrid.shared"
      ] &&
      defaultLabelProviderLabels == #[
        Name.mkSimple
          "Verso.VersoBlueprintTests.BlueprintAttribute.DefaultLabelProvider.qualifiedDefaultLabel",
        Name.mkSimple
          "Verso.VersoBlueprintTests.BlueprintAttribute.DefaultLabelProvider.qualifiedDefaultDefinition"
      ] &&
      reexportLabels.isEmpty

/- Hybrid fixtures exercise persisted bodies, structural Verso docstrings, and many-to-one labels. -/
/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let some bodyNode ← importedNode? "attr.hybrid.body"
      | return false
    let some sharedNode ← importedNode? "attr.hybrid.shared"
      | return false
    let versoDoc? ← liftM <| findInternalDocString? (← getEnv)
      `Verso.VersoBlueprintTests.BlueprintAttribute.HybridProvider.hybridVersoDocstring
    let bodyWasPersisted :=
      match bodyNode.statement with
      | some statement => !statement.previewBlocks.isEmpty && statement.elabStx.isEmpty
      | none => false
    pure <|
      bodyWasPersisted &&
      (match versoDoc? with | some (.inr _) => true | _ => false) &&
      sharedNode.leanDecls == #[
        `Verso.VersoBlueprintTests.BlueprintAttribute.HybridProvider.hybridSharedFirst,
        `Verso.VersoBlueprintTests.BlueprintAttribute.HybridProvider.hybridSharedSecond
      ]

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
      isBlueprintAttrRef
          `Verso.VersoBlueprintTests.BlueprintAttribute.Provider.exportedTheorem
          .theorem theoremNode &&
      isBlueprintAttrRef
          `Verso.VersoBlueprintTests.BlueprintAttribute.Provider.exportedDefinition
          .definition definitionNode &&
      isBlueprintAttrRef
          `Verso.VersoBlueprintTests.BlueprintAttribute.Provider.exportedInductive
          .definition inductiveNode

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

/- Bare attributes use qualified declaration names and retain explicit dependencies. -/
/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let decl :=
      `Verso.VersoBlueprintTests.BlueprintAttribute.DefaultLabelProvider.qualifiedDefaultLabel
    let label := Name.mkSimple decl.toString
    let some node ← importedNodeByName? label
      | return false
    let defaultDefinition :=
      Name.mkSimple
        "Verso.VersoBlueprintTests.BlueprintAttribute.DefaultLabelProvider.qualifiedDefaultDefinition"
    let some definitionNode ← importedNodeByName? defaultDefinition
      | return false
    pure <|
      node.statement.map (·.deps.map (·.label)) ==
        some #[Name.mkSimple "attr.exported.theorem"] &&
      isBlueprintAttrRef decl .theorem node &&
      isBlueprintAttrRef
        `Verso.VersoBlueprintTests.BlueprintAttribute.DefaultLabelProvider.qualifiedDefaultDefinition
        .definition
        definitionNode

end Verso.VersoBlueprintTests.BlueprintAttribute
