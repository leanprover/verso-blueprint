/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean.Data.NameMap
import Std.Data.TreeMap.Lemmas

/-! Laws for the actual comparator used by Lean's NameMap. Hash equality does
not identify names: the structural comparison breaks hash ties. -/
namespace Informal.NameMapLaws
open Lean Std
attribute [local instance] lexOrd

private def components : Name → List (Option String × Nat)
  | .anonymous => []
  | .num parent value => (none, value) :: components parent
  | .str parent value => (some value, 0) :: components parent

private theorem quickCmpAux_eq (a b : Name) :
    a.quickCmpAux b = compare (components a) (components b) := by
  induction a generalizing b with
  | anonymous => cases b <;> rfl
  | num parent value ih =>
    cases b with
    | anonymous => rfl
    | str _ _ => rfl
    | num parent' value' =>
      cases compared : compare value value' <;>
        simp only [compare] at compared <;>
        simp [Name.quickCmpAux, components, compare, List.compareLex, ih,
          compareLex, compareOn, Ordering.then, compared] <;> rfl
  | str parent value ih =>
    cases b with
    | anonymous => rfl
    | num _ _ => rfl
    | str parent' value' =>
      cases compared : compare value value' <;>
        simp only [compare] at compared <;>
        simp [Name.quickCmpAux, components, compare, List.compareLex, ih,
          compareLex, compareOn, Ordering.then, compared] <;> rfl

private theorem components_injective {a b : Name} (equal : components a = components b) : a = b := by
  induction a generalizing b <;> cases b <;> simp_all [components] <;> grind

private theorem quickCmp_eq :
    Name.quickCmp = compareLex (compareOn Name.hash) (compareOn components) := by
  funext a b
  simp only [Name.quickCmp, compareLex, compareOn, quickCmpAux_eq]
  rfl

/-- The actual hash-first comparator is transitive, without assuming the hash is
injective. Structural comparison orders names with equal hashes. -/
instance quickCmp_trans : TransCmp Name.quickCmp := by
  rw [quickCmp_eq]
  infer_instance

/-- Comparison equality is exact name equality, including string/numeral and
macro-scope components. It does not use display strings or hash injectivity. -/
instance quickCmp_lawfulEq : LawfulEqCmp Name.quickCmp where
  eq_of_compare {a b} equal := by
    rw [quickCmp_eq] at equal
    simp only [compareLex_eq_eq, compareOn] at equal
    exact components_injective (LawfulEqOrd.eq_of_compare equal.2)

/-- NameMap insertion updates precisely one structural name, not every name with
the same display spelling or hash. -/
theorem get?_insert (map : NameMap α) (key query : Name) (value : α) :
    (map.insert key value).get? query = if key = query then some value else map.get? query := by
  unfold NameMap at map
  change ((map : Std.TreeMap Name α Name.quickCmp).insert key value)[query]? =
    if key = query then some value else (map : Std.TreeMap Name α Name.quickCmp)[query]?
  rw [Std.TreeMap.getElem?_insert]
  simp only [LawfulEqCmp.compare_eq_iff_eq]

theorem getD_insert (map : NameMap α) (key query : Name) (value fallback : α) :
    (map.insert key value).getD query fallback =
      if key = query then value else map.getD query fallback := by
  unfold NameMap at map
  change Std.TreeMap.getD (Std.TreeMap.insert map key value) query fallback =
    if key = query then value else Std.TreeMap.getD map query fallback
  rw [Std.TreeMap.getD_insert]
  simp only [LawfulEqCmp.compare_eq_iff_eq]

theorem getD_insert_self (map : NameMap α) (key : Name) (value fallback : α) :
    (map.insert key value).getD key fallback = value := by
  unfold NameMap at map
  exact Std.TreeMap.getD_insert_self

/-- Enumeration preserves exact key/value pairs from the actual NameMap. -/
theorem mem_toArray (map : NameMap α) (key : Name) (value : α) :
    (key, value) ∈ map.toArray ↔ map.get? key = some value := by
  unfold NameMap at map
  exact Std.TreeMap.mem_toArray_iff_getElem?_eq_some

@[simp] theorem get?_empty (key : Name) :
    ({} : NameMap α).get? key = none := by
  rfl

end Informal.NameMapLaws
