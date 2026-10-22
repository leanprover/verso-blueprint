/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
module

meta import Vir.Attributes
import VersoBlueprintVir.ExternalMarkup
import VersoBlueprint.Lib.HtmlId

/-- Production selection policy; source bodies and callbacks stay in the browser. -/
@[vir_export]
public def VersoBlueprint.ExternalMarkup.selectMarkup (input : String) : String :=
  VersoBlueprint.ExternalMarkup.selectJson input

/-- Reuse the native DOM-id encoding; counters and DOM construction stay in JS. -/
@[vir_export]
public def VersoBlueprint.HtmlId.encode (key : String) : String :=
  Informal.HtmlId.key key
