/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintRealizationAdapter.Provider

open Informal

namespace DependencySelectionFixture

/-- An actually complete default theorem. -/
@[blueprint "dependencies.clean"]
theorem clean : True := True.intro

/-- A clean statement with an actually admitted proof. -/
@[blueprint "dependencies.admitted"]
theorem admitted : True := by sorry

/-- An independently complete proof-side dependency. -/
@[blueprint "dependencies.other"]
theorem other : True := True.intro

-- Untagged helper makes the theorem's type reach the associated clean proof.
def usingCleanType : Prop := let _proof : True := clean; True

set_option doc.verso true in
/--
The source uses {uses "dependencies.clean" (intent := "technical")}[clean support]
and {uses "dependencies.admitted" (intent := "auxiliary")}[unfinished support].
-/
@[blueprint "dependencies.source" (autoDeps := true)
  (uses := ["dependencies.missing", "dependencies.definition", "dependencies.grouped", "adapter.nonroundtrip"])
  (proofUses := ["dependencies.clean", "dependencies.missing"])]
theorem source : usingCleanType := other

/-- A supported source with no dependencies. -/
@[blueprint "dependencies.empty"]
theorem empty : True := True.intro

/-- A definition is outside the first default-theorem adapter. -/
@[blueprint "dependencies.definition"]
def definitionTarget : Nat := 1

/-- A grouped target must not silently select the first theorem. -/
@[blueprint "dependencies.grouped"]
theorem groupedOne : True := True.intro

@[blueprint "dependencies.grouped"]
theorem groupedTwo : True := True.intro

end DependencySelectionFixture
