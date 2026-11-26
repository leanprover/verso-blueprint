/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintValidationLaws.AxiomPolicy
import VersoBlueprintTests.BlueprintValidationLaws.AxiomPolicyFixtures

open VersoBlueprintTests.Verification

-- The real checker accepts the standard axioms and an axiom-free declaration.
run_cmd AxiomPolicy.audit #[``propext, ``Classical.choice, ``Quot.sound, ``True.intro] 4

/-- error: Axiom audit: 'VersoBlueprintTests.Verification.AxiomPolicyFixtures.usesDomainAssumption' uses forbidden axioms [VersoBlueprintTests.Verification.AxiomPolicyFixtures.forbiddenDomainAssumption] -/
#guard_msgs in
run_cmd AxiomPolicy.audit #[``AxiomPolicyFixtures.usesDomainAssumption] 1

/-- error: Axiom audit: 'VersoBlueprintTests.Verification.AxiomPolicyFixtures.usesSorry' uses forbidden axioms [sorryAx] -/
#guard_msgs in
run_cmd AxiomPolicy.audit #[``AxiomPolicyFixtures.usesSorry] 1

/-- error: Axiom audit: unknown checked declaration 'NoSuchVerificationEndpoint' -/
#guard_msgs in
run_cmd AxiomPolicy.audit #[`NoSuchVerificationEndpoint] 1

/-- error: Axiom audit: empty target inventory -/
#guard_msgs in
run_cmd AxiomPolicy.audit #[] 0

/-- error: Axiom audit: duplicate target 'True.intro' -/
#guard_msgs in
run_cmd AxiomPolicy.audit #[``True.intro, ``True.intro] 2

/-- error: Axiom audit: expected 2 targets, got 1 -/
#guard_msgs in
run_cmd AxiomPolicy.audit #[``True.intro] 2
