/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Data
import VersoBlueprint.ExternalRef.Laws

/-! Exact declaration membership of the keyed node projection. -/

namespace Informal.Data.Node
open Lean

private theorem mem_pushName (names : Array Name) (name query : Name) :
    query ∈ pushUniqueNativeName names name ↔ query ∈ names ∨ name.eraseMacroScopes = query := by
  unfold pushUniqueNativeName
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
    query ∈ declarations.foldl pushUniqueNativeName names ↔
      query ∈ names ∨ ∃ declaration ∈ declarations, declaration.eraseMacroScopes = query := by
  rw [← Array.foldl_toList]
  have h (xs : List Name) (names : Array Name) :
      query ∈ xs.foldl pushUniqueNativeName names ↔
        query ∈ names ∨ ∃ declaration ∈ xs, declaration.eraseMacroScopes = query := by
    induction xs generalizing names with
    | nil => simp
    | cons name xs ih =>
      rw [List.foldl_cons, ih, mem_pushName]
      simp [or_and_right, exists_or, or_assoc]
  simpa using h declarations.toList names

private theorem mem_external_fold (refs : Array ExternalRef) (names : Array Name) (query : Name) :
    query ∈ refs.foldl
        (fun acc ref => if ref.present then pushUniqueNativeName acc ref.canonical else acc) names ↔
      query ∈ names ∨ ∃ ref ∈ refs,
        ref.present = true ∧ ref.canonical.eraseMacroScopes = query := by
  rw [← Array.foldl_toList]
  have h (xs : List ExternalRef) (names : Array Name) :
      query ∈ xs.foldl
          (fun acc ref => if ref.present then pushUniqueNativeName acc ref.canonical else acc) names ↔
        query ∈ names ∨ ∃ ref ∈ xs,
          ref.present = true ∧ ref.canonical.eraseMacroScopes = query := by
    induction xs generalizing names with
    | nil => simp
    | cons ref xs ih =>
      rw [List.foldl_cons, ih]
      cases hp : ref.present <;> simp [hp, mem_pushName, or_and_right, exists_or, or_assoc]
  simpa using h refs.toList names

private theorem mem_inline_fold (codes : Array Code) (names : Array Name) (query : Name) :
    query ∈ codes.foldl
        (fun acc code => code.definedDeclNames.foldl pushUniqueNativeName acc) names ↔
      query ∈ names ∨ ∃ code ∈ codes, ∃ declaration ∈ code.definedDeclNames,
        declaration.eraseMacroScopes = query := by
  rw [← Array.foldl_toList]
  have h (xs : List Code) (names : Array Name) :
      query ∈ xs.foldl
          (fun acc code => code.definedDeclNames.foldl pushUniqueNativeName acc) names ↔
        query ∈ names ∨ ∃ code ∈ xs, ∃ declaration ∈ code.definedDeclNames,
          declaration.eraseMacroScopes = query := by
    induction xs generalizing names with
    | nil => simp
    | cons code xs ih =>
      rw [List.foldl_cons, ih, mem_fold_pushName]
      simp [or_and_right, exists_or, or_assoc]
  simpa using h codes.toList names

private theorem mem_inlineCode_source (node : Node) {code : Code} :
    code ∈ node.inlineCodes ↔ ∃ source ∈ node.sources, source.payload = .leanInline code := by
  simp only [Node.inlineCodes, Array.mem_filterMap]
  constructor
  · rintro ⟨source, hsource, hmatch⟩
    cases hp : source.payload with
    | prose body => simp [hp] at hmatch
    | leanInline inline =>
      simp only [hp] at hmatch
      cases hmatch
      exact ⟨source, hsource, hp⟩
    | text raw => simp [hp] at hmatch
    | markup markup => simp [hp] at hmatch
  · rintro ⟨source, hsource, hpayload⟩
    exact ⟨source, hsource, by simp only [hpayload]⟩

/-- Raw association and inline-code membership follows the keyed source inventories.
Present external references and all inline declaration names participate; missing
references remain in storage but do not create a native declaration index entry. -/
theorem mem_leanDecls (node : Node) (name : Name) :
    name ∈ node.leanDecls ↔
      (∃ association ∈ node.nativeAssociations,
        association.reference.present = true ∧
          association.reference.canonical.eraseMacroScopes = name) ∨
      (∃ source ∈ node.sources, ∃ code, source.payload = .leanInline code ∧
        ∃ declaration ∈ code.definedDeclNames, declaration.eraseMacroScopes = name) := by
  change name ∈ node.inlineCodes.foldl
      (fun acc code => code.definedDeclNames.foldl pushUniqueNativeName acc)
      (node.externalAssociationSnapshots.foldl
        (fun acc ref => if ref.present then pushUniqueNativeName acc ref.canonical else acc) #[]) ↔ _
  rw [mem_inline_fold, mem_external_fold]
  simp only [Node.externalAssociationSnapshots, Array.mem_map, mem_inlineCode_source]
  simp only [Array.mem_empty_iff, false_or]
  constructor
  · rintro (⟨ref, ⟨association, ha, href⟩, hpresent, hname⟩ |
      ⟨code, ⟨source, hsource, hpayload⟩, declaration, hdeclaration, hname⟩)
    · rw [← href] at hpresent hname
      exact Or.inl ⟨association, ha, hpresent, hname⟩
    · exact Or.inr ⟨source, hsource, code, hpayload, declaration, hdeclaration, hname⟩
  · rintro (⟨association, ha, hpresent, hname⟩ |
      ⟨source, hsource, code, hpayload, declaration, hdeclaration, hname⟩)
    · exact Or.inl ⟨association.reference, ⟨association, ha, rfl⟩, hpresent, hname⟩
    · exact Or.inr ⟨code, ⟨source, hsource, hpayload⟩, declaration, hdeclaration, hname⟩

/-- One-pass-stable keyed associations produce fixed canonical fields in the
derived node-wide display union. The raw associations themselves remain intact. -/
theorem associatedExternalRefs_fixed (node : Node)
    (fixed : ∀ association ∈ node.nativeAssociations,
      association.reference.canonical.eraseMacroScopes.eraseMacroScopes =
        association.reference.canonical.eraseMacroScopes)
    {ref : ExternalRef} (href : ref ∈ node.associatedExternalRefs) :
    ref.canonical.eraseMacroScopes = ref.canonical := by
  have stable : ∀ input ∈ (#[] : Array ExternalRef) ++ node.externalAssociationSnapshots,
      input.canonical.eraseMacroScopes.eraseMacroScopes = input.canonical.eraseMacroScopes := by
    intro input hin
    have hin' : input ∈ node.externalAssociationSnapshots := by simpa using hin
    have hassociation : ∃ association ∈ node.nativeAssociations,
        association.reference = input := by
      simpa [Node.externalAssociationSnapshots] using hin'
    rcases hassociation with ⟨association, hassociation, rfl⟩
    exact fixed association hassociation
  change ref ∈ ExternalRef.mergeSnapshots #[] node.externalAssociationSnapshots at href
  exact ExternalRef.mergeSnapshots_normalized_fixed #[]
    node.externalAssociationSnapshots stable href

end Informal.Data.Node
