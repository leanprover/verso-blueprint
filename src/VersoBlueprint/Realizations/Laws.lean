/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations
import VersoBlueprint.Util.QSortLaws

namespace Informal.Realizations
open Lean

private theorem mem_dedupStep [BEq α] [LawfulBEq α] (acc : Array α) (next value : α) :
    value ∈ (if acc.back? != some next then acc.push next else acc) ↔
      value ∈ acc ∨ next = value := by
  split
  · simp [eq_comm]
  · rename_i h
    have hb : acc.back? = some next := by simpa using h
    have hm := Array.mem_of_back? hb
    constructor
    · exact Or.inl
    · rintro (hmem | rfl)
      · exact hmem
      · exact hm

private theorem mem_dedupFold [BEq α] [LawfulBEq α]
    (values acc : Array α) (value : α) :
    value ∈ values.foldl (fun acc next => if acc.back? != some next then acc.push next else acc) acc ↔
      value ∈ acc ∨ value ∈ values := by
  rw [← Array.foldl_toList]
  have h (xs : List α) (acc : Array α) :
      value ∈ xs.foldl (fun acc next => if acc.back? != some next then acc.push next else acc) acc ↔
        value ∈ acc ∨ value ∈ xs := by
    induction xs generalizing acc with
    | nil => simp
    | cons next xs ih =>
      rw [List.foldl_cons, ih, mem_dedupStep]
      simp [or_assoc, eq_comm]
  simpa using h values.toList acc

/-- Canonical ordering and adjacent deduplication preserve exact membership.
No ordering laws are needed for this property; executable equality must be lawful. -/
theorem mem_canonical [BEq α] [LawfulBEq α] [Ord α] (values : Array α) (value : α) :
    value ∈ canonical values ↔ value ∈ values := by
  have step (next : α) (acc : Array α) :
      (if acc.back? != some next then pure (ForInStep.yield (acc.push next))
        else pure (ForInStep.yield acc) : Id (ForInStep (Array α))) =
      pure (ForInStep.yield (if acc.back? != some next then acc.push next else acc)) := by
    split <;> rfl
  simp only [canonical]
  simp only [step]
  simp only [Array.forIn_pure_yield_eq_foldl]
  change value ∈ (values.qsort (fun a b => compare a b == .lt)).foldl
    (fun acc next => if acc.back? != some next then acc.push next else acc) #[] ↔ _
  simp only [mem_dedupFold, Array.not_mem_empty, false_or]
  exact (QSortLaws.qsort_perm values _ _ _).mem_iff

/-- Canonicalization neither invents nor loses the existence of an obligation. -/
theorem canonical_eq_empty_iff [BEq α] [LawfulBEq α] [Ord α] (values : Array α) :
    canonical values = #[] ↔ values = #[] := by
  simp only [Array.eq_empty_iff_forall_not_mem, mem_canonical]

end Informal.Realizations
