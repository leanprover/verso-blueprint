/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean

/-! Test-only dependency policy for the pinned Lean toolchain. This queries the
checked environment directly; printed output is never an acceptance input. -/

namespace VersoBlueprintTests.Verification.AxiomPolicy
open Lean Elab Command

/-- Reviewed standard axioms. Domain assumptions and `sorryAx` are forbidden. -/
private def allowed : Array Name := #[``propext, ``Classical.choice, ``Quot.sound]

/-- Check and print the same nonempty, duplicate-free inventory. The reviewed
count detects accidental deletions; quoted names at the call site and the checked
environment lookup both prevent a missing target from passing as axiom-free.
This checks dependencies, not provider authenticity or completeness of the spec. -/
def audit (targets : Array Name) (expectedCount : Nat) : CommandElabM Unit := do
  if targets.isEmpty then
    throwError "Axiom audit: empty target inventory"
  if targets.size != expectedCount then
    throwError "Axiom audit: expected {expectedCount} targets, got {targets.size}"
  let env ← getEnv
  let mut seen : NameSet := {}
  for target in targets do
    if seen.contains target then
      throwError "Axiom audit: duplicate target '{target}'"
    seen := seen.insert target
    unless (env.checked.get.find? target).isSome do
      throwError "Axiom audit: unknown checked declaration '{target}'"
  -- Validate every target before reporting a successful inventory.
  let dependencies ← targets.mapM fun target => do
    let axioms ← collectAxioms target
    let unexpected := axioms.filter fun dependency => !allowed.contains dependency
    unless unexpected.isEmpty do
      throwError "Axiom audit: '{target}' uses forbidden axioms {unexpected.toList}"
    pure (target, axioms)
  for (target, axioms) in dependencies do
    logInfo m!"'{target}' depends on axioms: {axioms.toList}"
  logInfo m!"Axiom policy passed for {targets.size} declarations"

end VersoBlueprintTests.Verification.AxiomPolicy
