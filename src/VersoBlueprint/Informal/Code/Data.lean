/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Lean
public import VersoBlueprint.Data

public section

namespace Informal

open Lean

/-- How external markup code blocks should be rendered in the current document. -/
inductive ExternalMarkupDisplayMode where
  | hidden
  | summary
  | source
deriving Repr, Inhabited, BEq, ToJson, FromJson, Quote

def ExternalMarkupDisplayMode.parse? (raw : String) : Option ExternalMarkupDisplayMode :=
  match raw.trimAscii.toString.toLower with
  | "hidden" | "hide" | "none" => some .hidden
  | "summary" | "metadata" => some .summary
  | "source" | "raw" => some .source
  | _ => none

register_option verso.blueprint.externalMarkup.display : String := {
  defValue := "hidden"
  descr := "Default display mode for external markup blocks: `hidden` (default), `summary`, or `source`"
}

def ExternalMarkupDisplayMode.fromOptions (opts : Lean.Options) : ExternalMarkupDisplayMode :=
  match ExternalMarkupDisplayMode.parse? (verso.blueprint.externalMarkup.display.get opts) with
  | some mode => mode
  | none => .hidden

structure ExternalMarkupBlockData where
  label : Data.Label
  markup : Data.ExternalMarkup
  display : ExternalMarkupDisplayMode := .hidden
deriving Repr, Inhabited, FromJson, ToJson, Quote

end Informal
