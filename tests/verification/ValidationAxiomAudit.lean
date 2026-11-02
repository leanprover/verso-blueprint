/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Capture.PlanLaws
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

-- Complete imported-state rebuild and raw decoding.
#print axioms Informal.NameMapLaws.mem_toArray
#print axioms Informal.NameMapLaws.get?_empty
#print axioms Informal.Environment.State.reassembleImported_node_iff
#print axioms Informal.Environment.State.reassembleImported_conflicted_absent
#print axioms Informal.Environment.State.reassembleImported_unknown_absent
#print axioms Informal.Environment.State.reassembleImported_declaration_index
#print axioms Informal.Environment.State.reassembleImported_conflicted_unindexed
#print axioms Informal.Environment.State.reassembleImported_frame
#print axioms Informal.Environment.State.collectImportedEntry_unpublished
#print axioms Informal.Environment.State.collectImportedEntry_records
#print axioms Informal.Environment.State.collectImportedEntry_registrations
#print axioms Informal.Environment.State.collectImportedEntries_unpublished
#print axioms Informal.Environment.State.reassembleImported_no_resurrection

-- Observation-table acceptance and original-result provenance.
#print axioms Informal.Realizations.Capture.indexResults_lookup_iff
#print axioms Informal.Realizations.Capture.indexResults_success_iff
#print axioms Informal.Realizations.Capture.lookupResult_success_iff
#print axioms Informal.Realizations.Capture.indexResults_success_permutation
#print axioms Informal.Realizations.Capture.indexResults_lookup_permutation

-- Named index invariant and exact remaining local-update condition.
#print axioms Informal.Environment.State.reassembleImported_index_coherent
#print axioms Informal.Environment.State.addNode_index_coherent_iff

-- Production source accumulation and supported-state coherence.
#print axioms Informal.NodeAssembly.applyRegistrations_sources
#print axioms Informal.NodeAssembly.applyRegistrations_source_mem
#print axioms Informal.NodeAssembly.assemble_ok_source_inventory
#print axioms Informal.NodeAssembly.assemble_ok_leanDecls_input
#print axioms Informal.NodeAssembly.assemble_leanDecls_monotone
#print axioms Informal.NameMapLaws.getD_of_get?_eq_some
#print axioms Informal.Environment.State.reassembleImported_nodes_match
#print axioms Informal.Environment.State.addNode_declarations_preserved
#print axioms Informal.Environment.State.addNode_index_coherent
#print axioms Informal.Environment.State.addNode_after_import_index_coherent
#print axioms Informal.Environment.State.addNode_nodes_match
#print axioms Informal.Environment.State.addNode_coherent

-- Actual finalization provenance and same-candidate binding.
#print axioms Informal.Realizations.Capture.finish_binding_basis
#print axioms Informal.Realizations.Capture.finish_sources
#print axioms Informal.Realizations.Capture.finish_evidence_iff
#print axioms Informal.Realizations.Capture.finish_observation_current

-- Exact admission, absence, and finite registration histories.
#print axioms Informal.Environment.State.reassembleImported_admission_coherent
#print axioms Informal.Environment.State.addNode_admission_coherent
#print axioms Informal.Environment.State.AdmissionCoherent.node_iff
#print axioms Informal.Environment.State.AdmissionCoherent.nodes_match
#print axioms Informal.Environment.State.AdmissionCoherent.conflicted_absent
#print axioms Informal.Environment.State.AdmissionCoherent.unknown_absent
#print axioms Informal.Environment.State.admission_sequence_coherent

-- Native provider results through the actual recipe and final admitted evidence.
#print axioms Informal.Realizations.Capture.finish_nativeChecks
#print axioms Informal.Realizations.Capture.evaluate_nativeChecks_source
#print axioms Informal.Realizations.Capture.evaluate_native_evidence_source

-- Authored provider lineage and end-to-end completion suitability.
#print axioms Informal.Realizations.Capture.evaluate_proof_evidence_source
#print axioms Informal.Realizations.Capture.evaluate_complete_proof_provider

-- Joint authored projections and the main pure-capture completion contract.
#print axioms Informal.Realizations.Capture.AuthoredProofProjection
#print axioms Informal.Realizations.Capture.evaluate_assessment_justified

-- Generated dependency-selection provenance, exact scope, diagnostics and completion.
#print axioms Informal.Realizations.Capture.DependencySelection.edges
#print axioms Informal.Realizations.Capture.DependencySelection.mem_edges
#print axioms Informal.Realizations.Capture.DependencySelection.failures
#print axioms Informal.Realizations.Capture.DependencySelection.Source
#print axioms Informal.Realizations.Capture.DependencySelection.Source.validator
#print axioms Informal.Realizations.Capture.DependencySelection.failures_empty_iff
#print axioms Informal.Realizations.Capture.DependencySelection.mem_failures
#print axioms Informal.Realizations.Capture.DependencySelection.Source.outcomes
#print axioms Informal.Realizations.Capture.finish_uses
#print axioms Informal.Realizations.Capture.evaluate_dependency_selection_source
#print axioms Informal.Realizations.Capture.evaluate_complete_dependency_selection

-- Exact native target-selector acceptance and original contract membership.
#print axioms Informal.Realizations.Capture.TargetSelection.DeclarationValid
#print axioms Informal.Realizations.Capture.TargetSelection.Contract
#print axioms Informal.Realizations.Capture.selectTarget_ok_iff
#print axioms Informal.Realizations.Capture.selectTarget_membership
#print axioms Informal.Realizations.Capture.selectTarget_models_agree
#print axioms Informal.Realizations.Capture.selectTarget_nonempty
#print axioms Informal.Realizations.Capture.selectTarget_native_requirements

-- Successful emitted edges use the actual selector and source-owned Lean context.
#print axioms Informal.Realizations.Capture.selectUses_success_source
#print axioms Informal.Realizations.Capture.selectUses_success_contract
#print axioms Informal.Realizations.Capture.selectUses_success_nonempty
#print axioms Informal.Realizations.Capture.selectUses_success_native_requirements
#print axioms Informal.Realizations.Capture.finish_use_success_contract

-- Selected contracts survive actual wiring and final admission into real lookups.
#print axioms Informal.Realizations.Capture.finish_preserves_selection
#print axioms Informal.Realizations.Capture.TargetSelection.Retained
#print axioms Informal.Realizations.Capture.finish_use_target_retained
#print axioms Informal.Realizations.Capture.evaluate_use_target_retained
#print axioms Informal.Realizations.Capture.evaluate_complete_dependency_targets

-- Generated gates and selected keys are prerequisites of their native owner.
#print axioms Informal.Realizations.Capture.instReflBEqOrigin
#print axioms Informal.Realizations.Capture.instLawfulBEqOrigin
#print axioms Informal.Realizations.Capture.DependencySelection.GeneratedAt
#print axioms Informal.Realizations.Capture.DependencySelection.Wired
#print axioms Informal.Realizations.Capture.DependencySelection.Wired.source
#print axioms Informal.Realizations.Capture.evaluate_dependency_selection_wired
#print axioms Informal.Realizations.Capture.evaluate_complete_dependency_wiring

-- Positive creation, including unavailable gates; raw input need not be admitted.
#print axioms Informal.Realizations.Capture.DependencySelection.CollectorOwned
#print axioms Informal.Realizations.Capture.finish_original_expectations_agree
#print axioms Informal.Realizations.Capture.finish_native_dependency_gate_created
#print axioms Informal.Realizations.Capture.finish_closure_contract_source
#print axioms Informal.Realizations.Capture.evaluate_native_dependency_gate_created

-- Completed native parents justify exact scoped target obligations.
#print axioms Informal.Realizations.Capture.DependencySelection.Wired.for_contract
#print axioms Informal.Realizations.Capture.evaluate_local_dependency_selection_for_contract
#print axioms Informal.Realizations.Capture.evaluate_native_dependencies_justified
#print axioms Informal.Realizations.Capture.evaluate_failed_native_dependency_incomplete

-- Every collected use reaches its actual context-specific selection or diagnostic.
#print axioms Informal.Realizations.Capture.useRef_mergeByLabel_labels
#print axioms Informal.Realizations.Capture.UseSelection.Matches
#print axioms Informal.Realizations.Capture.UseSelection.ContextFor
#print axioms Informal.Realizations.Capture.selectUses_in_context
#print axioms Informal.Realizations.Capture.selectUses_without_context
#print axioms Informal.Realizations.Capture.finish_use_in_context
#print axioms Informal.Realizations.Capture.finish_use_without_context
#print axioms Informal.Realizations.Capture.finish_use_in_native_scope
#print axioms Informal.Realizations.Capture.finish_collected_use_justified

-- Exact ordinary source-use inventory through collection and public evaluation.
#print axioms Informal.Realizations.Capture.collectOrdinary_uses
#print axioms Informal.Realizations.Capture.collectAuthored_uses
#print axioms Informal.Realizations.Capture.assemble_uses
#print axioms Informal.Realizations.Capture.evaluate_use_collection
#print axioms Informal.Realizations.Capture.evaluate_use_in_context
#print axioms Informal.Realizations.Capture.evaluate_use_without_context
#print axioms Informal.Realizations.Capture.evaluate_ordinary_use_justified

-- Actual raw-to-plan preservation and accepted-node lookup connection.
#print axioms Informal.Realizations.Capture.plan_raw
#print axioms Informal.Realizations.Capture.plan_ordinary_nodes
#print axioms Informal.Realizations.Capture.plan_ordinary_uses
#print axioms Informal.Realizations.Capture.Raw.ofState_use_iff
#print axioms Informal.Realizations.Capture.evaluate_raw_use_in_context
#print axioms Informal.Realizations.Capture.evaluate_raw_use_without_context
#print axioms Informal.Realizations.Capture.evaluate_raw_use_justified
