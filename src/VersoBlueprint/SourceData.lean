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
  /-- Raw markup and its authored external location; never a rendered/parsed surrogate. -/
  | markup (value : Data.ExternalMarkup)
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

/-- One registration in the existing Blueprint entry/transaction. Metadata is
language independent; sources and dependencies retain their exact destinations.
This is raw authoring input, not a partial admitted model or validation result. -/
structure Registration extends Data.NodeContribution where
  sources : Array FacetSource := #[]
  uses : Array UseDeclaration := #[]
  deriving Repr, Inhabited

/-- Attach an explicit producer-chosen scope. Origin and intent are preserved
metadata: an authored `origin := automatic` does not imply native inference. -/
def usesFor (node : Name) (realization : Option Name) (facet : Name)
    (references : Array Data.UseRef) : Array UseDeclaration :=
  references.map fun reference => { node, realization, facet, reference }

/-- Provider bytes stay unmodified. Only redundant elaborated preview syntax is
compacted on export, as in the ordinary existing import boundary. -/
def Registration.compact (registration : Registration) : Registration :=
  { registration with sources := registration.sources.map fun source =>
      match source.payload with
      | .prose body =>
        { source with payload := .prose <|
            if body.previewBlocks.isEmpty then body else { body with elabStx := #[] } }
      | _ => source }

/-- A prose body or explicit authored kind establishes the concept's origin. -/
def Registration.claimsAuthoredNode (registration : Registration) : Bool :=
  registration.kind.isSome || registration.sources.any fun source =>
    match source.payload with | .prose body => body.hasBody | _ => false

/-- Exact source lookup for producers/consumers that require one named facet. -/
def Registration.proseAt (registration : Registration) (key : RealizationKey)
    (context : Context) (facet : Name) : Array Data.InformalBody :=
  registration.sources.filterMap fun source =>
    if source.destination != ⟨key, facet⟩ || source.context != context then none else
      match source.payload with | .prose body => some body | _ => none

/-- Native associations preserve Lean's typed identity and every snapshot field.
The collector must retain the whole association, including its destination, in
producer equality. Foreign identifiers never enter this Lean-provider type. -/
structure NativeAssociation where
  realization : RealizationKey
  context : Context
  facets : Array Name
  reference : Data.ExternalRef
  deriving Repr, Inhabited, DecidableEq, ToJson

/-- Basic raw-envelope assertions, before a complete composed model exists.
Retain malformed typed names for their separate native admission boundary. -/
def NativeAssociation.rawIssues (association : NativeAssociation) (node : Name) : Array Diagnostic := Id.run do
  let subject := (toJson (Subject.realization association.realization)).compress
  let diagnostic (code message : String) : Diagnostic := { code, subject, message }
  let mut issues := #[]
  if node.isAnonymous || !association.realization.valid || association.realization.node != node then
    issues := issues.push (diagnostic "source-destination-mismatch"
      "Native association destination must retain its enclosing concept")
  if !association.context.valid || association.context.language != `lean then
    issues := issues.push (diagnostic "wrong-native-context"
      "Native association requires an explicit Lean project context")
  if association.facets.isEmpty then
    issues := issues.push (diagnostic "empty-native-facets" "Native association must select explicit facets")
  if (canonical association.facets).size != association.facets.size then
    issues := issues.push (diagnostic "duplicate-native-facet" "Native association repeats a destination facet")
  if association.facets.any (·.isAnonymous) then
    issues := issues.push (diagnostic "unknown-native-facet" "Native association has an anonymous facet")
  return issues

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

/-- Structural source assertions available before complete model composition. -/
def FacetSource.rawIssues (source : FacetSource) (node : Name) : Array Diagnostic := Id.run do
  let subject := source.destination.subject
  let mut issues := #[]
  if node.isAnonymous || !source.destination.realization.valid || source.destination.realization.node != node then
    issues := issues.push (issue "source-destination-mismatch" subject "Source must retain its enclosing concept")
  if source.destination.facet.isAnonymous then
    issues := issues.push (issue "unknown-source-facet" subject "Source requires an explicit facet")
  if !source.context.valid || !source.document.valid || source.document.context != source.context then
    issues := issues.push (issue "source-document-context" subject "Source requires an explicit project, language and owning document")
  match source.payload with
  | .leanInline _ =>
    if source.context.language != `lean then
      issues := issues.push (issue "source-payload-context" subject "Compiled Lean payload requires a Lean source context")
  | .prose _ =>
    if source.context.language != `verso then
      issues := issues.push (issue "source-payload-context" subject "Verso prose requires a Verso source context")
  | .markup value =>
    if source.context.language != Name.mkSimple value.language.key then
      issues := issues.push (issue "source-payload-context" subject "Markup language must agree with its source context")
  | .text _ => pure ()
  match source.source.ok, source.source.location, source.source.error with
  | true, some location, none =>
    if blank location.path || location.path != source.document.path then
      issues := issues.push (issue "invalid-source-location" subject "Source location must belong to its owning document")
  | false, none, some reason =>
    if blank reason then
      issues := issues.push (issue "invalid-source-location" subject "Unavailable source needs an explanation")
  | _, _, _ =>
    issues := issues.push (issue "invalid-source-location" subject "Source location must be explicitly found or unavailable")
  return issues

/-- Structural assertions against the complete composed definition. This does
not read source, compare producer envelopes, admit a fragment or check a proof. -/
def FacetSource.issues (source : FacetSource) (node : Name) (model : Realization) : Array Diagnostic := Id.run do
  let subject := source.destination.subject
  let mut issues := source.rawIssues node ++
    destinationIssues node source.destination.realization source.context model
  if !model.facets.any (·.name == source.destination.facet) then
    issues := issues.push (issue "unknown-source-facet" subject "Source must select an explicitly declared facet")
  if !model.facets.any (fun facet => facet.name == source.destination.facet && facet.documents.contains source.document) then
    issues := issues.push (issue "source-document-membership" subject "Composed facet must retain its canonical source document")
  return issues

/-- Validate raw native destinations only. Missing declarations are retained,
not silently filtered. Name-stability admission and current native checking stay
with their existing owning boundaries; no spelling normalization occurs here. -/
def NativeAssociation.issues (association : NativeAssociation) (node : Name)
    (model : Realization) : Array Diagnostic := Id.run do
  let subject := Subject.realization association.realization
  let mut issues := association.rawIssues node ++
    destinationIssues node association.realization association.context model
  for name in association.facets do
    if name.isAnonymous || !model.facets.any (·.name == name) then
      issues := issues.push (issue "unknown-native-facet" subject "Native association selects an undeclared facet")
  return issues

/-- Full typed native union before resolution or presentation selection. Missing
references and inline definitions/theorems all remain inputs. This enumeration
does not erase macro scopes, parse a foreign name or certify native admission. -/
def nativeNames (associations : Array NativeAssociation) (sources : Array FacetSource) : Array Name := Id.run do
  let external := associations.map (·.reference.canonical)
  let inline := sources.flatMap fun source => match source.payload with
    | .leanInline code => code.definedDefs.map (·.name) ++ code.definedTheorems.map (·.name)
    | _ => #[]
  let mut seen : Std.HashSet Name := {}
  let mut names := #[]
  for name in external ++ inline do
    unless seen.contains name do
      seen := seen.insert name
      names := names.push name
  return names

/-- Check the complete native membership of an ordinary composed Lean model.
Unlike the destination-only `issues` checks, this requires exact realization and
facet unions. Call on the whole collected batch for this realization, including
all missing references and inline declarations, before full model admission.

The existing string ObjectKey codec has a bounded supported scope: reject a
non-round-tripping typed identity instead of comparing it to another declaration.
This is not the selected-name admission gate, source lookup or proof checking.
No model, input record, required key or presentation payload is changed. -/
def nativeMembershipIssues (node : Name) (model : Realization)
    (associations : Array NativeAssociation) (sources : Array FacetSource) : Array Diagnostic := Id.run do
  let subject := Subject.realization model.key
  let mut issues := destinationIssues node model.key model.context model ++
    associations.flatMap (·.issues node model) ++ sources.flatMap (·.issues node model)
  if model.context.language != `lean then
    issues := issues.push (issue "wrong-native-context" subject
      "Native membership checking requires an ordinary Lean realization")
  -- Keep the typed Name through collection; only a lossless supported spelling
  -- may cross the present pure model's ObjectKey boundary.
  let names := nativeNames associations sources
  for name in names do
    if name.isAnonymous || name.toString.toName != name then
      issues := issues.push (issue "unsupported-native-identity" subject
        "Collected native identity cannot be represented losslessly by the current ObjectKey codec")
  let object (name : Name) : ObjectKey := ⟨model.context, name.toString⟩
  let expected := canonical (names.map object)
  let actual := canonical (model.declarations.map (·.object))
  if actual != expected then
    issues := issues.push (issue "native-declaration-membership" subject
      "Composed declarations must equal the full native association and inline declaration union")
  for facet in model.facets do
    let external := associations.filter (·.facets.contains facet.name) |>.map (·.reference.canonical)
    let inline := sources.flatMap fun source =>
      if source.destination.facet != facet.name then #[] else match source.payload with
      | .leanInline code => code.definedDefs.map (·.name) ++ code.definedTheorems.map (·.name)
      | _ => #[]
    let expected := canonical ((external ++ inline).map object)
    if canonical facet.declarations != expected then
      issues := issues.push (issue "native-facet-membership" (.facet model.key facet.name)
        "Composed facet declarations must equal its full selected native and inline declaration union")
  return canonical issues

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
