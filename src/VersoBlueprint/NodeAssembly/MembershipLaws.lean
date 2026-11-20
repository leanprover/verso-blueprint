/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.NodeAssembly.Laws
import VersoBlueprint.ExternalRef.FoldLaws
import VersoBlueprint.Node.MembershipLaws

/-! Facet and declaration membership of successful production assembly. -/

namespace Informal.NodeAssembly
open Lean Informal.Data Informal.Contributions

private theorem selected_fold_membership {label : Label} {payloads : Array NodeContribution}
    {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled)
    (select : Record → Array ExternalRef)
    (stable : ∀ record ∈ records, record.label = label → ∀ ref ∈ select record,
      ref.canonical.eraseMacroScopes.eraseMacroScopes = ref.canonical.eraseMacroScopes)
    (requirePresent : Bool) (name : Name) :
    (∃ ref ∈ assembled.view.supports.foldl
        (fun acc record => ExternalRef.mergeSnapshots acc (select record)) #[],
      ref.canonical = name ∧ (requirePresent = true → ref.present = true)) ↔
      ∃ record ∈ records, record.label = label ∧ ∃ ref ∈ select record,
        ref.canonical.eraseMacroScopes = name ∧ (requirePresent = true → ref.present = true) := by
  have hs : ∀ record ∈ assembled.view.supports, ∀ ref ∈ select record,
      ref.canonical.eraseMacroScopes.eraseMacroScopes = ref.canonical.eraseMacroScopes := by
    intro record hr
    obtain ⟨hr, hl⟩ := (assemble_ok_supports h record).mp hr
    exact stable record hr hl
  rw [ExternalRef.mergeSnapshots_fold_membership select assembled.view.supports hs]
  simp only [assemble_ok_supports h]
  simp only [and_assoc]

/-- Both raw and present statement snapshots come exactly from selected statement inputs.
Use `false` for raw membership and `true` for present membership. -/
theorem assemble_ok_externalRefs_membership {label : Label} {payloads : Array NodeContribution}
    {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled)
    (requirePresent : Bool) (name : Name) :
    (∃ ref ∈ assembled.node.externalRefs,
      ref.canonical = name ∧ (requirePresent = true → ref.present = true)) ↔
      ∃ record ∈ records, record.label = label ∧ ∃ ref ∈ record.references,
        ref.canonical.eraseMacroScopes = name ∧ (requirePresent = true → ref.present = true) := by
  rw [assemble_ok_externalRefs h]
  exact selected_fold_membership h Record.references
    (fun record hr hl ref href => (assemble_ok_stableReferences h) record hr hl ref
      (Array.mem_append.mpr (.inl href))) requirePresent name

/-- The same principle for the proof facet, with no statement-reference inputs. -/
theorem assemble_ok_proofExternalRefs_membership {label : Label} {payloads : Array NodeContribution}
    {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled)
    (requirePresent : Bool) (name : Name) :
    (∃ ref ∈ assembled.node.proofExternalRefs,
      ref.canonical = name ∧ (requirePresent = true → ref.present = true)) ↔
      ∃ record ∈ records, record.label = label ∧ ∃ ref ∈ record.proofReferences,
        ref.canonical.eraseMacroScopes = name ∧ (requirePresent = true → ref.present = true) := by
  rw [assemble_ok_proofExternalRefs h]
  exact selected_fold_membership h Record.proofReferences
    (fun record hr hl ref href => (assemble_ok_stableReferences h) record hr hl ref
      (Array.mem_append.mpr (.inr href))) requirePresent name

/-- Raw statement membership includes missing observations. -/
theorem assemble_ok_externalRefs_raw_iff {label : Label} {payloads : Array NodeContribution}
    {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled)
    (name : Name) :
    (∃ ref ∈ assembled.node.externalRefs, ref.canonical = name) ↔
      ∃ record ∈ records, record.label = label ∧ ∃ ref ∈ record.references,
        ref.canonical.eraseMacroScopes = name := by
  simpa using assemble_ok_externalRefs_membership h false name

/-- Present statement membership retains any present matching observation. -/
theorem assemble_ok_externalRefs_present_iff {label : Label} {payloads : Array NodeContribution}
    {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled)
    (name : Name) :
    (∃ ref ∈ assembled.node.externalRefs, ref.canonical = name ∧ ref.present = true) ↔
      ∃ record ∈ records, record.label = label ∧ ∃ ref ∈ record.references,
        ref.canonical.eraseMacroScopes = name ∧ ref.present = true := by
  simpa using assemble_ok_externalRefs_membership h true name

/-- Raw proof membership includes missing observations. -/
theorem assemble_ok_proofExternalRefs_raw_iff {label : Label} {payloads : Array NodeContribution}
    {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled)
    (name : Name) :
    (∃ ref ∈ assembled.node.proofExternalRefs, ref.canonical = name) ↔
      ∃ record ∈ records, record.label = label ∧ ∃ ref ∈ record.proofReferences,
        ref.canonical.eraseMacroScopes = name := by
  simpa using assemble_ok_proofExternalRefs_membership h false name

/-- Present proof membership retains any present matching observation. -/
theorem assemble_ok_proofExternalRefs_present_iff {label : Label} {payloads : Array NodeContribution}
    {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled)
    (name : Name) :
    (∃ ref ∈ assembled.node.proofExternalRefs, ref.canonical = name ∧ ref.present = true) ↔
      ∃ record ∈ records, record.label = label ∧ ∃ ref ∈ record.proofReferences,
        ref.canonical.eraseMacroScopes = name ∧ ref.present = true := by
  simpa using assemble_ok_proofExternalRefs_membership h true name

/-- The projection retains the accepted payload reducer's literate blocks.
This is the minimal payload bridge needed for declaration membership. -/
theorem assemble_ok_literateCodes {label : Label} {payloads : Array NodeContribution}
    {records : List Record} {assembled : Assembly} {base : Node}
    (h : assemble label payloads records = .ok assembled)
    (hb : Node.applyContributions label {} payloads = .ok base) :
    assembled.node.literateCodes = base.literateCodes := by
  unfold assemble at h
  rw [hb] at h
  cases hr : resolve label records with
  | error _ => simp [hr] at h
  | ok view =>
    simp only [hr] at h
    split at h
    · cases h
      rfl
    · contradiction

private theorem association_facets (records : List Record) (label : Label) (name : Name) :
    Association records label name ↔
      (∃ record ∈ records, record.label = label ∧ ∃ ref ∈ record.references,
        ref.canonical.eraseMacroScopes = name ∧ ref.present = true) ∨
      (∃ record ∈ records, record.label = label ∧ ∃ ref ∈ record.proofReferences,
        ref.canonical.eraseMacroScopes = name ∧ ref.present = true) := by
  simp [Association, Record.allReferences, or_and_right, and_or_left, exists_or,
    and_comm, and_left_comm]

/-- Accepted declarations are selected present associations union accepted payload
literate declarations. Successful admission checks every selected external
observation, including missing ones. No naming premise is needed from the caller. -/
theorem assemble_ok_leanDecls_literate {label : Label} {payloads : Array NodeContribution}
    {records : List Record} {assembled : Assembly} {base : Node}
    (h : assemble label payloads records = .ok assembled)
    (hb : Node.applyContributions label {} payloads = .ok base)
    (name : Name) :
    name ∈ assembled.node.leanDecls ↔ Association records label name ∨
      (∃ code ∈ base.literateCodes, ∃ declaration ∈ code.definedDeclNames,
        declaration.eraseMacroScopes = name) := by
  have stable := assemble_ok_stableReferences h
  have supportStable : ∀ record ∈ assembled.view.supports, ∀ ref ∈ record.allReferences,
      ref.canonical.eraseMacroScopes.eraseMacroScopes = ref.canonical.eraseMacroScopes := by
    intro record hr
    obtain ⟨hr, hl⟩ := (assemble_ok_supports h record).mp hr
    exact stable record hr hl
  have fixed : ∀ ref ∈ assembled.node.externalAssociationSnapshots,
      ref.canonical.eraseMacroScopes = ref.canonical := by
    intro ref hr
    rcases Array.mem_append.mp hr with hr | hr
    · rw [assemble_ok_externalRefs h] at hr
      exact ExternalRef.mergeSnapshots_fold_normalized Record.references assembled.view.supports
        (fun record hrecord ref href =>
          supportStable record hrecord ref (Array.mem_append.mpr (.inl href))) ref hr
    · rw [assemble_ok_proofExternalRefs h] at hr
      exact ExternalRef.mergeSnapshots_fold_normalized Record.proofReferences assembled.view.supports
        (fun record hrecord ref href =>
          supportStable record hrecord ref (Array.mem_append.mpr (.inr href))) ref hr
  rw [Node.mem_leanDecls_of_fixed assembled.node fixed name, assemble_ok_literateCodes h hb]
  apply or_congr_left
  simp only [Node.externalAssociationSnapshots, Array.mem_append, or_and_right, exists_or]
  rw [assemble_ok_externalRefs_present_iff h,
    assemble_ok_proofExternalRefs_present_iff h]
  exact (association_facets records label name).symm

/-- The accepted node's declarations are exactly selected present associations
union declarations of the actual successful empty-seeded payload reducer result. -/
theorem assemble_ok_leanDecls {label : Label} {payloads : Array NodeContribution}
    {records : List Record} {assembled : Assembly} {base : Node}
    (h : assemble label payloads records = .ok assembled)
    (hb : Node.applyContributions label {} payloads = .ok base)
    (name : Name) :
    name ∈ assembled.node.leanDecls ↔ Association records label name ∨ name ∈ base.leanDecls := by
  have fields := Node.applyContributions_externalRefs hb
  have baseMembership : name ∈ base.leanDecls ↔
      ∃ code ∈ base.literateCodes, ∃ declaration ∈ code.definedDeclNames,
        declaration.eraseMacroScopes = name := by
    rw [Node.mem_leanDecls]
    simp [Node.externalAssociationSnapshots, fields.1, fields.2]
  rw [assemble_ok_leanDecls_literate h hb, baseMembership]

/-- The same union expressed using the actual accepted resolver declaration projection. -/
theorem assemble_ok_leanDecls_view {label : Label} {payloads : Array NodeContribution}
    {records : List Record} {assembled : Assembly} {base : Node}
    (h : assemble label payloads records = .ok assembled)
    (hb : Node.applyContributions label {} payloads = .ok base)
    (name : Name) :
    name ∈ assembled.node.leanDecls ↔ name ∈ assembled.view.declarations ∨ name ∈ base.leanDecls := by
  rw [assemble_ok_leanDecls h hb]
  rw [resolverLaws.association_exact label records assembled.view (assemble_ok_resolve h) name]

end Informal.NodeAssembly
