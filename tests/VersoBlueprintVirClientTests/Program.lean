/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
module

meta import VersoBlueprintVir
import VersoBlueprintVir.ExternalMarkup

/-- A deliberately small client export, independent of the document renderer. -/
@[vir_export]
public def VersoBlueprintVirClientTests.Program.title (name : String) : String :=
  "Blueprint: " ++ name

#guard VersoBlueprintVirClientTests.Program.title "FLT" == "Blueprint: FLT"
#guard VersoBlueprintVirClientTests.Program.title "" == "Blueprint: "

/-- Application policy only: JavaScript retains markup bodies and renderers. -/
@[vir_export]
public def VersoBlueprintVirClientTests.Program.selectMarkup (input : String) : String :=
  VersoBlueprint.ExternalMarkup.selectJson input
