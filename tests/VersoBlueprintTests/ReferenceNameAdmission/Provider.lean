/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.Blueprint.Support

open Lean Verso Genre Manual Informal

namespace Verso.VersoBlueprintTests.ReferenceNameAdmission

/-- A two-level hygienic suffix whose one-pass erased key still changes. -/
def malformedCanonical : Name :=
  let stem := Name.str (Name.str (Name.mkSimple "unstable") "_@") "_hyg"
  Name.str (Name.str stem "_@") "_hyg"

def testFact (label : Name) (site : Nat) (ref : Data.ExternalRef) (proof : Bool := false) :
    Contributions.Record := {
  id := { moduleName := `ReferenceNameAdmission, producer := `test, subject := label, site, slot := 0 }
  label
  references := if proof then #[] else #[ref]
  proofReferences := if proof then #[ref] else #[]
  priority := none
  source := none }

/-- Relevant committed producer fields, compared independently of their Repr. -/
def sameProducerNodes (before after : Environment.State) : Bool :=
  #[`checked_attribute, `checked_directive].all fun label =>
    match before.data.get? label, after.data.get? label with
    | some previous, some current =>
      previous.externalRefs == current.externalRefs &&
        previous.proofExternalRefs == current.proofExternalRefs &&
        previous.leanDecls == current.leanDecls && previous.tags == current.tags &&
        previous.priority == current.priority && previous.count == current.count
    | _, _ => false

@[blueprint "checked_attribute"]
theorem checkedAttribute : True := True.intro

#docs (Manual) checkedDirectives "Checked producer names" :=
:::::::
:::lemma_ "checked_directive" (lean := "Nat.add_assoc")
A real statement association.
:::
:::proof "checked_directive" (lean := "Nat.add_comm")
A real proof association.
:::
:::::::

-- Actual producer output is accepted without supplying a naming premise.
-- Both selected facets and the attribute record pass the production gate.
run_cmd do
  let state := Environment.informalExt.getState (← getEnv)
  let records := state.factRecords.reverse
  let some attributeNode := state.data.get? `checked_attribute
    | throwError "Attribute producer was rejected"
  let some directiveNode := state.data.get? `checked_directive
    | throwError "Directive producer was rejected"
  unless attributeNode.leanDecls.contains
      `Verso.VersoBlueprintTests.ReferenceNameAdmission.checkedAttribute &&
      directiveNode.externalRefs.size == 1 && directiveNode.proofExternalRefs.size == 1 &&
      directiveNode.leanDecls.contains `Nat.add_assoc && directiveNode.leanDecls.contains `Nat.add_comm &&
      (NodeAssembly.referenceNameErrors `checked_attribute records).isEmpty &&
      (NodeAssembly.referenceNameErrors `checked_directive records).isEmpty do
    throwError "Real producer snapshots did not pass checked name admission"

-- Rejection is atomic for present/missing observations on either facet. The
-- guarded Boolean ensures unexpected errors cannot pass by being dropped.
/-- info: true -/
#guard_msgs (drop error, info) in
#eval show CoreM Bool from do
  for proof in #[false, true] do
    for present in #[false, true] do
      let before := Environment.informalExt.getState (← getEnv)
      let bad : Data.ExternalRef := {
        written := malformedCanonical, canonical := malformedCanonical, present }
      let fact := testFact `checked_local_bad 20 bad proof
      let .error errors := NodeAssembly.assemble `checked_local_bad
          #[{ tags := #["must-not-leak"] }] [fact]
        | return false
      unless errors.any (·.contains "unstable canonical name") do return false
      let accepted ← Environment.contributeRecord fact { tags := #["must-not-leak"] }
      let after := Environment.informalExt.getState (← getEnv)
      unless accepted.isNone && after.factRecords == before.factRecords &&
          after.localFactRecords == before.localFactRecords && after.nextCount == before.nextCount &&
          after.leanNameLabels.toList == before.leanNameLabels.toList &&
          !after.data.contains `checked_local_bad && !after.pendingNodes.contains `checked_local_bad &&
          sameProducerNodes before after do return false
  return true

-- A colliding malformed variant must retain the existing identity diagnostics,
-- rather than being dropped or preempted by the later name check.
#guard
  let bad : Data.ExternalRef := { written := malformedCanonical, canonical := malformedCanonical }
  let fact := testFact `checked_collision 30 bad
  match NodeAssembly.assemble `checked_collision #[] [fact, { fact with priority := some "changed" }] with
  | .ok _ => false
  | .error errors => errors.any (·.contains "conflicting contribution identity") &&
      !errors.any (·.contains "unstable canonical name")

-- Simulate raw evidence exported by an external/older producer. This deliberate
-- test-only state injection bypasses local registration so the import boundary
-- must check again. The full malformed record remains in the exported evidence.
run_cmd do
  let good := testFact `checked_imported_bad 40 (Data.ExternalRef.ofName `Nat.add_assoc)
  let some _ ← Environment.contributeRecord good { tags := #["exported"] }
    | throwError "Valid import fixture seed was rejected"
  let bad := testFact `checked_imported_bad 41 {
    written := malformedCanonical, canonical := malformedCanonical, present := false } true
  Environment.modify fun state => { state with
    factRecords := Contributions.collector.insert bad state.factRecords
    localFactRecords := Contributions.collector.insert bad state.localFactRecords }

end Verso.VersoBlueprintTests.ReferenceNameAdmission
