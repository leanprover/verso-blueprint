/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Data
import Std.Data.TreeMap.Lemmas

/-! Canonical-name and presence laws for the production snapshot merge. -/

namespace Informal.Data.ExternalRef

open Lean Std
attribute [local instance] lexOrd

-- The production index uses Name.quickCmp. Its comparison laws are local to the
-- proofs; production does not import this module.
private def nameParts : Name → List (Bool × (Nat × String))
  | .anonymous => []
  | .num p n => (false, n, "") :: nameParts p
  | .str p s => (true, 0, s) :: nameParts p

private theorem quickCmpAux_eq (a b : Name) :
    a.quickCmpAux b = compare (nameParts a) (nameParts b) := by
  induction a generalizing b with
  | anonymous => cases b <;> rfl
  | num a n ih =>
    cases b with
    | anonymous => rfl
    | str b s => rfl
    | num b m =>
      simp only [Name.quickCmpAux, nameParts, List.compare_cons_cons, ← ih]
      change (match compare n m with | .eq => _ | ord => ord) =
        (Ordering.eq.then ((compare n m).then Ordering.eq)).then _
      cases compare n m <;> rfl
  | str a s ih =>
    cases b with
    | anonymous => rfl
    | num b n => rfl
    | str b t =>
      simp only [Name.quickCmpAux, nameParts, List.compare_cons_cons, ← ih]
      change (match compare s t with | .eq => _ | ord => ord) =
        (Ordering.eq.then (Ordering.eq.then (compare s t))).then _
      cases compare s t <;> rfl

private theorem nameParts_injective {a b : Name} (h : nameParts a = nameParts b) : a = b := by
  induction a generalizing b with
  | anonymous => cases b <;> simp_all [nameParts]
  | num a n ih =>
    cases b with
    | anonymous => simp [nameParts] at h
    | str b s => simp [nameParts] at h
    | num b m =>
      simp only [nameParts, List.cons.injEq, Prod.mk.injEq, true_and] at h
      have hp := ih h.2
      cases hp
      cases h.1.1
      rfl
  | str a s ih =>
    cases b with
    | anonymous => simp [nameParts] at h
    | num b n => simp [nameParts] at h
    | str b t =>
      simp only [nameParts, List.cons.injEq, Prod.mk.injEq, true_and] at h
      have hp := ih h.2
      cases hp
      cases h.1
      rfl

private theorem quickCmp_eq :
    Name.quickCmp = compareLex (compareOn Name.hash) (compareOn nameParts) := by
  funext a b
  simp only [Name.quickCmp, compareLex, compareOn, ← quickCmpAux_eq]
  cases compare a.hash b.hash <;> rfl

local instance : TransCmp Name.quickCmp := by
  rw [quickCmp_eq]
  infer_instance

local instance : LawfulEqCmp Name.quickCmp where
  eq_of_compare := by
    intro a b h
    rw [quickCmp_eq, compareLex_eq_eq] at h
    exact nameParts_injective (LawfulEqOrd.eq_of_compare h.2)

private theorem positions_empty (name : Name) :
    ({} : NameMap Nat).get? name = none := by
  exact TreeMap.getElem?_emptyc

private theorem positions_insert (positions : NameMap Nat) (key name : Name) (i : Nat) :
    (positions.insert key i).get? name = if key = name then some i else positions.get? name := by
  unfold NameMap at positions
  change ((positions : TreeMap Name Nat Name.quickCmp).insert key i)[name]? = _
  rw [TreeMap.getElem?_insert]
  simp only [LawfulEqCmp.compare_eq_iff_eq, TreeMap.get?_eq_getElem?]

private def combine (previous ref : ExternalRef) : ExternalRef :=
  let selected := if !previous.present && ref.present then ref else previous
  { selected with
    provedStatus := ProvedStatus.mergeConservative previous.provedStatus ref.provedStatus }

private theorem combine_canonical (previous ref : ExternalRef)
    (h : previous.canonical = ref.canonical) :
    (combine previous ref).canonical = previous.canonical := by
  unfold combine
  split <;> simp_all only

private theorem combine_present (previous ref : ExternalRef) :
    (combine previous ref).present = (previous.present || ref.present) := by
  cases hp : previous.present <;> cases hr : ref.present <;> simp [combine, hp, hr]

-- A proof-only presentation of the production loop body. The equality below
-- checks this presentation against mergeSnapshots rather than assuming it.
private def snapshotStep (state : NameMap Nat × Array ExternalRef) (ref : ExternalRef) :
    NameMap Nat × Array ExternalRef :=
  let ref := { ref with canonical := ref.canonical.eraseMacroScopes }
  match state.1.get? ref.canonical with
  | some i =>
    (state.1, state.2.set! i (combine state.2[i]! ref))
  | none => (state.1.insert ref.canonical state.2.size, state.2.push ref)

private theorem mergeSnapshots_eq_fold (current incoming : Array ExternalRef) :
    mergeSnapshots current incoming =
      ((current ++ incoming).foldl snapshotStep ({}, #[])).2 := by
  have hfold := congrArg (fun s : Id (NameMap Nat × Array ExternalRef) => s.run.2)
    (Array.forIn_pure_yield_eq_foldl (m := Id) (xs := current ++ incoming)
      (fun ref state => snapshotStep state ref) (({} : NameMap Nat), #[]))
  change _ = ((current ++ incoming).foldl snapshotStep ({}, #[])).2 at hfold
  rw [← hfold]
  unfold mergeSnapshots
  change (forIn (m := Id) (current ++ incoming) (({} : NameMap Nat), #[]) _).run.2 = _
  congr 3
  funext ref state
  unfold snapshotStep
  dsimp only
  split <;> simp_all only [combine]

private def Indexed (state : NameMap Nat × Array ExternalRef) : Prop :=
  ∀ name i, state.1.get? name = some i ↔
    i < state.2.size ∧ state.2[i]!.canonical = name

private theorem indexed_empty : Indexed ({}, #[]) := by
  intro name i
  simp [positions_empty]

private theorem indexed_set {positions : NameMap Nat} {refs : Array ExternalRef}
    (h : Indexed (positions, refs)) {i : Nat} (hi : i < refs.size) {ref : ExternalRef}
    (hc : ref.canonical = refs[i]!.canonical) : Indexed (positions, refs.set! i ref) := by
  intro name j
  by_cases hij : i = j
  · subst j
    simpa only [Prod.fst, Prod.snd, Array.size_set!, Array.getElem!_set!_self _ _ _ hi, hc]
      using h name i
  · simpa only [Prod.fst, Prod.snd, Array.size_set!, Array.getElem!_set!_ne _ _ _ _ hij]
      using h name j

private theorem indexed_push {positions : NameMap Nat} {refs : Array ExternalRef}
    (h : Indexed (positions, refs)) {ref : ExternalRef}
    (hnew : positions.get? ref.canonical = none) :
    Indexed (positions.insert ref.canonical refs.size, refs.push ref) := by
  dsimp only [Indexed, Prod.fst, Prod.snd] at h
  intro name j
  simp only [positions_insert, Array.size_push]
  by_cases hj : j = refs.size
  · subst j
    have hnone : positions.get? name ≠ some refs.size := by
      intro he
      have := ((h name refs.size).mp he).1
      omega
    simp only [Nat.lt_add_one, true_and]
    by_cases hn : ref.canonical = name <;> simp_all
  · by_cases hjlt : j < refs.size
    · have hjpush : j < refs.size + 1 := by omega
      have he : (refs.push ref)[j]! = refs[j]! := by
        rw [getElem!_pos (refs.push ref) j (by simpa using hjpush),
          Array.getElem_push_lt hjlt, getElem!_pos refs j hjlt]
      rw [he]
      by_cases hn : ref.canonical = name
      · subst name
        have hne : refs[j]!.canonical ≠ ref.canonical := by
          intro he
          have hget := (h ref.canonical j).mpr ⟨hjlt, he⟩
          rw [hnew] at hget
          contradiction
        simp only [↓reduceIte, Option.some.injEq, Ne.symm hj, hjpush, true_and, false_iff]
        exact hne
      · simpa only [hn, ↓reduceIte, hjlt, hjpush, true_and] using h name j
    · have hjout : ¬ j < refs.size + 1 := by omega
      have hnone : positions.get? name ≠ some j := by
        intro he
        exact hjlt ((h name j).mp he).1
      split <;> simp only [hjout, false_and, Option.some.injEq, Ne.symm hj, hnone]

private theorem indexed_step {state : NameMap Nat × Array ExternalRef}
    (h : Indexed state) (ref : ExternalRef) : Indexed (snapshotStep state ref) := by
  rcases state with ⟨positions, refs⟩
  unfold snapshotStep
  dsimp only
  split
  · rename_i i hget
    obtain ⟨hi, hc⟩ := (h ref.canonical.eraseMacroScopes i).mp hget
    apply indexed_set h hi
    exact combine_canonical _ _ hc
  · rename_i hget
    exact indexed_push (ref := { ref with canonical := ref.canonical.eraseMacroScopes }) h hget

private def lookup (state : NameMap Nat × Array ExternalRef) (name : Name) : Option Bool :=
  (state.1.get? name).map (fun i => state.2[i]!.present)

private theorem lookup_step {state : NameMap Nat × Array ExternalRef}
    (h : Indexed state) (ref : ExternalRef) (name : Name) :
    lookup (snapshotStep state ref) name =
      if ref.canonical.eraseMacroScopes = name then
        some ((lookup state name).getD false || ref.present)
      else lookup state name := by
  rcases state with ⟨positions, refs⟩
  unfold snapshotStep
  dsimp only
  split
  · rename_i i hget
    obtain ⟨hi, hc⟩ := (h ref.canonical.eraseMacroScopes i).mp hget
    by_cases hn : ref.canonical.eraseMacroScopes = name
    · subst name
      simp only [lookup, hget, Option.map_some,
        Array.getElem!_set!_self _ _ _ hi, combine_present, Option.getD_some,
        ↓reduceIte]
    · cases hj : positions.get? name with
      | none => simp [lookup, hn, hj]
      | some j =>
        have hij : i ≠ j := by
          intro he
          obtain ⟨_, hcj⟩ := (h name j).mp hj
          exact hn (hc.symm.trans (he ▸ hcj))
        simp only [lookup, hj, Option.map_some,
          Array.getElem!_set!_ne _ _ _ _ hij, hn, ↓reduceIte]
  · rename_i hget
    simp only [lookup]
    rw [positions_insert]
    by_cases hn : ref.canonical.eraseMacroScopes = name
    · subst name
      simp only [↓reduceIte, hget, Option.map_none, Option.getD_none,
        Bool.false_or, Option.map_some]
      rw [getElem!_pos _ _ (by simp), Array.getElem_push_eq]
    · simp only [hn, ↓reduceIte]
      cases hj : positions.get? name with
      | none => rfl
      | some j =>
        obtain ⟨hjlt, _⟩ := (h name j).mp hj
        dsimp only [Prod.snd] at hjlt
        simp only [Option.map_some]
        rw [getElem!_pos (refs.push { ref with canonical := ref.canonical.eraseMacroScopes }) j
            (by simpa using Nat.lt_succ_of_lt hjlt), Array.getElem_push_lt hjlt,
          getElem!_pos refs j hjlt]

private theorem indexed_fold (refs : List ExternalRef)
    {state : NameMap Nat × Array ExternalRef} (h : Indexed state) :
    Indexed (refs.foldl snapshotStep state) := by
  induction refs generalizing state with
  | nil => exact h
  | cons ref refs ih => exact ih (indexed_step h ref)

private theorem lookup_step_raw {state : NameMap Nat × Array ExternalRef}
    (h : Indexed state) (ref : ExternalRef) (name : Name) :
    (lookup (snapshotStep state ref) name).isSome = true ↔
      (lookup state name).isSome = true ∨ ref.canonical.eraseMacroScopes = name := by
  rw [lookup_step h]
  split <;> simp_all only [Option.isSome_some, or_true, or_false]

private theorem lookup_step_present {state : NameMap Nat × Array ExternalRef}
    (h : Indexed state) (ref : ExternalRef) (name : Name) :
    lookup (snapshotStep state ref) name = some true ↔
      lookup state name = some true ∨
        ref.canonical.eraseMacroScopes = name ∧ ref.present = true := by
  rw [lookup_step h]
  by_cases hn : ref.canonical.eraseMacroScopes = name
  · simp only [hn, ↓reduceIte, true_and]
    cases lookup state name <;> simp [Bool.or_eq_true]
  · simp only [hn, ↓reduceIte, false_and, or_false]

private theorem lookup_fold_raw (refs : List ExternalRef)
    {state : NameMap Nat × Array ExternalRef} (h : Indexed state) (name : Name) :
    (lookup (refs.foldl snapshotStep state) name).isSome = true ↔
      (lookup state name).isSome = true ∨
        ∃ ref ∈ refs, ref.canonical.eraseMacroScopes = name := by
  induction refs generalizing state with
  | nil => simp
  | cons ref refs ih =>
    rw [List.foldl_cons, ih (indexed_step h ref), lookup_step_raw h]
    simp [or_and_right, exists_or, or_assoc]

private theorem lookup_fold_present (refs : List ExternalRef)
    {state : NameMap Nat × Array ExternalRef} (h : Indexed state) (name : Name) :
    lookup (refs.foldl snapshotStep state) name = some true ↔
      lookup state name = some true ∨
        ∃ ref ∈ refs, ref.canonical.eraseMacroScopes = name ∧ ref.present = true := by
  induction refs generalizing state with
  | nil => simp
  | cons ref refs ih =>
    rw [List.foldl_cons, ih (indexed_step h ref), lookup_step_present h]
    simp [or_and_right, exists_or, or_assoc]

private theorem lookup_eq_some_iff {state : NameMap Nat × Array ExternalRef}
    (h : Indexed state) (name : Name) (present : Bool) :
    lookup state name = some present ↔
      ∃ ref ∈ state.2, ref.canonical = name ∧ ref.present = present := by
  constructor
  · intro hl
    cases hg : state.1.get? name with
    | none => simp [lookup, hg] at hl
    | some i =>
      obtain ⟨hi, hc⟩ := (h name i).mp hg
      refine ⟨state.2[i]!, ?_, hc, ?_⟩
      · exact Array.mem_iff_getElem.mpr ⟨i, hi, (getElem!_pos state.2 i hi).symm⟩
      · simpa only [lookup, hg, Option.map_some, Option.some.injEq] using hl
  · rintro ⟨ref, hr, hc, hp⟩
    obtain ⟨i, hi, he⟩ := Array.mem_iff_getElem.mp hr
    have he' : state.2[i]! = ref := (getElem!_pos state.2 i hi).trans he
    have hg := (h name i).mpr ⟨hi, he' ▸ hc⟩
    simp only [lookup, hg, Option.map_some, he', hp]

private theorem lookup_raw_iff {state : NameMap Nat × Array ExternalRef}
    (h : Indexed state) (name : Name) :
    (lookup state name).isSome = true ↔ ∃ ref ∈ state.2, ref.canonical = name := by
  simp only [Option.isSome_iff_exists, lookup_eq_some_iff h]
  constructor
  · rintro ⟨_, ref, hr, hc, _⟩
    exact ⟨ref, hr, hc⟩
  · rintro ⟨ref, hr, hc⟩
    exact ⟨ref.present, ref, hr, hc, rfl⟩

private theorem indexed_nodup {state : NameMap Nat × Array ExternalRef} (h : Indexed state) :
    (state.2.map (·.canonical)).toList.Nodup := by
  rw [List.nodup_iff_eq_of_getElem_eq]
  intro i j hi hj he
  have hi' : i < state.2.size := by simpa using hi
  have hj' : j < state.2.size := by simpa using hj
  have hc : state.2[i]!.canonical = state.2[j]!.canonical := by
    simpa only [Array.getElem_toList, Array.getElem_map,
      getElem!_pos state.2 i hi', getElem!_pos state.2 j hj'] using he
  have hgi := (h state.2[i]!.canonical i).mpr ⟨hi', rfl⟩
  have hgj := (h state.2[i]!.canonical j).mpr ⟨hj', hc.symm⟩
  exact Option.some.inj (hgi.symm.trans hgj)

private def mergedState (current incoming : Array ExternalRef) : NameMap Nat × Array ExternalRef :=
  (current ++ incoming).toList.foldl snapshotStep ({}, #[])

private theorem mergedState_indexed (current incoming : Array ExternalRef) :
    Indexed (mergedState current incoming) :=
  indexed_fold _ indexed_empty

private theorem mergedState_refs (current incoming : Array ExternalRef) :
    (mergedState current incoming).2 = mergeSnapshots current incoming := by
  rw [mergeSnapshots_eq_fold]
  simp only [mergedState, Array.foldl_toList]

/-- Raw snapshot names are exactly the union of the one-pass scope-erased inputs.
This includes missing references; no presence assumption is imposed on either input. -/
theorem mergeSnapshots_canonical_union (current incoming : Array ExternalRef) (name : Name) :
    (∃ ref ∈ mergeSnapshots current incoming, ref.canonical = name) ↔
      (∃ ref ∈ current, ref.canonical.eraseMacroScopes = name) ∨
      (∃ ref ∈ incoming, ref.canonical.eraseMacroScopes = name) := by
  rw [← mergedState_refs, ← lookup_raw_iff (mergedState_indexed current incoming)]
  rw [mergedState, lookup_fold_raw _ indexed_empty]
  simp only [lookup, positions_empty, Option.map_none, Option.isSome_none,
    Bool.false_eq_true, false_or, Array.toList_append, List.mem_append, Array.mem_toList_iff,
    or_and_right, exists_or]

/-- Every output canonical field is obtained by erasing one input canonical field once. -/
theorem mergeSnapshots_normalized (current incoming : Array ExternalRef)
    {ref : ExternalRef} (h : ref ∈ mergeSnapshots current incoming) :
    ∃ input ∈ current ++ incoming, input.canonical.eraseMacroScopes = ref.canonical := by
  have hu := (mergeSnapshots_canonical_union current incoming ref.canonical).mp ⟨ref, h, rfl⟩
  simpa only [Array.mem_append, or_and_right, exists_or] using hu

/-- Output canonical fields are unique, even when either input has duplicates. -/
theorem mergeSnapshots_canonical_nodup (current incoming : Array ExternalRef) :
    ((mergeSnapshots current incoming).map (·.canonical)).toList.Nodup := by
  rw [← mergedState_refs]
  exact indexed_nodup (mergedState_indexed current incoming)

/-- A name has a present output exactly when some matching input was present.
Missing references still contribute to `mergeSnapshots_canonical_union`. -/
theorem mergeSnapshots_present_iff (current incoming : Array ExternalRef) (name : Name) :
    (∃ ref ∈ mergeSnapshots current incoming, ref.canonical = name ∧ ref.present = true) ↔
      (∃ ref ∈ current, ref.canonical.eraseMacroScopes = name ∧ ref.present = true) ∨
      (∃ ref ∈ incoming, ref.canonical.eraseMacroScopes = name ∧ ref.present = true) := by
  rw [← mergedState_refs, ← lookup_eq_some_iff (mergedState_indexed current incoming)]
  rw [mergedState, lookup_fold_present _ indexed_empty]
  simp only [lookup, positions_empty, Option.map_none, reduceCtorEq,
    false_or, Array.toList_append, List.mem_append, Array.mem_toList_iff, or_and_right, exists_or]

/-- The presence field of each output is the disjunction of its matching input observations. -/
theorem mergeSnapshots_ref_present_iff (current incoming : Array ExternalRef)
    {ref : ExternalRef} (h : ref ∈ mergeSnapshots current incoming) :
    ref.present = true ↔
      (∃ input ∈ current, input.canonical.eraseMacroScopes = ref.canonical ∧ input.present = true) ∨
      (∃ input ∈ incoming, input.canonical.eraseMacroScopes = ref.canonical ∧ input.present = true) := by
  have hm : ref ∈ (mergedState current incoming).2 := by
    simpa only [mergedState_refs] using h
  have hl := (lookup_eq_some_iff (mergedState_indexed current incoming)
    ref.canonical ref.present).mpr ⟨ref, hm, rfl, rfl⟩
  have he := mergeSnapshots_present_iff current incoming ref.canonical
  rw [← mergedState_refs,
    ← lookup_eq_some_iff (mergedState_indexed current incoming), hl, Option.some.injEq] at he
  exact he

/-- Erasure-fixed outputs follow when every input's one-pass erasure is stable.
Lean's erasure is not idempotent on arbitrary, possibly malformed `Name` values. -/
theorem mergeSnapshots_normalized_fixed (current incoming : Array ExternalRef)
    (stable : ∀ input ∈ current ++ incoming,
      input.canonical.eraseMacroScopes.eraseMacroScopes = input.canonical.eraseMacroScopes)
    {ref : ExternalRef} (h : ref ∈ mergeSnapshots current incoming) :
    ref.canonical.eraseMacroScopes = ref.canonical := by
  obtain ⟨input, hi, hc⟩ := mergeSnapshots_normalized current incoming h
  rw [← hc]
  exact stable input hi

end Informal.Data.ExternalRef
