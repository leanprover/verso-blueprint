/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Html
import VersoBlueprint.Informal.LeanCodePreviewKey
import VersoBlueprint.Lib.ExtensionDecode
import VersoBlueprint.Process
meta import VersoBlueprint.Informal.LeanCodePreviewKey

namespace VersoBlueprintModuleTests.UtilityLeaves

open Lean

/-- Runtime-only process helper contract; the command is not executed by this test. -/
example : IO (Option String) :=
  Informal.Process.runTrimmedCommand? "true" #[]

/-- Runtime-only HTML helper contract. -/
example : Verso.Output.Html :=
  VersoBlueprint.Html.text "A&B"

/-- Runtime-only extension decoder contract. -/
example {m : Type → Type} {α : Type}
    [Monad m] [Verso.MonadBuildLog m] [FromJson α] (data : Json) : m (Option α) :=
  Informal.ExtensionDecode.decode? data (fun error => s!"decode failed: {error}")

/-- info: true -/
#guard_msgs in
#eval
  let decl := "Example.Contract".toName
  let label := "section.example".toName
  Informal.LeanCodePreviewKey.domainName == Name.mkSimple "Informal.LeanCodePreview" &&
    Informal.LeanCodePreviewKey.lookupKey decl ==
      "Informal.LeanCodePreview.Example.Contract" &&
    Informal.LeanCodePreviewKey.inlineLookupKey label ==
      "Informal.LeanCodePreview.Inline.section.example"

end VersoBlueprintModuleTests.UtilityLeaves
