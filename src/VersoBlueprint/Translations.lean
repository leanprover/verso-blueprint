/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Validation
import VersoBlueprint.Util.SHA256
import VersoBlueprint.Validation.BindingEncoding
import Lean.Util.SCC
import Std.Data.TreeSet.Basic

/-! Pure admission and validation for canonical Blueprint capture. Admission
checks supplied observations; it does not authenticate their providers. Production
consumers obtain fresh observations through `Realizations.Capture`. -/

namespace Informal.Translations

open Lean Realizations Validation

/-- An endpoint names one complete independently owned realization. -/
structure Endpoint where
  realization : RealizationKey
  deriving Ord, Repr, Inhabited, BEq, DecidableEq, ToJson

instance : Coe RealizationKey Endpoint := ⟨fun key => { realization := key }⟩

structure Translation where
  key : TranslationKey
  kind : Name := `correspondence
  /-- Classification only; tags never select validation policy or enter bindings. -/
  tags : Array Name := #[]
  source : Array Endpoint
  target : Array Endpoint
  /-- Exact requirements, including selected target validation and obligations. -/
  required : Array RequirementKey := #[]
  deriving Ord, Repr, Inhabited, BEq, DecidableEq, ToJson

structure Claim where
  key : ClaimKey
  interpretation : String
  assumptions : Array String := #[]
  /-- Validation of this claim itself. External mathematical obligations belong
  in these requirements' prerequisites and cannot replace claim-local evidence. -/
  required : Array RequirementKey := #[]
  deriving Ord, Repr, Inhabited, BEq, DecidableEq, ToJson

/-- Collected before cross-record resolution, permitting forward references. -/
structure Input where
  nodes : Array (Contribution Node) := #[]
  documents : Array (Contribution Document) := #[]
  objects : Array (Contribution ObjectObservation) := #[]
  realizations : Array (Contribution Realization) := #[]
  translations : Array (Contribution Translation) := #[]
  claims : Array (Contribution Claim) := #[]
  requirements : Array (Contribution Requirement) := #[]
  evidence : Array (Contribution Evidence) := #[]
  reviewSelections : Array (Contribution ReviewSelection) := #[]
  bindingInputs : Array (Contribution BindingInput) := #[]
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

/-- Availability of the same selection whose parts enter a content binding.
Native checks can use fresh observations without the semantic descriptors that
a review of native content requires. -/
private structure ContentAvailability where
  sourceIssues : Array Diagnostic := #[]
  semanticIssues : Array Diagnostic := #[]
  deriving Repr, Inhabited

/-- Construct only through full admission. All indexes/caches are derived from
this one immutable input; public source access cannot update a Registry. -/
structure Registry where
  private mk ::
  private input : Input
  private nodeValues : Array Node
  private documentValues : Array Document
  private objectValues : Array ObjectObservation
  private realizationValues : Array Realization
  private translationValues : Array Translation
  private claimValues : Array Claim
  private requirementValues : Array Requirement
  private semanticValues : Array BindingInput
  private reviewSelectionValues : Array ReviewSelection
  private evidenceValues : Array Evidence
  private nodeIndex : Std.HashMap Name Node
  private documentIndex : Std.HashMap DocumentKey Document
  private objectIndex : Std.HashMap ObjectKey ObjectObservation
  private realizationIndex : Std.HashMap RealizationKey Realization
  private translationIndex : Std.HashMap TranslationKey Translation
  private claimIndex : Std.HashMap ClaimKey Claim
  private requirementIndex : Std.HashMap RequirementKey Requirement
  private reviewSelectionIndex : Std.HashMap RequirementKey (Array ReviewSelection)
  private evidenceIndex : Std.HashMap RequirementKey (Array Evidence)
  private requiredIndex : Std.HashMap Subject (Array RequirementKey) := {}
  private contentAvailability : Std.HashMap Subject ContentAvailability := {}
  private bindings : Std.HashMap RequirementKey ContentBinding := {}
  private localValues : Std.HashMap RequirementKey Result := {}
  private resultValues : Std.HashMap RequirementKey Result := {}
  deriving Repr

private def values [BEq α] [Ord α] (records : Array (Contribution α)) : Array α :=
  canonical (records.map (·.value))

private def indexBy [BEq κ] [Hashable κ] (key : α → κ) (values : Array α) : Std.HashMap κ α :=
  values.foldl (fun out value => out.insert (key value) value) {}

/-- Read-only admitted source. Changing input requires complete admission. -/
def Registry.contributions (r : Registry) : Input := r.input

def Registry.nodes (r : Registry) : Array Node := r.nodeValues
def Registry.documents (r : Registry) : Array Document := r.documentValues
def Registry.objects (r : Registry) : Array ObjectObservation := r.objectValues
def Registry.realizations (r : Registry) : Array Realization := r.realizationValues
def Registry.translations (r : Registry) : Array Translation := r.translationValues
def Registry.claims (r : Registry) : Array Claim := r.claimValues
def Registry.requirements (r : Registry) : Array Requirement := r.requirementValues
def Registry.evidence (r : Registry) : Array Evidence := r.evidenceValues
def Registry.reviewSelections (r : Registry) : Array ReviewSelection := r.reviewSelectionValues

def Registry.bindingInputs (r : Registry) : Array BindingInput := r.semanticValues

def Registry.document? (r : Registry) (key : DocumentKey) : Option Document := r.documentIndex[key]?

def Registry.realization? (r : Registry) (key : RealizationKey) : Option Realization := r.realizationIndex[key]?
def Registry.translation? (r : Registry) (key : TranslationKey) : Option Translation := r.translationIndex[key]?
def Registry.requirement? (r : Registry) (key : RequirementKey) : Option Requirement := r.requirementIndex[key]?
def Registry.claim? (r : Registry) (key : ClaimKey) : Option Claim := r.claimIndex[key]?

private def issue [ToJson α] (code : String) (subject : α) (message : String)
    (origins : Array Origin := #[]) : Diagnostic :=
  { code, subject := (toJson subject).compress, message, origins := canonical origins }

private def familyIssues [BEq α] [Ord α] [BEq κ] [Hashable κ] [ToJson κ]
    (family : String) (key : α → κ) (records : Array (Contribution α)) : Array Diagnostic := Id.run do
  let mut buckets : Std.HashMap κ (Array (Contribution α)) := {}
  for record in records do
    let k := key record.value
    buckets := buckets.insert k ((buckets[k]?.getD #[]).push record)
  let mut diagnostics := #[]
  for (k, bucket) in buckets do
    if (values bucket).size > 1 then
      diagnostics := diagnostics.push <| issue "semantic-conflict" k
        s!"Incompatible {family} definitions" (bucket.map (·.origin))
  return diagnostics

/-- Check same-family records by typed equality, not lossy display serialization.
The tag below only distinguishes families sharing a producer id. -/
private def producerRecords [BEq α] (tag : String) (records : Array (Contribution α)) :
    Array (Name × String × Origin × Bool) := Id.run do
  let mut seen : Std.HashMap Name (Contribution α) := {}
  let mut result := #[]
  for record in records do
    let compatible :=  (seen[record.origin.id]?).all (· == record)
    seen := seen.insert record.origin.id record
    result := result.push (record.origin.id, tag, record.origin, compatible)
  return result

private def Input.structuralProducers (input : Input) : Array (Name × String × Origin × Bool) :=
  producerRecords "node" input.nodes ++ producerRecords "document" input.documents ++
    producerRecords "object" input.objects ++ producerRecords "realization" input.realizations ++
    producerRecords "translation" input.translations ++ producerRecords "claim" input.claims ++
    producerRecords "requirement" input.requirements ++
    producerRecords "reviewSelection" input.reviewSelections ++
    producerRecords "bindingInput" input.bindingInputs

private abbrev ProducerBuckets := Std.HashMap Name (Array (String × Origin × Bool))

/-- Extend only the affected producer buckets. An old structural bucket is
available by identity when an evidence producer tries to reuse that identity. -/
private def producerBuckets (records : Array (Name × String × Origin × Bool))
    (prior : ProducerBuckets := {}) : ProducerBuckets := Id.run do
  let mut buckets : ProducerBuckets := {}
  for (id, family, origin, compatible) in records do
    let bucket := buckets[id]?.getD (prior[id]?.getD #[])
    buckets := buckets.insert id (bucket.push (family, origin, compatible))
  return buckets

private def producerIssues (buckets : ProducerBuckets) : Array Diagnostic := Id.run do
  let mut diagnostics := #[]
  for (id, bucket) in buckets do
    if id.isAnonymous || bucket.any (·.2.1.moduleName.isAnonymous) || bucket.any (! ·.2.2) ||
        bucket.any (fun entry => entry.1 != bucket[0]!.1) then
      diagnostics := diagnostics.push <| issue "producer-collision" id
        "Producer-site identity is empty or has incompatible records" (bucket.map (·.2.1))
  return diagnostics

def Registry.hasSubject (r : Registry) : Subject → Bool
  | .realization key => (r.realization? key).isSome
  | .declaration key object => (r.realization? key).any (·.declarations.any (·.object == object))
  | .translation key => (r.translation? key).isSome
  | .claim key => (r.claim? key).isSome

/-- Own-type reuse is applicable only to these exact owned native selections.
Role data is checked independently of realization names. -/
def Registry.ownTypeEndpoints (r : Registry) (relation : Translation) (witness : ObjectKey) : Bool := Id.run do
  if relation.source.size != 1 || relation.target.size != 1 then return false
  let some proof := r.realization? relation.source[0]!.realization | return false
  let some statement := r.realization? relation.target[0]!.realization | return false
  return proof.role == `proof && statement.role == `statement &&
    proof.context == witness.context && statement.context == witness.context &&
    proof.documents.isEmpty && statement.documents.isEmpty &&
    proof.declarations.size == 1 && statement.declarations.size == 1 &&
    proof.declarations[0]!.object == witness && statement.declarations[0]!.object == witness &&
    proof.declarations[0]!.projection == .implementation && statement.declarations[0]!.projection == .statement

private def Registry.referenceIssues (r : Registry) : Array Diagnostic := Id.run do
  let mut diagnostics := #[]
  for node in r.nodes do
    if node.label.isAnonymous then
      diagnostics := diagnostics.push <| issue "invalid-node" node.label "Empty node label"
  for doc in r.documents do
    if !doc.key.valid then
      diagnostics := diagnostics.push <| issue "invalid-document" doc.key "Invalid document identity"
  for object in r.objects do
    if !object.key.valid then
      diagnostics := diagnostics.push <| issue "invalid-object" object.key "Invalid object identity"
    if let some doc := object.document then
      if doc.context != object.key.context || !r.documentIndex.contains doc then
        diagnostics := diagnostics.push <| issue "unknown-document" object.key "Missing/wrong-context source"
  for realization in r.realizations do
    if !realization.key.valid || !realization.context.valid ||
        !r.nodeIndex.contains realization.key.node then
      diagnostics := diagnostics.push <| issue "invalid-realization" realization.key "Missing node/context"
    if realization.role.isAnonymous then
      diagnostics := diagnostics.push <| issue "invalid-role" realization.key "Missing mathematical role"
    if (canonical (realization.declarations.map (·.object))).size != realization.declarations.size then
      diagnostics := diagnostics.push <| issue "duplicate-declaration" realization.key "Duplicate declaration"
    for doc in realization.documents do
      if doc.context != realization.context || !r.documentIndex.contains doc then
        diagnostics := diagnostics.push <| issue "unknown-document" realization.key "Missing/wrong-context owned source"
    for decl in realization.declarations do
      if !decl.object.valid || decl.object.context != realization.context then
        diagnostics := diagnostics.push <| issue "wrong-project" decl.object "Declaration is outside realization context"
      for key in decl.required do
        if key.subject.realization? != some realization.key then
          diagnostics := diagnostics.push <| issue "wrong-subject" key "Declaration requirement belongs elsewhere"
        if let .declaration _ object := key.subject then
          if object != decl.object then
            diagnostics := diagnostics.push <| issue "wrong-declaration-subject" key
              "A declaration-local requirement cannot validate a sibling declaration"
        if let .realization _ := key.subject then
          if let some req := r.requirement? key then
            if let .proof _ witness := req.expected then
              if witness != decl.object then
                diagnostics := diagnostics.push <| issue "wrong-witness" key "Declaration requires its own checked witness"
    for key in realization.requirements do
      if key.subject.realization? != some realization.key then
        diagnostics := diagnostics.push <| issue "wrong-subject" key "Realization requirement belongs elsewhere"
  for translation in r.translations do
    if translation.kind.isAnonymous || !translation.key.valid || translation.source.isEmpty || translation.target.isEmpty ||
        (canonical translation.source).size != translation.source.size ||
        (canonical translation.target).size != translation.target.size then
      diagnostics := diagnostics.push <| issue "invalid-endpoints" translation.key "Translation needs nonempty endpoints"
    for endpoint in translation.source ++ translation.target do
      match r.realization? endpoint.realization with
      | none => diagnostics := diagnostics.push <| issue "unknown-realization" endpoint "Missing translation endpoint"
      | some _ => pure ()
  for claim in r.claims do
    if (r.translation? claim.key.translation).isNone || claim.key.name.isAnonymous || blank claim.interpretation then
      diagnostics := diagnostics.push <| issue "invalid-claim" claim.key "Claim needs owner/name/interpretation"
    for key in claim.required do
      if key.subject != .claim claim.key then
        diagnostics := diagnostics.push <| issue "wrong-claim-subject" claim.key
          "Claim validation must name this claim; link external obligations through prerequisites"
          ((r.contributions.claims.filter (·.value.key == claim.key)).map (·.origin))
  for requirement in r.requirements do
    if !r.hasSubject requirement.key.subject || requirement.key.name.isAnonymous || !requirement.expected.valid then
      diagnostics := diagnostics.push <| issue "invalid-requirement" requirement.key "Invalid subject/name/expectation"
    if let .proves witness := requirement.expected then
      let valid : Bool := match requirement.key.subject with
        | .translation key => (r.translation? key).any fun relation =>
            relation.kind == `proves && r.ownTypeEndpoints relation witness
        | _ => false
      unless valid do
        diagnostics := diagnostics.push <| issue "wrong-proof-endpoints" requirement.key
          "Own-type proof support requires exact P/S selections of the same declaration"
    if requirement.expected.isNativeDeclarationCheck then
      match requirement.key.subject with
      | .declaration _ object =>
        if object.context.language != `lean then
          diagnostics := diagnostics.push <| issue "wrong-native-context" requirement.key
            "Native Lean checks require a Lean declaration subject"
      | _ =>
        diagnostics := diagnostics.push <| issue "wrong-native-subject" requirement.key
          "An own-declaration native check must name the exact declaration it checks"
    if let .proof goal witness := requirement.expected then
      if let .declaration _ object := requirement.key.subject then
        if witness != object then
          diagnostics := diagnostics.push <| issue "wrong-witness" requirement.key
            "Declaration requires its own checked witness"
      if let some key := requirement.key.subject.realization? then
        if !(r.realization? key).any (·.context == goal.context) then
          diagnostics := diagnostics.push <| issue "wrong-project" requirement.key "Proof goal is outside realization context"
      for doc in goal.documents do
        if doc.context != goal.context || !r.documentIndex.contains doc then
          diagnostics := diagnostics.push <| issue "unknown-document" requirement.key "Missing expected-goal source"
    for key in requirement.prerequisites do
      if (r.requirement? key).isNone then
        diagnostics := diagnostics.push <| issue "unknown-requirement" key "Missing prerequisite"
  let required := r.realizations.flatMap (·.requirements) ++
    r.translations.flatMap (·.required) ++ r.claims.flatMap (·.required)
  for key in required do
    if (r.requirement? key).isNone then
      diagnostics := diagnostics.push <| issue "unknown-requirement" key "Missing contract requirement"
  for selection in r.reviewSelections do
    unless (r.requirement? selection.requirement).any (fun req => match req.expected with
        | .review .. => true | _ => false) do
      diagnostics := diagnostics.push <| issue "invalid-review-selection" selection.requirement
        "Current review selections require an existing named-reviewer obligation"
  for input in r.bindingInputs do
    if !r.hasSubject input.subject || input.name.isAnonymous || blank input.content then
      diagnostics := diagnostics.push <| issue "invalid-binding-input" input.subject "Missing semantic subject/name/content"
  return diagnostics

private def Registry.evidenceIssues (r : Registry) (records : Array (Contribution Evidence))
    (evidence : Array Evidence) : Array Diagnostic :=
  familyIssues "evidence" (·.id) records ++ evidence.filterMap fun item =>
    if item.id.isAnonymous || (r.requirement? item.requirement).isNone then
      some (issue "invalid-evidence" item.id "Missing evidence identity/requirement")
    else none

private def Registry.computeRequiredFor (r : Registry) : Subject → Array RequirementKey
  | .realization key => (r.realization? key).map (·.requirements) |>.getD #[]
  | .declaration key object =>
      ((r.realization? key).bind (fun value => value.declarations.find? (·.object == object))).map
        (·.required) |>.getD #[]
  | .translation key =>
      ((r.translation? key).map (·.required) |>.getD #[]) ++
        (r.claims.filter (·.key.translation == key)).flatMap (·.required)
  | .claim key => (r.claim? key).map (·.required) |>.getD #[]

def Registry.requiredFor (r : Registry) (subject : Subject) : Array RequirementKey :=
  r.requiredIndex[subject]?.getD #[]

private def fingerprint (domain : String) (value : Json) : String :=
  SHA256.tagged domain #[value.compress]

private def sourceTag (scope : ContentScope) : Name :=
  if scope == .statement then NativeLean.statementContext else NativeLean.sourceContext

/-- Descriptors owned by one contract of the subject, not by the subject. -/
private def contractInput (name : Name) : Bool :=
  NativeLean.expectedContext.isPrefixOf name || NativeLean.expectedStatementContext.isPrefixOf name ||
    selectedUses.isPrefixOf name

/-- Only the native provider's two known content descriptors are scope-selected.
Other supplied inputs remain conservative. Expected-goal and dependency-selection
descriptors belong to individual contracts, never to every review of their
containing realization: a proof binds its expected-goal semantic context and a
selection check binds its selection record. No binding reads an expected-goal
statement descriptor. -/
private def selectedInput (scope : ContentScope) (native : Bool) (input : BindingInput) : Bool :=
  !contractInput input.name &&
    (!(native && (input.name == NativeLean.sourceContext || input.name == NativeLean.statementContext)) ||
      input.name == sourceTag scope)

private def Registry.documentIssues (r : Registry) (key : DocumentKey) : Array Diagnostic :=
  match r.documentIndex[key]? with
  | some document =>
    if blank document.text then #[issue "content-unavailable" key "Selected canonical source is empty"] else #[]
  | none => #[issue "content-unavailable" key "Selected canonical source is missing"]

/-- A resolved object is available through its source document, except a Lean
declaration: the compiled environment establishes its content, so its
availability does not depend on any document. -/
private def Registry.objectObservationIssues (r : Registry) (key : ObjectKey)
    (observation : Option ObjectObservation) : Array Diagnostic :=
  match observation with
  | some observation =>
    if observation.resolution != .resolved then
      #[issue "object-unavailable" key s!"{repr observation.resolution}: {observation.explanation}"]
    else if key.context.language == `lean then #[]
    else match observation.document with
      | some document => r.documentIssues document
      | none => #[issue "object-unavailable" key "No canonical source document for selected declaration"]
  | none => #[issue "object-unavailable" key "No source resolution observation"]

private def Registry.objectIssues (r : Registry) (key : ObjectKey) : Array Diagnostic :=
  r.objectObservationIssues key r.objectIndex[key]?

private structure SelectedContent where
  parts : Array String := #[]
  availability : ContentAvailability := {}
  deriving Inhabited

private def bindingInputPart (input : BindingInput) : String :=
  (BindingEncoding.bindingInput input).compress

private def claimPart (claim : Claim) : String :=
  (toJson (BindingEncoding.claimKey claim.key, claim.interpretation, claim.assumptions)).compress

private def combineAvailability (selections : Array SelectedContent) : ContentAvailability := {
  sourceIssues := selections.flatMap (·.availability.sourceIssues)
  semanticIssues := selections.flatMap (·.availability.semanticIssues) }

/-- Resolve an owned declaration or document once for both its binding parts
and availability. Role projections and endpoint order remain structural. -/
private def Registry.selectContent (r : Registry) (documents : Std.HashMap DocumentKey String)
    (subjectInputs : Std.HashMap Subject (Array BindingInput)) :
    Std.HashMap Subject SelectedContent := Id.run do
  let inputs (subject : Subject) (scope : ContentScope) (native : Bool) :=
    (subjectInputs[subject]?.getD #[]).filter (selectedInput scope native)
  let bindingSubjects := r.requirements.foldl (fun out req => out.insert req.key.subject)
    ({} : Std.HashSet Subject)
  -- Model parts are also used by relation endpoints. Source availability is
  -- needed for any model, even if no assessment binds that entire model.
  let boundModels := r.translations.foldl (fun out relation =>
    (relation.source ++ relation.target).foldl
      (fun out endpoint => out.insert (.realization endpoint.realization)) out) bindingSubjects
  let mut content : Std.HashMap Subject SelectedContent := {}
  for model in r.realizations do
    let subject := Subject.realization model.key
    let mut declarations := #[]
    let mut associationIssues := #[]
    let mut observationIssues := #[]
    for declaration in model.declarations do
      let object := declaration.object
      let subject := Subject.declaration model.key object
      let native := object.context.language == `lean
      let observation := r.objectIndex[object]?
      let inputs := inputs subject declaration.projection native
      let provenance := if native then #[] else
        observation.toArray.flatMap fun value => value.document.toArray.map (documents[·]!)
      let issues := r.objectObservationIssues object observation
      let selection : SelectedContent := {
        parts := #[(BindingEncoding.subject subject).compress, (toJson declaration.projection).compress] ++
          inputs.map bindingInputPart ++ provenance
        availability := {
          sourceIssues := declaration.sourceIssues ++ issues
          semanticIssues := if native && !(inputs.any (·.name == sourceTag declaration.projection)) then
            #[issue "semantic-context-unavailable" object
              "Selected native content lacks its requested semantic descriptor"] else #[] } }
      declarations := declarations.push selection
      associationIssues := associationIssues ++ declaration.sourceIssues
      observationIssues := observationIssues ++ issues
      content := content.insert subject selection
    let sourceIssues := associationIssues ++
      if model.documents.isEmpty && declarations.isEmpty then
        #[issue "content-unavailable" subject "Selected subject has no associated source content"]
      else model.documents.flatMap (r.documentIssues ·) ++ observationIssues
    content := content.insert subject {
      parts := if !boundModels.contains subject then #[] else
        #[(BindingEncoding.realizationKey model.key).compress,
        (BindingEncoding.context model.context).compress, Vir.nameKey model.role] ++
        (inputs subject .statement false).map bindingInputPart ++ model.documents.map (documents[·]!) ++
        declarations.map (fun declaration => SHA256.tagged "vbp.owned-declaration.v3" declaration.parts)
      availability := {
        sourceIssues, semanticIssues := declarations.flatMap (·.availability.semanticIssues) } }
  let models := content
  let endpoint (value : Endpoint) := models[Subject.realization value.realization]?.getD {}
  let endpointParts (values : Array SelectedContent) :=
    values.map (fun value => SHA256.tagged "vbp.endpoint.v3" value.parts)
  let claimsByRelation := r.claims.foldl (fun out claim =>
    out.insert claim.key.translation ((out[claim.key.translation]?.getD #[]).push claim))
    ({} : Std.HashMap TranslationKey (Array Claim))
  for relation in r.translations do
    let source := relation.source.map endpoint
    let target := relation.target.map endpoint
    let availability := combineAvailability (source ++ target)
    let endpoints := #[(BindingEncoding.translationKey relation.key).compress, Vir.nameKey relation.kind,
      SHA256.tagged "vbp.source-endpoints.v3" (endpointParts source),
      SHA256.tagged "vbp.target-endpoints.v3" (endpointParts target)]
    let claims := claimsByRelation[relation.key]?.getD #[]
    let insert (content : Std.HashMap Subject SelectedContent) (subject : Subject) (claims : Array Claim) :=
      content.insert subject {
        parts := endpoints ++ claims.map claimPart ++ (inputs subject .statement false).map bindingInputPart
        availability }
    content := insert content (.translation relation.key) claims
    for claim in claims do
      content := insert content (.claim claim.key) #[claim]
  return content

/-- Prerequisite identities are in the requirement encoding. Their contents
and evidence do not become selections of this contract. -/
private def Registry.deriveBindings (r : Registry) : Registry := Id.run do
  let documents := r.documents.foldl (fun out document =>
    out.insert document.key (fingerprint "vbp.document.v3" (BindingEncoding.document document)))
    ({} : Std.HashMap DocumentKey String)
  let subjectInputs := r.bindingInputs.foldl (fun out input =>
    out.insert input.subject ((out[input.subject]?.getD #[]).push input))
    ({} : Std.HashMap Subject (Array BindingInput))
  let content := r.selectContent documents subjectInputs
  let mut bindings := {}
  for requirement in r.requirements do
    let key := requirement.key
    let selected := content[key.subject]?.getD {}
    let inputs := subjectInputs[key.subject]?.getD #[]
    let mut parts := #[(BindingEncoding.requirement requirement).compress] ++ selected.parts ++
      (inputs.filter (·.name == selectedUsesFor key)).map bindingInputPart
    if let .proof goal witness := requirement.expected then
      let descriptors := inputs.filter (·.name == NativeLean.expectedContextFor key)
      parts := parts ++ #[(BindingEncoding.objectKey witness).compress] ++
        descriptors.map bindingInputPart ++ (goal.documents.filter (·.context.language != `lean)).map (documents[·]!)
    bindings := bindings.insert key ("vbp-binding-sha256-v3:" ++ SHA256.tagged "vbp.assessment.v3" parts)
  let contentAvailability := content.fold (fun out subject selected => out.insert subject selected.availability) {}
  return { r with bindings, contentAvailability }

/-- Exact bindings are derived once from this immutable admitted input. -/
def Registry.bindingFor (r : Registry) (key : RequirementKey) : Option ContentBinding :=
  r.bindings[key]?

/-- Exact selections, without widening a declaration to siblings. -/
private def Registry.subjectContentIssues (r : Registry) (subject : Subject) : Array Diagnostic :=
  if subject.translation?.isSome then #[] else
  match r.contentAvailability[subject]?, subject with
  | some selected, _ => selected.sourceIssues
  | none, .realization key => #[issue "unknown-realization" key "Missing source realization"]
  | none, .declaration .. =>
      #[issue "unknown-declaration" subject "Declaration is not owned by the selected realization"]
  | none, _ => #[]

private def Registry.availabilityIssues (r : Registry) (subject : Subject)
    (includeSemantics : Bool := true) : Array Diagnostic :=
  match r.contentAvailability[subject]? with
  | some available => canonical (available.sourceIssues ++ if includeSemantics then available.semanticIssues else #[])
  | none => match subject.translation? with
    | some key => #[issue "unknown-translation" key "Missing relation"]
    | none => r.subjectContentIssues subject

/-- Selection is resolved before suitability. No old matching approval is searched.
Distinct active selections are ordinary unresolved assessment data. -/
def Registry.selectedReview (r : Registry) (key : RequirementKey) : Except String (Option Name) :=
  match (r.reviewSelectionIndex[key]?.getD #[]).toList with
  | [] => .ok none
  | [selection] => .ok selection.judgment
  | _ => .error "conflicting-review-selections"

/-- Independent local suitability, before prerequisite traversal. -/
private def Registry.computeLocalResult (r : Registry) (key : RequirementKey) : Result := Id.run do
  let some req := r.requirement? key
    | return { status := .blocked, diagnostics := #[issue "unknown-requirement" key "Missing requirement"] }
  let mut candidates := r.evidenceIndex[key]?.getD #[]
  let mut reviewIssues := #[]
  if let .review .. := req.expected then
    match r.selectedReview key with
    | .error code =>
      reviewIssues := #[issue code key "Select one current judgment explicitly"]
    | .ok none =>
      reviewIssues := #[issue "no-current-review" key "No current approval selected"]
    | .ok (some id) =>
      candidates := candidates.filter (·.id == id)
      if candidates.isEmpty then
        reviewIssues := #[issue "missing-current-review" id "Selected judgment is unavailable"]
  match req.expected with
  | .proof _ witness =>
    let unavailable := match key.subject.realization? with
      | some owner => r.subjectContentIssues (.declaration owner witness)
      | none => r.objectIssues witness
    if !unavailable.isEmpty then
      return {
        status := .blocked
        diagnostics := unavailable.push (issue "witness-unavailable" witness "No current resolved witness source") }
    -- A correspondence proof validates selected endpoints as well as a formal
    -- goal. The standalone witness can stay checked on its own realization.
    if key.subject.translation?.isSome then
      let selected := r.availabilityIssues key.subject
      if !selected.isEmpty then return { status := .blocked, diagnostics := selected }
    unless r.bindingInputs.any (fun input => input.subject == key.subject &&
        input.name == NativeLean.expectedContextFor key) do
      return { status := .blocked, diagnostics := #[issue "semantic-context-unavailable" key
        "Expected proposition/witness lacks current provider/build semantic inputs"] }
  | _ =>
    let unavailable := if req.expected.isNativeDeclarationCheck then r.subjectContentIssues key.subject
      else r.availabilityIssues key.subject
    if !unavailable.isEmpty then
      return { status := .blocked, diagnostics := canonical (unavailable ++ reviewIssues) }
  if !reviewIssues.isEmpty then return { status := .pending, diagnostics := reviewIssues }
  let binding := (r.bindingFor key).getD ""
  if candidates.any (fun evidence => (evidence.mismatch? req binding).isNone) then
    return { status := .complete, localComplete := true }
  -- An old or unrelated unavailable observation cannot block current work.
  let providerUnavailable := candidates.any fun evidence =>
    evidence.mismatch? req binding == some "validation-unavailable"
  return {
    status := if providerUnavailable then .blocked else .pending
    diagnostics := candidates.filterMap fun evidence =>
      (evidence.mismatch? req binding).map fun code => issue code evidence.id
        s!"Evidence does not discharge requirement. {evidence.observation.explanation}" }

private def Registry.computeResults (r : Registry) : Std.HashMap RequirementKey Result := Id.run do
  let mut results : Std.HashMap RequirementKey Result := {}
  let prerequisites (key : RequirementKey) :=
    (r.requirement? key).map (·.prerequisites) |>.getD #[]
  -- Edges point to prerequisites, so SCC returns them before their dependents.
  let components := Lean.SCC.scc (r.requirements.map (·.key)).toList (fun key => (prerequisites key).toList)
  let localResult (key : RequirementKey) := r.localValues[key]?.getD { status := .blocked }
  for members in components do
    let component := canonical members.toArray
    let first := component[0]!
    let firstPrerequisites := prerequisites first
    let cyclic := component.size > 1 || firstPrerequisites.contains first
    let external :=
      if cyclic then
        let members := component.foldl (fun out key => out.insert key) ({} : Std.HashSet RequirementKey)
        canonical ((component.flatMap prerequisites).filter (fun key => !members.contains key))
      else firstPrerequisites
    let prerequisiteResults := external.map fun dependency =>
      results[dependency]?.getD { status := .blocked }
    if !cyclic && prerequisiteResults.all (·.complete) then
      results := results.insert first (localResult first)
      continue
    -- Share cycle reasons across members and deduplicate prerequisite reasons
    -- as they are collected. The ordered set uses the same order as `canonical`.
    let mut diagnostics : Std.TreeSet Diagnostic := {}
    for key in component do
      diagnostics := diagnostics.insertMany (localResult key).diagnostics
      if cyclic then
        diagnostics := diagnostics.insert (issue "requirement-cycle" key "Recursive validation requirement")
    for prerequisite in prerequisiteResults do
      diagnostics := diagnostics.insertMany prerequisite.diagnostics
    for key in component do
      let unfinished := issue "unfinished-prerequisite" key "A selected prerequisite requirement is unfinished"
      results := results.insert key { localResult key with
        status := .blocked, diagnostics := (diagnostics.insert unfinished).toArray }
  return results

/-- Cached local suitability and closure are derived from the same immutable
admitted snapshot; querying performs no graph traversal or provider operation. -/
def Registry.localResult (r : Registry) (key : RequirementKey) : Result :=
  r.localValues[key]?.getD {
    status := .blocked, diagnostics := #[issue "unknown-requirement" key "Missing requirement"] }

def Registry.resultForRequirement (r : Registry) (key : RequirementKey) : Result :=
  r.resultValues[key]?.getD {
    status := .blocked, diagnostics := #[issue "unknown-requirement" key "Missing requirement"] }

/-- Validate the input and derive its structural bindings once. The pure
callback can only read those bindings; its evidence is validated together
with all existing evidence before any registry escapes. -/
def admitWithEvidence (input : Input)
    (collect : (RequirementKey → Option ContentBinding) →
      Except (Array Diagnostic) (Array (Contribution Evidence))) :
    Except (Array Diagnostic) Registry := do
  let nodes := values input.nodes
  let documents := values input.documents
  let objects := values input.objects
  let realizations := values input.realizations
  let translations := values input.translations
  let claims := values input.claims
  -- Prerequisites are a set. Use the same canonical order as the binding
  -- encoding while preserving the exact producer records for replay.
  let requirementRecords := input.requirements.map fun record =>
    { record with value.prerequisites := canonical record.value.prerequisites }
  let requirements := values requirementRecords
  let evidence := values input.evidence
  let reviewSelectionIndex := (values input.reviewSelections).foldl (fun out selection =>
    out.insert selection.requirement ((out[selection.requirement]?.getD #[]).push selection))
    ({} : Std.HashMap RequirementKey (Array ReviewSelection))
  let r : Registry := {
    input, reviewSelectionIndex, reviewSelectionValues := values input.reviewSelections, nodeValues := nodes, documentValues := documents, objectValues := objects
    realizationValues := realizations, translationValues := translations
    claimValues := claims, requirementValues := requirements
    semanticValues := values input.bindingInputs, evidenceValues := evidence
    nodeIndex := indexBy (·.label) nodes, documentIndex := indexBy (·.key) documents
    objectIndex := indexBy (·.key) objects, realizationIndex := indexBy (·.key) realizations
    translationIndex := indexBy (·.key) translations, claimIndex := indexBy (·.key) claims
    requirementIndex := indexBy (·.key) requirements, evidenceIndex := {} }
  let structureProducers := producerBuckets input.structuralProducers
  let evidenceProducers := producerBuckets (producerRecords "evidence" input.evidence) structureProducers
  let allProducers := evidenceProducers.fold (fun out id bucket => out.insert id bucket) structureProducers
  let diagnostics := producerIssues allProducers ++
    familyIssues "node" (·.label) input.nodes ++ familyIssues "document" (·.key) input.documents ++
    familyIssues "object" (·.key) input.objects ++ familyIssues "realization" (·.key) input.realizations ++
    familyIssues "translation" (·.key) input.translations ++ familyIssues "claim" (·.key) input.claims ++
    familyIssues "requirement" (·.key) requirementRecords ++ r.evidenceIssues input.evidence evidence ++
    familyIssues "binding input" (fun value => (value.subject, value.name)) input.bindingInputs ++ r.referenceIssues
  unless diagnostics.isEmpty do throw (canonical diagnostics)
  let subjects := r.realizations.flatMap (fun value => #[Subject.realization value.key] ++
      value.declarations.map (fun decl => .declaration value.key decl.object)) ++
    r.translations.map (fun value => .translation value.key) ++ r.claims.map (fun value => .claim value.key)
  let requiredIndex := subjects.foldl (fun out subject => out.insert subject (r.computeRequiredFor subject))
    ({} : Std.HashMap Subject (Array RequirementKey))
  let r := { r with requiredIndex }
  let r := r.deriveBindings
  let additional ← collect r.bindingFor
  let (input, evidence) ← if additional.isEmpty then pure (input, evidence) else do
    let input := { input with evidence := input.evidence ++ additional }
    let evidence := values input.evidence
    let buckets := producerBuckets (producerRecords "evidence" input.evidence) structureProducers
    let diagnostics := producerIssues buckets ++ r.evidenceIssues input.evidence evidence
    unless diagnostics.isEmpty do throw (canonical diagnostics)
    pure (input, evidence)
  let evidenceIndex := evidence.foldl (fun out item =>
    out.insert item.requirement ((out[item.requirement]?.getD #[]).push item))
    ({} : Std.HashMap RequirementKey (Array Evidence))
  let r := { r with input, evidenceValues := evidence, evidenceIndex }
  let localValues := r.requirements.foldl (fun out req => out.insert req.key (r.computeLocalResult req.key))
    ({} : Std.HashMap RequirementKey Result)
  let r := { r with localValues }
  return { r with resultValues := r.computeResults }

/-- Admit a complete supplied batch. No partial registry escapes validation. -/
def admit (input : Input) : Except (Array Diagnostic) Registry :=
  admitWithEvidence input (fun _ => pure #[])

def Registry.resultFor (r : Registry) (subject : Subject) : Result := Id.run do
  if !r.hasSubject subject then
    return { status := .blocked, diagnostics := #[issue "unknown-subject" subject "Missing subject"] }
  let unavailable := if subject.translation?.isSome then r.availabilityIssues subject (includeSemantics := false)
    else r.subjectContentIssues subject
  if !unavailable.isEmpty then return { status := .blocked, diagnostics := unavailable }
  let keys := canonical (r.requiredFor subject)
  let results := keys.map (r.resultForRequirement ·)
  -- A missing contract changes the aggregate status, but existing contracts
  -- still report their own validation failures.
  let diagnostics := canonical (results.flatMap (·.diagnostics))
  let unassessed : Result := { status := .unassessed, diagnostics }
  -- Every required declaration needs its own explicit validation contract.
  if let .realization key := subject then
    if (r.realization? key).any (·.declarations.any (·.required.isEmpty)) then
      return unassessed
  if let .translation key := subject then
    let relation := (r.translation? key).get!
    if relation.kind == `proves then
      let supported := keys.any fun key =>
        (r.requirement? key).any fun req => match req.expected with
          | .proves witness => req.key.subject == subject && r.ownTypeEndpoints relation witness
          | .review criterion _ => criterion == `mathematicalProof &&
              (req.key.subject == subject || req.key.subject.translation? == some relation.key)
          | _ => false
      unless supported do
        return { unassessed with diagnostics := canonical (diagnostics.push (issue
          "missing-mathematical-support" key "A proves contract requires exact formal or mathematical review support")) }
    else if !(r.claims.any (·.key.translation == key)) then
      return unassessed
    -- Native support establishes the P/S connection, not additional authored
    -- claims. Every attached claim needs its own assessment contract.
    if r.claims.any (fun c => c.key.translation == key && c.required.isEmpty) then
      return unassessed
  if keys.isEmpty then return unassessed
  return {
    status := if results.all (·.complete) then .complete
      else if results.any (·.status == .blocked) then .blocked else .pending
    localComplete := results.all (·.localComplete)
    diagnostics }

/-- Select by identity and validation name, never by which alternative is complete.
The future default-Lean adapter supplies its explicit default realization name. -/
structure Selection where
  node : Name
  context : Context
  realization : Option Name := none
  role : Option Name := none
  requirement : Name
  deriving Repr, Inhabited

def Registry.selectRequirement (r : Registry) (selection : Selection) : Except Diagnostic RequirementKey :=
  let candidates := r.requirements.filter fun req =>
    match req.key.subject.realization? with
    | none => false
    | some key => key.node == selection.node &&
        selection.realization.all (· == key.name) &&
        (r.realization? key).any (·.context == selection.context) &&
        req.key.name == selection.requirement &&
        (r.realization? key).any (fun model => selection.role.all (· == model.role))
  match candidates.toList with
  | [req] => .ok req.key
  | [] => .error (issue "missing-prerequisite" selection.node "No matching selected requirement")
  | _ => .error (issue "ambiguous-prerequisite" selection.node "Select one realization and requirement")

/-- Inventory does not depend on rendered graph nodes or external task status. -/
def Registry.unfinished (r : Registry) : Array Translation :=
  r.translations.filter (fun t => !(r.resultFor (.translation t.key)).complete)

def Registry.actionable (r : Registry) : Array Translation :=
  r.translations.filter (fun t => (r.resultFor (.translation t.key)).actionable)

end Informal.Translations
