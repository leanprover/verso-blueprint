/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Validation.Laws
import VersoBlueprint.Translations.Laws

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
