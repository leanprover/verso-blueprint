/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintAttribute.Reexport
import VersoBlueprintTests.BlueprintAttribute.HybridProvider
import VersoBlueprintTests.BlueprintAttribute.DefaultLabelProvider
import VersoBlueprintTests.BlueprintAttribute.ProjectionGraft
import VersoBlueprint.Realizations.Capture

open Lean
open Lean.Elab Command Term
open Informal

namespace Verso.VersoBlueprintTests.BlueprintAttribute

private def importedState : CoreM Informal.Environment.State := do
  pure <| Informal.Environment.informalExt.getState (← getEnv)

private def importedNode? (label : String) : CoreM (Option Informal.Data.NodeInventory) := do
  pure <| (← importedState).inventory.get? (Name.mkSimple label)

private def importedNodeByName? (label : Name) : CoreM (Option Informal.Data.NodeInventory) := do
  pure <| (← importedState).inventory.get? label

private def importedNodeHasLocalContributions (label : String) : CoreM Bool := do
  pure <| !((← importedState).nodeRegistrations.getD (Name.mkSimple label) {}).localRegistrations.isEmpty

private def isBlueprintAttrRef (expectedDecl : Name) (expectedKind : Informal.Data.NodeKind)
    (node : Informal.Data.NodeInventory) : Bool :=
  match node.nativeRefsOn `statement with
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
      (theoremNode.proseView `markdown `statement).isSome &&
      definitionNode.kind == .definition &&
      definitionNode.hasAssociatedCode &&
      (definitionNode.proseView `markdown `statement).isSome &&
      inductiveNode.kind == .definition &&
      inductiveNode.hasAssociatedCode &&
      (inductiveNode.proseView `markdown `statement).isSome &&
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
        Name.mkSimple "attr.hybrid.shared",
        Name.mkSimple "attr.hybrid.late_docstring",
        Name.mkSimple "attr.hybrid.first_body"
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
    let some lateDocstringNode ← importedNode? "attr.hybrid.late_docstring"
      | return false
    let some firstBodyNode ← importedNode? "attr.hybrid.first_body"
      | return false
    let versoDoc? ← liftM <| findInternalDocString? (← getEnv)
      `Verso.VersoBlueprintTests.BlueprintAttribute.HybridProvider.hybridVersoDocstring
    let bodyWasPersisted :=
      match bodyNode.proseView `verso `statement with
      | some statement => statement.hasBody
      | none => false
    let lateDocstringDidNotFill :=
      match lateDocstringNode.proseView `verso `statement with
      | some statement =>
        !statement.hasBody &&
          (lateDocstringNode.usesOn `statement).map (·.label) ==
            #[Name.mkSimple "attr.hybrid.verso_docstring"]
      | none => false
    pure <|
      bodyWasPersisted &&
      (match versoDoc? with | some (.inr _) => true | _ => false) &&
      sharedNode.leanDecls == #[
        `Verso.VersoBlueprintTests.BlueprintAttribute.HybridProvider.hybridSharedFirst,
        `Verso.VersoBlueprintTests.BlueprintAttribute.HybridProvider.hybridSharedSecond
      ] &&
      lateDocstringDidNotFill &&
      lateDocstringNode.leanDecls == #[
        `Verso.VersoBlueprintTests.BlueprintAttribute.HybridProvider.hybridLateDocstringFirst,
        `Verso.VersoBlueprintTests.BlueprintAttribute.HybridProvider.hybridLateDocstringSecond
      ] &&
      firstBodyNode.leanDecls == #[
        `Verso.VersoBlueprintTests.BlueprintAttribute.HybridProvider.hybridFirstBody,
        `Verso.VersoBlueprintTests.BlueprintAttribute.HybridProvider.hybridLaterBody
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
private def importedStatementExportOk (node : Informal.Data.NodeInventory) : Bool :=
  match node.proseView `markdown `statement with
  | some st => (node.usesOn `statement).isEmpty &&
      st.hasBody
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
      (undocumentedNode.defaultProseView `statement).isNone

#docs (Verso.Genre.Manual) proofForMarkdownDocstring "Proof for Markdown docstring" :=
:::::::
:::proof "attr.exported.theorem"
A Verso proof of the Markdown statement.
:::
:::::::

/-- error: Label «attr.exported.theorem» already defined -/
#guard_msgs in
#docs (Verso.Genre.Manual) competingStatement "Competing statement" :=
:::::::
:::theorem "attr.exported.theorem"
A competing Verso statement.
:::
:::::::

run_cmd liftTermElabM do
  let markdownLabel := Name.mkSimple "attr.exported.theorem"
  let versoLabel := Name.mkSimple "attr.hybrid.verso_docstring"
  let raw := Realizations.Capture.Raw.ofState (← importedState)
  let plan := Realizations.Capture.plan { raw with
    nodes := raw.nodes.filter fun (label, _) => label == markdownLabel || label == versoLabel }
  let snapshot ← match ← Realizations.Capture.observe plan with
    | .ok observations =>
      match Realizations.Capture.evaluate plan observations with
      | .ok snapshot => pure snapshot
      | .error issues => throwError "Docstring capture failed: {repr issues}"
    | .error issues => throwError "Docstring observation failed: {repr issues}"
  unless snapshot.diagnostics.isEmpty do
    throwError "Docstring capture reported diagnostics: {repr snapshot.diagnostics}"
  for (label, format, role, marker) in #[
      (markdownLabel, `markdown, `statement, " Exported theorem used to verify `@[blueprint]` persistence across imports. "),
      (markdownLabel, `verso, `proof, "A Verso proof of the Markdown statement."),
      (versoLabel, `verso, `statement, "A *structurally emphasized Verso docstring body*")] do
    let key := Realizations.RealizationKey.forRole ⟨label, format⟩ role
    let some model := snapshot.registry.realization? key
      | throwError "Missing {format} {role} realization for {label}"
    let some document := snapshot.registry.documents.find? fun doc => model.documents.contains doc.key
      | throwError "Missing document for {format} {role} of {label}"
    unless model.context.language == format && document.key.context == model.context &&
        document.text.contains marker && (format != `markdown || document.text == marker) do
      throwError "Captured {format} {role} lost its source context or bytes: {repr document}"

-- Stored prose paths and native association paths may use different spellings.
-- A byte-identical copy at a different physical path still cannot own the comment.
run_cmd liftTermElabM do
  let label := Name.mkSimple "attr.exported.theorem"
  let raw := Realizations.Capture.Raw.ofState (← importedState)
  let some (_, node) := raw.nodes.find? (·.1 == label) | throwError "Missing attribute fixture"
  let some source := node.sources.find? (·.ownDocstring.isSome) | throwError "Missing owned source"
  let physical ← IO.FS.realPath source.document.path
  let check (spelling : String) (available : Bool)
      (reader : System.FilePath → IO String := IO.FS.readFile) := do
    let relocation (loc : Data.SourceLocation) := { loc with path := spelling }
    let moved := { source with document.path := spelling, source.location := source.source.location.map relocation }
    let node := { node with sources := #[moved] }
    let plan := Realizations.Capture.plan { raw with
      nodes := #[(label, node)], authored := #[]
      facts := raw.facts.map fun fact =>
        if fact.label == label && fact.id.producer == `blueprint.attribute then
          { fact with source := fact.source.map relocation } else fact }
    let .ok observed ← Realizations.Capture.observe plan reader | throwError "Source observation aborted"
    let .ok snap := Realizations.Capture.evaluate plan observed | throwError "Source replay aborted"
    let doc := snap.registry.documents.find? (·.key == moved.selectedDocumentKey)
    unless (doc.any (fun value => value.text.contains "Exported theorem")) == available &&
        (snap.diagnostics.any (·.code == "source-selection-unavailable")) == !available do
      throwError "Wrong path ownership for {spelling}: {repr snap.diagnostics}"
  let cwd ← IO.FS.realPath (← IO.currentDir)
  let relative := (physical.toString.dropPrefix (cwd.toString ++ "/")).toString
  unless relative != physical.toString do throwError "Expected a project-local source"
  -- A restored module can lack Lake trace inputs. The compiler registration
  -- still authenticates the exact bytes, including material outside the comment.
  let roots ← Lean.searchPathRef.get
  try
    Lean.searchPathRef.set []
    check ("./" ++ relative) true
    check physical.toString false fun path => return (← IO.FS.readFile path) ++ "\n-- edited after compilation"
  finally
    Lean.searchPathRef.set roots
  IO.FS.withTempDir fun tmp => do
    let other := tmp / "copy.lean"
    IO.FS.writeFile other (← IO.FS.readFile physical)
    check other.toString false
    unless System.Platform.isWindows do
      let link := tmp / "alias.lean"
      discard <| IO.Process.run { cmd := "ln", args := #["-s", physical.toString, link.toString] }
      check link.toString true

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
      (node.usesOn `statement).map (·.label) == #[Name.mkSimple "attr.exported.theorem"] &&
      isBlueprintAttrRef decl .theorem node &&
      isBlueprintAttrRef
        `Verso.VersoBlueprintTests.BlueprintAttribute.DefaultLabelProvider.qualifiedDefaultDefinition
        .definition
        definitionNode

-- Local additions follow imported declarations; repeated assembly must not
-- reverse either the imported prefix or the earlier local contributions.
@[blueprint "attr.hybrid.shared"]
def hybridSharedThird : Nat := 41

@[blueprint "attr.hybrid.shared"]
def hybridSharedFourth : Nat := 43

/-- info: true -/
#guard_msgs in
#eval show CoreM Bool from do
  let some node ← importedNode? "attr.hybrid.shared"
    | return false
  return node.leanDecls == #[
    `Verso.VersoBlueprintTests.BlueprintAttribute.HybridProvider.hybridSharedFirst,
    `Verso.VersoBlueprintTests.BlueprintAttribute.HybridProvider.hybridSharedSecond,
    `Verso.VersoBlueprintTests.BlueprintAttribute.hybridSharedThird,
    `Verso.VersoBlueprintTests.BlueprintAttribute.hybridSharedFourth]

end Verso.VersoBlueprintTests.BlueprintAttribute
