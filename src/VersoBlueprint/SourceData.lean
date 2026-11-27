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

/-- Where an authored source belongs. Prose, text and markup sources state the
role of their selected content, such as `statement`, `proof` or `implementation`.
Compiled Lean payloads state no role: capture derives each declaration's roles
from its checked classification. -/
structure SourceDestination where
  realization : RealizationKey
  role : Option Name
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

def SourceDestination.subject (destination : SourceDestination) : Subject :=
  match destination.role with
  | some role => .realization (destination.realization.forRole role)
  | none => .realization destination.realization

/-- Heterogeneous provider payloads retain their actual typed representation.
The canonical document/context and destination are supplied separately. -/
inductive ProviderPayload where
  | prose (body : Data.InformalBody)
  | leanInline (code : Data.Code)
  | text (raw : String)
  /-- Raw markup and its authored external location; never a rendered/parsed surrogate. -/
  | markup (value : Data.ExternalMarkup)
  deriving Repr, Inhabited

/-- Original fence bytes with a body range relative to the fence. The fence
establishes ownership; its body becomes the canonical document. -/
structure FencedSelection where
  private mk ::
  original : String
  body : Syntax.Range
  deriving Repr

/-- The direct doc comment of the declaration introducing an attribute node.
The attribute site locates the registration. The declaration owns the comment. -/
structure OwnDocstring where
  moduleName : Name
  canonical : Name
  deriving Repr

/-- A consumer directive explicitly selects the direct docstring of one of its
native attachments. The site lives in SourceSelection.source. An unavailable
upstream source is assessment data and leaves the native attachment usable. -/
structure AdoptedDocstring where
  consumerModule : Name
  canonical : Name
  moduleName : Name
  package : Option String
  /-- Physical owning path and exact registration-time source digest. -/
  owner : Except Diagnostic (String × String)
  deriving Repr, Inhabited

structure SourceSelection where
  destination : SourceDestination
  context : Context
  document : DocumentKey
  source : Data.SourceLocationResult
  payload : ProviderPayload
  ownDocstring : Option OwnDocstring := none
  adoption : Option AdoptedDocstring := none
  fence : Option (Except String FencedSelection) := none
  deriving Repr, Inhabited

/-- The original buffer and byte range a syntax selection points into. -/
private def syntaxRange (stx : Syntax) : Except String (String × Syntax.Range) := do
  let .original leading _ _ _ := stx.getHeadInfo
    | throw "Selection has no original syntax start"
  let .original _ _ trailing _ := stx.getTailInfo
    | throw "Selection has no original syntax end"
  unless leading.str == trailing.str do
    throw "Selection start and end belong to different source buffers"
  let some range := stx.getRange?
    | throw "Selection has no original byte range"
  unless range.start.byteIdx <= range.stop.byteIdx &&
      String.Pos.Raw.isValid leading.str range.start && String.Pos.Raw.isValid leading.str range.stop do
    throw "Selection range has invalid UTF-8 boundaries in its source buffer"
  return (leading.str, range)

private def extract (buffer : String) (range : Syntax.Range) : String :=
  String.Pos.Raw.extract buffer range.start range.stop

def FencedSelection.ofSyntax (buffer : String) (fence contents : Syntax) : Except String FencedSelection := do
  let (fenceBuffer, outer) ← syntaxRange fence
  let (bodyBuffer, inner) ← syntaxRange contents
  unless fenceBuffer == buffer && bodyBuffer == buffer &&
      outer.start.byteIdx <= inner.start.byteIdx && inner.stop.byteIdx <= outer.stop.byteIdx do
    throw "Code block body is outside its original fence"
  return {
    original := extract buffer outer
    body := ⟨⟨inner.start.byteIdx - outer.start.byteIdx⟩, ⟨inner.stop.byteIdx - outer.start.byteIdx⟩⟩ }

private def FencedSelection.text (fence : FencedSelection) : String := extract fence.original fence.body

/-- Stable identity for the exact authored source selection: the hash of the
selected bytes. Coordinates are deliberately absent so moving an unchanged body
does not change its identity. -/
private def SourceSelection.selectionIdentity (source : SourceSelection) : Option String := do
  let text ← match source.payload with
    | .prose body => some ((syntaxRange body.stx).map fun (buffer, range) => extract buffer range)
    | _ => source.fence.map (·.map FencedSelection.text)
  return (text.map SHA256.text).toOption.getD "unavailable"

def SourceSelection.selectedDocumentKey (source : SourceSelection) : DocumentKey := Id.run do
  if let some selection := source.adoption then
    let ownerPath := (selection.owner.toOption.map (·.1)).getD ""
    return { source.document with path := source.document.path ++ "#adopted-docstring:" ++
      (toJson (Vir.nameKey selection.consumerModule, Vir.nameKey source.destination.realization.node,
        selection.package, Vir.nameKey selection.moduleName, Vir.nameKey selection.canonical, ownerPath)).compress }
  -- The verified raw comment is the document content. Its stable identity
  -- carries the owner and declaration, independent of the attribute syntax.
  let identity := match source.ownDocstring with
    | some owner => some (toJson ("own-docstring", Vir.nameKey owner.moduleName, Vir.nameKey owner.canonical))
    | none => source.selectionIdentity.map Json.str
  match identity with
  | some identity => return { source.document with
      path := source.document.path ++ "#selection:" ++ (toJson (
        Vir.nameKey source.destination.realization.node,
        Vir.nameKey source.destination.realization.name,
        Vir.nameKey (source.destination.role.getD .anonymous),
        identity)).compress }
  | none => return source.document

/-- The whole original source buffer a prose selection's stored syntax points into. -/
def SourceSelection.proseBuffer? (source : SourceSelection) : Option String :=
  match source.payload with
  | .prose body => (syntaxRange body.stx).toOption.map (·.1)
  | _ => none

private def SourceSelection.selectionIssue (source : SourceSelection) (message : String) : Diagnostic := {
  code := "source-selection-unavailable", subject := (toJson source.destination.subject).compress, message }

private def SourceSelection.locationForSelection (source : SourceSelection) : Except Diagnostic Data.SourceLocation := do
  let some location := source.source.location
    | throw (source.selectionIssue (source.source.error.getD "Source selection has no original location"))
  unless source.source.ok && location.path == source.document.path do
    throw (source.selectionIssue "Source selection is unavailable at its canonical owning path")
  return location

/-- Extract an original prose selection from the source buffer its stored syntax
points into, as compiled. No file is read, so a source edited or removed after
its module was built does not change the result. Cached preview/AST renderings
and nearby text are never substituted. -/
def SourceSelection.selectedText (source : SourceSelection) : Except Diagnostic String := do
  let .prose body := source.payload
    | throw (source.selectionIssue "Only prose sources select text from their stored syntax")
  let location ← source.locationForSelection
  let (buffer, range) ← (syntaxRange body.stx).mapError source.selectionIssue
  unless (FileMap.ofString buffer).utf8RangeToLspRange range == location.range do
    throw (source.selectionIssue "Stored UTF-16 source range disagrees with the owning FileMap")
  return extract buffer range

/-- Check the exact owning fence at its recorded UTF-16 location. An unrelated
edit can preserve that location; moving or changing the fence requires a rebuild. -/
def SourceSelection.selectedFenceText (source : SourceSelection) (document : Document) : Except Diagnostic String := do
  let some selection := source.fence
    | throw (source.selectionIssue "Source has no recorded code block selection")
  let fence ← selection.mapError source.selectionIssue
  let location ← source.locationForSelection
  let map := FileMap.ofString document.text
  let range := map.lspRangeToUtf8Range location.range
  unless source.document == document.key && range.start.byteIdx <= range.stop.byteIdx &&
      map.utf8RangeToLspRange range == location.range && extract document.text range == fence.original do
    throw (source.selectionIssue "Current source disagrees with the original code block at its owning location")
  return fence.text

/-- Absent realization means an authored concept-level constraint. Automatic or
manual origin is metadata, not a substitute for this explicit scope. -/
structure UseDeclaration where
  node : Name
  realization : Option Name := none
  /-- Whose dependency this is: the statement's or the proof's. -/
  role : Name
  reference : Data.UseRef
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

private def useRoleAccepts (axis ownerRole : Name) : Bool :=
  axis == ownerRole || (ownerRole == `implementation && (axis == `statement || axis == `proof))

private def useNameSelects (name : Name) (owner : RealizationKey) (ownerRole : Name) : Bool :=
  name == owner.name || (RealizationKey.forRole ⟨owner.node, name⟩ ownerRole) == owner

/-- Source dependency axes retain their authored meaning. For a computational
definition, both ordinary axes constrain its single implementation realization.
Exact current keys and ordinary producer base-name shorthand use the same rule. -/
def useSelectsRealization (node : Name) (realization : Option Name) (role : Name)
    (model : Realization) : Bool :=
  model.key.node == node && useRoleAccepts role model.role &&
    realization.all fun name => useNameSelects name model.key model.role

/-- Registration precedes capture. A scoped use and its producer shorthand must
agree wherever their selectors overlap, including when one arrives on import.
Concept-wide declarations retain their own authority. -/
def UseDeclaration.scopesOverlap (left right : UseDeclaration) : Bool :=
  left.node == right.node && left.role == right.role && (
    left.realization == right.realization || match left.realization, right.realization with
      | some a, some b =>
        let overlapsAt (role : Name) := useNameSelects a ⟨left.node, b⟩ role ||
          useNameSelects b ⟨left.node, a⟩ role
        overlapsAt left.role || (useRoleAccepts left.role `implementation && overlapsAt `implementation)
      | _, _ => false)

/-- One registration in the existing Blueprint entry/transaction. Metadata is
language independent; sources and dependencies retain their exact destinations.
This is raw authoring input, not a partial admitted model or validation result. -/
structure Registration extends Data.NodeContribution where
  sources : Array SourceSelection := #[]
  uses : Array UseDeclaration := #[]
  deriving Repr, Inhabited

/-- Attach an explicit producer-chosen scope. Origin and intent are preserved
metadata: an authored `origin := automatic` does not imply native inference. -/
def usesFor (node : Name) (realization : Option Name) (role : Name)
    (references : Array Data.UseRef) : Array UseDeclaration :=
  references.map fun reference => { node, realization, role, reference }

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

/-- Native associations preserve Lean's typed identity and every snapshot field.
The collector must retain the whole association, including its destination, in
producer equality. Foreign identifiers never enter this Lean-provider type. -/
structure NativeAssociation where
  realization : RealizationKey
  context : Context
  /-- Where the declaration is presented, such as `statement` or `proof`. Roles
  come from the checked declaration; this placement is their fallback only when
  the declaration cannot be classified, so it stays visible where it was put. -/
  placement : Name
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
  if association.placement.isAnonymous then
    issues := issues.push (diagnostic "unknown-native-placement" "Native association requires an explicit placement")
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
def SourceSelection.rawIssues (source : SourceSelection) (node : Name) : Array Diagnostic := Id.run do
  let subject := source.destination.subject
  let mut issues := #[]
  if node.isAnonymous || !source.destination.realization.valid || source.destination.realization.node != node then
    issues := issues.push (issue "source-destination-mismatch" subject "Source must retain its enclosing concept")
  match source.payload, source.destination.role with
  | .leanInline _, some _ =>
    issues := issues.push (issue "unexpected-source-role" subject
      "Compiled Lean sources take their roles from the checked declarations")
  | .leanInline _, none => pure ()
  | _, none =>
    issues := issues.push (issue "unknown-source-role" subject "Source requires an explicit role")
  | _, some role =>
    if role.isAnonymous then
      issues := issues.push (issue "unknown-source-role" subject "Source requires an explicit role")
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
  if let some owner := source.ownDocstring then
    unless (source.payload matches .prose _) && source.destination.role == some `statement &&
        source.adoption.isNone && !owner.moduleName.isAnonymous && !owner.canonical.isAnonymous do
      issues := issues.push (issue "invalid-own-docstring" subject
        "An attribute docstring requires a prose statement and its owning declaration")
  if let some selection := source.adoption then
    unless (source.payload matches .prose _) && source.destination.role == some `statement &&
        source.context.language == source.destination.realization.name &&
        !selection.consumerModule.isAnonymous && !selection.canonical.isAnonymous do
      issues := issues.push (issue "invalid-docstring-adoption" subject
        "Adoption requires one consumer-owned prose statement and a canonical declaration")
  if source.fence.isSome then
    match source.payload with
    | .text _ | .markup _ => pure ()
    | _ =>
      issues := issues.push (issue "unexpected-source-selection" subject "Only text and markup payloads can select a code block body")
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
def SourceSelection.issues (source : SourceSelection) (node : Name) (model : Realization) : Array Diagnostic := Id.run do
  let subject := source.destination.subject
  let mut issues := source.rawIssues node ++
    destinationIssues node model.key source.context model
  if source.destination.role.all (fun role =>
      model.key != source.destination.realization.forRole role || model.role != role) then
    issues := issues.push (issue "source-role-mismatch" subject "Source must select its explicit realization role")
  if !model.documents.contains source.selectedDocumentKey then
    issues := issues.push (issue "source-document-membership" subject "Composed realization must retain its selected source document")
  return issues

/-- Full typed native union before resolution or presentation selection. Missing
references and inline definitions/theorems all remain inputs. This enumeration
does not erase macro scopes, parse a foreign name or certify native admission. -/
def nativeNames (associations : Array NativeAssociation) (sources : Array SourceSelection) : Array Name := Id.run do
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

/-- The direct roles one compiled Lean declaration contributes. Only its
classification decides: the checked roles, or the owning-source roles when the
check is unavailable. Without either, the declaration still belongs somewhere:
a native association falls back to its placement and an inline payload to the
kind it was elaborated as, so an unresolved declaration stays visible. -/
def declarationRoles (associations : Array NativeAssociation) (sources : Array SourceSelection)
    (classified : Array Name) (name : Name) : Array Name := Id.run do
  unless classified.isEmpty do return canonical classified
  let mut fallback := (associations.filter (·.reference.canonical == name)).map (·.placement)
  for source in sources do
    if let .leanInline code := source.payload then
      if code.definedDeclNames.contains name then
        let theorems := (code.definedTheorems.map (·.name)).foldl Data.pushUniqueNativeName #[]
        fallback := fallback.push (if theorems.contains name then `proof else `implementation)
  return canonical fallback

/-- Check the complete native membership of an ordinary composed Lean model.
Unlike the destination-only `issues` checks, this requires the exact union of
declarations whose roles include this realization's role. Call on the whole
collected batch for this realization, including all missing references and
inline declarations, before full model admission.

The existing string ObjectKey codec has a bounded supported scope: reject a
non-round-tripping typed identity instead of comparing it to another declaration.
This is not the selected-name admission gate, source lookup or proof checking.
No model, input record, required key or presentation payload is changed. -/
def nativeMembershipIssues (node : Name) (model : Realization)
    (associations : Array NativeAssociation) (sources : Array SourceSelection)
    (checkedRoles : Array (Name × Array Name) := #[]) : Array Diagnostic := Id.run do
  let subject := Subject.realization model.key
  let rolesFor (name : Name) : Array Name :=
    declarationRoles associations sources ((checkedRoles.find? (·.1 == name)).map (·.2) |>.getD #[]) name
  let belongsHere (base : RealizationKey) : Bool := base.forRole model.role == model.key
  let mut issues := destinationIssues node model.key model.context model
  issues := issues ++ associations.flatMap fun association => Id.run do
    let mut found := association.rawIssues node ++ destinationIssues node model.key association.context model
    if (rolesFor association.reference.canonical).contains model.role && !belongsHere association.realization then
      found := found.push (issue "source-destination-mismatch" (.realization model.key)
        "Native association does not belong to this direct realization")
    return found
  issues := issues ++ sources.flatMap fun source => Id.run do
    let mut found := source.rawIssues node ++ destinationIssues node model.key source.context model
    let selectsHere := match source.payload with
      | .leanInline code => code.definedDeclNames.any fun name => (rolesFor name).contains model.role
      | _ => source.destination.role == some model.role
    if selectsHere && !belongsHere source.destination.realization then
      found := found.push (issue "source-destination-mismatch" (.realization model.key)
        "Source belongs to a different direct realization")
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
  let expectedNames := names.filter fun name => (rolesFor name).contains model.role
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
  let role := use.role
  match use.realization with
  | none =>
    if role != `statement && role != `proof then
      issues := issues.push (diagnostic "unknown-shared-use-axis" "Shared uses require a statement or proof axis")
  | some name =>
    let candidates := (canonical models).filter (useSelectsRealization node use.realization use.role)
    if name.isAnonymous || candidates.isEmpty then
      issues := issues.push (diagnostic "missing-use-realization" "Use selects no declared realization")
    else if candidates.size != 1 then
      issues := issues.push (diagnostic "ambiguous-use-realization" "Use selects competing realization definitions")
    else if role.isAnonymous then
      issues := issues.push (diagnostic "unknown-use-role" "Use selects an empty realization role")
  return issues

end Informal.SourceData
