/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Informal.Block.Render
import VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintHeaderExtras

open Verso
open Informal
open Verso.VersoBlueprintTests.Blueprint.Support

private def textHtml (text : String) : Output.Html :=
  .text true text

private def renderedHeaderExtras : String :=
  (renderHeaderExtras {
    group? := some <| HeaderExtra.group (textHtml "group")
    uses? := some <| HeaderExtra.uses (textHtml "uses")
    code? := some <| HeaderExtra.code (textHtml "code")
    usedBy? := some <| HeaderExtra.usedBy (textHtml "used by")
    markup? := some <| HeaderExtra.markup (textHtml "markup")
    custom := #[
      HeaderExtra.custom (Lean.Name.mkSimple "source") (textHtml "source")
        (order := 25) (wrapperClass := "etingof-extra")
    ]
  }).asString

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out := renderedHeaderExtras
    pure <|
      hasSubstr out "bp_extras_with_group" &&
      hasSubstr out "bp_extras_with_uses" &&
      hasSubstr out "bp_extras_with_custom" &&
      hasSubstr out "bp_extra_slot_group" &&
      hasSubstr out "bp_extra_slot_uses" &&
      hasSubstr out "bp_extra_slot_code" &&
      hasSubstr out "bp_extra_slot_used_by" &&
      hasSubstr out "bp_extra_slot_markup" &&
      hasSubstr out "bp_extra_slot_custom bp_extra_slot_custom_source etingof-extra" &&
      appearsBefore out "bp_extra_slot_group" "bp_extra_slot_uses" &&
      appearsBefore out "bp_extra_slot_uses" "bp_extra_slot_custom_source" &&
      appearsBefore out "bp_extra_slot_custom_source" "bp_extra_slot_used_by" &&
      appearsBefore out "bp_extra_slot_used_by" "bp_extra_slot_markup" &&
      appearsBefore out "bp_extra_slot_markup" "bp_extra_slot_code" &&
      appearsBefore out "bp_extra_slot_used_by" "bp_extra_slot_code"

end Verso.VersoBlueprintTests.BlueprintHeaderExtras
