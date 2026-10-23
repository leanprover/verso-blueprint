/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Contributions.Laws
import VersoBlueprint.NodeAssembly

/-! Acceptance and selected-projection laws for the production node assembler. -/

namespace Informal.NodeAssembly

open Lean Informal.Data Informal.Contributions

/-- The executable admission check is exact for both facets, including missing references. -/
theorem referenceNameErrors_isEmpty_iff (label : Label) (records : List Record) :
    (referenceNameErrors label records).isEmpty = true ↔ StableReferences records label := by
  simp [referenceNameErrors, List.flatMap_eq_nil_iff, StableReferences, recordsFor]

/-- Every accepted assembly has checked stable one-pass declaration keys.
This guarantee applies equally to local registrations and imported reassembly. -/
theorem assemble_ok_stableReferences {label : Label} {payloads : Array NodeContribution}
    {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled) : StableReferences records label := by
  unfold assemble at h
  cases hn : Node.applyContributions label {} payloads with
  | error _ => simp [hn] at h
  | ok node =>
    cases hr : resolve label records with
    | error _ => simp [hn, hr] at h
    | ok view =>
      simp only [hn, hr] at h
      split at h
      · rename_i hstable
        exact (referenceNameErrors_isEmpty_iff label records).mp hstable
      · contradiction

/-- Successful assembly returns the actual resolver result as its accepted view. -/
theorem assemble_ok_resolve {label : Label} {payloads : Array NodeContribution}
    {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled) :
    resolve label records = .ok assembled.view := by
  unfold assemble at h
  cases hn : Node.applyContributions label {} payloads with
  | error _ => simp [hn] at h
  | ok node =>
    cases hr : resolve label records with
    | error _ => simp [hn, hr] at h
    | ok view =>
      simp only [hn, hr] at h
      split at h
      · cases h
        rfl
      · contradiction

/-- Assembly accepts exactly when payload reduction, complete evidence resolution,
and the selected-reference name check all succeed. Authored-origin validity
belongs to the environment's admission boundary. -/
theorem assemble_success_iff (label : Label) (payloads : Array NodeContribution)
    (records : List Record) :
    (∃ assembled, assemble label payloads records = .ok assembled) ↔
      (∃ node, Node.applyContributions label {} payloads = .ok node) ∧
        NoCollision records label ∧ ¬ PriorityDisagreement records label ∧
        StableReferences records label := by
  constructor
  · rintro ⟨assembled, h⟩
    have accepted := (resolverLaws.success_iff label records).mp
      ⟨assembled.view, assemble_ok_resolve h⟩
    refine ⟨?_, accepted.1, accepted.2, assemble_ok_stableReferences h⟩
    unfold assemble at h
    cases hn : Node.applyContributions label {} payloads with
    | error _ => simp [hn] at h
    | ok node => exact ⟨node, rfl⟩
  · rintro ⟨⟨node, hn⟩, hc, hp, hs⟩
    obtain ⟨view, hr⟩ := (resolverLaws.success_iff label records).mpr ⟨hc, hp⟩
    have he := (referenceNameErrors_isEmpty_iff label records).mpr hs
    simp only [assemble, hn, hr, he, ↓reduceIte]
    exact ⟨_, rfl⟩

/-- A successful production assembly exposes the resolver's accepted priority. -/
theorem assemble_ok_priority {label : Label} {payloads : Array NodeContribution}
    {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled) :
    assembled.node.priority = assembled.view.priority := by
  unfold assemble at h
  cases hn : Node.applyContributions label {} payloads with
  | error _ => simp [hn] at h
  | ok node =>
    cases hr : resolve label records with
    | error _ => simp [hn, hr] at h
    | ok view =>
      simp only [hn, hr] at h
      split at h
      · cases h
        rfl
      · contradiction

/-- The returned node has no priority exactly when no input record claims one. -/
theorem assemble_ok_priority_none_iff {label : Label} {payloads : Array NodeContribution}
    {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled) :
    assembled.node.priority = none ↔ ∀ value, ¬ Priority records label value := by
  rw [assemble_ok_priority h]
  exact resolverLaws.priority_none_iff label records assembled.view (assemble_ok_resolve h)

/-- The returned priority is claimed by the input and agrees with every input claim. -/
theorem assemble_ok_priority_some_iff {label : Label} {payloads : Array NodeContribution}
    {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled) (value : String) :
    assembled.node.priority = some value ↔
      Priority records label value ∧ ∀ other, Priority records label other → other = value := by
  rw [assemble_ok_priority h]
  exact resolverLaws.priority_some_iff label records assembled.view (assemble_ok_resolve h) value

/-- A successful production assembly retains exactly the resolver's supports. -/
theorem assemble_ok_supports {label : Label} {payloads : Array NodeContribution}
    {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled) (record : Record) :
    record ∈ assembled.view.supports ↔ record ∈ records ∧ record.label = label := by
  exact resolverLaws.supports_exact label records assembled.view (assemble_ok_resolve h) record

/-- Attribute-attachment capability is projected from every accepted support. -/
theorem assemble_ok_blueprintAttributeAttachments {label : Label}
    {payloads : Array NodeContribution} {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled) :
    assembled.node.blueprintAttributeAttachments =
      supportsHaveBlueprintAttributeAttachments assembled.view.supports := by
  unfold assemble at h
  cases hn : Node.applyContributions label {} payloads with
  | error _ => simp [hn] at h
  | ok node =>
    cases hr : resolve label records with
    | error _ => simp [hn, hr] at h
    | ok view =>
      simp only [hn, hr] at h
      split at h
      · cases h
        rfl
      · contradiction

/-- The assembled attribute capability is true exactly for accepted input evidence. -/
theorem assemble_ok_blueprintAttributeAttachments_iff {label : Label}
    {payloads : Array NodeContribution} {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled) :
    assembled.node.blueprintAttributeAttachments = true ↔
      ∃ record ∈ records, record.label = label ∧
        record.allReferences.any (fun ref => ref.origin == .blueprintAttr) = true := by
  rw [assemble_ok_blueprintAttributeAttachments h]
  simp only [supportsHaveBlueprintAttributeAttachments, List.any_eq_true]
  constructor
  · rintro ⟨record, hrecord, href⟩
    obtain ⟨hin, hlabel⟩ := (assemble_ok_supports h record).mp hrecord
    exact ⟨record, hin, hlabel, href⟩
  · rintro ⟨record, hin, hlabel, href⟩
    exact ⟨record, (assemble_ok_supports h record).mpr ⟨hin, hlabel⟩, href⟩

/-- Statement snapshots are projected only from the statement side of supports. -/
theorem assemble_ok_externalRefs {label : Label} {payloads : Array NodeContribution}
    {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled) :
    assembled.node.externalRefs = assembled.view.supports.foldl
      (fun refs record => ExternalRef.mergeSnapshots refs record.references) #[] := by
  unfold assemble at h
  cases hn : Node.applyContributions label {} payloads with
  | error _ => simp [hn] at h
  | ok node =>
    cases hr : resolve label records with
    | error _ => simp [hn, hr] at h
    | ok view =>
      simp only [hn, hr] at h
      split at h
      · cases h
        rfl
      · contradiction

/-- Proof snapshots are projected only from the proof side of supports. -/
theorem assemble_ok_proofExternalRefs {label : Label} {payloads : Array NodeContribution}
    {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled) :
    assembled.node.proofExternalRefs = assembled.view.supports.foldl
      (fun refs record => ExternalRef.mergeSnapshots refs record.proofReferences) #[] := by
  unfold assemble at h
  cases hn : Node.applyContributions label {} payloads with
  | error _ => simp [hn] at h
  | ok node =>
    cases hr : resolve label records with
    | error _ => simp [hn, hr] at h
    | ok view =>
      simp only [hn, hr] at h
      split at h
      · cases h
        rfl
      · contradiction

end Informal.NodeAssembly
