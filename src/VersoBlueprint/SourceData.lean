/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.SourcePayload
import VersoBlueprint.Realizations
import VersoBlueprint.Util.SHA256
import Vir.Package.Name

/-! Keyed raw source inputs for the canonical collector. These are recipes and
subordinate presentation payloads, not admitted model fragments or observations.
Producer identities belong to the complete registration envelope. This module
installs no store, producer, default selection policy or completion evaluator. -/

namespace Informal.SourceData

open Lean Realizations

/-- Existing source directives name their implementation side `body`; captured
records use the model's common `proof` role for the checked implementation. -/
def selectedRole (role : Name) : Name :=
  if role == Name.mkSimple "body" then `proof else role

/-- Interpret a legacy source slot using the checked native content roles.
Computational definitions have no separately declared proposition, so the
legacy statement/body slots select their implementation value. A checked
statement/proof pair always belongs to both direct roles: selecting either
facet of the same declaration must not lose the other native projection. -/
def selectedNativeRole (slot : Name) (roles : Array Name) : Name :=
  if slot == Name.mkSimple "body" then
    if roles.contains `proof then `proof
    else if roles.contains `implementation then `implementation
    else if roles.contains `statement then `statement
    else selectedRole slot
  else if slot == `statement && roles.contains `implementation && !roles.contains `statement then
    `implementation
  else slot

/-- Resolve source-selected slots to the native direct roles they can actually
provide. A theorem/proof-valued definition has two checked projections of one
declaration, so either source slot retains both; other declaration classes keep
only their checked role. -/
def selectedNativeRoles (slots roles : Array Name) : Array Name := Id.run do
  let mut selected := canonical (slots.map fun slot => selectedNativeRole slot roles)
  if roles.contains `statement && roles.contains `proof &&
      (selected.contains `statement || selected.contains `proof) then
    selected := canonical (selected ++ #[`statement, `proof])
  return selected

structure FacetDestination where
  realization : RealizationKey
  facet : Name
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

def FacetDestination.subject (destination : FacetDestination) : Subject :=
  .realization (destination.realization.forRole (selectedRole destination.facet))

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

/-- Stable identity for the exact authored source selection. Coordinates are
deliberately absent so moving unchanged prose does not change its identity. -/
private def FacetSource.selectionIdentity (source : FacetSource) : String :=
  match source.payload with
  | .prose body => Id.run do
    let .original leading _ _ _ := body.stx.getHeadInfo | return "unavailable"
    let .original _ _ trailing _ := body.stx.getTailInfo | return "unavailable"
    unless leading.str == trailing.str do return "unavailable"
    let some range := body.stx.getRange? | return "unavailable"
    if range.start.byteIdx > range.stop.byteIdx || range.stop.byteIdx > leading.str.utf8ByteSize then
      return "unavailable"
    let bytes := String.Pos.Raw.extract leading.str ⟨range.start.byteIdx⟩ ⟨range.stop.byteIdx⟩
    SHA256.text bytes
  | _ => "whole-document"

def FacetSource.selectedDocumentKey (source : FacetSource) : DocumentKey :=
  match source.payload with
  | .prose _ => { source.document with
      path := source.document.path ++ "#selection:" ++ (toJson (
        Vir.nameKey source.destination.realization.node,
        Vir.nameKey source.destination.realization.name,
        Vir.nameKey (selectedRole source.destination.facet),
        source.selectionIdentity)).compress }
  | _ => source.document

/-- Extract only an original prose selection from its owning document. Cached
preview/AST renderings and nearby text are never substituted. -/
def FacetSource.selectedText (source : FacetSource) (document : Document) : Except Diagnostic String := do
  let .prose body := source.payload
    | return document.text
  let subject := source.destination.subject
  let fail (message : String) : Except Diagnostic String := .error {
    code := "source-selection-unavailable", subject := (toJson subject).compress, message }
  unless document.key == source.document do
    return ← fail "Owning document identity disagrees with the source selection"
  let some location := source.source.location
    | return ← fail (source.source.error.getD "Source selection has no original location")
  unless source.source.ok && location.path == document.key.path do
    return ← fail "Source selection is unavailable at its canonical owning path"
  let .original leading _ _ _ := body.stx.getHeadInfo
    | return ← fail "Prose selection has no original syntax start"
  let .original _ _ trailing _ := body.stx.getTailInfo
    | return ← fail "Prose selection has no original syntax end"
  unless leading.str == document.text && trailing.str == document.text do
    return ← fail "Prose syntax belongs to a different source buffer"
  let some range := body.stx.getRange?
    | return ← fail "Prose selection has no original byte range"
  let map := FileMap.ofString document.text
  unless map.utf8RangeToLspRange range == location.range do
    return ← fail "Stored UTF-16 source range disagrees with the owning FileMap"
  unless range.start.byteIdx <= range.stop.byteIdx &&
      range.stop.byteIdx <= document.text.utf8ByteSize do
    return ← fail "Prose selection range is outside its owning document"
  return String.Pos.Raw.extract document.text ⟨range.start.byteIdx⟩ ⟨range.stop.byteIdx⟩

/-- Absent realization means an authored concept-level constraint. Automatic or
manual origin is metadata, not a substitute for this explicit scope. -/
structure UseDeclaration where
  node : Name
  realization : Option Name := none
  facet : Name
  reference : Data.UseRef
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

/-- Source dependency axes retain their authored meaning. For a computational
definition, both ordinary axes constrain its single implementation realization.
Exact current keys and ordinary producer base-name shorthand use the same rule. -/
def useSelectsRealization (node : Name) (realization : Option Name) (facet : Name)
    (model : Realization) : Bool :=
  let role := selectedRole facet
  let compatible := model.role == role ||
    (model.context.language == `lean && model.role == `implementation &&
      (role == `statement || role == `proof))
  model.key.node == node && compatible && realization.all fun name =>
    model.key == ⟨node, name⟩ || model.key == (RealizationKey.forRole ⟨node, name⟩ model.role)

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
    if source.context.language != `verso && source.context.language != `markdown then
      issues := issues.push (issue "source-payload-context" subject
        "Prose requires its original Verso or Markdown source context")
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
    destinationIssues node model.key source.context model
  if model.key != source.destination.realization.forRole (selectedRole source.destination.facet) ||
      model.role != selectedRole source.destination.facet then
    issues := issues.push (issue "source-role-mismatch" subject "Source must select its explicit realization role")
  if !model.documents.contains source.selectedDocumentKey then
    issues := issues.push (issue "source-document-membership" subject "Composed realization must retain its selected source document")
  return issues

/-- Validate raw native destinations only. Missing declarations are retained,
not silently filtered. Name-stability admission and current native checking stay
with their existing owning boundaries; no spelling normalization occurs here. -/
def NativeAssociation.issues (association : NativeAssociation) (node : Name)
    (model : Realization) : Array Diagnostic := Id.run do
  let subject := Subject.realization (association.realization.forRole model.role)
  let mut issues := association.rawIssues node ++
    destinationIssues node model.key association.context model
  for name in association.facets do
    if name.isAnonymous then
      issues := issues.push (issue "unknown-native-role" subject "Native association has an empty selected role")
  if !(association.facets.any (fun role => selectedRole role == model.role)) then
    issues := issues.push (issue "unknown-native-role" subject "Native association does not select this realization role")
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
    (associations : Array NativeAssociation) (sources : Array FacetSource)
    (checkedRoles : Array (Name × Array Name) := #[]) : Array Diagnostic := Id.run do
  let subject := Subject.realization model.key
  let rolesFor (name : Name) : Option (Array Name) := (checkedRoles.find? (·.1 == name)).map (·.2)
  let selectedRolesFor (name : Name) : Array Name := Id.run do
    let mut slots := associations.filter (·.reference.canonical == name) |>.flatMap (·.facets)
    for source in sources do
      if let .leanInline code := source.payload then
        if code.definedDeclNames.contains name then slots := slots.push source.destination.facet
    let roles := rolesFor name |>.getD #[]
    if roles.isEmpty then return canonical (slots.map selectedRole)
    return selectedNativeRoles slots roles
  let mut issues := destinationIssues node model.key model.context model
  if checkedRoles.isEmpty then
    issues := issues ++ associations.flatMap (·.issues node model) ++ sources.flatMap (·.issues node model)
  else
    issues := issues ++ associations.flatMap fun association => Id.run do
      let mut found := association.rawIssues node ++ destinationIssues node model.key association.context model
      let name := association.reference.canonical
      if let some roles := rolesFor name then
        if association.realization.forRole model.role != model.key then
          found := found.push (issue "source-destination-mismatch" (.realization model.key)
            "Native association does not belong to this direct realization")
        if !roles.isEmpty then
          for slot in association.facets do
            if !(roles.contains (selectedNativeRole slot roles)) then
              found := found.push (issue "native-role-membership" (.realization model.key)
                "Native association selects a role incompatible with the checked declaration")
      else if association.facets.any (fun slot => selectedRole slot == model.role) then
        if association.realization.forRole model.role != model.key then
          found := found.push (issue "source-destination-mismatch" (.realization model.key)
            "Missing native declaration belongs to a different direct realization")
      return found
    issues := issues ++ sources.flatMap fun source => Id.run do
      let mut found := source.rawIssues node ++ destinationIssues node model.key source.context model
      if let .leanInline code := source.payload then
        if source.destination.realization.forRole model.role != model.key then
          found := found.push (issue "source-destination-mismatch" (.realization model.key)
            "Inline source does not belong to this direct realization")
        for name in code.definedDeclNames do
          if let some roles := rolesFor name then
            if !roles.isEmpty && !(roles.contains (selectedNativeRole source.destination.facet roles)) then
              found := found.push (issue "native-role-membership" (.realization model.key)
                "Inline source selects a role incompatible with the checked declaration")
          else if selectedRole source.destination.facet == model.role &&
              source.destination.realization.forRole model.role != model.key then
            found := found.push (issue "source-destination-mismatch" (.realization model.key)
              "Inline source belongs to a different direct realization")
      else if selectedRole source.destination.facet == model.role &&
          source.destination.realization.forRole model.role != model.key then
        found := found.push (issue "source-destination-mismatch" (.realization model.key)
          "Native source belongs to a different direct realization")
      return found
  if model.context.language != `lean then
    issues := issues.push (issue "wrong-native-context" subject
      "Native membership checking requires an ordinary Lean realization")
  let expectedProjection := if model.role == `statement then .statement else .implementation
  if model.role != `statement && model.role != `proof && model.role != `implementation then
    issues := issues.push (issue "unknown-native-role" subject
      "Lean declarations require a statement, proof, or implementation role")
  if model.declarations.any (·.projection != expectedProjection) then
    issues := issues.push (issue "native-role-projection" subject
      "Each native declaration projection must agree with its direct realization role")
  -- Keep the typed Name through collection; only a lossless supported spelling
  -- may cross the present pure model's ObjectKey boundary.
  let names := nativeNames associations sources
  for name in names do
    if name.isAnonymous || name.toString.toName != name then
      issues := issues.push (issue "unsupported-native-identity" subject
        "Collected native identity cannot be represented losslessly by the current ObjectKey codec")
  let object (name : Name) : ObjectKey := ⟨model.context, name.toString⟩
  let expectedNames := names.filter fun name => selectedRolesFor name |>.contains model.role
  let expected := canonical (expectedNames.map object)
  if canonical (model.declarations.map (·.object)) != expected then
    issues := issues.push (issue "native-role-membership" (.realization model.key)
      "Composed realization declarations must equal its selected native and inline declarations")
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
  let role := selectedRole use.facet
  match use.realization with
  | none =>
    if role != `statement && role != `proof then
      issues := issues.push (diagnostic "unknown-shared-use-axis" "Shared uses require a statement or proof axis")
  | some name =>
    let candidates := (canonical models).filter (useSelectsRealization node use.realization use.facet)
    if name.isAnonymous || candidates.isEmpty then
      issues := issues.push (diagnostic "missing-use-realization" "Use selects no declared realization")
    else if candidates.size != 1 then
      issues := issues.push (diagnostic "ambiguous-use-realization" "Use selects competing realization definitions")
    else if role.isAnonymous then
      issues := issues.push (diagnostic "unknown-use-role" "Use selects an empty realization role")
  return issues

end Informal.SourceData
