/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintValidationLaws.AxiomPolicy
import VersoBlueprint.Realizations.Capture.NativeRequestLaws
import VersoBlueprint.Translations.SelectionLaws
import VersoBlueprint.Environment.AdmissionLaws

-- One reviewed inventory drives both enforcement and dependency reporting.
-- Keep the expected count in sync when adding or deliberately retiring endpoints.
private def validationAxiomTargets : Array Lean.Name := #[
  ``Informal.Validation.Evidence.mismatch?_eq_none_iff,
  ``Informal.Validation.Evidence.accepted_requirement,
  ``Informal.Validation.Evidence.accepted_binding,
  ``Informal.Validation.Evidence.rejects_changed_binding,
  ``Informal.Validation.Evidence.accepted_proof,
  ``Informal.Validation.Evidence.accepted_review,
  ``Informal.Validation.Evidence.accepted_native_check,
  ``Informal.Validation.Evidence.mismatch?_prerequisites,

  ``Informal.QSortLaws.qsort_perm,
  ``Informal.Realizations.mem_canonical,
  ``Informal.Realizations.canonical_eq_empty_iff,
  ``Informal.Translations.Registry.complete_requires_all,
  ``Informal.Translations.Registry.empty_requirements_not_complete,
  ``Informal.Translations.Registry.unfinished_requirement_not_complete,
  ``Informal.Translations.Registry.complete_hasSubject,


  -- Admission and prerequisite soundness.
  ``Informal.Translations.admit_sources,
  ``Informal.Translations.admit_requirement_mem,
  ``Informal.Translations.admit_evidence_mem,
  ``Informal.Translations.admit_realization_mem,
  ``Informal.Translations.admit_translation_mem,
  ``Informal.Translations.admit_claim_mem,
  ``Informal.Translations.admit_document_mem,
  ``Informal.Translations.admit_object_mem,
  ``Informal.Translations.admit_bindingInput_mem,
  ``Informal.Translations.admit_requiredFor_realization,
  ``Informal.Translations.admit_requiredFor_declaration,
  ``Informal.Translations.admit_requiredFor_claim,
  ``Informal.Translations.admit_requiredFor_translation,
  ``Informal.Translations.mem_realization_requirements,
  ``Informal.Translations.admit_complete_realization_requires,
  ``Informal.Translations.admit_local_complete_evidence,
  ``Informal.Translations.admit_complete_induction,
  ``Informal.Translations.admit_complete_requirement_local,
  ``Informal.Translations.admit_complete_requirement_evidence,
  ``Informal.Translations.admit_complete_selected_evidence,
  ``Informal.Translations.admit_stale_evidence_incomplete,
  ``Informal.Translations.admit_requirements_agree,
  ``Informal.Translations.admit_realizations_agree,
  ``Informal.Translations.admit_translations_agree,
  ``Informal.Translations.admit_claims_agree,
  ``Informal.Translations.admit_requirement_lookup_iff,
  ``Informal.Translations.admit_realization_lookup_iff,
  ``Informal.Translations.admit_translation_lookup_iff,
  ``Informal.Translations.admit_claim_lookup_iff,
  ``Informal.Translations.admit_complete_authored_realization_requires,
  ``Informal.Translations.admit_realization_requirement_exists,
  ``Informal.Translations.admit_requiredFor_facet_mem_iff,
  ``Informal.Translations.admit_complete_accessible,
  ``Informal.Translations.admit_complete_prerequisites_local,
  ``Informal.Translations.admit_complete_prerequisites_evidence,
  ``Informal.Translations.admit_cycle_incomplete,
  ``Informal.Translations.admit_reachable_cycle_incomplete,
  ``Informal.Translations.admit_complete_authored_realization_evidence,
  ``Informal.Translations.admit_bindings_evidence,
  ``Informal.Translations.admit_complete_proof_sources,

  -- Production capture and assessments.
  ``Informal.Realizations.Capture.evaluate_admitted,
  ``Informal.Realizations.Capture.Snapshot.assessment_complete_result,
  ``Informal.Realizations.Capture.Snapshot.assessment_complete_native,
  ``Informal.Realizations.Capture.evaluate_assessment_evidence,
  ``Informal.Realizations.Capture.evaluate_native_statement_evidence,
  ``Informal.Realizations.Capture.evaluate_native_proof_evidence,
  ``Informal.Realizations.Capture.evaluate_valid_handles,

  -- Prerequisite selection.
  ``Informal.Translations.Registry.selectRequirement_matches,
  ``Informal.Translations.admit_selection_matches,
  ``Informal.Translations.Registry.selectRequirement_congr,
  ``Informal.Translations.admit_selection_sources,

  -- Actual NameMap comparator.
  ``Informal.NameMapLaws.quickCmp_trans,
  ``Informal.NameMapLaws.quickCmp_lawfulEq,
  ``Informal.NameMapLaws.get?_insert,
  ``Informal.NameMapLaws.getD_insert,
  ``Informal.NameMapLaws.getD_insert_self,

  -- Pure environment admission.
  ``Informal.Environment.State.addNode_no_resurrection,
  ``Informal.Environment.State.addNode_assembled,
  ``Informal.Environment.State.addNode_records,
  ``Informal.Environment.State.addNode_other_labels,
  ``Informal.Environment.State.addNode_frame,
  ``Informal.Environment.State.addNode_count,
  ``Informal.Environment.State.addNode_nativeAssociations,
  ``Informal.Environment.State.addNode_success_iff,
  ``Informal.Environment.State.addNode_declaration_index,

  -- Complete imported-state rebuild and raw decoding.
  ``Informal.NameMapLaws.mem_toArray,
  ``Informal.NameMapLaws.get?_empty,
  ``Informal.Environment.State.reassembleImported_node_iff,
  ``Informal.Environment.State.reassembleImported_conflicted_absent,
  ``Informal.Environment.State.reassembleImported_unknown_absent,
  ``Informal.Environment.State.reassembleImported_declaration_index,
  ``Informal.Environment.State.reassembleImported_conflicted_unindexed,
  ``Informal.Environment.State.reassembleImported_frame,
  ``Informal.Environment.State.collectImportedEntry_unpublished,
  ``Informal.Environment.State.collectImportedEntry_records,
  ``Informal.Environment.State.collectImportedEntry_registrations,
  ``Informal.Environment.State.collectImportedEntries_unpublished,
  ``Informal.Environment.State.reassembleImported_no_resurrection,

  -- Observation-table acceptance and original-result provenance.
  ``Informal.Realizations.Capture.indexResults_lookup_iff,
  ``Informal.Realizations.Capture.indexResults_success_iff,
  ``Informal.Realizations.Capture.lookupResult_success_iff,
  ``Informal.Realizations.Capture.indexResults_success_permutation,
  ``Informal.Realizations.Capture.indexResults_lookup_permutation,

  -- Named index invariant and exact remaining local-update condition.
  ``Informal.Environment.State.reassembleImported_index_coherent,
  ``Informal.Environment.State.addNode_index_coherent_iff,

  -- Production source accumulation and supported-state coherence.
  ``Informal.NodeAssembly.applyRegistrations_sources,
  ``Informal.NodeAssembly.applyRegistrations_source_mem,
  ``Informal.NodeAssembly.assemble_ok_source_inventory,
  ``Informal.NodeAssembly.assemble_ok_leanDecls_input,
  ``Informal.NodeAssembly.assemble_leanDecls_monotone,
  ``Informal.NameMapLaws.getD_of_get?_eq_some,
  ``Informal.Environment.State.reassembleImported_nodes_match,
  ``Informal.Environment.State.addNode_declarations_preserved,
  ``Informal.Environment.State.addNode_index_coherent,
  ``Informal.Environment.State.addNode_after_import_index_coherent,
  ``Informal.Environment.State.addNode_nodes_match,
  ``Informal.Environment.State.addNode_coherent,

  -- Actual finalization provenance and same-candidate binding.
  ``Informal.Realizations.Capture.finish_binding_basis,
  ``Informal.Realizations.Capture.finish_sources,
  ``Informal.Realizations.Capture.finish_evidence_iff,
  ``Informal.Realizations.Capture.finish_observation_current,

  -- Exact admission, absence, and finite registration histories.
  ``Informal.Environment.State.reassembleImported_admission_coherent,
  ``Informal.Environment.State.addNode_admission_coherent,
  ``Informal.Environment.State.AdmissionCoherent.node_iff,
  ``Informal.Environment.State.AdmissionCoherent.nodes_match,
  ``Informal.Environment.State.AdmissionCoherent.conflicted_absent,
  ``Informal.Environment.State.AdmissionCoherent.unknown_absent,
  ``Informal.Environment.State.admission_sequence_coherent,

  -- Native provider results through the actual recipe and final admitted evidence.
  ``Informal.Realizations.Capture.finish_nativeChecks,
  ``Informal.Realizations.Capture.evaluate_nativeChecks_source,
  ``Informal.Realizations.Capture.evaluate_native_evidence_source,

  -- Authored provider lineage and end-to-end completion suitability.
  ``Informal.Realizations.Capture.evaluate_proof_evidence_source,
  ``Informal.Realizations.Capture.evaluate_complete_proof_provider,

  -- Joint authored projections and the main pure-capture completion contract.
  ``Informal.Realizations.Capture.AuthoredProofProjection,
  ``Informal.Realizations.Capture.evaluate_assessment_justified,

  -- Generated dependency-selection provenance, exact scope, diagnostics and completion.
  ``Informal.Realizations.Capture.DependencySelection.edges,
  ``Informal.Realizations.Capture.DependencySelection.mem_edges,
  ``Informal.Realizations.Capture.DependencySelection.failures,
  ``Informal.Realizations.Capture.DependencySelection.Source,
  ``Informal.Realizations.Capture.DependencySelection.Source.validator,
  ``Informal.Realizations.Capture.DependencySelection.failures_empty_iff,
  ``Informal.Realizations.Capture.DependencySelection.mem_failures,
  ``Informal.Realizations.Capture.DependencySelection.Source.outcomes,
  ``Informal.Realizations.Capture.finish_uses,
  ``Informal.Realizations.Capture.evaluate_dependency_selection_source,
  ``Informal.Realizations.Capture.evaluate_complete_dependency_selection,

  -- Exact native target-selector acceptance and original contract membership.
  ``Informal.Realizations.Capture.TargetSelection.DeclarationValid,
  ``Informal.Realizations.Capture.TargetSelection.Contract,
  ``Informal.Realizations.Capture.selectTarget_ok_iff,
  ``Informal.Realizations.Capture.selectTarget_membership,
  ``Informal.Realizations.Capture.selectTarget_models_agree,
  ``Informal.Realizations.Capture.selectTarget_nonempty,
  ``Informal.Realizations.Capture.selectTarget_native_requirements,

  -- Successful emitted edges use the actual selector and source-owned Lean context.
  ``Informal.Realizations.Capture.selectUses_success_source,
  ``Informal.Realizations.Capture.selectUses_success_contract,
  ``Informal.Realizations.Capture.selectUses_success_nonempty,
  ``Informal.Realizations.Capture.selectUses_success_native_requirements,
  ``Informal.Realizations.Capture.finish_use_success_contract,

  -- Selected contracts survive actual wiring and final admission into real lookups.
  ``Informal.Realizations.Capture.finish_preserves_selection,
  ``Informal.Realizations.Capture.TargetSelection.Retained,
  ``Informal.Realizations.Capture.finish_use_target_retained,
  ``Informal.Realizations.Capture.evaluate_use_target_retained,
  ``Informal.Realizations.Capture.evaluate_complete_dependency_targets,

  -- Generated gates and selected keys are prerequisites of their native owner.
  ``Informal.Realizations.Capture.instReflBEqOrigin,
  ``Informal.Realizations.Capture.instLawfulBEqOrigin,
  ``Informal.Realizations.Capture.DependencySelection.GeneratedAt,
  ``Informal.Realizations.Capture.DependencySelection.Wired,
  ``Informal.Realizations.Capture.DependencySelection.Wired.source,
  ``Informal.Realizations.Capture.evaluate_dependency_selection_wired,
  ``Informal.Realizations.Capture.evaluate_complete_dependency_wiring,

  -- Positive creation, including unavailable gates; raw input need not be admitted.
  ``Informal.Realizations.Capture.DependencySelection.CollectorOwned,
  ``Informal.Realizations.Capture.finish_original_expectations_agree,
  ``Informal.Realizations.Capture.finish_native_dependency_gate_created,
  ``Informal.Realizations.Capture.finish_closure_contract_source,
  ``Informal.Realizations.Capture.evaluate_native_dependency_gate_created,

  -- Completed native parents justify exact scoped target obligations.
  ``Informal.Realizations.Capture.DependencySelection.Wired.for_contract,
  ``Informal.Realizations.Capture.evaluate_local_dependency_selection_for_contract,
  ``Informal.Realizations.Capture.evaluate_native_dependencies_justified,
  ``Informal.Realizations.Capture.evaluate_failed_native_dependency_incomplete,

  -- Every collected use reaches its actual context-specific selection or diagnostic.
  ``Informal.Realizations.Capture.useRef_mergeByLabel_labels,
  ``Informal.Realizations.Capture.UseSelection.Matches,
  ``Informal.Realizations.Capture.UseSelection.ContextFor,
  ``Informal.Realizations.Capture.selectUses_in_context,
  ``Informal.Realizations.Capture.selectUses_without_context,
  ``Informal.Realizations.Capture.finish_use_in_context,
  ``Informal.Realizations.Capture.finish_use_without_context,
  ``Informal.Realizations.Capture.finish_use_in_native_scope,
  ``Informal.Realizations.Capture.finish_collected_use_justified,

  -- Exact ordinary source-use inventory through collection and public evaluation.
  ``Informal.Realizations.Capture.collectOrdinary_uses,
  ``Informal.Realizations.Capture.collectAuthored_uses,
  ``Informal.Realizations.Capture.assemble_uses,
  ``Informal.Realizations.Capture.evaluate_use_collection,
  ``Informal.Realizations.Capture.evaluate_use_in_context,
  ``Informal.Realizations.Capture.evaluate_use_without_context,
  ``Informal.Realizations.Capture.evaluate_ordinary_use_justified,

  -- Actual raw-to-plan preservation and accepted-node lookup connection.
  ``Informal.Realizations.Capture.plan_raw,
  ``Informal.Realizations.Capture.plan_ordinary_nodes,
  ``Informal.Realizations.Capture.plan_ordinary_uses,
  ``Informal.Realizations.Capture.Raw.ofState_use_iff,
  ``Informal.Realizations.Capture.evaluate_raw_use_in_context,
  ``Informal.Realizations.Capture.evaluate_raw_use_without_context,
  ``Informal.Realizations.Capture.evaluate_raw_use_justified,

  -- Exact ordinary contract creation and retention through public evaluation.
  ``Informal.Realizations.Capture.collectOrdinary_requirements,
  ``Informal.Realizations.Capture.collectAuthored_requirements,
  ``Informal.Realizations.Capture.assemble_nativeRequirements,
  ``Informal.Realizations.Capture.evaluate_nativeRequirements,
  ``Informal.Realizations.Capture.evaluate_native_contract_created,
  ``Informal.Realizations.Capture.evaluate_planned_use_justified,

  -- Joint model inventory, authored enrichment and final membership creation.
  ``Informal.Realizations.Capture.collectOrdinary_modelInventory,
  ``Informal.Realizations.Capture.collectAuthored_modelInventory,
  ``Informal.Realizations.Capture.assemble_modelInventory,
  ``Informal.Realizations.Capture.evaluate_modelInventory,
  ``Informal.Realizations.Capture.evaluate_model_created,
  ``Informal.Realizations.Capture.evaluate_declared_use_justified,

  -- The real planner preserves sources and enumerates their declarations exactly.
  ``Informal.Realizations.Capture.plan_realization_sources,
  ``Informal.Realizations.Capture.plan_realization_fields,
  ``Informal.Realizations.Capture.plan_declaration_names,
  ``Informal.Realizations.Capture.plan_declaration_mem_iff,
  ``Informal.Realizations.Capture.plan_raw_realization,
  ``Informal.Realizations.Capture.evaluate_raw_source_use_justified,

  -- Source-facing proof-key coverage through the actual public assessment.
  ``Informal.Translations.Input.DeclarationRequires,
  ``Informal.Realizations.Capture.collectOrdinary_declarationRequired,
  ``Informal.Realizations.Capture.collectAuthored_declarationRequired,
  ``Informal.Realizations.Capture.assemble_declarationRequired,
  ``Informal.Realizations.Capture.evaluate_declarationRequired,
  ``Informal.Realizations.Capture.evaluate_native_proof_selected,
  ``Informal.Realizations.Capture.evaluate_raw_native_proof_selected,
  ``Informal.Realizations.Capture.evaluate_raw_assessment_declaration_justified,

  -- Facet source union and selected contracts through the actual public queries.
  ``Informal.Translations.Input.FacetRequires,
  ``Informal.Realizations.Capture.nativeNames_mem_iff,
  ``Informal.Realizations.Capture.nativeNames_filter_subset,
  ``Informal.Realizations.Capture.collectOrdinary_facetRequired,
  ``Informal.Realizations.Capture.collectAuthored_facetRequired,
  ``Informal.Realizations.Capture.assemble_facetRequired,
  ``Informal.Realizations.Capture.evaluate_facetRequired,
  ``Informal.Realizations.Capture.evaluate_native_facet_selected,
  ``Informal.Realizations.Capture.evaluate_raw_native_facet_selected,
  ``Informal.Realizations.Capture.evaluate_raw_facet_declaration_justified,

  -- Authored goal selection from raw retained records through public completion.
  ``Informal.Translations.Input.ExpectedSelected,
  ``Informal.Realizations.Capture.collectAuthored_expectedSelected,
  ``Informal.Realizations.Capture.assemble_expectedSelected,
  ``Informal.Realizations.Capture.evaluate_expectedSelected,
  ``Informal.Realizations.Capture.evaluate_expected_selected,
  ``Informal.Realizations.Capture.plan_authored_record_mem_iff,
  ``Informal.Realizations.Capture.evaluate_raw_expected_selected,
  ``Informal.Realizations.Capture.evaluate_raw_assessment_expected_justified,

  -- Generated check handles preserve their exact declaration/project requests.
  ``Informal.Realizations.Capture.plan_declaration_check_request,
  ``Informal.Realizations.Capture.plan_declaration_check,
  ``Informal.Realizations.Capture.plan_declaration_check_job,
  ``Informal.Realizations.Capture.plan_raw_declaration_check,

  -- Authored goal positions retain their expected/specification/document chain.
  ``Informal.Realizations.Capture.AuthoredRequestChain,
  ``Informal.Realizations.Capture.plan_authored_goal_handles,
  ``Informal.Realizations.Capture.plan_authored_goal_request,
  ``Informal.Realizations.Capture.AuthoredRequestChain.jobs,
  ``Informal.Realizations.Capture.plan_raw_authored_goal_request,

  -- Native source positions preserve full associations at bounded observer jobs.
  ``Informal.Realizations.Capture.NativeRequestSequence,
  ``Informal.Realizations.Capture.NativeRequestSequence.job,
  ``Informal.Realizations.Capture.plan_native_request_sequence,
  ``Informal.Realizations.Capture.plan_native_requests,
  ``Informal.Realizations.Capture.plan_raw_native_request
]

run_cmd VersoBlueprintTests.Verification.AxiomPolicy.audit validationAxiomTargets 255
