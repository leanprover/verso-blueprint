/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
module

meta import Vir.Attributes
import VersoBlueprintVir.ExternalMarkup

/-- Production selection policy; source bodies and callbacks stay in the browser. -/
@[vir_export]
public def VersoBlueprint.ExternalMarkup.selectMarkup (input : String) : String :=
  VersoBlueprint.ExternalMarkup.selectJson input
