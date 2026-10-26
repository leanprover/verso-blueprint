/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintCanonicalNativePersistence.Harness
import VersoBlueprintTests.BlueprintCanonicalNativePersistence.Owner
import VersoBlueprintTests.BlueprintCanonicalNativePersistence.Attachment

/-! Ordinary attribute/registration/import controls for keyed native storage.
Source snapshot classification is real; no Registry, native validation evidence
or correspondence success is manually constructed by this consumer. -/

open Lean Informal

namespace CanonicalNativePersistence

private def context : Realizations.Context := ⟨`lean, `blueprintFixtures⟩
private def label : Name := Name.mkSimple "canonical.native"

run_cmd Lean.Elab.Command.liftCoreM do
  let state := Environment.informalExt.getState (← getEnv)
  let records := state.factRecords.filter (·.label == label)
  unless records.length == 4 && state.localFactRecords.isEmpty &&
      state.pendingNodes.all (fun _ pending => pending.localRegistrations.isEmpty) &&
      state.authoringRecords.isEmpty do
    throwError "Imports must retain complete native inputs once, with no local export or enrolled default"
  let associations := records.toArray.flatMap (·.nativeAssociations)
  unless associations.size == 4 && associations.all (·.context == context) do
    throwError "Producer context changed or native input disappeared on import replay"
  let refs (name facet : Name) := records.toArray.flatMap fun record =>
    record.referencesAt ⟨label, name⟩ context facet
  unless (refs `lean `statement).size == 2 && (refs `lean `proof).isEmpty &&
      (refs `alternative `statement).map (·.canonical) == #[``additional] &&
      (refs `alternative `proof).map (·.canonical) == #[``additional] &&
      (refs `pending `proof).size == 1 && !(refs `pending `proof)[0]!.present do
    throwError "Exact native realization/facet selection borrowed or dropped a source"
  unless records.all (fun record =>
      (record.referencesAt ⟨label, `alternative⟩ ⟨`lean, `wrongProject⟩ `proof).isEmpty) do
    throwError "A same-spelled native reference from another project was selected"
  let some node := state.data.get? label | throwError "Ordinary imported concept was not accepted"
  unless node.leanDecls.size == 2 && node.leanDecls.contains ``original &&
      node.leanDecls.contains ``additional &&
      (state.leanNameLabels.getD `CanonicalNativePersistence.notDeclared #[]).isEmpty do
    throwError "Node-wide native membership must include every present destination and no missing declaration"
  withOptions (fun options => options.set `verso.blueprint.project "changedQueryProject") do
    let after := Environment.informalExt.getState (← getEnv)
    unless reprStr after == reprStr state &&
        (after.factRecords.filter (·.label == label)).all (fun record =>
          record.nativeAssociations.all (·.context == context)) do
      throwError "Query options relabeled persisted native source contexts"

run_cmd Lean.Elab.Command.liftCoreM do
  let state := Environment.informalExt.getState (← getEnv)
  let some original := state.factRecords.find? (fun record =>
      record.label == label && record.id.producer == `test.scopedNative && record.id.site == 1)
    | throwError "Missing actual imported scoped source"
  let association := original.nativeAssociations[0]!
  -- A real current native reference may be attached to any named facet of an
  -- independently keyed realization. The node inventory and native label
  -- index must retain that accepted source without projecting it into a fixed
  -- statement/proof slot.
  let beforeArbitraryFacet ← getEnv
  try
    let ref ← externalRefSnapshotAtCurrentDir (← getOptions)
      (Data.ExternalRef.ofName `Nat.add_assoc)
    unless ref.present do throwError "Arbitrary-facet control needs a real current native declaration"
    let selected : Realizations.RealizationKey := ⟨label, `arbitraryFacet⟩
    let arbitrary : SourceData.NativeAssociation := {
      realization := selected, context, facets := #[`body], reference := ref }
    let oldLabels ← Environment.labelsForLeanDecl `Nat.add_assoc
    unless !oldLabels.contains label do
      throwError "Arbitrary-facet index control was already installed"
    let some accepted ← Environment.contributeRecord {
      id := ⟨← getMainModule, `test.arbitraryFacet, label, 500, 0⟩, label
      nativeAssociations := #[arbitrary]
      priority := none, source := none } {}
        | throwError "An arbitrary named native facet was rejected"
    let retained := accepted.nativeAssociations.any fun item =>
      item.realization == selected && item.context == context && item.facets == #[`body] &&
        item.reference.canonical == `Nat.add_assoc && item.reference.present
    let newLabels ← Environment.labelsForLeanDecl `Nat.add_assoc
    unless retained && accepted.leanDecls.contains `Nat.add_assoc && newLabels.contains label do
      throwError "Accepted arbitrary-facet association was lost from the node or native-name index"
  finally
    setEnv beforeArbitraryFacet

  -- Whole destinations participate in same-producer collision identity.
  rejected "native destinations" <| Environment.contributeRecord { original with
    nativeAssociations := #[{ association with realization := ⟨label, `changed⟩ }] } { tags := #["rejected"] }
  let fresh := { original with id := { original.id with moduleName := ← getMainModule, site := 100 } }
  rejected "source-context-mismatch" <| Environment.contributeRecord { fresh with
    nativeAssociations := #[{ association with context := ⟨`lean, `otherProject⟩ }] } {}
  rejected "empty-native-facets" <| Environment.contributeRecord { fresh with
    nativeAssociations := #[{ association with facets := #[] }] } {}
  rejected "source-destination-mismatch" <| Environment.contributeRecord { fresh with
    nativeAssociations := #[{ association with realization := ⟨`wrongConcept, `alternative⟩ }] } {}
  -- A successful inner native contribution must also roll back on an enclosing
  -- directive exception. This covers the raw/native/local-export fields too.
  let before := Environment.informalExt.getState (← getEnv)
  let failed ← try
    let _ : Option (Unit × Nat) ← Environment.withDirective
      (pure { label, kind := .proof }) .missing do
        let some _ ← Environment.contributeRecord { fresh with nativeAssociations := #[{
          association with realization := ⟨label, `inner⟩ }] } { tags := #["inner"] }
          | throwError "Inner native control did not pass ordinary registration"
        throwError "expected enclosing native transaction failure"
    pure false
  catch error =>
    pure ((← error.toMessageData.toString).contains "expected enclosing native transaction failure")
  unless failed && reprStr before == reprStr (Environment.informalExt.getState (← getEnv)) do
    throwError "Enclosing exception did not restore the complete native registration transaction"

run_cmd Lean.Elab.Command.liftCoreM do
  let env ← getEnv
  try
    -- No imported module configures this consumer. Explicit options apply to
    -- subsequent producers; empty options cannot invent a native project.
    let missing ← try
      withOptions (fun options => options.set `verso.blueprint.project "") do
        let _ ← Environment.sourceProject
        pure false
    catch error =>
      pure ((← error.toMessageData.toString).contains "explicit canonical")
    unless missing do throwError "Missing native project configuration was silently accepted"
    withOptions (fun options => options.set `verso.blueprint.project "") do
      let some node ← Environment.contribute `metadataWithoutNativeProject { tags := #["metadata"] }
        | throwError "Metadata-only registration incorrectly required a native context"
      unless node.tags == #["metadata"] do throwError "Metadata-only registration changed its input"
  finally
    setEnv env

elab "#native_registration_unchanged " command:command : command => do
  let before := Environment.informalExt.getState (← getEnv)
  try
    Lean.Elab.Command.elabCommand command
  finally
    unless reprStr before == reprStr (Environment.informalExt.getState (← getEnv)) do
      throwError "Rejected ordinary native attribute changed a Blueprint store"

/-- error: Blueprint sources require an explicit canonical 'verso.blueprint.project' option -/
#guard_msgs in
#native_registration_unchanged
set_option verso.blueprint.project "" in
@[blueprint "canonical.native.unconfigured"]
theorem missingProject : True := True.intro

end CanonicalNativePersistence
