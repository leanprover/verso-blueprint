/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoBlueprint.Contributions.Laws
public import VersoBlueprint.NodeAssembly
-- Laws inspect implementation bodies without exposing them to ordinary consumers.
import all VersoBlueprint.NodeAssembly

public section

/-! Laws for the production node assembler's selected association projection. -/

namespace Informal.NodeAssembly

open Lean Informal.Data Informal.Contributions

/-- A successful production assembly exposes the resolver's accepted priority. -/
theorem assemble_ok_priority {label : Label} {legacy : Array NodeContribution}
    {records : List Record} {assembled : Assembly}
    (h : assemble label legacy records = .ok assembled) :
    assembled.node.priority = assembled.view.priority := by
  unfold assemble at h
  cases hn : Node.applyContributions label {} legacy with
  | error _ => simp [hn] at h
  | ok node =>
    cases hr : resolve label records with
    | error _ => simp [hn, hr] at h
    | ok view =>
      simp [hn, hr] at h
      cases h
      rfl

/-- A successful production assembly retains exactly the resolver's supports. -/
theorem assemble_ok_supports {label : Label} {legacy : Array NodeContribution}
    {records : List Record} {assembled : Assembly}
    (h : assemble label legacy records = .ok assembled) (record : Record) :
    record ∈ assembled.view.supports ↔ record ∈ records ∧ record.label = label := by
  unfold assemble at h
  cases hn : Node.applyContributions label {} legacy with
  | error _ => simp [hn] at h
  | ok node =>
    cases hr : resolve label records with
    | error _ => simp [hn, hr] at h
    | ok view =>
      simp [hn, hr] at h
      cases h
      exact resolverLaws.supports_exact label records view hr record

/-- Attribute-attachment capability is projected from every accepted support. -/
theorem assemble_ok_blueprintAttributeAttachments {label : Label}
    {legacy : Array NodeContribution} {records : List Record} {assembled : Assembly}
    (h : assemble label legacy records = .ok assembled) :
    assembled.node.blueprintAttributeAttachments =
      supportsHaveBlueprintAttributeAttachments assembled.view.supports := by
  unfold assemble at h
  cases hn : Node.applyContributions label {} legacy with
  | error _ => simp [hn] at h
  | ok node =>
    cases hr : resolve label records with
    | error _ => simp [hn, hr] at h
    | ok view =>
      simp [hn, hr] at h
      cases h
      rfl

/-- The assembled attribute capability is true exactly for accepted input evidence. -/
theorem assemble_ok_blueprintAttributeAttachments_iff {label : Label}
    {legacy : Array NodeContribution} {records : List Record} {assembled : Assembly}
    (h : assemble label legacy records = .ok assembled) :
    assembled.node.blueprintAttributeAttachments = true ↔
      ∃ record ∈ records, record.label = label ∧
        record.references.any (fun ref => ref.origin == .blueprintAttr) = true := by
  rw [assemble_ok_blueprintAttributeAttachments h]
  simp only [supportsHaveBlueprintAttributeAttachments, List.any_eq_true]
  constructor
  · rintro ⟨record, hrecord, href⟩
    obtain ⟨hin, hlabel⟩ := (assemble_ok_supports h record).mp hrecord
    exact ⟨record, hin, hlabel, href⟩
  · rintro ⟨record, hin, hlabel, href⟩
    exact ⟨record, (assemble_ok_supports h record).mpr ⟨hin, hlabel⟩, href⟩

end Informal.NodeAssembly
