/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Contributions.Laws
import VersoBlueprint.NodeAssembly

/-! Acceptance and inventory-projection laws for the production node assembler. -/

namespace Informal.NodeAssembly

open Lean Informal.Data Informal.Contributions

/-- The executable name check is exact over every selected observation, including
missing references and all named facets. -/
theorem referenceNameErrors_isEmpty_iff (label : Label) (records : List Record) :
    (referenceNameErrors label records).isEmpty = true ↔ StableReferences records label := by
  simp [referenceNameErrors, List.flatMap_eq_nil_iff, StableReferences, recordsFor]

theorem referenceNameErrors_eq_empty_iff (label : Label) (records : List Record) :
    referenceNameErrors label records = #[] ↔ StableReferences records label := by
  simpa only [Array.isEmpty_iff] using referenceNameErrors_isEmpty_iff label records

/-- The final admission check succeeds exactly when raw keyed destinations are
valid and every retained native name is stable under the next erasure. -/
theorem admissionErrors_isEmpty_iff (label : Label) (payloads : Array SourceData.Registration)
    (records : List Record) :
    (admissionErrors label payloads records).isEmpty = true ↔
      (sourceDestinationIssues label payloads records).isEmpty = true ∧
        StableReferences records label := by
  simp only [admissionErrors, Array.isEmpty_iff, Array.append_eq_empty_iff]
  constructor
  · rintro ⟨hsource, hnames⟩
    exact ⟨hsource, (referenceNameErrors_eq_empty_iff label records).mp hnames⟩
  · rintro ⟨hsource, hstable⟩
    exact ⟨hsource, (referenceNameErrors_eq_empty_iff label records).mpr hstable⟩

/-- Successful admission proves stability for every selected native name. -/
theorem assemble_ok_stableReferences {label : Label} {payloads : Array SourceData.Registration}
    {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled) : StableReferences records label := by
  unfold assemble at h
  cases hn : Node.applyRegistrations label {} payloads with
  | error _ => simp [hn] at h
  | ok node =>
    cases hr : resolve label records with
    | error _ => simp [hn, hr] at h
    | ok view =>
      simp only [hn, hr] at h
      split at h
      · rename_i hadmission
        exact ((admissionErrors_isEmpty_iff label payloads records).mp hadmission).2
      · contradiction

/-- A successful assembly exposes both halves of the final admission guard. -/
theorem assemble_ok_admissionErrors {label : Label} {payloads : Array SourceData.Registration}
    {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled) :
    (admissionErrors label payloads records).isEmpty = true := by
  unfold assemble at h
  cases hn : Node.applyRegistrations label {} payloads with
  | error _ => simp [hn] at h
  | ok node =>
    cases hr : resolve label records with
    | error _ => simp [hn, hr] at h
    | ok view =>
      by_cases he : (admissionErrors label payloads records).isEmpty = true
      · exact he
      · simp [hn, hr, he] at h

/-- The projection does not rewrite the payload source inventory. -/
theorem assemble_ok_sources {label : Label} {payloads : Array SourceData.Registration}
    {records : List Record} {assembled : Assembly} {base : Node}
    (h : assemble label payloads records = .ok assembled)
    (hb : Node.applyRegistrations label {} payloads = .ok base) :
    assembled.node.sources = base.sources := by
  unfold assemble at h
  rw [hb] at h
  cases hr : resolve label records with
  | error _ => simp [hr] at h
  | ok view =>
    by_cases he : (admissionErrors label payloads records).isEmpty = true
    · simp [hr, he] at h
      cases h
      rfl
    · simp [hr, he] at h

/-- Successful assembly returns the actual resolver result as its accepted view. -/
theorem assemble_ok_resolve {label : Label} {payloads : Array SourceData.Registration}
    {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled) :
    resolve label records = .ok assembled.view := by
  unfold assemble at h
  cases hn : Node.applyRegistrations label {} payloads with
  | error _ => simp [hn] at h
  | ok node =>
    cases hr : resolve label records with
    | error _ => simp [hn, hr] at h
    | ok view =>
      by_cases he : (admissionErrors label payloads records).isEmpty = true
      · simp [hn, hr, he] at h
        cases h
        rfl
      · simp [hn, hr, he] at h

/-- Raw destination validation is necessary for accepted production state. -/
theorem assemble_ok_sourceDestinations {label : Label} {payloads : Array SourceData.Registration}
    {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled) :
    (sourceDestinationIssues label payloads records).isEmpty = true := by
  unfold assemble at h
  cases hn : Node.applyRegistrations label {} payloads with
  | error _ => simp [hn] at h
  | ok node =>
    cases hr : resolve label records with
    | error _ => simp [hn, hr] at h
    | ok view =>
      have he := assemble_ok_admissionErrors h
      exact ((admissionErrors_isEmpty_iff label payloads records).mp he).1

/-- Assembly accepts exactly when payloads, complete evidence and raw native
sources agree. Authored-origin validity belongs to the environment boundary;
actual composed membership and selected-name admission are separate obligations. -/
theorem assemble_success_iff (label : Label) (payloads : Array SourceData.Registration)
    (records : List Record) :
    (∃ assembled, assemble label payloads records = .ok assembled) ↔
      (∃ node, Node.applyRegistrations label {} payloads = .ok node) ∧
        (NoCollision records label ∧ ¬ PriorityDisagreement records label) ∧
        ((sourceDestinationIssues label payloads records).isEmpty = true ∧
          StableReferences records label) := by
  constructor
  · rintro ⟨assembled, h⟩
    have accepted := (resolverLaws.success_iff label records).mp
      ⟨assembled.view, assemble_ok_resolve h⟩
    have admitted := (admissionErrors_isEmpty_iff label payloads records).mp
      (assemble_ok_admissionErrors h)
    refine ⟨?_, accepted, ⟨admitted.1, admitted.2⟩⟩
    unfold assemble at h
    cases hn : Node.applyRegistrations label {} payloads with
    | error _ => simp [hn] at h
    | ok node => exact ⟨node, rfl⟩
  · rintro ⟨⟨node, hn⟩, accepted, ⟨hs, hstable⟩⟩
    obtain ⟨view, hr⟩ := (resolverLaws.success_iff label records).mpr accepted
    have he := (admissionErrors_isEmpty_iff label payloads records).mpr ⟨hs, hstable⟩
    simp only [assemble, hn, hr, he, ite_true]
    exact ⟨_, rfl⟩

/-- A successful production assembly exposes the resolver's accepted priority. -/
theorem assemble_ok_priority {label : Label} {payloads : Array SourceData.Registration}
    {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled) :
    assembled.node.priority = assembled.view.priority := by
  unfold assemble at h
  cases hn : Node.applyRegistrations label {} payloads with
  | error _ => simp [hn] at h
  | ok node =>
    cases hr : resolve label records with
    | error _ => simp [hn, hr] at h
    | ok view =>
      by_cases he : (admissionErrors label payloads records).isEmpty = true
      · simp [hn, hr, he] at h
        cases h
        rfl
      · simp [hn, hr, he] at h

/-- The returned node has no priority exactly when no input record claims one. -/
theorem assemble_ok_priority_none_iff {label : Label} {payloads : Array SourceData.Registration}
    {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled) :
    assembled.node.priority = none ↔ ∀ value, ¬ Priority records label value := by
  rw [assemble_ok_priority h]
  exact resolverLaws.priority_none_iff label records assembled.view (assemble_ok_resolve h)

/-- The returned priority is claimed by the input and agrees with every input claim. -/
theorem assemble_ok_priority_some_iff {label : Label} {payloads : Array SourceData.Registration}
    {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled) (value : String) :
    assembled.node.priority = some value ↔
      Priority records label value ∧ ∀ other, Priority records label other → other = value := by
  rw [assemble_ok_priority h]
  exact resolverLaws.priority_some_iff label records assembled.view (assemble_ok_resolve h) value

/-- A successful production assembly retains exactly the resolver's supports. -/
theorem assemble_ok_supports {label : Label} {payloads : Array SourceData.Registration}
    {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled) (record : Record) :
    record ∈ assembled.view.supports ↔ record ∈ records ∧ record.label = label := by
  exact resolverLaws.supports_exact label records assembled.view (assemble_ok_resolve h) record

/-- The assembled node retains every native association from every accepted support,
including associations attached to arbitrary named facets. -/
theorem assemble_ok_nativeAssociations {label : Label} {payloads : Array SourceData.Registration}
    {records : List Record} {assembled : Assembly}
    (h : assemble label payloads records = .ok assembled) :
    assembled.node.nativeAssociations = assembled.view.supports.toArray.flatMap (·.nativeAssociations) := by
  unfold assemble at h
  cases hn : Node.applyRegistrations label {} payloads with
  | error _ => simp [hn] at h
  | ok node =>
    cases hr : resolve label records with
    | error _ => simp [hn, hr] at h
    | ok view =>
      by_cases he : (admissionErrors label payloads records).isEmpty = true
      · simp [hn, hr, he] at h
        cases h
        rfl
      · simp [hn, hr, he] at h

end Informal.NodeAssembly
