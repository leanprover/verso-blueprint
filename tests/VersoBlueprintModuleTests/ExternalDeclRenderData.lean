/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.ExternalDeclRender.Data
meta import VersoBlueprint.ExternalDeclRender.Data

namespace VersoBlueprintModuleTests.ExternalDeclRenderData

open Lean
open Informal

local macro "externalDeclRenderedHtmlContract" : term => do
  let rendered : ExternalDeclRenderedHtml := {
    html :=
      "<code data-bp-external-hover-local=\"2\">x</code>" ++
        "<span data-bp-external-hover-inline-local=\"2\"></span>"
    hoverPayloads := #[{ localId := 2, html := "hover" }]
  }
  return quote rendered

/-- info: true -/
#guard_msgs in
#eval
  let rendered : ExternalDeclRenderedHtml := externalDeclRenderedHtmlContract
  let roundtripOk :=
    match Lean.fromJson? (α := ExternalDeclRenderedHtml) (Lean.toJson rendered) with
    | .ok decoded =>
        decoded.html == rendered.html &&
          decoded.hoverPayloads.size == 1 &&
          decoded.hoverPayloads[0]!.localId == 2 &&
          decoded.hoverPayloads[0]!.html == "hover"
    | .error _ => false
  let rewritten := rendered.rewriteHovers #[{
    localId := 2
    attrReplacement := "data-verso-hover=\"7\""
    inlineReplacement := ""
  }]
  roundtripOk &&
    rewritten == "<code data-verso-hover=\"7\">x</code>" &&
    rendered.selfContained ==
      "<code >x</code><span class=\"hover-info\">hover</span>" &&
    (ExternalDeclRenderError.moduleUnavailable ``Nat).message ==
      "module unavailable for Nat"

end VersoBlueprintModuleTests.ExternalDeclRenderData
