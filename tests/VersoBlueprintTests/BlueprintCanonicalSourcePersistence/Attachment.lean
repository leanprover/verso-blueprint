/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintCanonicalSourcePersistence.Owner

open Verso.Genre Informal

#docs (Manual) storageAttachment "Source attachment" :=
:::::::
:::proof "storage.source" (uses := "storage.native") (uses_intent := "technical")
This is prose, with no claim of proofreading or proof checking.
:::
:::::::

-- Ordinary imported registration with an explicitly named foreign realization.
-- These are source bytes only; there is no foreign resolver or proof observation.
open Lean Elab Command in
run_cmd liftTermElabM do
  let label := Name.mkSimple "storage.source"
  let source ← Environment.sourceAt label `rocqTranslation `implementation `rocq
    (.text "Definition flag_identity (b : bool) := b.") (← getRef)
  unless (← Environment.contribute label { sources := #[source] }).isSome do
    throwError "Named foreign source registration failed"
