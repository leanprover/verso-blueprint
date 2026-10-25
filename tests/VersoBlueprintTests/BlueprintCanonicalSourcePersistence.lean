/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintCanonicalSourcePersistence.Owner
import VersoBlueprintTests.BlueprintCanonicalSourcePersistence.Attachment
import VersoBlueprintTests.BlueprintCanonicalNativePersistence.Harness

open Lean Informal SourceData

-- Old source/dependency constructor slots really are gone; these are not aliases.
#check_failure (fun (input : Data.NodeContribution) => input.statementBody)
#check_failure (fun (input : Data.NodeContribution) => input.literateCodes)
#check_failure (fun (input : Registration) => input.proofUses)
#check_failure (fun (input : Registration) => input.rustCode)

run_cmd Lean.Elab.Command.liftCoreM do
  let label := Name.mkSimple "storage.source"
  let state := Environment.informalExt.getState (← getEnv)
  let registrations := (state.pendingNodes.getD label {}).registrations
  let sources := registrations.flatMap (·.sources)
  let uses := registrations.flatMap (·.uses)
  unless sources.size == 6 && state.importedConflicts.isEmpty &&
      state.pendingNodes.all (fun _ pending => pending.localRegistrations.isEmpty) do
    throwError "Diamond import duplicated a source or re-exported imported registrations"
  unless sources.all (fun source => source.context.project == `blueprintFixtures &&
      source.destination.realization.node == label && source.document.context == source.context &&
      source.source.ok && source.source.location.any (·.path == source.document.path)) do
    throwError "Owning document, project, destination or UTF-16 source location was lost"
  unless sources.all (fun source => source.document.path.endsWith "Owner.lean" ||
      source.document.path.endsWith "Attachment.lean") do
    throwError "Consumer module replaced the owning source path"
  unless sources.any (fun source => source.destination == ⟨⟨label, `verso⟩, `statement⟩) &&
      sources.any (fun source => source.destination == ⟨⟨label, `verso⟩, `proof⟩) &&
      sources.any (fun source => source.destination == ⟨⟨label, `lean⟩, `body⟩) do
    throwError "Realization and facet identities were flattened"
  unless uses.any (fun use => use.reference.label == Name.mkSimple "storage.forward" &&
      use.facet == `statement && use.realization.isNone && use.reference.origin == .manual) &&
      uses.any (fun use => use.reference.label == Name.mkSimple "storage.native" &&
      use.facet == `proof && use.realization == some `lean && use.reference.origin == .automatic) &&
      uses.any (fun use => use.reference.label == Name.mkSimple "storage.native" &&
      use.facet == `proof && use.realization.isNone && use.reference.intent == .technical) &&
      uses.any (fun use => use.reference.label == Name.mkSimple "storage.tagged" &&
      use.realization.isNone && use.reference.origin == .automatic && use.reference.intent == .auxiliary) do
    throwError "Shared forward references, scoped inference or proof intent were lost"
  let inline := nativeNames #[] sources
  unless inline == #[`storedInline] && (← Environment.labelsForLeanDecl `storedInline) == #[label] do
    throwError "Inline declaration membership/index was lost"
  let rust := sources.filterMap fun source => match source.payload with | .text raw => some raw | _ => none
  unless rust == #["fn example() -> &'static str { \"𝒫::bad»name\" }\n"] do
    throwError "Original Rust text changed: {repr rust}"
  let markup := sources.filterMap fun source => match source.payload with | .markup value => some value | _ => none
  unless markup.size == 2 && markup[0]!.raw == "\\forall x,\\;𝒫(x)\n" &&
      markup[1]!.raw == "**𝒫** and `foreign::name.with.dot»tail`\n" &&
      markup.all (·.slot == "body.with.dot") &&
      markup[0]!.location == some { path := "paper.tex", range := {
        start := ⟨2, 3⟩, «end» := ⟨2, 12⟩ } } && markup[1]!.location.isNone do
    throwError "Raw markup or authored external location changed: {repr markup}"
  let oldEnv ← getEnv
  try
    withOptions (fun opts => opts.set `verso.blueprint.project "differentQueryProject") do
      unless reprStr state == reprStr (Environment.informalExt.getState (← getEnv)) do
        throwError "Query-site project option relabeled stored sources"
    let source := sources[0]!
    CanonicalNativePersistence.rejected "source-destination-mismatch" <|
      Environment.contribute label { sources := #[{ source with
        destination := ⟨⟨`sibling, `verso⟩, `statement⟩ }] }
    -- Empty source payload avoids a duplicate-body failure, reaching context validation.
    CanonicalNativePersistence.rejected "source-context-mismatch" <|
      Environment.contribute label { sources := #[{ source with
        context := ⟨`verso, `otherProject⟩
        document := ⟨⟨`verso, `otherProject⟩, source.document.path⟩
        payload := .prose { stx := .missing } }] }
    CanonicalNativePersistence.rejected "source-document-context" <|
      Environment.contribute label { sources := #[{ source with
        document := ⟨⟨`verso, `otherProject⟩, source.document.path⟩
        payload := .prose { stx := .missing } }] }
    CanonicalNativePersistence.rejected "unsupported-source-projection" <|
      Environment.contribute label { sources := #[{ source with
        destination := ⟨⟨label, `alternative⟩, `statement⟩
        payload := .prose { stx := .missing } }] }
    CanonicalNativePersistence.rejected "unsupported-use-projection" <|
      Environment.contribute label { uses := #[{
        node := `sibling, facet := `proof, reference := { label := `target } }] }
    -- A source/native context mismatch also rejects when each group is valid alone.
    let leanSource := (sources.find? (·.context.language == `lean)).get!
    CanonicalNativePersistence.rejected "source-context-mismatch" <|
      Environment.contributeRecord {
        id := ⟨← getMainModule, `test, label, 1, 0⟩, label, priority := none, source := none
        nativeAssociations := #[{
          realization := ⟨label, `lean⟩, context := ⟨`lean, `otherProject⟩, facets := #[`statement]
          reference := Data.ExternalRef.ofName `storedInline }] } {}
    unless leanSource.destination.facet == `body do throwError "Control missed inline input"
  finally
    setEnv oldEnv
