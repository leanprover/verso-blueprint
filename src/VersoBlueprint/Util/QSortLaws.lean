/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
module
public import Init.Data.Array.QSort.Basic
import all Init.Data.Array.QSort.Basic
import Lean
public import Init.Data.Vector.Perm

public section
namespace Informal.QSortLaws

private theorem partitionLoop_perm {α : Type u} {n : Nat} (lt : α → α → Bool)
    (lo hi : Nat) (hhi : hi < n) (pivot : α) (xs : Vector α n)
    (i k : Nat) (ilo : lo ≤ i) (ik : i ≤ k) (w : k ≤ hi) :
    Vector.Perm (Array.qpartition.loop lt lo hi hhi pivot xs i k ilo ik w).2 xs := by
  fun_induction Array.qpartition.loop lt lo hi hhi pivot xs i k ilo ik w
  · rename_i ih
    exact ih.trans (Vector.swap_perm _ _)
  · assumption
  · apply Vector.swap_perm <;> omega

private theorem partition_perm {α : Type u} {n : Nat} (xs : Vector α n)
    (lt : α → α → Bool) (lo hi : Nat) (w : lo ≤ hi) (hlo : lo < n) (hhi : hi < n) :
    Vector.Perm (Array.qpartition xs lt lo hi w hlo hhi).2 xs := by
  unfold Array.qpartition
  apply (partitionLoop_perm ..).trans
  split <;> split <;> split <;>
    repeat first | exact .refl _ | apply (Vector.swap_perm _ _).trans

private theorem sort_perm {α : Type u} {n : Nat} (lt : α → α → Bool)
    (xs : Vector α n) (lo hi : Nat) (w : lo ≤ hi) (hlo : lo < n) (hhi : hi < n) :
    Vector.Perm (Array.qsort.sort lt xs lo hi w hlo hhi) xs := by
  fun_induction Array.qsort.sort lt xs lo hi w hlo hhi
  case case1 xs lo hi w hlo hhi _ mid hmid part heq _ =>
    simpa only [heq] using partition_perm xs lt lo hi w hlo hhi
  case case2 xs lo hi w hlo hhi _ mid hmid part heq _ ihLeft _ ihRight =>
    have hp : part.Perm xs := by
      simpa only [heq] using partition_perm xs lt lo hi w hlo hhi
    exact ihRight.trans (ihLeft.trans hp)
  case case3 => exact .refl _

/-- Production quicksort preserves the full input multiset, even for a comparator
with no ordering laws and when only a subrange is selected. -/
theorem qsort_perm (xs : Array α) (lt : α → α → Bool) (lo hi : Nat) :
    Array.Perm (xs.qsort lt lo hi) xs := by
  unfold Array.qsort
  split
  · exact .refl _
  · exact (sort_perm ..).toArray

end Informal.QSortLaws
