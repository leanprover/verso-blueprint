/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.SourcePayload
import VersoBlueprint.Realizations

/-! Keyed raw source inputs for the canonical collector. These are recipes and
subordinate presentation payloads, not admitted model fragments or observations.
Producer identities belong to the complete registration envelope. This module
installs no store, producer, default selection policy or completion evaluator. -/

namespace Informal.SourceData

open Lean Realizations

structure FacetDestination where
  realization : RealizationKey
  facet : Name
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

def FacetDestination.subject (destination : FacetDestination) : Subject :=
  .facet destination.realization destination.facet

/-- Heterogeneous provider payloads retain their actual typed representation.
The canonical document/context and destination are supplied separately. -/
inductive ProviderPayload where
  | prose (body : Data.InformalBody)
  | leanInline (code : Data.Code)
  | text (raw : String)
  deriving Repr, Inhabited

structure FacetSource where
  destination : FacetDestination
  context : Context
  document : DocumentKey
  source : Data.SourceLocationResult
  payload : ProviderPayload
  deriving Repr, Inhabited

/-- Absent realization means an authored concept-level constraint. Automatic or
manual origin is metadata, not a substitute for this explicit scope. -/
structure UseDeclaration where
  node : Name
  realization : Option Name := none
  facet : Name
  reference : Data.UseRef
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

/-- Native associations preserve Lean's typed identity and every snapshot field.
The collector must retain the whole association, including its destination, in
producer equality. Foreign identifiers never enter this Lean-provider type. -/
structure NativeAssociation where
  realization : RealizationKey
  context : Context
  facets : Array Name
  reference : Data.ExternalRef
  deriving Repr, Inhabited, DecidableEq, ToJson

private def issue (code : String) (subject : Subject) (message : String) : Diagnostic :=
  { code, subject := (toJson subject).compress, message }

private def destinationIssues (node : Name) (key : RealizationKey) (context : Context)
    (model : Realization) : Array Diagnostic := Id.run do
  let subject := Subject.realization key
  let mut issues := #[]
  if node.isAnonymous || !key.valid || key.node != node || key != model.key then
    issues := issues.push (issue "source-destination-mismatch" subject
      "Enclosing concept, source destination and composed realization must agree")
  if !context.valid || context != model.context then
    issues := issues.push (issue "source-context-mismatch" subject
      "Source context must equal its composed realization context")
  return issues

/-- Structural assertions against the complete composed definition. This does
not read source, compare producer envelopes, admit a fragment or check a proof. -/
def FacetSource.issues (source : FacetSource) (node : Name) (model : Realization) : Array Diagnostic := Id.run do
  let subject := source.destination.subject
  let mut issues := destinationIssues node source.destination.realization source.context model
  if source.destination.facet.isAnonymous ||
      !model.facets.any (·.name == source.destination.facet) then
    issues := issues.push (issue "unknown-source-facet" subject
      "Source destination must select an explicitly declared facet")
  if !source.document.valid || source.document.context != source.context then
    issues := issues.push (issue "source-document-context" subject
      "Canonical source document must belong to this source context")
  if !model.facets.any (fun facet => facet.name == source.destination.facet &&
      facet.documents.contains source.document) then
    issues := issues.push (issue "source-document-membership" subject
      "Composed facet must retain its canonical source document")
  match source.payload with
  | .leanInline _ =>
    if source.context.language != `lean then
      issues := issues.push (issue "source-payload-context" subject
        "Compiled Lean payload requires a Lean source context")
  | _ => pure ()
  match source.source.ok, source.source.location, source.source.error with
  | true, some location, none =>
    if blank location.path then
      issues := issues.push (issue "invalid-source-location" subject "Original source path is empty")
  | false, none, some reason =>
    if blank reason then
      issues := issues.push (issue "invalid-source-location" subject "Unavailable source needs an explanation")
  | _, _, _ =>
    issues := issues.push (issue "invalid-source-location" subject
      "Source location must be explicitly found or unavailable")
  return issues

/-- Validate raw native destinations only. Missing declarations are retained,
not silently filtered. Name-stability admission and current native checking stay
with their existing owning boundaries; no spelling normalization occurs here. -/
def NativeAssociation.issues (association : NativeAssociation) (node : Name)
    (model : Realization) : Array Diagnostic := Id.run do
  let subject := Subject.realization association.realization
  let mut issues := destinationIssues node association.realization association.context model
  if association.context.language != `lean then
    issues := issues.push (issue "wrong-native-context" subject "Native Lean association requires Lean context")
  if association.facets.isEmpty then
    issues := issues.push (issue "empty-native-facets" subject "Native association must select explicit facets")
  if (canonical association.facets).size != association.facets.size then
    issues := issues.push (issue "duplicate-native-facet" subject "Native association repeats a destination facet")
  for name in association.facets do
    if name.isAnonymous || !model.facets.any (·.name == name) then
      issues := issues.push (issue "unknown-native-facet" subject "Native association selects an undeclared facet")
  return issues

/-- Preserve concept-level statement/proof axes and explicit realization scope.
This does not resolve the target label or turn a selection error into a status. -/
def UseDeclaration.issues (use : UseDeclaration) (node : Name)
    (models : Array Realization) : Array Diagnostic := Id.run do
  let diagnostic (code message : String) : Diagnostic := {
    code, subject := use.node.toString, message }
  let mut issues := #[]
  if node.isAnonymous || use.node != node || (use.reference.label : Name).isAnonymous then
    issues := issues.push (diagnostic "use-destination-mismatch" "Use must preserve its enclosing concept and target label")
  match use.realization with
  | none =>
    if use.facet != `statement && use.facet != `proof then
      issues := issues.push (diagnostic "unknown-shared-use-axis" "Shared uses require a statement or proof axis")
  | some name =>
    let candidates := (canonical models).filter (fun model => model.key == ⟨node, name⟩)
    if name.isAnonymous || candidates.isEmpty then
      issues := issues.push (diagnostic "missing-use-realization" "Use selects no declared realization")
    else if candidates.size != 1 then
      issues := issues.push (diagnostic "ambiguous-use-realization" "Use selects competing realization definitions")
    else if use.facet.isAnonymous || !candidates[0]!.facets.any (·.name == use.facet) then
      issues := issues.push (diagnostic "unknown-use-facet" "Use selects an undeclared realization facet")
  return issues

end Informal.SourceData
