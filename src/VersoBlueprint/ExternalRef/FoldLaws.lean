/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.ExternalRef.Laws

/-! Membership of the actual snapshot fold used by the two assembly facets. -/

namespace Informal.Data.ExternalRef
open Lean

private theorem reverse_induction {α : Type} {motive : List α → Prop}
    (nil : motive [])
    (append_singleton : ∀ inputs input, motive inputs → motive (inputs ++ [input]))
    (inputs : List α) : motive inputs := by
  have h : ∀ xs : List α, motive xs.reverse := by
    intro xs
    induction xs with
    | nil => exact nil
    | cons x xs ih => simpa using append_singleton xs.reverse x ih
  simpa using h inputs.reverse

/-- Repeated merges keep one-pass keys when erasure is stable for every input. -/
theorem mergeSnapshots_fold_normalized {α : Type} (select : α → Array ExternalRef)
    (inputs : List α)
    (stable : ∀ input ∈ inputs, ∀ ref ∈ select input,
      ref.canonical.eraseMacroScopes.eraseMacroScopes = ref.canonical.eraseMacroScopes) :
    ∀ ref ∈ inputs.foldl (fun acc input => mergeSnapshots acc (select input)) #[],
      ref.canonical.eraseMacroScopes = ref.canonical := by
  induction inputs using reverse_induction with
  | nil => simp
  | append_singleton inputs input ih =>
    have stableInputs : ∀ item ∈ inputs, ∀ ref ∈ select item,
        ref.canonical.eraseMacroScopes.eraseMacroScopes = ref.canonical.eraseMacroScopes :=
      fun item hi => stable item (List.mem_append_left _ hi)
    simp only [List.foldl_append, List.foldl_cons, List.foldl_nil]
    intro ref href
    apply mergeSnapshots_normalized_fixed _ _ ?_ href
    intro candidate hc
    rcases Array.mem_append.mp hc with hc | hc
    · simp only [ih stableInputs candidate hc]
    · exact stable input (by simp) candidate hc

private theorem mergeSnapshots_membership (current incoming : Array ExternalRef)
    (fixed : ∀ ref ∈ current, ref.canonical.eraseMacroScopes = ref.canonical)
    (requirePresent : Bool) (name : Name) :
    (∃ ref ∈ mergeSnapshots current incoming,
      ref.canonical = name ∧ (requirePresent = true → ref.present = true)) ↔
      (∃ ref ∈ current, ref.canonical = name ∧ (requirePresent = true → ref.present = true)) ∨
      (∃ ref ∈ incoming, ref.canonical.eraseMacroScopes = name ∧
        (requirePresent = true → ref.present = true)) := by
  cases requirePresent
  · simp only [Bool.false_eq_true, false_implies, and_true]
    rw [mergeSnapshots_canonical_union]
    apply or_congr_left
    apply exists_congr
    intro ref
    constructor <;> rintro ⟨hr, hc⟩
    · exact ⟨hr, (fixed ref hr) ▸ hc⟩
    · exact ⟨hr, (fixed ref hr).symm ▸ hc⟩
  · simp only [true_implies]
    rw [mergeSnapshots_present_iff]
    apply or_congr_left
    apply exists_congr
    intro ref
    constructor <;> rintro ⟨hr, hc, hp⟩
    · exact ⟨hr, (fixed ref hr) ▸ hc, hp⟩
    · exact ⟨hr, (fixed ref hr).symm ▸ hc, hp⟩

/-- One membership principle for raw (`false`) and present (`true`) snapshots.
It describes the production fold with one erased key per input observation.
The stability premise prevents later merges from changing those keys again. -/
theorem mergeSnapshots_fold_membership {α : Type} (select : α → Array ExternalRef)
    (inputs : List α)
    (stable : ∀ input ∈ inputs, ∀ ref ∈ select input,
      ref.canonical.eraseMacroScopes.eraseMacroScopes = ref.canonical.eraseMacroScopes)
    (requirePresent : Bool) (name : Name) :
    (∃ ref ∈ inputs.foldl (fun acc input => mergeSnapshots acc (select input)) #[],
      ref.canonical = name ∧ (requirePresent = true → ref.present = true)) ↔
      ∃ input ∈ inputs, ∃ ref ∈ select input,
        ref.canonical.eraseMacroScopes = name ∧ (requirePresent = true → ref.present = true) := by
  induction inputs using reverse_induction with
  | nil => simp
  | append_singleton inputs input ih =>
    have stableInputs : ∀ item ∈ inputs, ∀ ref ∈ select item,
        ref.canonical.eraseMacroScopes.eraseMacroScopes = ref.canonical.eraseMacroScopes :=
      fun item hi => stable item (List.mem_append_left _ hi)
    simp only [List.foldl_append, List.foldl_cons, List.foldl_nil]
    rw [mergeSnapshots_membership _ _ (mergeSnapshots_fold_normalized select inputs stableInputs),
      ih stableInputs]
    simp [or_and_right, exists_or]

/-- Every sequence result has unique canonical fields, without a stability premise. -/
theorem mergeSnapshots_fold_canonical_nodup {α : Type} (select : α → Array ExternalRef)
    (inputs : List α) :
    ((inputs.foldl (fun acc input => mergeSnapshots acc (select input)) #[]).map
      (·.canonical)).toList.Nodup := by
  induction inputs using reverse_induction with
  | nil => simp
  | append_singleton inputs input _ =>
    simp only [List.foldl_append, List.foldl_cons, List.foldl_nil]
    exact mergeSnapshots_canonical_nodup _ _

end Informal.Data.ExternalRef
