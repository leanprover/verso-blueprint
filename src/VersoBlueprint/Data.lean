/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.SourceData
import VersoBlueprint.Realizations

namespace Informal.Data

open Lean
set_option doc.verso true

/-- An assembled body and the declarations needed to validate its dependencies. -/
structure InformalData extends InformalBody where
  /-- One declaration per label and authority; manual precedence never erases validation evidence. -/
  useDeclarations : Array UseRef := #[]
deriving Repr, Inhabited

def InformalData.hasBody (data : InformalData) : Bool := data.toInformalBody.hasBody

/-- Effective dependency edges, with manual metadata taking precedence. -/
def InformalData.deps (data : InformalData) : Array UseRef :=
  UseRef.mergeByLabel #[] data.useDeclarations

def InformalData.dependencyLabels (data : InformalData) : Array Label :=
  data.deps.map (·.label)

/-- The compiled node information of one label: the checked assembly of all its
registrations, together with their module provenance. It is derived state,
rebuilt from the persisted registrations on import, and never exported itself.
This is not an admitted validation registry: source facts and rendered snapshots
cannot establish proof completion. Destinations and scopes remain explicit. -/
structure NodeInventory extends NodeMetadata where
  sources : Array SourceData.SourceSelection := #[]
  uses : Array SourceData.UseDeclaration := #[]
  nativeAssociations : Array SourceData.NativeAssociation := #[]
  /-- The module that introduced the label; an authored origin takes precedence. -/
  origin : Name := .anonymous
  /-- Every module that contributed an accepted registration. -/
  modules : Array Name := #[]
deriving Repr, Inhabited

/-- Shared metadata for the validation model; source inventory is collected separately. -/
def NodeInventory.toConcept (node : NodeInventory) (label : Name) (title : String) : Realizations.Node :=
  { toNodeMetadata := node.toNodeMetadata, label, title }

/-- Effective edge metadata for presentation. This is intentionally an aggregate;
validation consumes the original scoped `uses`, never this flattened view. -/
def NodeInventory.usesOn (node : NodeInventory) (role : Name) : Array UseRef :=
  UseRef.mergeByLabel #[] ((node.uses.filter (·.role == role)).map (·.reference))

/-- A named prose view for rendering. Admission permits one nonempty prose body
per realization and role. Dependency-only views retain the ordinary placeholder behavior;
this presentation value is never stored or used to infer validation scope. -/
def NodeInventory.proseView (node : NodeInventory) (realization role : Name) : Option InformalData := Id.run do
  let bodies := node.sources.filterMap fun source =>
    if source.destination.realization.name != realization || source.destination.role != some role then none
    else match source.payload with | .prose body => some body | _ => none
  let body := bodies.find? (·.hasBody) <|> bodies[0]?
  let useDeclarations := ((node.uses.filter (·.role == role)).map (·.reference)).foldl
    (fun refs ref => if refs.contains ref then refs else refs.push ref) #[]
  match body with
  | some body => return some { toInformalBody := body, useDeclarations }
  | none => return if useDeclarations.isEmpty then none
    else some { stx := .missing, useDeclarations }

/-- Native source snapshots at one presentation placement, across all realizations.
The original association inventory retains the realization and context. -/
def NodeInventory.nativeRefsOn (node : NodeInventory) (placement : Name) : Array ExternalRef :=
  ExternalRef.mergeSnapshots #[] <|
    (node.nativeAssociations.filter (·.placement == placement)).map (·.reference)

def NodeInventory.inlineCodes (node : NodeInventory) : Array Code :=
  node.sources.filterMap fun source => match source.payload with
    | .leanInline code => some code | _ => none

def NodeInventory.hasAttributeAssociations (node : NodeInventory) : Bool :=
  node.nativeAssociations.any (·.reference.origin == .blueprintAttr)

/-- All captured associations, including arbitrary named placements. -/
def NodeInventory.externalAssociationSnapshots (node : NodeInventory) : Array ExternalRef :=
  node.nativeAssociations.map (·.reference)

/-- Canonical node associations from every placement. Rendering keeps each placement's
snapshot; node-level projections retain every observed status conservatively. -/
def NodeInventory.associatedExternalRefs (node : NodeInventory) : Array ExternalRef :=
  ExternalRef.mergeSnapshots #[] node.externalAssociationSnapshots

/-- External summary entries not already supplied by a compiled literate declaration. -/
def NodeInventory.summaryExternalRefs (node : NodeInventory) : Array ExternalRef :=
  let names := node.inlineCodes.foldl (init := ({} : NameSet)) fun names code =>
    code.definedDeclNames.foldl (fun names name => names.insert name) names
  node.associatedExternalRefs.filter fun ref => !names.contains ref.canonical.eraseMacroScopes

/-- Prefer each inline declaration once for summaries, preserving status evidence
from every external and inline association of the same canonical declaration.
The authored code blocks remain unchanged for rendering and provenance. -/
def NodeInventory.summaryLiterateCodes (node : NodeInventory) : Array Code := Id.run do
  let observations := node.associatedExternalRefs.map
      (fun ref => (ref.canonical, if ref.present then ref.provedStatus else .missing)) ++
    node.inlineCodes.flatMap fun code =>
      code.definedDefs.map (fun decl => (decl.name, decl.provedStatus)) ++
      code.definedTheorems.map (fun decl => (decl.name, decl.provedStatus))
  let statuses := ProvedStatus.indexByName observations
  let mut seen : NameSet := {}
  let mut codes := #[]
  for code in node.inlineCodes do
    let mut definitions := #[]
    let mut theorems := #[]
    for decl in code.definedDefs do
      let name := decl.name.eraseMacroScopes
      unless seen.contains name do
        seen := seen.insert name
        definitions := definitions.push { decl with provedStatus := statuses.getD name decl.provedStatus }
    for decl in code.definedTheorems do
      let name := decl.name.eraseMacroScopes
      unless seen.contains name do
        seen := seen.insert name
        theorems := theorems.push { decl with provedStatus := statuses.getD name decl.provedStatus }
    codes := codes.push { code with definedDefs := definitions, definedTheorems := theorems }
  return codes

def NodeInventory.leanDecls (node : NodeInventory) : Array Name :=
  let external := node.externalAssociationSnapshots.foldl (init := #[]) fun acc ref =>
    if ref.present then pushUniqueNativeName acc ref.canonical else acc
  node.inlineCodes.foldl (init := external) fun acc code =>
    code.definedDeclNames.foldl pushUniqueNativeName acc

def NodeInventory.hasAssociatedCode (node : NodeInventory) : Bool :=
  !node.nativeAssociations.isEmpty || !node.inlineCodes.isEmpty

def NodeInventory.hasStatementBody (node : NodeInventory) : Bool := (node.proseView `verso `statement).any (·.hasBody)

def NodeInventory.hasProofBody (node : NodeInventory) : Bool := (node.proseView `verso `proof).any (·.hasBody)

end Informal.Data
