/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

-- Print production proof dependencies for review; this is not an automated allowlist check.
import VersoBlueprint.NodeAssembly.Laws
import VersoBlueprint.NodeAssembly.MembershipLaws
import VersoBlueprint.ExternalRef.Laws
import VersoBlueprint.ExternalRef.FoldLaws
import VersoBlueprint.Node.MembershipLaws

#print axioms Informal.Contributions.collectorLaws
#print axioms Informal.Contributions.resolverLaws
#print axioms Informal.Contributions.resolve_collect
#print axioms Informal.Contributions.independentAssociations
#print axioms Informal.NodeAssembly.referenceNameErrors_isEmpty_iff
#print axioms Informal.NodeAssembly.referenceNameErrors_eq_empty_iff
#print axioms Informal.NodeAssembly.admissionErrors_isEmpty_iff
#print axioms Informal.NodeAssembly.assemble_ok_stableReferences
#print axioms Informal.NodeAssembly.assemble_ok_admissionErrors
#print axioms Informal.NodeAssembly.assemble_ok_resolve
#print axioms Informal.NodeAssembly.assemble_ok_sourceDestinations
#print axioms Informal.NodeAssembly.assemble_success_iff
#print axioms Informal.NodeAssembly.assemble_ok_priority
#print axioms Informal.NodeAssembly.assemble_ok_priority_none_iff
#print axioms Informal.NodeAssembly.assemble_ok_priority_some_iff
#print axioms Informal.NodeAssembly.assemble_ok_supports
#print axioms Informal.NodeAssembly.assemble_ok_sources
#print axioms Informal.NodeAssembly.assemble_ok_nativeAssociations
#print axioms Informal.NodeAssembly.assemble_ok_nativeAssociations_membership
#print axioms Informal.NodeAssembly.assemble_ok_hasAttributeAssociations
#print axioms Informal.NodeAssembly.assemble_ok_leanDecls_sources
#print axioms Informal.NodeAssembly.assemble_ok_missingAssociation_mem

#print axioms Informal.Data.ExternalRef.mergeSnapshots_canonical_union
#print axioms Informal.Data.ExternalRef.mergeSnapshots_normalized
#print axioms Informal.Data.ExternalRef.mergeSnapshots_canonical_nodup
#print axioms Informal.Data.ExternalRef.mergeSnapshots_present_iff
#print axioms Informal.Data.ExternalRef.mergeSnapshots_ref_present_iff
#print axioms Informal.Data.ExternalRef.mergeSnapshots_normalized_fixed
#print axioms Informal.Data.ExternalRef.mergeSnapshots_fold_normalized
#print axioms Informal.Data.ExternalRef.mergeSnapshots_fold_membership
#print axioms Informal.Data.ExternalRef.mergeSnapshots_fold_canonical_nodup

#print axioms Informal.Data.Node.mem_leanDecls
#print axioms Informal.Data.Node.associatedExternalRefs_fixed
