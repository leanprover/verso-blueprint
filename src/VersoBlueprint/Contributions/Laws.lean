/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Contributions

open Lean Informal.Data
namespace Informal.Contributions

/-- The legacy payload projection preserves both selected semantic fields. -/
theorem Record.toNodeContribution_priority (r : Record) :
    r.toNodeContribution.priority = r.priority := rfl

theorem Record.toNodeContribution_leanCode (r : Record) :
    r.toNodeContribution.leanCode = #[.external r.references] := rfl

structure CollectorLaws (c : Collector σ) : Prop where
  empty_exact : ∀ r, r ∉ c.records c.empty
  insert_exact : ∀ s r x, x ∈ c.records (c.insert r s) ↔ x = r ∨ x ∈ c.records s
  collection_exact : ∀ rs r, r ∈ c.records (c.collect rs) ↔ r ∈ rs
  permutation : ∀ s rs ts, List.Perm rs ts →
    EvidenceEq (c.records (c.extend s rs)) (c.records (c.extend s ts))
  batching : ∀ s bs,
    EvidenceEq (c.records (c.batches s bs)) (c.records (c.extend s bs.flatten))
  replay : ∀ s r,
    EvidenceEq (c.records (c.insert r (c.insert r s))) (c.records (c.insert r s))
  collision_exact : ∀ rs id, Collision (c.records (c.collect rs)) id ↔ Collision rs id

structure ResolverLaws (resolve : Resolver) : Prop where
  success_iff : ∀ label rs,
    (∃ v, resolve label rs = .ok v) ↔ NoCollision rs label ∧ ¬ PriorityDisagreement rs label
  association_exact : ∀ label rs v, resolve label rs = .ok v →
    ∀ d, d ∈ v.declarations ↔ Association rs label d
  supports_exact : ∀ label rs v, resolve label rs = .ok v →
    ∀ r, r ∈ v.supports ↔ r ∈ rs ∧ r.label = label
  priority_none_iff : ∀ label rs v, resolve label rs = .ok v →
    (v.priority = none ↔ ∀ value, ¬ Priority rs label value)
  priority_some_iff : ∀ label rs v, resolve label rs = .ok v →
    ∀ value, v.priority = some value ↔
      Priority rs label value ∧ ∀ other, Priority rs label other → other = value
  collision_group_exact : ∀ label rs d, resolve label rs = .error d →
    ∀ id, d.hasCollision id ↔ RelevantCollision rs label id
  collision_support_exact : ∀ label rs d, resolve label rs = .error d →
    ∀ id r, d.collisionSupport id r ↔ RelevantCollision rs label id ∧ r ∈ rs ∧ r.id = id
  priority_group_exact : ∀ label rs d, resolve label rs = .error d →
    ∀ value, d.hasPriority value ↔ PriorityDisagreement rs label ∧ Priority rs label value
  priority_support_exact : ∀ label rs d, resolve label rs = .error d →
    ∀ value r, d.prioritySupport value r ↔
      PriorityDisagreement rs label ∧ r ∈ rs ∧ r.label = label ∧ r.priority = some value
  congruence : ∀ label rs ts, EvidenceEq rs ts → OutcomeEq (resolve label rs) (resolve label ts)


@[simp] theorem mem_insert (s : List Record) (r x : Record) :
    x ∈ insert r s ↔ x = r ∨ x ∈ s := by
  unfold insert
  split
  · rename_i h
    constructor
    · exact Or.inr
    · rintro (rfl | hx)
      · exact h
      · exact hx
  · simp

@[simp] theorem mem_extend (s rs : List Record) (x : Record) :
    x ∈ collector.extend s rs ↔ x ∈ s ∨ x ∈ rs := by
  induction rs generalizing s with
  | nil => simp [Collector.extend, collector]
  | cons r rs ih =>
    change x ∈ collector.extend (insert r s) rs ↔ _
    rw [ih, mem_insert]
    simp only [List.mem_cons]
    simp [or_assoc, or_left_comm, or_comm]

@[simp] theorem mem_collect (rs : List Record) (r : Record) :
    r ∈ collector.collect rs ↔ r ∈ rs := by
  change r ∈ collector.extend [] rs ↔ _
  simp

theorem collision_congr {rs ts : List Record} (h : EvidenceEq rs ts) (id : ContributionId) :
    Collision rs id ↔ Collision ts id := by
  change ∀ r, r ∈ rs ↔ r ∈ ts at h
  simp only [Collision, h]

theorem batches_eq (s : List Record) (bs : List (List Record)) :
    collector.batches s bs = collector.extend s bs.flatten := by
  induction bs generalizing s with
  | nil => rfl
  | cons b bs ih =>
    change collector.batches (collector.extend s b) bs = _
    rw [ih]
    simp [Collector.extend, List.foldl_append]

/-- Collection preserves full evidence for every input, including collisions. -/
theorem collectorLaws : CollectorLaws collector where
  empty_exact := by simp [collector]
  insert_exact := mem_insert
  collection_exact := mem_collect
  permutation := by
    intro s rs ts h x
    change x ∈ collector.extend s rs ↔ x ∈ collector.extend s ts
    simp only [mem_extend, h.mem_iff]
  batching := by
    intro s bs
    rw [batches_eq]
    intro r
    rfl
  replay := by
    intro s r x
    simp [collector]
  collision_exact := by
    intro rs id
    exact collision_congr (mem_collect rs) id

@[simp] theorem mem_recordsFor (label : Label) (rs : List Record) (r : Record) :
    r ∈ recordsFor label rs ↔ r ∈ rs ∧ r.label = label := by
  simp [recordsFor]

@[simp] theorem mem_variants (rs : List Record) (id : ContributionId) (r : Record) :
    r ∈ variants rs id ↔ r ∈ rs ∧ r.id = id := by
  simp [variants]

@[simp] theorem mem_priorityValues (label : Label) (rs : List Record) (v : String) :
    v ∈ priorityValues label rs ↔ Priority rs label v := by
  simp [priorityValues, Priority, and_assoc]

@[simp] theorem priorityDisagrees_eq (label : Label) (rs : List Record) :
    priorityDisagrees label rs = true ↔ PriorityDisagreement rs label := by
  simp only [priorityDisagrees, List.any_eq_true, decide_eq_true_eq, mem_priorityValues,
    PriorityDisagreement]
  constructor
  · rintro ⟨a, ha, b, hb, hab⟩
    exact ⟨a, b, ha, hb, hab⟩
  · rintro ⟨a, b, ha, hb, hab⟩
    exact ⟨a, ha, b, hb, hab⟩

@[simp] theorem mem_collisionIds (label : Label) (rs : List Record) (id : ContributionId) :
    id ∈ collisionIds label rs ↔ RelevantCollision rs label id := by
  simp only [collisionIds, List.mem_filter, List.mem_eraseDups, List.mem_map,
    decide_eq_true_eq]
  constructor
  · exact And.right
  · intro h
    obtain ⟨r, hr, hid, _⟩ := h.2
    exact ⟨⟨r, hr, hid⟩, h⟩

@[simp] theorem view_declarations (label : Label) (rs : List Record) (d : Name) :
    d ∈ (view label rs).declarations ↔ Association rs label d := by
  simp [view, Association, and_assoc]

private theorem has_bucket {α β : Type} (keys : List α) (f : α → List β) (key : α) :
    (∃ bucket, (key, bucket) ∈ keys.map (fun k => (k, f k))) ↔ key ∈ keys := by
  constructor
  · rintro ⟨bucket, h⟩
    obtain ⟨k, hk, he⟩ := List.mem_map.mp h
    have eq : k = key := congrArg Prod.fst he
    simpa [eq] using hk
  · intro h
    exact ⟨f key, List.mem_map.mpr ⟨key, h, rfl⟩⟩

private theorem bucket_support {α β : Type} (keys : List α) (f : α → List β)
    (key : α) (r : β) :
    (∃ bucket, (key, bucket) ∈ keys.map (fun k => (k, f k)) ∧ r ∈ bucket) ↔
      key ∈ keys ∧ r ∈ f key := by
  constructor
  · rintro ⟨bucket, h, hr⟩
    obtain ⟨k, hk, he⟩ := List.mem_map.mp h
    obtain ⟨rfl, rfl⟩ := Prod.mk.inj he
    exact ⟨hk, hr⟩
  · rintro ⟨hk, hr⟩
    exact ⟨f key, List.mem_map.mpr ⟨key, hk, rfl⟩, hr⟩

@[simp] theorem diagnostics_collision (label : Label) (rs : List Record) (id : ContributionId) :
    (diagnostics label rs).hasCollision id ↔ RelevantCollision rs label id := by
  simp only [diagnostics, Diagnostics.hasCollision, has_bucket, mem_collisionIds]

@[simp] theorem diagnostics_collision_support (label : Label) (rs : List Record)
    (id : ContributionId) (r : Record) :
    (diagnostics label rs).collisionSupport id r ↔
      RelevantCollision rs label id ∧ r ∈ rs ∧ r.id = id := by
  simp only [diagnostics, Diagnostics.collisionSupport, bucket_support, mem_collisionIds, mem_variants]

@[simp] theorem diagnostics_priority (label : Label) (rs : List Record) (v : String) :
    (diagnostics label rs).hasPriority v ↔ PriorityDisagreement rs label ∧ Priority rs label v := by
  by_cases h : priorityDisagrees label rs = true
  · simp only [diagnostics, h, ↓reduceIte, Diagnostics.hasPriority, has_bucket,
      mem_priorityValues, (priorityDisagrees_eq label rs).mp h, true_and]
  · simp [diagnostics, Diagnostics.hasPriority, h, mt (priorityDisagrees_eq label rs).mpr h]

@[simp] theorem diagnostics_priority_support (label : Label) (rs : List Record)
    (v : String) (r : Record) :
    (diagnostics label rs).prioritySupport v r ↔
      PriorityDisagreement rs label ∧ r ∈ rs ∧ r.label = label ∧ r.priority = some v := by
  by_cases h : priorityDisagrees label rs = true
  · have hd := (priorityDisagrees_eq label rs).mp h
    simp only [diagnostics, h, ↓reduceIte, Diagnostics.prioritySupport, List.mem_map]
    constructor
    · rintro ⟨bucket, ⟨v', hv', heq⟩, hr⟩
      cases heq
      simpa [and_assoc] using And.intro hd hr
    · rintro ⟨_, hr, hl, hp⟩
      refine ⟨_, ⟨v, ?_, rfl⟩, ?_⟩
      · exact (mem_priorityValues label rs v).mpr ⟨r, hr, hl, hp⟩
      · simp [hr, hl, hp]
  · simp [diagnostics, Diagnostics.prioritySupport, h, mt (priorityDisagrees_eq label rs).mpr h]

@[simp] theorem collisions_empty (label : Label) (rs : List Record) :
    (collisionIds label rs).isEmpty = true ↔ NoCollision rs label := by
  simp [List.isEmpty_iff, List.eq_nil_iff_forall_not_mem, NoCollision]

@[simp] theorem acceptance (label : Label) (rs : List Record) :
    ((collisionIds label rs).isEmpty && !priorityDisagrees label rs) = true ↔
      NoCollision rs label ∧ ¬ PriorityDisagreement rs label := by
  rw [Bool.and_eq_true, collisions_empty]
  apply and_congr Iff.rfl
  rw [← priorityDisagrees_eq]
  cases priorityDisagrees label rs <;> decide

theorem resolve_success (label : Label) (rs : List Record) :
    (∃ v, resolve label rs = .ok v) ↔ NoCollision rs label ∧ ¬ PriorityDisagreement rs label := by
  rw [← acceptance label rs]
  unfold resolve
  split <;> simp_all

theorem resolve_ok {label : Label} {rs : List Record} {v : View}
    (h : resolve label rs = .ok v) : v = view label rs := by
  unfold resolve at h
  split at h
  · exact (Except.ok.inj h).symm
  · cases h

theorem resolve_error {label : Label} {rs : List Record} {d : Diagnostics}
    (h : resolve label rs = .error d) : d = diagnostics label rs := by
  unfold resolve at h
  split at h
  · cases h
  · exact (Except.error.inj h).symm

theorem view_priority_none (label : Label) (rs : List Record) :
    (view label rs).priority = none ↔ ∀ value, ¬ Priority rs label value := by
  simp [view, List.head?_eq_none_iff, List.eq_nil_iff_forall_not_mem]

theorem view_priority_some (label : Label) (rs : List Record)
    (h : ¬ PriorityDisagreement rs label) (value : String) :
    (view label rs).priority = some value ↔
      Priority rs label value ∧ ∀ other, Priority rs label other → other = value := by
  change (priorityValues label rs).head? = some value ↔ _
  cases he : priorityValues label rs with
  | nil =>
    have hp : ∀ v, ¬ Priority rs label v := by
      intro v hv
      have := (mem_priorityValues label rs v).mpr hv
      simp [he] at this
    simp [hp]
  | cons first rest =>
    have hf : Priority rs label first := (mem_priorityValues label rs first).mp (by simp [he])
    have allEq : ∀ v, Priority rs label v → v = first := by
      intro v hv
      by_cases heq : v = first
      · exact heq
      · exact False.elim (h ⟨v, first, hv, hf, heq⟩)
    simp only [List.head?_cons, Option.some.injEq]
    constructor
    · rintro rfl
      exact ⟨hf, allEq⟩
    · rintro ⟨hv, _⟩
      exact (allEq value hv).symm

theorem relevantCollision_congr {rs ts : List Record} (h : EvidenceEq rs ts)
    (label : Label) (id : ContributionId) :
    RelevantCollision rs label id ↔ RelevantCollision ts label id := by
  have hm : ∀ r, r ∈ rs ↔ r ∈ ts := h
  simp only [RelevantCollision, collision_congr h, hm]

theorem noCollision_congr {rs ts : List Record} (h : EvidenceEq rs ts) (label : Label) :
    NoCollision rs label ↔ NoCollision ts label := by
  simp only [NoCollision, relevantCollision_congr h]

theorem priority_congr {rs ts : List Record} (h : EvidenceEq rs ts) (label : Label) (v : String) :
    Priority rs label v ↔ Priority ts label v := by
  have hm : ∀ r, r ∈ rs ↔ r ∈ ts := h
  simp only [Priority, hm]

theorem disagreement_congr {rs ts : List Record} (h : EvidenceEq rs ts) (label : Label) :
    PriorityDisagreement rs label ↔ PriorityDisagreement ts label := by
  simp only [PriorityDisagreement, priority_congr h]

theorem association_congr {rs ts : List Record} (h : EvidenceEq rs ts)
    (label : Label) (decl : Name) : Association rs label decl ↔ Association ts label decl := by
  have hm : ∀ r, r ∈ rs ↔ r ∈ ts := h
  simp only [Association, hm]

theorem diagnostics_congr {rs ts : List Record} (h : EvidenceEq rs ts) (label : Label) :
    (diagnostics label rs).Equivalent (diagnostics label ts) := by
  have hm : ∀ r, r ∈ rs ↔ r ∈ ts := h
  constructor
  · intro id
    simp only [diagnostics_collision, relevantCollision_congr h]
  constructor
  · intro id r
    simp only [diagnostics_collision_support, relevantCollision_congr h, hm]
  constructor
  · intro v
    simp only [diagnostics_priority, disagreement_congr h, priority_congr h]
  · intro v r
    simp only [diagnostics_priority_support, disagreement_congr h, hm]

theorem view_congr {rs ts : List Record} (h : EvidenceEq rs ts) (label : Label)
    (hd : ¬ PriorityDisagreement rs label) : (view label rs).Equivalent (view label ts) := by
  have ht : ¬ PriorityDisagreement ts label := mt (disagreement_congr h label).mpr hd
  constructor
  · intro d
    simp only [view_declarations, association_congr h]
  constructor
  · cases hv : (view label rs).priority with
    | none =>
      have hp := (view_priority_none label rs).mp hv
      symm
      apply (view_priority_none label ts).mpr
      intro value hv'
      exact hp value ((priority_congr h label value).mpr hv')
    | some value =>
      have hp := (view_priority_some label rs hd value).mp hv
      symm
      apply (view_priority_some label ts ht value).mpr
      refine ⟨(priority_congr h label value).mp hp.1, ?_⟩
      intro other ho
      exact hp.2 other ((priority_congr h label other).mpr ho)
  · intro r
    simp only [view, mem_recordsFor, h r]

theorem resolve_valid {label : Label} {rs : List Record}
    (h : NoCollision rs label ∧ ¬ PriorityDisagreement rs label) :
    resolve label rs = .ok (view label rs) := by
  unfold resolve
  simp only [if_pos ((acceptance label rs).mpr h)]

theorem resolve_invalid {label : Label} {rs : List Record}
    (h : ¬ (NoCollision rs label ∧ ¬ PriorityDisagreement rs label)) :
    resolve label rs = .error (diagnostics label rs) := by
  unfold resolve
  simp only [if_neg (mt (acceptance label rs).mp h)]

/-- Equivalent complete evidence gives equivalent success or complete diagnostics. -/
theorem resolve_congr (label : Label) {rs ts : List Record} (h : EvidenceEq rs ts) :
    OutcomeEq (resolve label rs) (resolve label ts) := by
  have hv : (NoCollision rs label ∧ ¬ PriorityDisagreement rs label) ↔
      (NoCollision ts label ∧ ¬ PriorityDisagreement ts label) :=
    and_congr (noCollision_congr h label) (not_congr (disagreement_congr h label))
  by_cases accepted : ((collisionIds label rs).isEmpty && !priorityDisagrees label rs) = true
  · have good := (acceptance label rs).mp accepted
    rw [resolve_valid good, resolve_valid (hv.mp good)]
    exact view_congr h label good.2
  · have bad := mt (acceptance label rs).mpr accepted
    rw [resolve_invalid bad, resolve_invalid (mt hv.mpr bad)]
    exact diagnostics_congr h label

/-- Exactness on both accepted and rejected inputs; no collision-free assumption. -/
theorem resolverLaws : ResolverLaws resolve where
  success_iff := resolve_success
  association_exact := by
    intro label rs v h d
    rw [resolve_ok h]
    exact view_declarations label rs d
  supports_exact := by
    intro label rs v h r
    rw [resolve_ok h]
    exact mem_recordsFor label rs r
  priority_none_iff := by
    intro label rs v h
    rw [resolve_ok h]
    exact view_priority_none label rs
  priority_some_iff := by
    intro label rs v h value
    rw [resolve_ok h]
    exact view_priority_some label rs ((resolve_success label rs).mp ⟨v, h⟩).2 value
  collision_group_exact := by
    intro label rs d h id
    rw [resolve_error h]
    exact diagnostics_collision label rs id
  collision_support_exact := by
    intro label rs d h id r
    rw [resolve_error h]
    exact diagnostics_collision_support label rs id r
  priority_group_exact := by
    intro label rs d h value
    rw [resolve_error h]
    exact diagnostics_priority label rs value
  priority_support_exact := by
    intro label rs d h value r
    rw [resolve_error h]
    exact diagnostics_priority_support label rs value r
  congruence := fun label _ _ h => resolve_congr label h

/-- The resolver observes the same facts before and after replay deduplication. -/
theorem resolve_collect (label : Label) (rs : List Record) :
    OutcomeEq (resolve label (collector.collect rs)) (resolve label rs) :=
  resolve_congr label (mem_collect rs)

/-- Independent bodyless fact records compose without shared module ancestry.
All supported declarations and both complete provenance records survive. -/
theorem independentAssociations (a b : Record) (label : Label)
    (hid : a.id ≠ b.id) (ha : a.label = label) (hb : b.label = label)
    (pa : a.priority = none) (pb : b.priority = none)
    (rs : List Record) (hp : List.Perm rs [a, b]) :
    ∃ v, resolve label rs = .ok v ∧
      (∀ d, d ∈ v.declarations ↔ Association [a, b] label d) ∧
      v.priority = none ∧ EvidenceEq v.supports [a, b] := by
  have he : EvidenceEq rs [a, b] := fun _ => hp.mem_iff
  have nc : NoCollision [a, b] label := by
    intro id h
    obtain ⟨x, hx, y, hy, hxi, hyi, hne⟩ := h.1
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hx hy
    rcases hx with rfl | rfl <;> rcases hy with rfl | rfl
    · exact hne rfl
    · exact hid (hxi.trans hyi.symm)
    · exact hid (hyi.trans hxi.symm)
    · exact hne rfl
  have np : ∀ value, ¬ Priority [a, b] label value := by
    simp [Priority, pa, pb]
  have nd : ¬ PriorityDisagreement [a, b] label := by
    rintro ⟨x, y, hx, _, _⟩
    exact np x hx
  have valid : NoCollision rs label ∧ ¬ PriorityDisagreement rs label :=
    ⟨(noCollision_congr he label).mpr nc, mt (disagreement_congr he label).mp nd⟩
  refine ⟨view label rs, resolve_valid valid, ?_, ?_, ?_⟩
  · intro d
    exact (view_declarations label rs d).trans (association_congr he label d)
  · apply (view_priority_none label rs).mpr
    intro value hv
    exact np value ((priority_congr he label value).mp hv)
  · intro r
    simp only [view, mem_recordsFor, hp.mem_iff, List.mem_cons, List.not_mem_nil, or_false]
    constructor
    · exact And.left
    · intro hr
      refine ⟨hr, ?_⟩
      rcases hr with rfl | rfl
      · exact ha
      · exact hb

end Informal.Contributions
