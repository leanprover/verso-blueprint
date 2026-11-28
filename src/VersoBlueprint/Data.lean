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

/-- Effective edge metadata for presentation. Validation consumes the original
scoped {name}`NodeInventory.uses` declarations. -/
def NodeInventory.usesOn (node : NodeInventory) (role : Name) : Array UseRef :=
  UseRef.mergeByLabel #[] ((node.uses.filter (·.role == role)).map (·.reference))

/-- A named prose view for rendering. Admission permits one nonempty prose body
per realization and role. Dependency-only views retain the ordinary placeholder behavior;
this presentation value is never stored or used to infer validation scope. -/
def NodeInventory.proseView (node : NodeInventory) (realization role : Name) : Option InformalBody := Id.run do
  let bodies := node.sources.filterMap fun source =>
    if source.destination.realization.name != realization || source.destination.role != some role then none
    else match source.payload with | .prose body _ => some body | _ => none
  return bodies.find? (·.hasBody) <|> bodies[0]? <|>
    (if node.uses.any (·.role == role) then some default else none)

/-- The ordinary displayed prose for a role, including Markdown declaration
docstrings. Prefer a Verso body when present, then Markdown, then placeholders. -/
def NodeInventory.defaultProseView (node : NodeInventory) (role : Name) : Option InformalBody :=
  let verso := node.proseView `verso role
  let markdown := node.proseView `markdown role
  verso.filter (·.hasBody) <|> markdown.filter (·.hasBody) <|> verso <|> markdown

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

def NodeInventory.leanDecls (node : NodeInventory) : Array Name :=
  let external := node.externalAssociationSnapshots.foldl (init := #[]) fun acc ref =>
    if ref.present then pushUniqueNativeName acc ref.canonical else acc
  node.inlineCodes.foldl (init := external) fun acc code =>
    code.definedDeclNames.foldl pushUniqueNativeName acc

def NodeInventory.hasAssociatedCode (node : NodeInventory) : Bool :=
  !node.nativeAssociations.isEmpty || !node.inlineCodes.isEmpty

def NodeInventory.hasStatementBody (node : NodeInventory) : Bool :=
  node.sources.any (·.adoption.isSome) || (node.defaultProseView `statement).any (·.hasBody)

def NodeInventory.hasProofBody (node : NodeInventory) : Bool := (node.defaultProseView `proof).any (·.hasBody)

end Informal.Data
