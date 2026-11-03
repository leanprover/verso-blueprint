/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Validation
import VersoBlueprint.Util.Merkle
import VersoBlueprint.Validation.BindingEncoding

/-! Pure admission and validation for canonical Blueprint capture. Admission
checks supplied observations; it does not authenticate their providers. Production
consumers obtain fresh observations through `Realizations.Capture`. -/

namespace Informal.Translations

open Lean Realizations Validation

/-- Empty facet selection means the whole realization; otherwise every named
facet must exist. Selection is part of the reviewed correspondence contract. -/
structure Endpoint where
  realization : RealizationKey
  facets : Array Name := #[]
  deriving Ord, Repr, Inhabited, BEq, DecidableEq, ToJson

instance : Coe RealizationKey Endpoint := ⟨fun key => { realization := key }⟩

structure Translation where
  key : TranslationKey
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
  bindingInputs : Array (Contribution BindingInput) := #[]
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

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
  private evidenceValues : Array Evidence
  private nodeIndex : Std.HashMap Name Node
  private documentIndex : Std.HashMap DocumentKey Document
  private objectIndex : Std.HashMap ObjectKey ObjectObservation
  private realizationIndex : Std.HashMap RealizationKey Realization
  private translationIndex : Std.HashMap TranslationKey Translation
  private claimIndex : Std.HashMap ClaimKey Claim
  private requirementIndex : Std.HashMap RequirementKey Requirement
  private evidenceIndex : Std.HashMap RequirementKey (Array Evidence)
  private requiredIndex : Std.HashMap Subject (Array RequirementKey) := {}
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
def Registry.bindingInputs (r : Registry) : Array BindingInput := r.semanticValues

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

private def Input.producerIssues (input : Input) : Array Diagnostic := Id.run do
  let records := producerRecords "node" input.nodes ++ producerRecords "document" input.documents ++
    producerRecords "object" input.objects ++ producerRecords "realization" input.realizations ++
    producerRecords "translation" input.translations ++ producerRecords "claim" input.claims ++
    producerRecords "requirement" input.requirements ++ producerRecords "evidence" input.evidence ++
    producerRecords "bindingInput" input.bindingInputs
  let mut buckets : Std.HashMap Name (Array (String × Origin × Bool)) := {}
  for (id, family, origin, compatible) in records do
    buckets := buckets.insert id ((buckets[id]?.getD #[]).push (family, origin, compatible))
  let mut diagnostics := #[]
  for (id, bucket) in buckets do
    if id.isAnonymous || bucket.any (·.2.1.moduleName.isAnonymous) || bucket.any (! ·.2.2) ||
        bucket.any (fun entry => entry.1 != bucket[0]!.1) then
      diagnostics := diagnostics.push <| issue "producer-collision" id
        "Producer-site identity is empty or has incompatible records" (bucket.map (·.2.1))
  return diagnostics

def Registry.hasSubject (r : Registry) : Subject → Bool
  | .realization key => (r.realization? key).isSome
  | .facet key name => (r.realization? key).any (·.facets.any (·.name == name))
  | .declaration key object => (r.realization? key).any (·.declarations.any (·.object == object))
  | .translation key => (r.translation? key).isSome
  | .claim key => (r.claim? key).isSome

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
    if (canonical (realization.facets.map (·.name))).size != realization.facets.size ||
        realization.facets.any (·.name.isAnonymous) then
      diagnostics := diagnostics.push <| issue "invalid-facets" realization.key "Empty or duplicate facet"
    if (canonical (realization.declarations.map (·.object))).size != realization.declarations.size then
      diagnostics := diagnostics.push <| issue "duplicate-declaration" realization.key "Duplicate declaration"
    for facet in realization.facets do
      for doc in facet.documents do
        if doc.context != realization.context || !r.documentIndex.contains doc then
          diagnostics := diagnostics.push <| issue "unknown-document" realization.key "Missing/wrong-context facet source"
      if (canonical facet.declarations).size != facet.declarations.size then
        diagnostics := diagnostics.push <| issue "duplicate-facet-declaration" realization.key "Duplicate selected declaration"
      for object in facet.declarations do
        if !realization.declarations.any (·.object == object) then
          diagnostics := diagnostics.push <| issue "unknown-facet-declaration" realization.key
            "Facet selects a declaration outside this realization's associations"
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
        if let some req := r.requirement? key then
          if let .proof _ witness := req.expected then
            if witness != decl.object then
              diagnostics := diagnostics.push <| issue "wrong-witness" key "Declaration requires its own checked witness"
    for key in realization.requirements do
      if key.subject.realization? != some realization.key then
        diagnostics := diagnostics.push <| issue "wrong-subject" key "Realization requirement belongs elsewhere"
  for translation in r.translations do
    if !translation.key.valid || translation.source.isEmpty || translation.target.isEmpty ||
        (canonical translation.source).size != translation.source.size ||
        (canonical translation.target).size != translation.target.size then
      diagnostics := diagnostics.push <| issue "invalid-endpoints" translation.key "Translation needs nonempty endpoints"
    for endpoint in translation.source ++ translation.target do
      match r.realization? endpoint.realization with
      | none => diagnostics := diagnostics.push <| issue "unknown-realization" endpoint "Missing translation endpoint"
      | some realization =>
        if (canonical endpoint.facets).size != endpoint.facets.size then
          diagnostics := diagnostics.push <| issue "invalid-endpoint-facets" endpoint "Duplicate selected facet"
        for facet in endpoint.facets do
          if !realization.facets.any (·.name == facet) then
            diagnostics := diagnostics.push <| issue "unknown-facet" endpoint "Missing selected endpoint facet"
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
    if requirement.expected.isNativeDeclarationCheck then
      match requirement.key.subject with
      | .declaration _ object =>
        if object.context.language != `lean then
          diagnostics := diagnostics.push <| issue "wrong-native-context" requirement.key
            "Native Lean checks require a Lean declaration subject"
      | _ =>
        diagnostics := diagnostics.push <| issue "wrong-native-subject" requirement.key
          "An own-declaration native check must name the exact declaration it checks"
    if let .proof goal _ := requirement.expected then
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
  for evidence in r.evidence do
    if evidence.id.isAnonymous || (r.requirement? evidence.requirement).isNone then
      diagnostics := diagnostics.push <| issue "invalid-evidence" evidence.id "Missing evidence identity/requirement"
  for input in r.bindingInputs do
    if !r.hasSubject input.subject || input.name.isAnonymous || blank input.content then
      diagnostics := diagnostics.push <| issue "invalid-binding-input" input.subject "Missing semantic subject/name/content"
  return diagnostics

private def Registry.computeRequiredFor (r : Registry) : Subject → Array RequirementKey
  | .realization key => (r.realization? key).map (·.requirements) |>.getD #[]
  | .facet key name => r.requirements.filterMap fun req =>
      if ((r.realization? key).bind (fun value => value.facets.find? (·.name == name))).any
          (·.required.contains req.key) then some req.key else none
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

private def setFingerprint (domain : String) (parts : Array String) : String :=
  SHA256.tagged domain (canonical parts)

private def sourceTag (scope : ContentScope) : Name :=
  if scope == .statement then NativeLean.statementContext else NativeLean.sourceContext

private def expectedTag (scope : ContentScope) (key : RequirementKey) : Name :=
  if scope == .statement then NativeLean.expectedStatementContextFor key else NativeLean.expectedContextFor key

private def expectedInput (name : Name) : Bool :=
  NativeLean.expectedContext.isPrefixOf name || (`lean.expectedStatementContext).isPrefixOf name

/-- Only the native provider's two known content descriptors are scope-selected.
Other supplied inputs remain conservative. Expected-goal descriptors belong to
individual contracts, never to every review of their containing realization. -/
private def selectedInput (scope : ContentScope) (native : Bool) (input : BindingInput) : Bool :=
  !expectedInput input.name &&
    (!(native && (input.name == NativeLean.sourceContext || input.name == NativeLean.statementContext)) ||
      input.name == sourceTag scope)

/-- Bind selected content and the reviewed contract. Prerequisites contribute
statement contracts, while their current completion remains an evaluator gate.
Sibling obligations and source locators are not mathematical review content. -/
private def Registry.computeBindings (r : Registry) : Except String (Std.HashMap RequirementKey ContentBinding) := do
  let documents := r.documents.foldl (fun out document =>
    out.insert document.key (fingerprint "vbp.document.v2" (BindingEncoding.document document)))
    ({} : Std.HashMap DocumentKey String)
  let documentParts (keys : Array DocumentKey) := keys.map (documents[·]!)
  let declarationInputs := r.bindingInputs.foldl (fun out input =>
    match input.subject with
    | .declaration _ object => out.insert object ((out[object]?.getD #[]).push input)
    | _ => out) ({} : Std.HashMap ObjectKey (Array BindingInput))
  let subjectInputs := r.bindingInputs.foldl (fun out input =>
    out.insert input.subject ((out[input.subject]?.getD #[]).push input))
    ({} : Std.HashMap Subject (Array BindingInput))
  let mut objectDigests : Std.HashMap (ObjectKey × ContentScope) String := {}
  let objectKeys := canonical <| r.objects.map (·.key) ++
    r.realizations.flatMap (fun model => model.declarations.map (·.object)) ++
    r.requirements.filterMap (fun req => match req.expected with | .proof _ witness => some witness | _ => none)
  for key in objectKeys do
    for scope in #[ContentScope.statement, ContentScope.implementation] do
      let content := (declarationInputs[key]?.getD #[]).filter (selectedInput scope (key.context.language == `lean))
      let provenance := if key.context.language == `lean then #[] else
        r.objectIndex[key]?.toArray.flatMap (fun object => documentParts object.document.toArray)
      objectDigests := objectDigests.insert (key, scope) <| SHA256.tagged "vbp.bound-object.v2" (#[
        (BindingEncoding.objectKey key).compress,
        setFingerprint "vbp.object-semantics.v2" (content.map fun input =>
          (toJson (Vir.nameKey input.name, input.content)).compress)] ++ provenance)
  let objectDigest (scope : ContentScope) (key : ObjectKey) := objectDigests[(key, scope)]!
  let modelParts (scope : ContentScope) (key : RealizationKey) (facets : Array Name) : Array String :=
    match r.realization? key with
    | none => #[]
    | some model =>
      let selected := model.facets.filter fun facet => facets.isEmpty || facets.contains facet.name
      let objects := if facets.isEmpty then model.declarations.map (·.object)
        else selected.flatMap (·.declarations)
      -- Only declaration-backed Lean source has a semantic replacement. An
      -- authored document without a selected declaration remains byte-bound.
      let sourceDocuments := selected.flatMap (·.documents) |>.filter fun document =>
        document.context.language != `lean || !objects.any (fun object =>
          (r.objectIndex[object]?).any (·.document == some document))
      let subjects := #[Subject.realization key] ++ selected.map (Subject.facet key ·.name)
      let content := (subjects.flatMap fun subject => subjectInputs[subject]?.getD #[]).filter
        (selectedInput scope (model.context.language == `lean))
      #[(BindingEncoding.realizationKey key).compress, (BindingEncoding.context model.context).compress] ++
        content.map (fun input => (BindingEncoding.bindingInput input).compress) ++
        selected.map (fun facet => (toJson (Vir.nameKey facet.name,
          facet.declarations.map BindingEncoding.objectKey)).compress) ++
        documentParts sourceDocuments ++ objects.map (objectDigest scope)
  let subjectParts (scope : ContentScope) (subject : Subject) : Array String := Id.run do
    match subject with
    | .realization key => return modelParts scope key #[]
    | .facet key name => return modelParts scope key #[name]
    | .declaration _ object => return #[objectDigest scope object]
    | .translation _ | .claim _ =>
      let some key := subject.translation? | return #[]
      let some translation := r.translation? key | return #[]
      let endpoints (values : Array Endpoint) := values.map fun endpoint =>
        SHA256.tagged "vbp.endpoint.v2" (modelParts scope endpoint.realization endpoint.facets)
      let mut parts := #[(BindingEncoding.translationKey key).compress,
        setFingerprint "vbp.source-endpoints.v2" (endpoints translation.source),
        setFingerprint "vbp.target-endpoints.v2" (endpoints translation.target)]
      if let .claim key := subject then
        if let some claim := r.claim? key then
          parts := parts.push (toJson (BindingEncoding.claimKey key, claim.interpretation, claim.assumptions)).compress
      return parts
  let vertices := r.requirements.flatMap fun req => #[
    (req.key, ContentScope.statement), (req.key, ContentScope.implementation)]
  let mut payloads : Std.HashMap (RequirementKey × ContentScope) String := {}
  let mut edges : Std.HashMap (RequirementKey × ContentScope) (Array (RequirementKey × ContentScope)) := {}
  for requirement in r.requirements do
    for scope in #[ContentScope.statement, ContentScope.implementation] do
      let key := requirement.key
      let contract := match requirement.expected with
        | .proof goal witness =>
          let selectedGoal := { goal with documents := goal.documents.filter (·.context.language != `lean) }
          { requirement with expected := .proof selectedGoal witness }
        | _ => requirement
      let subjects := canonical <| #[key.subject] ++
        key.subject.realization?.toArray.map Subject.realization ++
        key.subject.translation?.toArray.map Subject.translation
      let native := key.subject.realization?.any fun owner =>
        (r.realization? owner).any (·.context.language == `lean)
      let inputs := (subjects.flatMap fun subject => subjectInputs[subject]?.getD #[]).filter fun input =>
        if expectedInput input.name then input.name == expectedTag scope key
        else selectedInput scope native input
      let mut parts := #[(BindingEncoding.requirement contract).compress] ++ subjectParts scope key.subject ++
        inputs.map (fun input => (BindingEncoding.bindingInput input).compress)
      if let .proof goal witness := requirement.expected then
        parts := parts ++ #[objectDigest scope witness] ++ documentParts (goal.documents.filter (·.context.language != `lean))
      payloads := payloads.insert (key, scope) (setFingerprint "vbp.binding-local.v2" parts)
      edges := edges.insert (key, scope) (requirement.prerequisites.map (·, ContentScope.statement))
  let graph ← Merkle.graph vertices
    (fun (key, scope) => (toJson (BindingEncoding.requirementKey key, scope)).compress)
    (payloads[·]!) (edges[·]!)
  return r.requirements.foldl (fun result req => result.insert req.key
    ("vbp-binding-sha256-v2:" ++ graph[(req.key, req.scope)]!)) {}

/-- Exact bindings are derived once from this immutable admitted input. No
provider state, persistence or independent source of semantic truth is cached. -/
def Registry.bindingFor (r : Registry) (key : RequirementKey) : Option ContentBinding :=
  r.bindings[key]?

private def Registry.documentIssues (r : Registry) (key : DocumentKey) : Array Diagnostic :=
  match r.documentIndex[key]? with
  | some document =>
    if blank document.text then #[issue "content-unavailable" key "Selected canonical source is empty"] else #[]
  | none => #[issue "content-unavailable" key "Selected canonical source is missing"]

private def Registry.objectIssues (r : Registry) (key : ObjectKey) : Array Diagnostic :=
  match r.objectIndex[key]? with
  | some observation =>
    if observation.resolution != .resolved then
      #[issue "object-unavailable" key s!"{repr observation.resolution}: {observation.explanation}"]
    else match observation.document with
      | some document => r.documentIssues document
      | none => #[issue "object-unavailable" key "No canonical source document for selected declaration"]
  | none => #[issue "object-unavailable" key "No source resolution observation"]

private def Registry.contentIssues (r : Registry) (subject : Subject)
    (documents : Array DocumentKey) (objects : Array ObjectKey) : Array Diagnostic :=
  if documents.isEmpty && objects.isEmpty then
    #[issue "content-unavailable" subject "Selected subject has no associated source content"]
  else documents.flatMap (r.documentIssues ·) ++ objects.flatMap (r.objectIssues ·)

/-- Preserve source selection instead of widening a declaration/facet to its
whole realization. Whole-realization queries still inspect all declarations. -/
private def Registry.subjectContentIssues (r : Registry) (subject : Subject) : Array Diagnostic :=
  match subject with
  | .realization key =>
    match r.realization? key with
    | some realization => r.contentIssues subject (realization.facets.flatMap (·.documents))
        (realization.declarations.map (·.object))
    | none => #[issue "unknown-realization" key "Missing source realization"]
  | .facet key name =>
    match (r.realization? key).bind (fun value => value.facets.find? (·.name == name)) with
    | some facet => r.contentIssues subject facet.documents facet.declarations
    | none => #[issue "unknown-facet" subject "Missing source facet"]
  | .declaration _ object => r.objectIssues object
  | _ => #[]

private def Registry.semanticIssues (r : Registry) (objects : Array ObjectKey) (scope : ContentScope) : Array Diagnostic :=
  objects.filterMap fun object =>
    let tag := if object.context.language == `lean then sourceTag scope else NativeLean.sourceContext
    if r.bindingInputs.any (fun input => input.name == tag &&
        match input.subject with | .declaration _ actual => actual == object | _ => false) then none
    else some <| issue "semantic-context-unavailable" object "Selected declaration lacks the requested semantic content"

private def Registry.availabilityIssues (r : Registry) (subject : Subject) (scope : ContentScope := .implementation) (includeSemantics : Bool := true) : Array Diagnostic :=
  let selected (key : RealizationKey) (facets : Array Name) :=
    (r.realization? key).map (fun value =>
      if facets.isEmpty then value.declarations.map (·.object)
      else value.facets.filter (fun facet => facets.contains facet.name) |>.flatMap (·.declarations)) |>.getD #[]
  match subject.translation? with
  | none =>
    let objects := match subject with
      | .realization key => selected key #[]
      | .facet key name => selected key #[name]
      | .declaration _ object => #[object]
      | _ => #[]
    canonical (r.subjectContentIssues subject ++ (if includeSemantics then r.semanticIssues objects scope else #[]))
  | some key =>
    match r.translation? key with
    | none => #[issue "unknown-translation" key "Missing source translation"]
    | some translation => canonical <| (translation.source ++ translation.target).flatMap fun endpoint =>
        let content := if endpoint.facets.isEmpty then r.subjectContentIssues (.realization endpoint.realization)
          else endpoint.facets.flatMap fun name => r.subjectContentIssues (.facet endpoint.realization name)
        content ++ (if includeSemantics then r.semanticIssues (selected endpoint.realization endpoint.facets) scope else #[])

/-- Independent local suitability, before prerequisite traversal. -/
private def Registry.computeLocalResult (r : Registry) (key : RequirementKey) : Result := Id.run do
  let some req := r.requirement? key
    | return { status := .blocked, diagnostics := #[issue "unknown-requirement" key "Missing requirement"] }
  match req.expected with
  | .proof _ witness =>
    let unavailable := r.objectIssues witness
    if !unavailable.isEmpty then
      return {
        status := .blocked
        diagnostics := unavailable.push (issue "witness-unavailable" witness "No current resolved witness source") }
    -- A correspondence proof validates selected endpoints as well as a formal
    -- goal. The standalone witness can stay checked on its own realization.
    if key.subject.translation?.isSome then
      let selected := r.availabilityIssues key.subject req.scope
      if !selected.isEmpty then return { status := .blocked, diagnostics := selected }
    unless r.bindingInputs.any (fun input => input.subject == key.subject &&
        input.name == expectedTag req.scope key) do
      return { status := .blocked, diagnostics := #[issue "semantic-context-unavailable" key
        "Expected proposition/witness lacks current provider/build semantic inputs"] }
  | _ =>
    let unavailable := if req.expected.isNativeDeclarationCheck then r.subjectContentIssues key.subject
      else r.availabilityIssues key.subject req.scope
    if !unavailable.isEmpty then return { status := .blocked, diagnostics := unavailable }
  for prerequisite in req.prerequisites do
    if let some contract := r.requirement? prerequisite then
      let unavailable := r.availabilityIssues prerequisite.subject .statement
      if !unavailable.isEmpty then return { status := .blocked, diagnostics := unavailable }
      if let .proof .. := contract.expected then
        unless r.bindingInputs.any (fun input => input.subject == prerequisite.subject &&
            input.name == expectedTag .statement prerequisite) do
          return { status := .blocked, diagnostics := #[issue "semantic-context-unavailable" prerequisite
            "Prerequisite expected proposition lacks current statement semantics"] }
  let binding := (r.bindingFor key).getD ""
  let candidates := r.evidenceIndex[key]?.getD #[]
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

private structure Components where
  next : Nat := 0
  indices : Std.HashMap RequirementKey Nat := {}
  lows : Std.HashMap RequirementKey Nat := {}
  stack : Array RequirementKey := #[]
  onStack : Std.HashSet RequirementKey := {}
  finished : Array (Array RequirementKey) := #[]

/-- Tarjan's walk visits every requirement/edge once. Components are emitted
prerequisite-first, so closure evaluation never replays shared diamond paths. -/
private partial def visitComponent (r : Registry) (key : RequirementKey) : StateM Components Unit := do
  let index := (← get).next
  modify fun state => { state with
    next := index + 1, indices := state.indices.insert key index
    lows := state.lows.insert key index, stack := state.stack.push key
    onStack := state.onStack.insert key }
  for dependency in ((r.requirement? key).map (·.prerequisites)).getD #[] do
    if !(← get).indices.contains dependency then
      visitComponent r dependency
      modify fun state => { state with
        lows := state.lows.insert key (min (state.lows[key]?.getD index) (state.lows[dependency]?.getD index)) }
    else if (← get).onStack.contains dependency then
      modify fun state => { state with
        lows := state.lows.insert key (min (state.lows[key]?.getD index) (state.indices[dependency]?.getD index)) }
  if (← get).lows[key]? == some index then
    let mut component := #[]
    let mut done := false
    while !done do
      let state ← get
      let member := state.stack.back!
      set { state with stack := state.stack.pop, onStack := state.onStack.erase member }
      component := component.push member
      done := member == key
    modify fun state => { state with finished := state.finished.push (canonical component) }

private def Registry.computeResults (r : Registry) : Std.HashMap RequirementKey Result := Id.run do
  let build : StateM Components Unit := do
    for requirement in r.requirements do
      unless (← get).indices.contains requirement.key do visitComponent r requirement.key
  let (_, components) := build.run {}
  let mut results : Std.HashMap RequirementKey Result := {}
  for component in components.finished do
    let members := component.foldl (fun out key => out.insert key) ({} : Std.HashSet RequirementKey)
    let cyclic := component.size > 1 || component.any fun key =>
      (r.requirement? key).any (·.prerequisites.contains key)
    let cycleDiagnostics := if cyclic then component.map fun key =>
        issue "requirement-cycle" key "Recursive validation requirement"
      else #[]
    for key in component do
      let own := r.localValues[key]?.getD { status := .blocked }
      let dependencies := if cyclic then component.flatMap (fun member =>
          ((r.requirement? member).map (·.prerequisites)).getD #[])
        else ((r.requirement? key).map (·.prerequisites)).getD #[]
      let external := dependencies.filter (fun dependency => !members.contains dependency)
      let prerequisiteResults := external.map fun dependency =>
        results[dependency]?.getD { status := .blocked }
      if !cyclic && prerequisiteResults.all (·.complete) then
        results := results.insert key own
      else
        let cycleLocalDiagnostics := if cyclic then component.flatMap fun member =>
          (r.localValues[member]?.getD { status := .blocked }).diagnostics else #[]
        results := results.insert key { own with
          status := .blocked
          diagnostics := canonical <| own.diagnostics ++ cycleLocalDiagnostics ++ cycleDiagnostics ++
            prerequisiteResults.flatMap (·.diagnostics) ++
            #[issue "unfinished-prerequisite" key "A selected prerequisite requirement is unfinished"] }
  return results

/-- Cached local suitability and closure are derived from the same immutable
admitted snapshot; querying performs no graph traversal or provider operation. -/
def Registry.localResult (r : Registry) (key : RequirementKey) : Result :=
  r.localValues[key]?.getD {
    status := .blocked, diagnostics := #[issue "unknown-requirement" key "Missing requirement"] }

def Registry.resultForRequirement (r : Registry) (key : RequirementKey) : Result :=
  r.resultValues[key]?.getD {
    status := .blocked, diagnostics := #[issue "unknown-requirement" key "Missing requirement"] }

/-- Fatal admission remains all-or-nothing. No temporary input/index escapes
before full reference validation, binding construction and closure evaluation. -/
def admit (input : Input) : Except (Array Diagnostic) Registry := Id.run do
  let nodes := values input.nodes
  let documents := values input.documents
  let objects := values input.objects
  let realizations := values input.realizations
  let translations := values input.translations
  let claims := values input.claims
  let requirements := values input.requirements
  let evidence := values input.evidence
  let evidenceIndex := evidence.foldl (fun out item =>
    out.insert item.requirement ((out[item.requirement]?.getD #[]).push item))
    ({} : Std.HashMap RequirementKey (Array Evidence))
  let r : Registry := {
    input, nodeValues := nodes, documentValues := documents, objectValues := objects
    realizationValues := realizations, translationValues := translations
    claimValues := claims, requirementValues := requirements
    semanticValues := values input.bindingInputs, evidenceValues := evidence
    nodeIndex := indexBy (·.label) nodes, documentIndex := indexBy (·.key) documents
    objectIndex := indexBy (·.key) objects, realizationIndex := indexBy (·.key) realizations
    translationIndex := indexBy (·.key) translations, claimIndex := indexBy (·.key) claims
    requirementIndex := indexBy (·.key) requirements, evidenceIndex }
  let diagnostics := input.producerIssues ++
    familyIssues "node" (·.label) input.nodes ++ familyIssues "document" (·.key) input.documents ++
    familyIssues "object" (·.key) input.objects ++ familyIssues "realization" (·.key) input.realizations ++
    familyIssues "translation" (·.key) input.translations ++ familyIssues "claim" (·.key) input.claims ++
    familyIssues "requirement" (·.key) input.requirements ++ familyIssues "evidence" (·.id) input.evidence ++
    familyIssues "binding input" (fun value => (value.subject, value.name)) input.bindingInputs ++ r.referenceIssues
  unless diagnostics.isEmpty do return .error (canonical diagnostics)
  let subjects := r.realizations.flatMap (fun value => #[Subject.realization value.key] ++
      value.facets.map (fun facet => .facet value.key facet.name) ++
      value.declarations.map (fun decl => .declaration value.key decl.object)) ++
    r.translations.map (fun value => .translation value.key) ++ r.claims.map (fun value => .claim value.key)
  let requiredIndex := subjects.foldl (fun out subject => out.insert subject (r.computeRequiredFor subject))
    ({} : Std.HashMap Subject (Array RequirementKey))
  let r := { r with requiredIndex }
  let bindings ← match r.computeBindings with
    | .ok bindings => pure bindings
    | .error message => return .error #[{ code := "invalid-binding-graph", subject := "Blueprint", message }]
  let r := { r with bindings }
  let localValues := r.requirements.foldl (fun out req => out.insert req.key (r.computeLocalResult req.key))
    ({} : Std.HashMap RequirementKey Result)
  let r := { r with localValues }
  return .ok { r with resultValues := r.computeResults }

def Registry.resultFor (r : Registry) (subject : Subject) : Result := Id.run do
  if !r.hasSubject subject then
    return { status := .blocked, diagnostics := #[issue "unknown-subject" subject "Missing subject"] }
  let unavailable := if subject.translation?.isSome then r.availabilityIssues subject (includeSemantics := false)
    else r.subjectContentIssues subject
  if !unavailable.isEmpty then return { status := .blocked, diagnostics := unavailable }
  let keys := canonical (r.requiredFor subject)
  -- Every required declaration needs its own explicit validation contract.
  if let .realization key := subject then
    if (r.realization? key).any (·.declarations.any (·.required.isEmpty)) then
      return { status := .unassessed }
  if let .translation key := subject then
    if !(r.claims.any (·.key.translation == key)) ||
        r.claims.any (fun c => c.key.translation == key && c.required.isEmpty) then
      return { status := .unassessed }
  if keys.isEmpty then return { status := .unassessed }
  let results := keys.map (r.resultForRequirement ·)
  return {
    status := if results.all (·.complete) then .complete
      else if results.any (·.status == .blocked) then .blocked else .pending
    localComplete := results.all (·.localComplete)
    diagnostics := canonical (results.flatMap (·.diagnostics)) }

/-- Select by identity and validation name, never by which alternative is complete.
The future default-Lean adapter supplies its explicit default realization name. -/
structure Selection where
  node : Name
  context : Context
  realization : Option Name := none
  facet : Option Name := none
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
        (match selection.facet, req.key.subject with
         | none, _ => true
         | some name, .facet _ actual => name == actual
         | _, _ => false)
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
