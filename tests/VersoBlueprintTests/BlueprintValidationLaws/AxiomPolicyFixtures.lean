/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
module
public import Init
import Lean.Elab.GuardMsgs

/-! Deliberately invalid proof dependencies, imported only by the audit's rejection
tests. Module export exercises Lean's imported axiom-dependency lookup too. -/

namespace VersoBlueprintTests.Verification.AxiomPolicyFixtures

public axiom forbiddenDomainAssumption : True

public theorem usesDomainAssumption : True := forbiddenDomainAssumption

/-- warning: declaration uses `sorry` -/
#guard_msgs in
public theorem usesSorry : True := by sorry

end VersoBlueprintTests.Verification.AxiomPolicyFixtures
