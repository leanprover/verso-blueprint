/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Capture.Laws
import VersoBlueprint.Translations.SelectionLaws
import VersoBlueprint.Environment.AdmissionLaws

-- Dependency inspection, not an automatic allowlist or provider verification.
#print axioms Informal.Validation.Evidence.mismatch?_eq_none_iff
#print axioms Informal.Validation.Evidence.accepted_requirement
#print axioms Informal.Validation.Evidence.accepted_binding
#print axioms Informal.Validation.Evidence.rejects_changed_binding
#print axioms Informal.Validation.Evidence.accepted_proof
#print axioms Informal.Validation.Evidence.accepted_review
#print axioms Informal.Validation.Evidence.accepted_native_check
#print axioms Informal.Validation.Evidence.mismatch?_prerequisites

#print axioms Informal.QSortLaws.qsort_perm
#print axioms Informal.Realizations.mem_canonical
#print axioms Informal.Realizations.canonical_eq_empty_iff
#print axioms Informal.Translations.Registry.complete_requires_all
#print axioms Informal.Translations.Registry.empty_requirements_not_complete
#print axioms Informal.Translations.Registry.unfinished_requirement_not_complete
#print axioms Informal.Translations.Registry.complete_hasSubject


-- Admission and prerequisite soundness.
#print axioms Informal.Translations.admit_sources
#print axioms Informal.Translations.admit_requirement_mem
#print axioms Informal.Translations.admit_evidence_mem
#print axioms Informal.Translations.admit_realization_mem
#print axioms Informal.Translations.admit_translation_mem
#print axioms Informal.Translations.admit_claim_mem
#print axioms Informal.Translations.admit_document_mem
#print axioms Informal.Translations.admit_object_mem
#print axioms Informal.Translations.admit_bindingInput_mem
#print axioms Informal.Translations.admit_requiredFor_realization
#print axioms Informal.Translations.admit_requiredFor_declaration
#print axioms Informal.Translations.admit_requiredFor_claim
#print axioms Informal.Translations.admit_requiredFor_translation
#print axioms Informal.Translations.mem_realization_requirements
#print axioms Informal.Translations.admit_complete_realization_requires
#print axioms Informal.Translations.admit_local_complete_evidence
#print axioms Informal.Translations.admit_complete_induction
#print axioms Informal.Translations.admit_complete_requirement_local
#print axioms Informal.Translations.admit_complete_requirement_evidence
#print axioms Informal.Translations.admit_complete_selected_evidence
#print axioms Informal.Translations.admit_stale_evidence_incomplete
#print axioms Informal.Translations.admit_requirements_agree
#print axioms Informal.Translations.admit_realizations_agree
#print axioms Informal.Translations.admit_translations_agree
#print axioms Informal.Translations.admit_claims_agree
#print axioms Informal.Translations.admit_requirement_lookup_iff
#print axioms Informal.Translations.admit_realization_lookup_iff
#print axioms Informal.Translations.admit_translation_lookup_iff
#print axioms Informal.Translations.admit_claim_lookup_iff
#print axioms Informal.Translations.admit_complete_authored_realization_requires
#print axioms Informal.Translations.admit_realization_requirement_exists
#print axioms Informal.Translations.admit_requiredFor_facet_mem_iff
#print axioms Informal.Translations.admit_complete_accessible
#print axioms Informal.Translations.admit_complete_prerequisites_local
#print axioms Informal.Translations.admit_complete_prerequisites_evidence
#print axioms Informal.Translations.admit_cycle_incomplete
#print axioms Informal.Translations.admit_reachable_cycle_incomplete
#print axioms Informal.Translations.admit_complete_authored_realization_evidence
#print axioms Informal.Translations.admit_bindings_evidence
#print axioms Informal.Translations.admit_complete_proof_sources

-- Production capture and assessments.
#print axioms Informal.Realizations.Capture.evaluate_admitted
#print axioms Informal.Realizations.Capture.Snapshot.assessment_complete_result
#print axioms Informal.Realizations.Capture.Snapshot.assessment_complete_native
#print axioms Informal.Realizations.Capture.evaluate_assessment_evidence
#print axioms Informal.Realizations.Capture.evaluate_native_statement_evidence
#print axioms Informal.Realizations.Capture.evaluate_native_proof_evidence
#print axioms Informal.Realizations.Capture.evaluate_valid_handles

-- Prerequisite selection.
#print axioms Informal.Translations.Registry.selectRequirement_matches
#print axioms Informal.Translations.admit_selection_matches
#print axioms Informal.Translations.Registry.selectRequirement_congr
#print axioms Informal.Translations.admit_selection_sources

-- Actual NameMap comparator.
#print axioms Informal.NameMapLaws.quickCmp_trans
#print axioms Informal.NameMapLaws.quickCmp_lawfulEq
#print axioms Informal.NameMapLaws.get?_insert
#print axioms Informal.NameMapLaws.getD_insert
#print axioms Informal.NameMapLaws.getD_insert_self

-- Pure environment admission.
#print axioms Informal.Environment.State.addNode_no_resurrection
#print axioms Informal.Environment.State.addNode_assembled
#print axioms Informal.Environment.State.addNode_records
#print axioms Informal.Environment.State.addNode_other_labels
#print axioms Informal.Environment.State.addNode_frame
#print axioms Informal.Environment.State.addNode_count
#print axioms Informal.Environment.State.addNode_nativeAssociations
#print axioms Informal.Environment.State.addNode_success_iff
#print axioms Informal.Environment.State.addNode_declaration_index
