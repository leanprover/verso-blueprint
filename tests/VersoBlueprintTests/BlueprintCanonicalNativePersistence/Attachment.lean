/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintCanonicalNativePersistence.Owner

open Lean Informal

namespace CanonicalNativePersistence

@[blueprint "canonical.native"]
theorem additional : True := original

run_cmd Lean.Elab.Command.liftCoreM do
  let node := Name.mkSimple "canonical.native"
  let reference ← externalRefSnapshotAtCurrentDir (← getOptions)
    (Data.ExternalRef.ofName ``additional)
  unless reference.present do throwError "Actual native attachment did not resolve"
  let some _ ← Environment.contributeRecord {
    id := ⟨← getMainModule, `test.scopedNative, node, 1, 0⟩, label := node
    nativeAssociations := #[{
      realization := ⟨node, `alternative⟩, context := ⟨`lean, ← Environment.sourceProject⟩
      facets := #[`statement, `proof], reference }]
    priority := none, source := none } {}
    | throwError "Actual scoped native attachment was rejected"
  let missing ← externalRefSnapshotAtCurrentDir (← getOptions)
    (Data.ExternalRef.ofName `CanonicalNativePersistence.notDeclared)
  unless !missing.present do throwError "Missing-source control unexpectedly resolved"
  let some _ ← Environment.contributeRecord {
    id := ⟨← getMainModule, `test.scopedNative, node, 2, 0⟩, label := node
    nativeAssociations := #[{
      realization := ⟨node, `pending⟩, context := ⟨`lean, ← Environment.sourceProject⟩
      facets := #[`proof], reference := missing }]
    priority := none, source := none } {}
    | throwError "Missing source must remain raw selected evidence"

end CanonicalNativePersistence
