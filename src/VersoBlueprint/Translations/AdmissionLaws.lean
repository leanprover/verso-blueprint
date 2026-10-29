/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Translations.Laws
import Std.Data.HashMap.Lemmas
import Std.Data.HashSet.Lemmas

/-! Admission-to-query guarantees for production Registry values. Source/index
coherence follows from actual admission; completed results admit induction over
their prerequisites even without a correctness axiom for the partial SCC walk.
These laws concern supplied observations, not authentication of their providers. -/

namespace Informal.Translations
open Lean Realizations Validation

deriving instance ReflBEq, LawfulBEq for DocumentKey, Goal, Expectation, Requirement,
  ProofObservation, ReviewObservation, CheckObservation, Observation, Evidence,
  Facet, Realizations.Declaration, Realization, Endpoint, Translation, Claim,
  Resolution, Document, ObjectObservation, BindingInput

-- The production module predates `module` / `import all`. Open its private
-- implementation names in this proof scope only; no aliases or production API
-- are exported. Proof terms still reference the original kernel declarations.
run_cmd do
  let env ← getEnv
  let some owner := env.getModuleIdxFor? ``admit
    | throwError "Admission implementation must be imported before opening its proof scope"
  for (name, _) in env.constants.toList do
    if env.getModuleIdxFor? name == some owner then
      if let some user := privateToUserName? name then
        if (`Informal.Translations).isPrefixOf user then
          Elab.Command.modifyScope fun scope => { scope with
            openDecls := .explicit (user.replacePrefix `Informal.Translations .anonymous) name :: scope.openDecls }

/-- Admission preserves all supplied source records up to canonical ordering and
duplicate removal. The original contributions remain available unchanged. -/
structure Registry.SourcesMatch (registry : Registry) (input : Input) : Prop where
  contributions : registry.contributions = input
  nodes : registry.nodes = canonical (input.nodes.map (·.value))
  documents : registry.documents = canonical (input.documents.map (·.value))
  objects : registry.objects = canonical (input.objects.map (·.value))
  realizations : registry.realizations = canonical (input.realizations.map (·.value))
  translations : registry.translations = canonical (input.translations.map (·.value))
  claims : registry.claims = canonical (input.claims.map (·.value))
  requirements : registry.requirements = canonical (input.requirements.map (·.value))
  evidence : registry.evidence = canonical (input.evidence.map (·.value))
  bindingInputs : registry.bindingInputs = canonical (input.bindingInputs.map (·.value))

theorem admit_sources (h : admit input = .ok registry) : registry.SourcesMatch input := by
  simp only [admit, Id.run, pure, bind] at h
  split at h
  · split at h
    · cases h
      exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
    · contradiction
  · contradiction

private def Registry.subjects (r : Registry) : Array Subject :=
  r.realizations.flatMap (fun value => #[Subject.realization value.key] ++
      value.facets.map (fun facet => .facet value.key facet.name) ++
      value.declarations.map (fun decl => .declaration value.key decl.object)) ++
    r.translations.map (fun value => .translation value.key) ++ r.claims.map (fun value => .claim value.key)

private structure Registry.IndexesMatch (r : Registry) : Prop where
  documentIndex : (Registry.documentIndex r) = indexBy (·.key) r.documents
  objectIndex : (Registry.objectIndex r) = indexBy (·.key) r.objects
  realizationIndex : (Registry.realizationIndex r) = indexBy (·.key) r.realizations
  translationIndex : (Registry.translationIndex r) = indexBy (·.key) r.translations
  claimIndex : (Registry.claimIndex r) = indexBy (·.key) r.claims
  requirementIndex : (Registry.requirementIndex r) = indexBy (·.key) r.requirements
  evidenceIndex : (Registry.evidenceIndex r) = r.evidence.foldl (fun out item =>
    out.insert item.requirement ((out[item.requirement]?.getD #[]).push item)) {}
  requiredIndex : (Registry.requiredIndex r) = r.subjects.foldl
    (fun out subject => out.insert subject (Registry.computeRequiredFor r subject)) {}
  localValues : (Registry.localValues r) = r.requirements.foldl
    (fun out req => out.insert req.key (Registry.computeLocalResult r req.key)) {}

set_option maxHeartbeats 800000 in
private theorem admit_indexes (h : admit input = .ok registry) : registry.IndexesMatch := by
  simp only [admit, Id.run, pure, bind] at h
  split at h
  · split at h
    · cases h
      exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
    · contradiction
  · contradiction

private theorem fold_insert_preserves [BEq κ] [LawfulBEq κ] [Hashable κ]
    (key : α → κ) (predicate : κ → α → Prop) (xs : List α) (initial : Std.HashMap κ α)
    (hi : ∀ k v, initial[k]? = some v → predicate k v)
    (hx : ∀ v ∈ xs, predicate (key v) v) :
    ∀ k v, (xs.foldl (fun out value => out.insert (key value) value) initial)[k]? = some v →
      predicate k v := by
  induction xs generalizing initial with
  | nil => exact hi
  | cons x xs ih =>
    apply ih
    · intro k v hv
      rw [Std.HashMap.getElem?_insert] at hv
      split at hv
      · rename_i he
        have hk : key x = k := by simpa using he
        cases hv
        rw [← hk]
        exact hx x (by simp)
      · exact hi k v hv
    · intro v hv
      exact hx v (by simp [hv])

private theorem indexBy_lookup [BEq κ] [LawfulBEq κ] [Hashable κ]
    (key : α → κ) (xs : Array α) (h : (indexBy key xs)[k]? = some value) :
    value ∈ xs ∧ key value = k := by
  unfold indexBy at h
  rw [← Array.foldl_toList] at h
  apply fold_insert_preserves key (fun k v => v ∈ xs ∧ key v = k) xs.toList {} ?_ ?_ k value h
  · simp
  · intro v hv
    exact ⟨by simpa using hv, rfl⟩

private theorem fold_insert_function [BEq κ] [LawfulBEq κ] [Hashable κ]
    (keys : List κ) (value : κ → α) (initial : Std.HashMap κ α) (key : κ) :
    (keys.foldl (fun out k => out.insert k (value k)) initial)[key]? =
      if key ∈ keys then some (value key) else initial[key]? := by
  induction keys generalizing initial with
  | nil => simp
  | cons k keys ih =>
    simp only [List.foldl_cons, ih, List.mem_cons, Std.HashMap.getElem?_insert]
    by_cases h : key ∈ keys
    · simp [h]
    · by_cases he : key = k
      · subst k
        simp [h]
      · simp [h, he, Ne.symm he]

private theorem array_fold_insert_function [BEq κ] [LawfulBEq κ] [Hashable κ]
    (keys : Array κ) (value : κ → α) (key : κ) :
    (keys.foldl (fun out k => out.insert k (value k)) ({} : Std.HashMap κ α))[key]? =
      if key ∈ keys then some (value key) else none := by
  rw [← Array.foldl_toList, fold_insert_function]
  simp

private theorem Registry.requiredFor_of_subjects (r : Registry) (hi : r.IndexesMatch)
    (hs : subject ∈ r.subjects) :
    r.requiredFor subject = Registry.computeRequiredFor r subject := by
  unfold Registry.requiredFor
  rw [hi.requiredIndex, array_fold_insert_function]
  simp [hs]

private theorem Registry.hasSubject_mem_subjects (r : Registry) (hi : r.IndexesMatch)
    (known : r.hasSubject subject = true) : subject ∈ r.subjects := by
  have realMem {key value} (h : r.realization? key = some value) :
      value ∈ r.realizations ∧ value.key = key := by
    rw [Registry.realization?, hi.realizationIndex] at h
    exact indexBy_lookup _ _ h
  have transMem {key value} (h : r.translation? key = some value) :
      value ∈ r.translations ∧ value.key = key := by
    rw [Registry.translation?, hi.translationIndex] at h
    exact indexBy_lookup _ _ h
  have claimMem {key value} (h : r.claim? key = some value) :
      value ∈ r.claims ∧ value.key = key := by
    rw [Registry.claim?, hi.claimIndex] at h
    exact indexBy_lookup _ _ h
  cases subject with
  | realization key =>
    obtain ⟨value, hv⟩ := Option.isSome_iff_exists.mp known
    obtain ⟨hm, hk⟩ := realMem hv
    simp only [Registry.subjects, Array.mem_append, Array.mem_flatMap, Array.mem_map]
    exact .inl (.inl ⟨value, hm, by simp [hk]⟩)
  | facet key name =>
    simp only [Registry.hasSubject, Option.any_eq_true, Array.any_eq_true] at known
    obtain ⟨value, hv, facet, hf, he⟩ := known
    obtain ⟨hm, hk⟩ := realMem hv
    simp only [Registry.subjects, Array.mem_append, Array.mem_flatMap, Array.mem_map]
    refine .inl (.inl ⟨value, hm, ?_⟩)
    simp only [hk]
    exact .inl (.inr ⟨value.facets[facet], Array.getElem_mem hf, by simp [beq_iff_eq.mp he]⟩)
  | declaration key object =>
    simp only [Registry.hasSubject, Option.any_eq_true, Array.any_eq_true] at known
    obtain ⟨value, hv, decl, hd, he⟩ := known
    obtain ⟨hm, hk⟩ := realMem hv
    simp only [Registry.subjects, Array.mem_append, Array.mem_flatMap, Array.mem_map]
    refine .inl (.inl ⟨value, hm, ?_⟩)
    simp only [hk]
    exact .inr ⟨value.declarations[decl], Array.getElem_mem hd, by simp [beq_iff_eq.mp he]⟩
  | translation key =>
    obtain ⟨value, hv⟩ := Option.isSome_iff_exists.mp known
    obtain ⟨hm, hk⟩ := transMem hv
    simp only [Registry.subjects, Array.mem_append, Array.mem_flatMap, Array.mem_map]
    exact .inl (.inr ⟨value, hm, by simp [hk]⟩)
  | claim key =>
    obtain ⟨value, hv⟩ := Option.isSome_iff_exists.mp known
    obtain ⟨hm, hk⟩ := claimMem hv
    simp only [Registry.subjects, Array.mem_append, Array.mem_flatMap, Array.mem_map]
    exact .inr ⟨value, hm, by simp [hk]⟩

/-- Requirements survive collection exactly, including complete records rather
than just their keys. -/
theorem admit_requirement_mem (h : admit input = .ok registry) (requirement : Requirement) :
    requirement ∈ registry.requirements ↔
      ∃ record ∈ input.requirements, record.value = requirement := by
  rw [(admit_sources h).requirements, mem_canonical]
  exact Array.mem_map

/-- Evidence observations and their bindings/provenance payloads are not silently
discarded by canonical collection. -/
theorem admit_evidence_mem (h : admit input = .ok registry) (evidence : Evidence) :
    evidence ∈ registry.evidence ↔ ∃ record ∈ input.evidence, record.value = evidence := by
  rw [(admit_sources h).evidence, mem_canonical]
  exact Array.mem_map

theorem admit_realization_mem (h : admit input = .ok registry) (realization : Realization) :
    realization ∈ registry.realizations ↔
      ∃ record ∈ input.realizations, record.value = realization := by
  rw [(admit_sources h).realizations, mem_canonical]
  exact Array.mem_map

theorem admit_translation_mem (h : admit input = .ok registry) (translation : Translation) :
    translation ∈ registry.translations ↔
      ∃ record ∈ input.translations, record.value = translation := by
  rw [(admit_sources h).translations, mem_canonical]
  exact Array.mem_map

theorem admit_claim_mem (h : admit input = .ok registry) (claim : Claim) :
    claim ∈ registry.claims ↔ ∃ record ∈ input.claims, record.value = claim := by
  rw [(admit_sources h).claims, mem_canonical]
  exact Array.mem_map

theorem admit_document_mem (h : admit input = .ok registry) (document : Document) :
    document ∈ registry.documents ↔ ∃ record ∈ input.documents, record.value = document := by
  rw [(admit_sources h).documents, mem_canonical]
  exact Array.mem_map

theorem admit_object_mem (h : admit input = .ok registry) (object : ObjectObservation) :
    object ∈ registry.objects ↔ ∃ record ∈ input.objects, record.value = object := by
  rw [(admit_sources h).objects, mem_canonical]
  exact Array.mem_map

theorem admit_bindingInput_mem (h : admit input = .ok registry) (bindingInput : BindingInput) :
    bindingInput ∈ registry.bindingInputs ↔ ∃ record ∈ input.bindingInputs, record.value = bindingInput := by
  rw [(admit_sources h).bindingInputs, mem_canonical]
  exact Array.mem_map

private theorem admit_requiredFor (h : admit input = .ok registry)
    (known : registry.hasSubject subject = true) :
    registry.requiredFor subject = Registry.computeRequiredFor registry subject :=
  registry.requiredFor_of_subjects (admit_indexes h)
    (registry.hasSubject_mem_subjects (admit_indexes h) known)

/-- The required-index cache for a realization is derived from the selected
authored record, including its facet and declaration contracts. -/
theorem admit_requiredFor_realization (h : admit input = .ok registry)
    (selected : registry.realization? key = some realization) :
    registry.requiredFor (.realization key) = realization.requirements := by
  rw [admit_requiredFor h (by simp [Registry.hasSubject, selected])]
  simp [Registry.computeRequiredFor, selected]

theorem admit_requiredFor_declaration (h : admit input = .ok registry)
    (selected : registry.realization? key = some realization)
    (declaration : realization.declarations.find? (·.object == object) = some decl) :
    registry.requiredFor (.declaration key object) = decl.required := by
  have known : registry.hasSubject (.declaration key object) = true := by
    simp only [Registry.hasSubject, selected, Option.any_some]
    obtain ⟨hp, i, hi, he, _⟩ := Array.find?_eq_some_iff_getElem.mp declaration
    exact Array.any_eq_true.mpr ⟨i, hi, by simpa [he] using hp⟩
  rw [admit_requiredFor h known]
  simp [Registry.computeRequiredFor, selected, declaration]

theorem admit_requiredFor_claim (h : admit input = .ok registry)
    (selected : registry.claim? key = some claim) :
    registry.requiredFor (.claim key) = claim.required := by
  rw [admit_requiredFor h (by simp [Registry.hasSubject, selected])]
  simp [Registry.computeRequiredFor, selected]

theorem admit_requiredFor_translation (h : admit input = .ok registry)
    (selected : registry.translation? key = some translation) :
    registry.requiredFor (.translation key) = translation.required ++
      (registry.claims.filter (·.key.translation == key)).flatMap (·.required) := by
  rw [admit_requiredFor h (by simp [Registry.hasSubject, selected])]
  simp [Registry.computeRequiredFor, selected]

/-- Facet selection keeps exactly the authored keys that name collected
requirements. Reference-validation correctness is a separate obligation. -/
private theorem admit_requiredFor_facet (h : admit input = .ok registry)
    (selected : registry.realization? key = some realization)
    (facet : realization.facets.find? (·.name == name) = some authored) :
    registry.requiredFor (.facet key name) = registry.requirements.filterMap
      (fun req => if authored.required.contains req.key then some req.key else none) := by
  have known : registry.hasSubject (.facet key name) = true := by
    simp only [Registry.hasSubject, selected, Option.any_some]
    obtain ⟨hp, i, hi, he, _⟩ := Array.find?_eq_some_iff_getElem.mp facet
    exact Array.any_eq_true.mpr ⟨i, hi, by simpa [he] using hp⟩
  rw [admit_requiredFor h known]
  simp [Registry.computeRequiredFor, selected, facet]

private theorem admit_requiredFor_facet_mem (h : admit input = .ok registry)
    (selected : registry.realization? key = some realization)
    (facet : realization.facets.find? (·.name == name) = some authored) :
    requirement ∈ registry.requiredFor (.facet key name) ↔
      requirement ∈ authored.required ∧
        ∃ record ∈ input.requirements, record.value.key = requirement := by
  rw [admit_requiredFor_facet h selected facet]
  simp only [Array.mem_filterMap, admit_requirement_mem h]
  constructor
  · rintro ⟨req, ⟨record, hr, he⟩, accepted⟩
    split at accepted
    · cases accepted
      exact ⟨by simpa using ‹authored.required.contains req.key = true›, record, hr, by rw [he]⟩
    · contradiction
  · rintro ⟨selectedKey, record, hr, he⟩
    refine ⟨record.value, ⟨record, hr, rfl⟩, ?_⟩
    simp [he, selectedKey]

/-- Deduplication of realization-wide, facet, and declaration requirements
preserves the union of all three authored sources. -/
theorem mem_realization_requirements (realization : Realization) (key : RequirementKey) :
    key ∈ realization.requirements ↔ key ∈ realization.required ∨
      (∃ facet ∈ realization.facets, key ∈ facet.required) ∨
      (∃ declaration ∈ realization.declarations, key ∈ declaration.required) := by
  simp [Realization.requirements]

/-- Completed realizations cannot hide a selected facet or declaration contract
behind another complete contract. This connects admission, source selection,
deduplication, and the actual public completion query. -/
theorem admit_complete_realization_requires (h : admit input = .ok registry)
    (selected : registry.realization? realizationKey = some realization)
    (complete : (registry.resultFor (.realization realizationKey)).complete = true)
    (required : key ∈ realization.required ∨
      (∃ facet ∈ realization.facets, key ∈ facet.required) ∨
      (∃ declaration ∈ realization.declarations, key ∈ declaration.required)) :
    (registry.resultForRequirement key).complete = true := by
  apply (registry.complete_requires_all _ complete).2
  rw [admit_requiredFor_realization h selected]
  exact (mem_realization_requirements realization key).mpr required

private theorem fold_bucket_mem [BEq κ] [LawfulBEq κ] [Hashable κ]
    (key : α → κ) (xs : List α) (initial : Std.HashMap κ (Array α)) (k : κ) (value : α) :
    value ∈ ((xs.foldl (fun out item =>
      out.insert (key item) ((out[key item]?.getD #[]).push item)) initial)[k]?.getD #[]) ↔
      value ∈ (initial[k]?.getD #[]) ∨ (value ∈ xs ∧ key value = k) := by
  induction xs generalizing initial with
  | nil => simp
  | cons x xs ih =>
    simp only [List.foldl_cons, ih, Std.HashMap.getElem?_insert, List.mem_cons]
    by_cases he : key x = k
    · simp [he, Array.mem_push]
      grind
    · simp [he]
      grind

private theorem Registry.evidenceIndex_mem (r : Registry) (hi : r.IndexesMatch)
    (key : RequirementKey) (evidence : Evidence) :
    evidence ∈ ((Registry.evidenceIndex r)[key]?.getD #[]) ↔
      evidence ∈ r.evidence ∧ evidence.requirement = key := by
  rw [hi.evidenceIndex, ← Array.foldl_toList, fold_bucket_mem]
  simp

private theorem Registry.localResult_eq (r : Registry) (hi : r.IndexesMatch)
    (key : RequirementKey) :
    r.localResult key = if key ∈ r.requirements.map (·.key) then Registry.computeLocalResult r key
      else { status := .blocked, diagnostics := #[issue "unknown-requirement" key "Missing requirement"] } := by
  unfold Registry.localResult
  rw [hi.localValues]
  have lookup := array_fold_insert_function (r.requirements.map (·.key))
    (Registry.computeLocalResult r) key
  simp only [Array.foldl_map] at lookup
  rw [lookup]
  split <;> rfl

private theorem Registry.computeLocalResult_complete (r : Registry) (key : RequirementKey)
    (h : (Registry.computeLocalResult r key).complete = true) :
    ∃ requirement, r.requirement? key = some requirement ∧
      ∃ evidence ∈ ((Registry.evidenceIndex r)[key]?.getD #[]),
        evidence.mismatch? requirement ((r.bindingFor key).getD "") = none := by
  cases found : r.requirement? key with
  | none => simp [Registry.computeLocalResult, found, Result.complete] at h
  | some requirement =>
    refine ⟨requirement, rfl, ?_⟩
    apply Classical.byContradiction
    intro noEvidence
    have candidates : (((Registry.evidenceIndex r)[key]?.getD #[]).any
        (fun evidence => (evidence.mismatch? requirement ((r.bindingFor key).getD "")).isNone)) = false := by
      apply Bool.eq_false_iff.mpr
      intro accepted
      obtain ⟨i, hi, hm⟩ := Array.any_eq_true.mp accepted
      apply noEvidence ⟨_, Array.getElem_mem hi, ?_⟩
      simpa using hm
    cases expected : requirement.expected <;>
      simp [Registry.computeLocalResult, found, expected, candidates, Result.complete] at h
    all_goals repeat (first | (solve | simp [Id.run, pure] at h) | split at h)


/-- Cached local completion is backed by an original admitted requirement and
an original evidence record satisfying the exact contract at the current binding.
This does not authenticate the producer or prove prerequisite closure. -/
theorem admit_local_complete_evidence (h : admit input = .ok registry)
    (complete : (registry.localResult key).complete = true) :
    ∃ requirement ∈ input.requirements, ∃ evidence ∈ input.evidence,
      registry.requirement? key = some requirement.value ∧ requirement.value.key = key ∧
      evidence.value.Fits requirement.value ((registry.bindingFor key).getD "") := by
  have hi := admit_indexes h
  rw [registry.localResult_eq hi] at complete
  split at complete
  · obtain ⟨req, found, observation, selected, accepted⟩ :=
      registry.computeLocalResult_complete key complete
    have indexed := found
    rw [Registry.requirement?, hi.requirementIndex] at indexed
    obtain ⟨reqMem, reqKey⟩ := indexBy_lookup _ _ indexed
    obtain ⟨observationMem, _⟩ := (registry.evidenceIndex_mem hi key observation).mp selected
    obtain ⟨requirement, hr, reqEq⟩ := (admit_requirement_mem h req).mp reqMem
    obtain ⟨evidence, he, observationEq⟩ := (admit_evidence_mem h observation).mp observationMem
    refine ⟨requirement, hr, evidence, he, ?_⟩
    rw [reqEq, observationEq]
    exact ⟨found, reqKey, (Evidence.mismatch?_eq_none_iff ..).mp accepted⟩
  · simp [Result.complete] at complete

private theorem eq_of_mem_size_le_one (xs : Array α) (ha : a ∈ xs) (hb : b ∈ xs)
    (small : xs.size ≤ 1) : a = b := by
  obtain ⟨i, hi, he⟩ := Array.mem_iff_getElem.mp ha
  obtain ⟨j, hj, hjEq⟩ := Array.mem_iff_getElem.mp hb
  have hij : i = j := by omega
  subst j
  exact he.symm.trans hjEq

private theorem array_forIn_preserves_mem (xs : Array α) (initial : β)
    (body : α → β → Id (ForInStep β)) (predicate : β → Prop)
    (start : predicate initial)
    (step : ∀ a ∈ xs, ∀ b, predicate b → predicate (body a b).run.value) :
    predicate (forIn xs initial body).run := by
  rw [← Array.forIn_toList]
  have loop (as : List α) (b : β) (hb : predicate b) (subset : ∀ a ∈ as, a ∈ xs) :
      predicate (forIn as b body).run := by
    induction as generalizing b with
    | nil => exact hb
    | cons a as ih =>
      have next := step a (subset a (by simp)) b hb
      simp only [List.forIn_cons, bind, Id.run, pure]
      cases h : body a b with
      | done result => simpa [h, Id.run, ForInStep.value] using next
      | yield result =>
        apply ih result (by simpa [h, Id.run, ForInStep.value] using next)
        intro a ha
        exact subset a (by simp [ha])
  exact loop xs.toList initial start (by simp)

private theorem hashSet_fold_mem [BEq α] [LawfulBEq α] [Hashable α]
    (values : Array α) (value : α) :
    value ∈ values.foldl (fun out x => out.insert x) ({} : Std.HashSet α) ↔ value ∈ values := by
  rw [← Array.foldl_toList]
  have loop (xs : List α) (initial : Std.HashSet α) :
      value ∈ xs.foldl (fun out x => out.insert x) initial ↔ value ∈ initial ∨ value ∈ xs := by
    induction xs generalizing initial with
    | nil => simp
    | cons x xs ih =>
      simp only [List.foldl_cons, ih, Std.HashSet.mem_insert, beq_iff_eq, List.mem_cons]
      grind
  simpa using loop values.toList {}

/-- Direct requirement dependency, using the same admitted lookup as the
production closure evaluator. The dependency is the first relation argument. -/
def Registry.Prerequisite (r : Registry) (dependency key : RequirementKey) : Prop :=
  ∃ requirement, r.requirement? key = some requirement ∧ dependency ∈ requirement.prerequisites

private def CompleteResultsSatisfy (predicate : RequirementKey → Prop)
    (results : Std.HashMap RequirementKey Result) : Prop :=
  ∀ key value, results[key]? = some value → value.complete = true → predicate key

private theorem completeResultsSatisfy_insert (predicate : RequirementKey → Prop)
    (results : Std.HashMap RequirementKey Result) (safe : CompleteResultsSatisfy predicate results)
    (key : RequirementKey) (value : Result) (backed : value.complete = true → predicate key) :
    CompleteResultsSatisfy predicate (results.insert key value) := by
  intro k v hv hc
  rw [Std.HashMap.getElem?_insert] at hv
  split at hv
  · rename_i he
    have hk : key = k := by simpa using he
    cases hv
    exact hk ▸ backed hc
  · exact safe k v hv hc

private theorem Registry.computeResults_induction (r : Registry) (predicate : RequirementKey → Prop)
    (step : ∀ key, (r.localResult key).complete = true →
      (∀ dependency, r.Prerequisite dependency key → predicate dependency) → predicate key) :
    CompleteResultsSatisfy predicate (Registry.computeResults r) := by
  unfold Registry.computeResults
  simp only [Id.run, bind, pure]
  split
  apply array_forIn_preserves_mem
  · intro key value found
    simp at found
  · intro component _ results safe
    change CompleteResultsSatisfy predicate (forIn (m := Id) component results _)
    apply array_forIn_preserves_mem _ _ _ _ safe
    intro key keyMem results safe
    dsimp only [Id.run]
    generalize cyclicEq : (decide (component.size > 1) || component.any fun key =>
      (r.requirement? key).any (·.prerequisites.contains key)) = cyclic
    cases cyclic
    · simp only [Bool.not_false, Bool.true_and, Bool.false_eq_true, ↓reduceIte]
      split
      · rename_i dependenciesComplete
        apply completeResultsSatisfy_insert _ _ safe
        intro ownComplete
        apply step key
        · unfold Registry.localResult
          cases found : (Registry.localValues r)[key]? <;> simp_all [Result.complete]
        · intro dependency prerequisite
          obtain ⟨requirement, found, needed⟩ := prerequisite
          have small : component.size ≤ 1 := by
            have hs := (Bool.or_eq_false_iff.mp cyclicEq).1
            simpa using hs
          have notSelf : dependency ≠ key := by
            intro same
            have noSelf := Array.any_eq_false'.mp (Bool.or_eq_false_iff.mp cyclicEq).2 key keyMem
            have selfNeeded : key ∈ requirement.prerequisites := same ▸ needed
            simp [found, selfNeeded] at noSelf
          have outside : (component.foldl (fun out k => out.insert k)
              ({} : Std.HashSet RequirementKey)).contains dependency = false := by
            apply Bool.eq_false_iff.mpr
            intro contained
            have member := (hashSet_fold_mem component dependency).mp
              (Std.HashSet.mem_iff_contains.mpr contained)
            exact notSelf (eq_of_mem_size_le_one component member keyMem small)
          have dependencyComplete : (results[dependency]?.getD { status := .blocked }).complete = true := by
            apply Array.all_eq_true'.mp dependenciesComplete
            apply Array.mem_map.mpr
            refine ⟨dependency, ?_, rfl⟩
            simp [found, needed, outside]
          cases cached : results[dependency]? with
          | none => simp [cached, Result.complete] at dependencyComplete
          | some value => exact safe dependency value cached (by simpa [cached] using dependencyComplete)
      · apply completeResultsSatisfy_insert _ _ safe
        simp [Result.complete]
    · simp only [Bool.not_true, Bool.false_and, Bool.false_eq_true, ↓reduceIte, ForInStep.value]
      apply completeResultsSatisfy_insert _ _ safe
      simp [Result.complete]

private theorem Registry.computeResults_apply (r : Registry) (predicate : RequirementKey → Prop)
    (key : RequirementKey) (fallback : Result) (unfinished : fallback.complete = false)
    (complete : ((Registry.computeResults r)[key]?.getD fallback).complete = true)
    (step : ∀ key, (r.localResult key).complete = true →
      (∀ dependency, r.Prerequisite dependency key → predicate dependency) → predicate key) :
    predicate key := by
  cases found : (Registry.computeResults r)[key]? with
  | none => simp [found, unfinished] at complete
  | some result =>
    apply r.computeResults_induction predicate step key result found
    simpa [found] using complete

/-- Rule induction for actual completed results. Each completion is justified by
local success and already justified prerequisites. No SCC correctness assumption
is used: the consumer enforces this rule for any component sequence. -/
theorem admit_complete_induction (h : admit input = .ok registry)
    (complete : (registry.resultForRequirement key).complete = true)
    (predicate : RequirementKey → Prop)
    (step : ∀ key, (registry.localResult key).complete = true →
      (∀ dependency, registry.Prerequisite dependency key → predicate dependency) → predicate key) :
    predicate key := by
  simp only [admit, Id.run, pure, bind] at h
  split at h
  · split at h
    · cases h
      have justified := Registry.computeResults_apply _ predicate key _ rfl complete step
      exact justified
    · contradiction
  · contradiction

/-- Prerequisite evaluation may withhold local success but cannot create it.
This holds independently of the opaque component traversal's correctness. -/
theorem admit_complete_requirement_local (h : admit input = .ok registry)
    (complete : (registry.resultForRequirement key).complete = true) :
    (registry.localResult key).complete = true :=
  admit_complete_induction h complete (fun key => (registry.localResult key).complete = true)
    (fun _ own _ => own)

/-- A completed requirement is justified by original admitted evidence at its
current binding. Dependency completion never substitutes for local evidence. -/
theorem admit_complete_requirement_evidence (h : admit input = .ok registry)
    (complete : (registry.resultForRequirement key).complete = true) :
    ∃ requirement ∈ input.requirements, ∃ evidence ∈ input.evidence,
      registry.requirement? key = some requirement.value ∧ requirement.value.key = key ∧
      evidence.value.Fits requirement.value ((registry.bindingFor key).getD "") :=
  admit_local_complete_evidence h (admit_complete_requirement_local h complete)

/-- Every contract selected by a completed public subject has original fitting
evidence. This is an admission-to-query guarantee, not provider authentication
or a proof that the prerequisite graph was partitioned correctly. -/
theorem admit_complete_selected_evidence (h : admit input = .ok registry)
    (complete : (registry.resultFor subject).complete = true)
    (selected : key ∈ registry.requiredFor subject) :
    ∃ requirement ∈ input.requirements, ∃ evidence ∈ input.evidence,
      registry.requirement? key = some requirement.value ∧ requirement.value.key = key ∧
      evidence.value.Fits requirement.value ((registry.bindingFor key).getD "") :=
  admit_complete_requirement_evidence h ((registry.complete_requires_all _ complete).2 key selected)

/-- Stale records cannot become complete by being reindexed or by having
completed prerequisites. Only evidence for this requirement is constrained. -/
theorem admit_stale_evidence_incomplete (h : admit input = .ok registry)
    (stale : ∀ evidence ∈ input.evidence, evidence.value.requirement = key →
      evidence.value.binding ≠ (registry.bindingFor key).getD "") :
    (registry.resultForRequirement key).complete = false := by
  cases complete : (registry.resultForRequirement key).complete
  · rfl
  · obtain ⟨requirement, _, evidence, he, _, reqKey, fits⟩ :=
      admit_complete_requirement_evidence h complete
    exact False.elim <| stale evidence he (fits.1.trans reqKey) fits.2.2.1

private theorem ite_yield (condition : Prop) [Decidable condition] (a b : α) :
    (if condition then ForInStep.yield a else ForInStep.yield b : Id (ForInStep α)) =
      ForInStep.yield (if condition then a else b) := by
  split <;> rfl

private theorem array_forIn_yield (xs : Array α) (initial : β) (step : α → β → β) :
    forIn (m := Id) xs initial (fun a b => ForInStep.yield (step a b)) =
      xs.foldl (fun b a => step a b) initial := by
  exact Array.forIn_pure_yield_eq_foldl (m := Id) step initial

private theorem list_forIn_yield (xs : List α) (initial : β) (step : α → β → β) :
    forIn (m := Id) xs initial (fun a b => ForInStep.yield (step a b)) =
      xs.foldl (fun b a => step a b) initial := by
  exact List.forIn_pure_yield_eq_foldl (m := Id) step initial

private theorem collect_errors_empty (xs : List α) (fails : α → Prop) [DecidablePred fails] (error : α → β)
    (initial : Array β) :
    xs.foldl (fun out x => if fails x then out.push (error x) else out) initial = #[] ↔
      initial = #[] ∧ ∀ x ∈ xs, ¬fails x := by
  induction xs generalizing initial with
  | nil => simp
  | cons x xs ih =>
    simp only [List.foldl_cons]
    split
    · rename_i failed
      rw [ih]
      simp [failed]
    · rename_i passed
      rw [ih]
      simp [passed]

private theorem familyIssues_coherent [BEq α] [LawfulBEq α] [Ord α]
    [BEq κ] [LawfulBEq κ] [Hashable κ] [ToJson κ]
    (family : String) (key : α → κ) (records : Array (Contribution α))
    (empty : familyIssues family key records = #[])
    (ha : a ∈ records) (hb : b ∈ records) (same : key a.value = key b.value) :
    a.value = b.value := by
  unfold familyIssues at empty
  simp only [Id.run, bind, pure, Std.HashMap.forIn_eq_forIn_toList] at empty
  simp only [ite_yield, array_forIn_yield, list_forIn_yield] at empty
  rw [collect_errors_empty] at empty
  let buckets := records.foldl (fun out record => out.insert (key record.value)
    ((out[key record.value]?.getD #[]).push record)) ({} : Std.HashMap κ (Array (Contribution α)))
  have member (record : Contribution α) (hr : record ∈ records) :
      record ∈ (buckets[key record.value]?.getD #[]) := by
    dsimp only [buckets]
    rw [← Array.foldl_toList, fold_bucket_mem]
    simp [hr]
  have ma := member a ha
  have mb : b ∈ (buckets[key a.value]?.getD #[]) := by rw [same]; exact member b hb
  cases lookup : buckets[key a.value]? with
  | none => simp [lookup] at ma
  | some bucket =>
    have small := empty.2 (key a.value, bucket)
      (Std.HashMap.mem_toList_iff_getElem?_eq_some.mpr lookup)
    have size : (values bucket).size ≤ 1 := by simpa using small
    have va : a.value ∈ values bucket := by
      apply (mem_canonical _ _).mpr
      exact Array.mem_map.mpr ⟨a, by simpa [lookup] using ma, rfl⟩
    have vb : b.value ∈ values bucket := by
      apply (mem_canonical _ _).mpr
      exact Array.mem_map.mpr ⟨b, by simpa [lookup] using mb, rfl⟩
    exact eq_of_mem_size_le_one _ va vb size

private theorem admit_family_checks (h : admit input = .ok registry) :
    familyIssues "requirement" (·.key) input.requirements = #[] ∧
    familyIssues "realization" (·.key) input.realizations = #[] ∧
    familyIssues "translation" (·.key) input.translations = #[] ∧
    familyIssues "claim" (·.key) input.claims = #[] := by
  simp only [admit, Id.run, pure, bind] at h
  split at h
  · rename_i valid
    simp only [Array.isEmpty_iff, Array.append_eq_empty_iff] at valid
    grind only
  · contradiction

/-- Accepted same-key authored requirements agree as complete records. This
comes from the production conflict check, not a caller's uniqueness assumption. -/
theorem admit_requirements_agree (h : admit input = .ok registry)
    (ha : a ∈ input.requirements) (hb : b ∈ input.requirements)
    (same : a.value.key = b.value.key) : a.value = b.value :=
  familyIssues_coherent _ _ _ (admit_family_checks h).1 ha hb same

theorem admit_realizations_agree (h : admit input = .ok registry)
    (ha : a ∈ input.realizations) (hb : b ∈ input.realizations)
    (same : a.value.key = b.value.key) : a.value = b.value :=
  familyIssues_coherent _ _ _ (admit_family_checks h).2.1 ha hb same

theorem admit_translations_agree (h : admit input = .ok registry)
    (ha : a ∈ input.translations) (hb : b ∈ input.translations)
    (same : a.value.key = b.value.key) : a.value = b.value :=
  familyIssues_coherent _ _ _ (admit_family_checks h).2.2.1 ha hb same

theorem admit_claims_agree (h : admit input = .ok registry)
    (ha : a ∈ input.claims) (hb : b ∈ input.claims)
    (same : a.value.key = b.value.key) : a.value = b.value :=
  familyIssues_coherent _ _ _ (admit_family_checks h).2.2.2 ha hb same

private theorem fold_lookup_isSome [BEq κ] [LawfulBEq κ] [Hashable κ]
    (key : α → κ) (xs : List α) (initial : Std.HashMap κ α) (k : κ) :
    ((xs.foldl (fun out value => out.insert (key value) value) initial)[k]?).isSome =
      (initial[k]?.isSome || xs.any (fun value => key value == k)) := by
  induction xs generalizing initial with
  | nil => simp
  | cons x xs ih =>
    simp only [List.foldl_cons, ih, Std.HashMap.getElem?_insert, List.any_cons]
    by_cases he : key x = k
    · simp [he]
    · have hb : (key x == k) = false := by simpa using he
      simp [hb]

private theorem indexBy_lookup_iff [BEq κ] [LawfulBEq κ] [Hashable κ]
    (key : α → κ) (xs : Array α)
    (coherent : ∀ a ∈ xs, ∀ b ∈ xs, key a = key b → a = b) :
    (indexBy key xs)[k]? = some value ↔ value ∈ xs ∧ key value = k := by
  constructor
  · exact indexBy_lookup key xs
  · rintro ⟨member, same⟩
    have present : ((indexBy key xs)[k]?).isSome = true := by
      unfold indexBy
      rw [← Array.foldl_toList, fold_lookup_isSome]
      simp only [Std.HashMap.getElem?_empty, Option.isSome_none, Bool.false_or]
      exact List.any_eq_true.mpr ⟨value, by simpa using member, by simp [same]⟩
    obtain ⟨found, hf⟩ := Option.isSome_iff_exists.mp present
    obtain ⟨hm, hk⟩ := indexBy_lookup key xs hf
    have eq := coherent found hm value member (hk.trans same.symm)
    simpa [eq] using hf

private theorem lookup_values_iff [BEq α] [LawfulBEq α] [Ord α]
    [BEq κ] [LawfulBEq κ] [Hashable κ]
    (key : α → κ) (records : Array (Contribution α))
    (coherent : ∀ a ∈ records, ∀ b ∈ records, key a.value = key b.value → a.value = b.value) :
    (indexBy key (values records))[k]? = some value ↔
      ∃ record ∈ records, record.value = value ∧ key value = k := by
  have members (value : α) : value ∈ values records ↔
      ∃ record ∈ records, record.value = value := by
    unfold values
    rw [mem_canonical]
    exact Array.mem_map
  rw [indexBy_lookup_iff]
  · simp only [members]
    constructor
    · rintro ⟨⟨record, hr, hv⟩, hk⟩
      exact ⟨record, hr, hv, hk⟩
    · rintro ⟨record, hr, hv, hk⟩
      exact ⟨⟨record, hr, hv⟩, hk⟩
  · intro a ha b hb same
    obtain ⟨ra, hra, hva⟩ := (members a).mp ha
    obtain ⟨rb, hrb, hvb⟩ := (members b).mp hb
    have agree := coherent ra hra rb hrb (by simpa [hva, hvb] using same)
    simpa [hva, hvb] using agree

/-- The requirement index contains exactly the original coherent source records. -/
theorem admit_requirement_lookup_iff (h : admit input = .ok registry) :
    registry.requirement? key = some requirement ↔
      ∃ record ∈ input.requirements, record.value = requirement ∧ requirement.key = key := by
  rw [Registry.requirement?, (admit_indexes h).requirementIndex, (admit_sources h).requirements]
  exact lookup_values_iff _ _ (fun _ ha _ hb same => admit_requirements_agree h ha hb same)

theorem admit_realization_lookup_iff (h : admit input = .ok registry) :
    registry.realization? key = some realization ↔
      ∃ record ∈ input.realizations, record.value = realization ∧ realization.key = key := by
  rw [Registry.realization?, (admit_indexes h).realizationIndex, (admit_sources h).realizations]
  exact lookup_values_iff _ _ (fun _ ha _ hb same => admit_realizations_agree h ha hb same)

theorem admit_translation_lookup_iff (h : admit input = .ok registry) :
    registry.translation? key = some translation ↔
      ∃ record ∈ input.translations, record.value = translation ∧ translation.key = key := by
  rw [Registry.translation?, (admit_indexes h).translationIndex, (admit_sources h).translations]
  exact lookup_values_iff _ _ (fun _ ha _ hb same => admit_translations_agree h ha hb same)

theorem admit_claim_lookup_iff (h : admit input = .ok registry) :
    registry.claim? key = some claim ↔
      ∃ record ∈ input.claims, record.value = claim ∧ claim.key = key := by
  rw [Registry.claim?, (admit_indexes h).claimIndex, (admit_sources h).claims]
  exact lookup_values_iff _ _ (fun _ ha _ hb same => admit_claims_agree h ha hb same)

/-- Completion covers every original authored realization record, not merely
whichever record happened to be retained by a last-write index. -/
theorem admit_complete_authored_realization_requires (h : admit input = .ok registry)
    (authored : record ∈ input.realizations)
    (complete : (registry.resultFor (.realization record.value.key)).complete = true)
    (required : key ∈ record.value.required ∨
      (∃ facet ∈ record.value.facets, key ∈ facet.required) ∨
      (∃ declaration ∈ record.value.declarations, key ∈ declaration.required)) :
    (registry.resultForRequirement key).complete = true :=
  admit_complete_realization_requires h
    ((admit_realization_lookup_iff h).mpr ⟨record, authored, rfl, rfl⟩) complete required

private theorem Registry.referenceIssues_requirements (r : Registry)
    (empty : Registry.referenceIssues r = #[])
    (required : key ∈ r.realizations.flatMap (·.requirements) ++
      r.translations.flatMap (·.required) ++ r.claims.flatMap (·.required)) :
    ∃ requirement, r.requirement? key = some requirement := by
  unfold Registry.referenceIssues at empty
  simp only [Id.run, bind, pure] at empty
  simp only [ite_yield, array_forIn_yield] at empty
  rw [← Array.foldl_toList, collect_errors_empty] at empty
  have evidenceEmpty := empty.1
  rw [← Array.foldl_toList, collect_errors_empty] at evidenceEmpty
  have contractsEmpty := evidenceEmpty.1
  rw [← Array.foldl_toList, collect_errors_empty] at contractsEmpty
  have known := contractsEmpty.2 key (by simpa using required)
  cases found : r.requirement? key with
  | none => simp [found] at known
  | some requirement => exact ⟨requirement, rfl⟩

set_option maxHeartbeats 800000 in
private theorem admit_references (h : admit input = .ok registry) :
    Registry.referenceIssues registry = #[] := by
  simp only [admit, Id.run, pure, bind] at h
  split at h
  · rename_i valid
    simp only [Array.isEmpty_iff, Array.append_eq_empty_iff] at valid
    split at h
    · cases h
      exact valid.2
    · contradiction
  · contradiction

/-- Every requirement authored by a collected realization has a real admitted
definition. This includes contracts selected by facets and declarations. -/
theorem admit_realization_requirement_exists (h : admit input = .ok registry)
    (authored : realization ∈ registry.realizations)
    (required : key ∈ realization.requirements) :
    ∃ record ∈ input.requirements, record.value.key = key := by
  have selected : key ∈ registry.realizations.flatMap (·.requirements) ++
      registry.translations.flatMap (·.required) ++ registry.claims.flatMap (·.required) := by
    simp only [Array.mem_append, Array.mem_flatMap]
    exact .inl (.inl ⟨realization, authored, required⟩)
  obtain ⟨requirement, found⟩ := registry.referenceIssues_requirements (admit_references h) selected
  obtain ⟨record, hr, he, hk⟩ := (admit_requirement_lookup_iff h).mp found
  exact ⟨record, hr, he ▸ hk⟩

/-- On admitted input, the facet cache keeps every authored requirement; the
lookup intersection cannot silently erase a missing reference. -/
theorem admit_requiredFor_facet_mem_iff (h : admit input = .ok registry)
    (selected : registry.realization? key = some realization)
    (facet : realization.facets.find? (·.name == name) = some authored) :
    requirement ∈ registry.requiredFor (.facet key name) ↔ requirement ∈ authored.required := by
  rw [admit_requiredFor_facet_mem h selected facet]
  constructor
  · exact And.left
  · intro required
    refine ⟨required, ?_⟩
    obtain ⟨record, hr, he, _⟩ := (admit_realization_lookup_iff h).mp selected
    apply admit_realization_requirement_exists h ((admit_realization_mem h _).mpr ⟨record, hr, he⟩)
    apply (mem_realization_requirements _ _).mpr
    exact .inr (.inl ⟨authored, Array.mem_of_find?_eq_some facet, required⟩)

/-- A completed requirement has a well-founded prerequisite justification;
cyclic or infinitely descending obligations cannot certify completion. -/
theorem admit_complete_accessible (h : admit input = .ok registry)
    (complete : (registry.resultForRequirement key).complete = true) :
    Acc registry.Prerequisite key :=
  admit_complete_induction h complete (Acc registry.Prerequisite)
    (fun key _ dependencies => Acc.intro key dependencies)

/-- Every transitively required obligation has passed its own local validation.
The path is read from actual admitted requirement records. -/
theorem admit_complete_prerequisites_local (h : admit input = .ok registry)
    (complete : (registry.resultForRequirement key).complete = true) :
    ∀ dependency, Relation.TransGen registry.Prerequisite dependency key →
      (registry.localResult dependency).complete = true := by
  have justified := admit_complete_induction h complete (fun key =>
    (registry.localResult key).complete = true ∧
    ∀ dependency, Relation.TransGen registry.Prerequisite dependency key →
      (registry.localResult dependency).complete = true) ?_
  · exact justified.2
  · intro key own dependencies
    refine ⟨own, ?_⟩
    intro dependency path
    cases path with
    | single edge => exact (dependencies dependency edge).1
    | tail path edge => exact (dependencies _ edge).2 _ path

/-- Transitive prerequisite success is backed by original fitting evidence,
including the current binding of each prerequisite, not the root's binding. -/
theorem admit_complete_prerequisites_evidence (h : admit input = .ok registry)
    (complete : (registry.resultForRequirement key).complete = true)
    (path : Relation.TransGen registry.Prerequisite dependency key) :
    ∃ requirement ∈ input.requirements, ∃ evidence ∈ input.evidence,
      registry.requirement? dependency = some requirement.value ∧ requirement.value.key = dependency ∧
      evidence.value.Fits requirement.value ((registry.bindingFor dependency).getD "") :=
  admit_local_complete_evidence h (admit_complete_prerequisites_local h complete dependency path)

private theorem accessible_not_self {relation : α → α → Prop} (accessible : Acc relation key) :
    ¬relation key key := by
  induction accessible with
  | intro key _ ih =>
    intro self
    exact ih key self self

/-- Even if every cycle member has individually suitable evidence, circular
prerequisite justification cannot produce a completed cached result. -/
theorem admit_cycle_incomplete (h : admit input = .ok registry)
    (cycle : Relation.TransGen registry.Prerequisite key key) :
    (registry.resultForRequirement key).complete = false := by
  cases complete : (registry.resultForRequirement key).complete
  · rfl
  · exact False.elim <| accessible_not_self (admit_complete_accessible h complete).transGen cycle

/-- A reachable cycle blocks certification of its consumers as well as its own
members, even when those consumers have suitable local observations. -/
theorem admit_reachable_cycle_incomplete (h : admit input = .ok registry)
    (path : Relation.TransGen registry.Prerequisite dependency key)
    (cycle : Relation.TransGen registry.Prerequisite dependency dependency) :
    (registry.resultForRequirement key).complete = false := by
  cases complete : (registry.resultForRequirement key).complete
  · rfl
  · have reachable := (admit_complete_accessible h complete).inv_of_transGen path
    exact False.elim <| accessible_not_self reachable.transGen cycle

/-- The source-facing contract combines original authoring, required-index
preservation, completed closure, and fitting original evidence. -/
theorem admit_complete_authored_realization_evidence (h : admit input = .ok registry)
    (authored : record ∈ input.realizations)
    (complete : (registry.resultFor (.realization record.value.key)).complete = true)
    (required : key ∈ record.value.required ∨
      (∃ facet ∈ record.value.facets, key ∈ facet.required) ∨
      (∃ declaration ∈ record.value.declarations, key ∈ declaration.required)) :
    ∃ requirement ∈ input.requirements, ∃ evidence ∈ input.evidence,
      registry.requirement? key = some requirement.value ∧ requirement.value.key = key ∧
      evidence.value.Fits requirement.value ((registry.bindingFor key).getD "") :=
  admit_complete_requirement_evidence h
    (admit_complete_authored_realization_requires h authored complete required)

set_option maxHeartbeats 1000000 in
/-- Evidence is checked against a binding, never included in its own binding.
Replacing only evidence cannot change any binding when both complete inputs are
admitted. This is exact string equality, not a cryptographic assumption. -/
theorem admit_bindings_evidence (before : admit input = .ok first)
    (after : admit { input with evidence } = .ok second) (key : RequirementKey) :
    first.bindingFor key = second.bindingFor key := by
  simp only [admit, Id.run, pure, bind] at before after
  split at before
  · split at before
    · rename_i bindingsBefore boundBefore
      cases before
      split at after
      · split at after
        · rename_i bindingsAfter boundAfter
          cases after
          have same := boundBefore.symm.trans boundAfter
          cases same
          rfl
        · contradiction
      · contradiction
    · contradiction
  · contradiction

private theorem Registry.computeLocalResult_proof_sources (r : Registry)
    (found : r.requirement? key = some requirement)
    (expected : requirement.expected = .proof goal witness)
    (complete : (Registry.computeLocalResult r key).complete = true) :
    Registry.objectIssues r witness = #[] ∧
      ∃ semantic ∈ r.bindingInputs, semantic.subject = key.subject ∧
        semantic.name = NativeLean.expectedContextFor key := by
  have available : (Registry.objectIssues r witness).isEmpty = true := by
    apply Classical.byContradiction
    intro unavailable
    simp only [Array.isEmpty_iff] at unavailable
    simp [Registry.computeLocalResult, found, expected, unavailable, Result.complete] at complete
  have empty := Array.isEmpty_iff.mp available
  refine ⟨empty, ?_⟩
  apply Classical.byContradiction
  intro absent
  have noSemantic : (r.bindingInputs.any (fun input => input.subject == key.subject &&
      input.name == NativeLean.expectedContextFor key)) = false := by
    apply Bool.eq_false_iff.mpr
    intro present
    apply absent
    simpa only [Array.any_eq_true', Bool.and_eq_true, beq_iff_eq] using present
  simp [Registry.computeLocalResult, found, expected, empty, noSemantic, Result.complete] at complete
  all_goals repeat (first | (solve | simp [Id.run, pure] at complete) | split at complete)

private theorem admit_object_sources (admitted : admit input = .ok registry)
    (available : Registry.objectIssues registry key = #[]) :
    ∃ object ∈ input.objects, object.value.key = key ∧ object.value.resolution = .resolved ∧
      ∃ document ∈ input.documents, object.value.document = some document.value.key ∧
        blank document.value.text = false := by
  cases objectFound : (Registry.objectIndex registry)[key]? with
  | none => simp [Registry.objectIssues, objectFound] at available
  | some object =>
    by_cases resolved : object.resolution = .resolved
    · cases documentKey : object.document with
      | none => simp [Registry.objectIssues, objectFound, resolved, documentKey] at available
      | some document =>
        cases documentFound : (Registry.documentIndex registry)[document]? with
        | none => simp [Registry.objectIssues, objectFound, resolved, documentKey,
            Registry.documentIssues, documentFound] at available
        | some source =>
          have content : blank source.text = false := by
            simpa [Registry.objectIssues, objectFound, resolved, documentKey,
              Registry.documentIssues, documentFound] using available
          have objectLookup := objectFound
          rw [(admit_indexes admitted).objectIndex] at objectLookup
          obtain ⟨objectMember, objectKey⟩ := indexBy_lookup _ _ objectLookup
          have documentLookup := documentFound
          rw [(admit_indexes admitted).documentIndex] at documentLookup
          obtain ⟨documentMember, sourceKey⟩ := indexBy_lookup _ _ documentLookup
          obtain ⟨originalObject, ho, rfl⟩ := (admit_object_mem admitted object).mp objectMember
          obtain ⟨originalDocument, hd, rfl⟩ := (admit_document_mem admitted source).mp documentMember
          exact ⟨originalObject, ho, objectKey, resolved, originalDocument, hd,
            by simpa [sourceKey] using documentKey, content⟩
    · simp [Registry.objectIssues, objectFound, resolved] at available

/-- Independent proof completion requires an original resolved witness with
nonblank canonical source, and the selected expected-goal semantic input.
These are supplied source/provider records, not authenticated filesystem facts. -/
theorem admit_complete_proof_sources (admitted : admit input = .ok registry)
    (found : registry.requirement? key = some requirement)
    (expected : requirement.expected = .proof goal witness)
    (complete : (registry.resultForRequirement key).complete = true) :
    (∃ object ∈ input.objects, object.value.key = witness ∧ object.value.resolution = .resolved ∧
      ∃ document ∈ input.documents, object.value.document = some document.value.key ∧
        blank document.value.text = false) ∧
    ∃ semantic ∈ input.bindingInputs, semantic.value.subject = key.subject ∧
      semantic.value.name = NativeLean.expectedContextFor key := by
  have localComplete := admit_complete_requirement_local admitted complete
  rw [registry.localResult_eq (admit_indexes admitted)] at localComplete
  split at localComplete
  · obtain ⟨source, semantic, member, subject, name⟩ :=
      registry.computeLocalResult_proof_sources found expected localComplete
    obtain ⟨original, originalMember, rfl⟩ := (admit_bindingInput_mem admitted semantic).mp member
    exact ⟨admit_object_sources admitted source, original, originalMember, subject, name⟩
  · simp [Result.complete] at localComplete

end Informal.Translations
