/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.ReferenceNameAdmission.Provider
import VersoBlueprint.ExternalRef.FoldLaws
import VersoBlueprint.NodeAssembly.MembershipLaws

open Lean Informal
open Verso.VersoBlueprintTests.ReferenceNameAdmission

-- Imported reassembly must reject the label without filtering its raw malformed
-- evidence or allowing a later valid local registration to resurrect the node.
/-- info: true -/
#guard_msgs (drop error, info) in
#eval show CoreM Bool from do
  let before := Environment.informalExt.getState (← getEnv)
  let selected := before.factRecords.filter (·.label == `checked_imported_bad)
  if before.data.contains `checked_imported_bad || selected.length != 2 then return false
  unless selected.any (fun record => record.nativeAssociations.any fun association =>
      association.facets.contains `implementation && association.reference.canonical == malformedCanonical && !association.reference.present) do return false
  unless before.importedConflicts.any (fun conflict => conflict.label == `checked_imported_bad &&
      conflict.reasons.any (·.contains "unstable canonical name")) do return false
  unless before.leanNameLabels.toList.all (fun (_, labels) =>
      !labels.contains `checked_imported_bad) do return false
  let some pendingBefore := before.pendingNodes.get? `checked_imported_bad
    | return false
  let good := testFact `checked_imported_bad 42 (Data.ExternalRef.ofName `Nat.add_comm)
  let accepted ← Environment.contributeRecord good { tags := #["must-not-resurrect"] }
  let after := Environment.informalExt.getState (← getEnv)
  let some pendingAfter := after.pendingNodes.get? `checked_imported_bad
    | return false
  return accepted.isNone && !after.data.contains `checked_imported_bad &&
    after.factRecords == before.factRecords && after.localFactRecords == before.localFactRecords &&
    after.nextCount == before.nextCount &&
    after.leanNameLabels.toList == before.leanNameLabels.toList &&
    pendingAfter.registrations.size == pendingBefore.registrations.size &&
    pendingAfter.localRegistrations.size == pendingBefore.localRegistrations.size &&
    pendingAfter.registrations.map (·.tags) == pendingBefore.registrations.map (·.tags) &&
    pendingAfter.localRegistrations.map (·.tags) == pendingBefore.localRegistrations.map (·.tags) &&
    sameProducerNodes before after
