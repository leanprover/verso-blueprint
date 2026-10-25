/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintCanonicalSourcePersistence.Owner

open Lean Informal

-- Deliberately bypass public admission to exercise malformed import decoding.
-- Both source contexts must survive the raw batch and exclude the accepted node.
run_cmd Lean.Elab.Command.liftCoreM do
  let label := Name.mkSimple "storage.source"
  let state := Environment.informalExt.getState (← getEnv)
  let pending := state.pendingNodes.getD label {}
  let some source := (pending.registrations.flatMap (·.sources)).find? (·.context.language == `lean)
    | throwError "Missing actual inline source"
  let variant : SourceData.Registration := { sources := #[{ source with
    context := ⟨`lean, `otherProject⟩
    document := ⟨⟨`lean, `otherProject⟩, source.document.path⟩
    payload := .leanInline { stx := .missing } }] }
  Environment.modify fun state => { state with
    pendingNodes := state.pendingNodes.insert label { pending with localRegistrations := #[variant] } }
