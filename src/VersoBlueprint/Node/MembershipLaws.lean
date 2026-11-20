/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Data

/-! Exact declaration membership of the production node projection. -/

namespace Informal.Data.Node
open Lean

-- A proof-only presentation of the private production helper. The projection
-- equality below is checked by definitional equality against Node.leanDecls.
private def pushName (names : Array Name) (name : Name) : Array Name :=
  let name := name.eraseMacroScopes
  if names.contains name then names else names.push name

private theorem mem_pushName (names : Array Name) (name query : Name) :
    query ∈ pushName names name ↔ query ∈ names ∨ name.eraseMacroScopes = query := by
  unfold pushName
  dsimp only
  split
  · rename_i h
    have hm := Array.mem_of_contains_eq_true h
    constructor
    · exact Or.inl
    · rintro (hq | he)
      · exact hq
      · exact he ▸ hm
  · simp [eq_comm]

private theorem mem_fold_pushName (names declarations : Array Name) (query : Name) :
    query ∈ declarations.foldl pushName names ↔
      query ∈ names ∨ ∃ declaration ∈ declarations, declaration.eraseMacroScopes = query := by
  rw [← Array.foldl_toList]
  have h (xs : List Name) (names : Array Name) :
      query ∈ xs.foldl pushName names ↔
        query ∈ names ∨ ∃ declaration ∈ xs, declaration.eraseMacroScopes = query := by
    induction xs generalizing names with
    | nil => simp
    | cons name xs ih =>
      rw [List.foldl_cons, ih, mem_pushName]
      simp [or_and_right, exists_or, or_assoc]
  simpa using h declarations.toList names

private theorem mem_external_fold (refs : Array ExternalRef) (names : Array Name) (query : Name) :
    query ∈ refs.foldl (fun acc ref => if ref.present then pushName acc ref.canonical else acc) names ↔
      query ∈ names ∨ ∃ ref ∈ refs,
        ref.present = true ∧ ref.canonical.eraseMacroScopes = query := by
  rw [← Array.foldl_toList]
  have h (xs : List ExternalRef) (names : Array Name) :
      query ∈ xs.foldl (fun acc ref => if ref.present then pushName acc ref.canonical else acc) names ↔
        query ∈ names ∨ ∃ ref ∈ xs,
          ref.present = true ∧ ref.canonical.eraseMacroScopes = query := by
    induction xs generalizing names with
    | nil => simp
    | cons ref xs ih =>
      rw [List.foldl_cons, ih]
      cases hp : ref.present <;> simp [hp, mem_pushName, or_and_right, exists_or, or_assoc]
  simpa using h refs.toList names

private theorem mem_literate_fold (codes : Array Code) (names : Array Name) (query : Name) :
    query ∈ codes.foldl (fun acc code => code.definedDeclNames.foldl pushName acc) names ↔
      query ∈ names ∨ ∃ code ∈ codes, ∃ declaration ∈ code.definedDeclNames,
        declaration.eraseMacroScopes = query := by
  rw [← Array.foldl_toList]
  have h (xs : List Code) (names : Array Name) :
      query ∈ xs.foldl (fun acc code => code.definedDeclNames.foldl pushName acc) names ↔
        query ∈ names ∨ ∃ code ∈ xs, ∃ declaration ∈ code.definedDeclNames,
          declaration.eraseMacroScopes = query := by
    induction xs generalizing names with
    | nil => simp
    | cons code xs ih =>
      rw [List.foldl_cons, ih, mem_fold_pushName]
      simp [or_and_right, exists_or, or_assoc]
  simpa using h codes.toList names

/-- Arbitrary-node membership keeps the projection's exact erasure conventions.
Literate declarations are erased after Code.definedDeclNames, without assuming stability. -/
theorem mem_leanDecls (node : Node) (name : Name) :
    name ∈ node.leanDecls ↔
      (∃ ref ∈ node.externalAssociationSnapshots,
        ref.present = true ∧ ref.canonical.eraseMacroScopes = name) ∨
      (∃ code ∈ node.literateCodes, ∃ declaration ∈ code.definedDeclNames,
        declaration.eraseMacroScopes = name) := by
  change name ∈ node.literateCodes.foldl
    (fun acc code => code.definedDeclNames.foldl pushName acc)
    (node.externalAssociationSnapshots.foldl
      (fun acc ref => if ref.present then pushName acc ref.canonical else acc) #[]) ↔ _
  rw [mem_literate_fold, mem_external_fold]
  simp

/-- With erasure-fixed external snapshots, their actual fields name the associations.
The literate disjunct still records its exact additional erasure. -/
theorem mem_leanDecls_of_fixed (node : Node)
    (fixed : ∀ ref ∈ node.externalAssociationSnapshots,
      ref.canonical.eraseMacroScopes = ref.canonical) (name : Name) :
    name ∈ node.leanDecls ↔
      (∃ ref ∈ node.externalAssociationSnapshots,
        ref.canonical = name ∧ ref.present = true) ∨
      (∃ code ∈ node.literateCodes, ∃ declaration ∈ code.definedDeclNames,
        declaration.eraseMacroScopes = name) := by
  rw [mem_leanDecls]
  apply or_congr_left
  apply exists_congr
  intro ref
  constructor <;> rintro ⟨hr, hfirst, hsecond⟩
  · exact ⟨hr, (fixed ref hr) ▸ hsecond, hfirst⟩
  · exact ⟨hr, hsecond, (fixed ref hr).symm ▸ hfirst⟩

end Informal.Data.Node
