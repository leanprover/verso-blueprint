/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.NodeAssembly.Laws
import VersoBlueprint.Node.MembershipLaws

/-! Membership laws for the complete keyed native-association and source inventories.

The former separate statement/proof array equations are intentionally retired:
one association retains its entire realization key, context and selected facet array,
and arbitrary named facets participate in the same node-wide projection.
-/

namespace Informal.NodeAssembly
open Lean Informal.Data Informal.Contributions

/-- The accepted node retains exactly the full associations from its accepted
records. The witness preserves realization, context and every selected facet. -/
theorem assemble_ok_nativeAssociations_membership {label : Label}
    {payloads : Array SourceData.Registration} {records : List Record}
    {assembled : Assembly} (h : assemble label payloads records = .ok assembled)
    (association : SourceData.NativeAssociation) :
    association ∈ assembled.node.nativeAssociations ↔
      ∃ record ∈ records, record.label = label ∧
        association ∈ record.nativeAssociations := by
  rw [assemble_ok_nativeAssociations h]
  simp only [Array.mem_flatMap, List.mem_toArray]
  constructor
  · rintro ⟨record, hrecord, hassociation⟩
    rcases (assemble_ok_supports h record).mp hrecord with ⟨hrecord, hlabel⟩
    exact ⟨record, hrecord, hlabel, hassociation⟩
  · rintro ⟨record, hrecord, hlabel, hassociation⟩
    exact ⟨record, (assemble_ok_supports h record).mpr ⟨hrecord, hlabel⟩, hassociation⟩

/-- Attribute presence is derived from the full accepted association inventory;
there is no second stored capability flag to drift out of sync. -/
theorem assemble_ok_hasAttributeAssociations {label : Label}
    {payloads : Array SourceData.Registration} {records : List Record}
    {assembled : Assembly} (h : assemble label payloads records = .ok assembled) :
    assembled.node.hasAttributeAssociations = true ↔
      ∃ record ∈ records, record.label = label ∧
        ∃ association ∈ record.nativeAssociations,
          (association.reference.origin == .blueprintAttr) = true := by
  simp only [Data.Node.hasAttributeAssociations, Array.any_eq_true']
  constructor
  · rintro ⟨association, hassociation, horigin⟩
    obtain ⟨record, hrecord, hlabel, hassociation⟩ :=
      (assemble_ok_nativeAssociations_membership h association).mp hassociation
    exact ⟨record, hrecord, hlabel, association, hassociation, horigin⟩
  · rintro ⟨record, hrecord, hlabel, association, hassociation, horigin⟩
    exact ⟨association,
      (assemble_ok_nativeAssociations_membership h association).mpr
        ⟨record, hrecord, hlabel, hassociation⟩,
      horigin⟩

private theorem association_nativeAssociations_iff (records : List Record)
    (label : Label) (name : Name) :
    Association records label name ↔
      ∃ record ∈ records, record.label = label ∧
        ∃ association ∈ record.nativeAssociations,
          association.reference.present = true ∧
            association.reference.canonical.eraseMacroScopes = name := by
  simp only [Association, Record.allReferences, Array.toList_map,
    Array.mem_toList_iff, List.mem_map]
  constructor
  · rintro ⟨record, hrecord, hlabel, ref, ⟨association, hassociation, href⟩,
      hpresent, hname⟩
    rw [← href] at hpresent hname
    exact ⟨record, hrecord, hlabel, association, hassociation, hpresent, hname⟩
  · rintro ⟨record, hrecord, hlabel, association, hassociation, hpresent, hname⟩
    exact ⟨record, hrecord, hlabel, association.reference,
      ⟨association, hassociation, rfl⟩, hpresent, hname⟩

/-- Successful assembly's native declaration names come from the full accepted
association union plus inline code in the successful keyed payload source set.
No per-language or statement/proof projection filters the native witnesses. -/
theorem assemble_ok_leanDecls_sources {label : Label}
    {payloads : Array SourceData.Registration} {records : List Record}
    {assembled : Assembly} {base : Node}
    (h : assemble label payloads records = .ok assembled)
    (hb : Node.applyRegistrations label {} payloads = .ok base)
    (name : Name) :
    name ∈ assembled.node.leanDecls ↔
      Association records label name ∨
        (∃ source ∈ base.sources, ∃ code, source.payload = .leanInline code ∧
          ∃ declaration ∈ code.definedDeclNames,
            declaration.eraseMacroScopes = name) := by
  rw [Informal.Data.Node.mem_leanDecls]
  have hassoc :
      (∃ association ∈ assembled.node.nativeAssociations,
        association.reference.present = true ∧
          association.reference.canonical.eraseMacroScopes = name) ↔
        Association records label name := by
    constructor
    · rintro ⟨association, hassociation, hpresent, hname⟩
      obtain ⟨record, hrecord, hlabel, hraw⟩ :=
        (assemble_ok_nativeAssociations_membership h association).mp hassociation
      exact (association_nativeAssociations_iff records label name).mpr
        ⟨record, hrecord, hlabel, association, hraw, hpresent, hname⟩
    · intro hAssociation
      rcases (association_nativeAssociations_iff records label name).mp hAssociation with
        ⟨record, hrecord, hlabel, association, hraw, hpresent, hname⟩
      exact ⟨association,
        (assemble_ok_nativeAssociations_membership h association).mpr
          ⟨record, hrecord, hlabel, hraw⟩,
        hpresent, hname⟩
  have hsources := assemble_ok_sources h hb
  constructor
  · rintro (hassociation | ⟨source, hsource, code, hpayload, declaration, hdecl, hname⟩)
    · exact Or.inl (hassoc.mp hassociation)
    · apply Or.inr
      refine ⟨source, ?_, code, hpayload, declaration, hdecl, hname⟩
      rw [← hsources]
      exact hsource
  · rintro (hAssociation | ⟨source, hsource, code, hpayload, declaration, hdecl, hname⟩)
    · exact Or.inl (hassoc.mpr hAssociation)
    · apply Or.inr
      refine ⟨source, ?_, code, hpayload, declaration, hdecl, hname⟩
      rw [hsources]
      exact hsource

/-- A raw missing association remains in the admitted node's selectable
inventory. Presence affects declaration membership, never evidence retention. -/
theorem assemble_ok_missingAssociation_mem {label : Label}
    {payloads : Array SourceData.Registration} {records : List Record}
    {assembled : Assembly} (h : assemble label payloads records = .ok assembled)
    {record : Record} (hr : record ∈ records) (hl : record.label = label)
    {association : SourceData.NativeAssociation}
    (ha : association ∈ record.nativeAssociations)
    (hm : association.reference.present = false) :
    association ∈ assembled.node.nativeAssociations ∧ association.reference.present = false := by
  exact ⟨(assemble_ok_nativeAssociations_membership h association).mpr
      ⟨record, hr, hl, ha⟩, hm⟩

end Informal.NodeAssembly
