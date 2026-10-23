/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Validation

/-! Bounded pure registry/admission and one validation projection. This module is
not installed into the existing Blueprint environment or graph. Its provider
observations must come from real language checks before production use. -/

namespace Informal.Translations

open Lean Realizations Validation

/-- Empty facet selection means the whole realization; otherwise every named
facet must exist. Selection is part of the reviewed correspondence contract. -/
structure Endpoint where
  realization : RealizationKey
  facets : Array Name := #[]
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

instance : Coe RealizationKey Endpoint := ⟨fun key => { realization := key }⟩

structure Translation where
  key : TranslationKey
  source : Array Endpoint
  target : Array Endpoint
  /-- Exact requirements, including selected target validation and obligations. -/
  required : Array RequirementKey := #[]
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

structure Claim where
  key : ClaimKey
  interpretation : String
  assumptions : Array String := #[]
  required : Array RequirementKey := #[]
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

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
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

/-- Construct only through `admit`; accepted provenance remains inspectable. -/
structure Registry where
  private mk ::
  contributions : Input
  deriving Repr

private def values [BEq α] [ToJson α] (records : Array (Contribution α)) : Array α :=
  canonical (records.map (·.value))

def Registry.nodes (r : Registry) : Array Node := values r.contributions.nodes
def Registry.documents (r : Registry) : Array Document := values r.contributions.documents
def Registry.objects (r : Registry) : Array ObjectObservation := values r.contributions.objects
def Registry.realizations (r : Registry) : Array Realization := values r.contributions.realizations
def Registry.translations (r : Registry) : Array Translation := values r.contributions.translations
def Registry.claims (r : Registry) : Array Claim := values r.contributions.claims
def Registry.requirements (r : Registry) : Array Requirement := values r.contributions.requirements
def Registry.evidence (r : Registry) : Array Evidence := values r.contributions.evidence

def Registry.realization? (r : Registry) (key : RealizationKey) : Option Realization :=
  r.realizations.find? (·.key == key)

def Registry.translation? (r : Registry) (key : TranslationKey) : Option Translation :=
  r.translations.find? (·.key == key)

def Registry.requirement? (r : Registry) (key : RequirementKey) : Option Requirement :=
  r.requirements.find? (·.key == key)

def Registry.claim? (r : Registry) (key : ClaimKey) : Option Claim := r.claims.find? (·.key == key)

private def issue [ToJson α] (code : String) (subject : α) (message : String)
    (origins : Array Origin := #[]) : Diagnostic :=
  { code, subject := (toJson subject).compress, message, origins := canonical origins }

private def familyIssues [BEq α] [ToJson α] [BEq κ] [ToJson κ]
    (family : String) (key : α → κ) (records : Array (Contribution α)) : Array Diagnostic := Id.run do
  let mut diagnostics := #[]
  for k in canonical (records.map (fun record => key record.value)) do
    let bucket := records.filter (fun record => key record.value == k)
    if (values bucket).size > 1 then
      diagnostics := diagnostics.push <| issue "semantic-conflict" k
        s!"Incompatible {family} definitions" (bucket.map (·.origin))
  return diagnostics

private def producerRecords [ToJson α] (tag : String) (records : Array (Contribution α)) :
    Array (Name × String × Origin) :=
  records.map fun record =>
    (record.origin.id, (toJson (tag, record)).compress, record.origin)

private def Input.producerIssues (input : Input) : Array Diagnostic := Id.run do
  let records := producerRecords "node" input.nodes ++ producerRecords "document" input.documents ++
    producerRecords "object" input.objects ++ producerRecords "realization" input.realizations ++
    producerRecords "translation" input.translations ++ producerRecords "claim" input.claims ++
    producerRecords "requirement" input.requirements ++ producerRecords "evidence" input.evidence
  let mut diagnostics := #[]
  for id in canonical (records.map (·.1)) do
    let bucket := records.filter (·.1 == id)
    if id.isAnonymous || bucket.any (·.2.2.moduleName.isAnonymous) ||
        (canonical (bucket.map (·.2.1))).size > 1 then
      diagnostics := diagnostics.push <| issue "producer-collision" id
        "Producer-site identity is empty or has incompatible records" (bucket.map (·.2.2))
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
      if doc.context != object.key.context || !r.documents.any (·.key == doc) then
        diagnostics := diagnostics.push <| issue "unknown-document" object.key "Missing/wrong-context source"
  for realization in r.realizations do
    if !realization.key.valid || !realization.context.valid ||
        !r.nodes.any (·.label == realization.key.node) then
      diagnostics := diagnostics.push <| issue "invalid-realization" realization.key "Missing node/context"
    if (canonical (realization.facets.map (·.name))).size != realization.facets.size ||
        realization.facets.any (·.name.isAnonymous) then
      diagnostics := diagnostics.push <| issue "invalid-facets" realization.key "Empty or duplicate facet"
    if (canonical (realization.declarations.map (·.object))).size != realization.declarations.size then
      diagnostics := diagnostics.push <| issue "duplicate-declaration" realization.key "Duplicate declaration"
    for facet in realization.facets do
      for doc in facet.documents do
        if doc.context != realization.context || !r.documents.any (·.key == doc) then
          diagnostics := diagnostics.push <| issue "unknown-document" realization.key "Missing/wrong-context facet source"
    for decl in realization.declarations do
      if !decl.object.valid || decl.object.context != realization.context then
        diagnostics := diagnostics.push <| issue "wrong-project" decl.object "Declaration is outside realization context"
      for key in decl.required do
        if key.subject.realization? != some realization.key then
          diagnostics := diagnostics.push <| issue "wrong-subject" key "Declaration requirement belongs elsewhere"
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
  for requirement in r.requirements do
    if !r.hasSubject requirement.key.subject || requirement.key.name.isAnonymous || !requirement.expected.valid then
      diagnostics := diagnostics.push <| issue "invalid-requirement" requirement.key "Invalid subject/name/expectation"
    if let .proof goal _ := requirement.expected then
      if let some key := requirement.key.subject.realization? then
        if !(r.realization? key).any (·.context == goal.context) then
          diagnostics := diagnostics.push <| issue "wrong-project" requirement.key "Proof goal is outside realization context"
      for doc in goal.documents do
        if doc.context != goal.context || !r.documents.any (·.key == doc) then
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
  return diagnostics

/-- Fatal structural admission is all-or-nothing; missing provider observations
and unsuitable evidence instead remain inspectable unfinished validation. -/
def admit (input : Input) : Except (Array Diagnostic) Registry := Id.run do
  let r := Registry.mk input
  let diagnostics := input.producerIssues ++
    familyIssues "node" (·.label) input.nodes ++ familyIssues "document" (·.key) input.documents ++
    familyIssues "object" (·.key) input.objects ++ familyIssues "realization" (·.key) input.realizations ++
    familyIssues "translation" (·.key) input.translations ++ familyIssues "claim" (·.key) input.claims ++
    familyIssues "requirement" (·.key) input.requirements ++ familyIssues "evidence" (·.id) input.evidence ++
    r.referenceIssues
  if diagnostics.isEmpty then return .ok r
  return .error (canonical diagnostics)

def Registry.requiredFor (r : Registry) : Subject → Array RequirementKey
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

private def Registry.subjectRealizations (r : Registry) (subject : Subject) : Array RealizationKey :=
  match subject.realization?, subject.translation? with
  | some key, _ => #[key]
  | _, some key => (r.translation? key).map (fun t => (t.source ++ t.target).map (·.realization)) |>.getD #[]
  | _, _ => #[]

/-- Exact canonical structured binding. Includes selected endpoint documents and
the connected contracts/goals, never evidence, time, or producer replay order.
Whole participating documents deliberately give conservative invalidation. -/
def Registry.bindingFor (r : Registry) (key : RequirementKey) : Option ContentBinding := do
  let _ ← r.requirement? key
  let mut keys := #[key]
  for _ in [:r.requirements.size + 1] do
    let more := keys.flatMap fun current =>
      match r.requirement? current with
      | none => #[]
      | some req =>
        let parent := match req.key.subject.translation?, req.key.subject.realization? with
          | some owner, _ => r.requiredFor (.translation owner)
          | _, some owner => r.requiredFor (.realization owner)
          | _, _ => #[]
        req.prerequisites ++ r.requiredFor req.key.subject ++ parent
    keys := canonical (keys ++ more)
  let requirements := r.requirements.filter (fun req => keys.contains req.key)
  let subjects := canonical (requirements.map (·.key.subject))
  let translationKeys := canonical (subjects.filterMap (·.translation?))
  let realizationKeys := canonical (subjects.flatMap (r.subjectRealizations ·))
  let realizations := r.realizations.filter (fun value => realizationKeys.contains value.key)
  let witnesses := requirements.filterMap fun req => match req.expected with
    | .proof _ witness => some witness
    | _ => none
  let objects := r.objects.filter fun object => witnesses.contains object.key ||
    realizations.any (·.declarations.any (·.object == object.key))
  let documentKeys := canonical <| realizations.flatMap (fun value => value.facets.flatMap (·.documents)) ++
    objects.filterMap (·.document) ++ requirements.flatMap (fun req => match req.expected with
      | .proof goal _ => goal.documents
      | _ => #[])
  return (Json.mkObj [
    ("requirement", toJson key), ("contracts", toJson requirements),
    ("realizations", toJson realizations),
    ("objects", toJson (objects.map fun o => (o.key, o.document))),
    ("translations", toJson (r.translations.filter (fun t => translationKeys.contains t.key))),
    ("claims", toJson (r.claims.filter (fun c => translationKeys.contains c.key.translation))),
    ("documents", toJson (r.documents.filter (fun d => documentKeys.contains d.key)))]).compress

private def Registry.availabilityIssues (r : Registry) (subject : Subject) : Array Diagnostic :=
  (r.subjectRealizations subject).flatMap fun key =>
    ((r.realization? key).map (·.declarations) |>.getD #[]).filterMap fun decl =>
      match r.objects.find? (·.key == decl.object) with
      | some observation =>
        if observation.resolution == .resolved && observation.document.isSome then none
        else some <| issue "object-unavailable" decl.object s!"{repr observation.resolution}: {observation.explanation}"
      | none => some <| issue "object-unavailable" decl.object "No source resolution observation"

/-- Independent local suitability, before prerequisite traversal. -/
def Registry.localResult (r : Registry) (key : RequirementKey) : Result := Id.run do
  let some req := r.requirement? key
    | return { status := .blocked, diagnostics := #[issue "unknown-requirement" key "Missing requirement"] }
  match req.expected with
  | .proof _ witness =>
    let observation := r.objects.find? (·.key == witness)
    if !observation.any (fun o => o.resolution == .resolved && o.document.isSome) then
      return {
        status := .blocked
        diagnostics := #[issue "witness-unavailable" witness "No current resolved witness source"] }
  | _ =>
    let unavailable := r.availabilityIssues key.subject
    if !unavailable.isEmpty then return { status := .blocked, diagnostics := unavailable }
  let binding := (r.bindingFor key).getD ""
  let candidates := r.evidence.filter (·.requirement == key)
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

private def Registry.evaluate (r : Registry) : Nat → Array RequirementKey → RequirementKey → Result
  | 0, _, key => { status := .blocked, diagnostics := #[issue "requirement-cycle" key "Requirement traversal exhausted"] }
  | fuel + 1, path, key => Id.run do
    let own := r.localResult key
    if path.contains key then
      return { own with
        status := .blocked
        diagnostics := own.diagnostics.push (issue "requirement-cycle" key "Recursive validation requirement") }
    let some req := r.requirement? key | return own
    let dependencies := req.prerequisites.map (r.evaluate fuel (path.push key) ·)
    if dependencies.all (·.complete) then return own
    return { own with
      status := .blocked
      diagnostics := canonical <| own.diagnostics ++ dependencies.flatMap (·.diagnostics) ++
        #[issue "unfinished-prerequisite" key "A selected prerequisite requirement is unfinished"] }

def Registry.resultForRequirement (r : Registry) (key : RequirementKey) : Result :=
  r.evaluate (r.requirements.size + 1) #[] key

def Registry.resultFor (r : Registry) (subject : Subject) : Result := Id.run do
  if !r.hasSubject subject then
    return { status := .blocked, diagnostics := #[issue "unknown-subject" subject "Missing subject"] }
  let unavailable := r.availabilityIssues subject
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
