/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Informal.ExternalCode
meta import VersoBlueprint.ExternalDeclRender
meta import VersoBlueprint.Informal.ExternalCode

namespace VersoBlueprintModuleTests.ExternalDeclRender

open Lean

local macro "externalCodeParseContract" : term => do
  let (refs, invalid) :=
    Informal.ExternalCode.parseExternalCodeList (some "Nat.add, List.map")
  let contract : Nat × Nat × Array Name :=
    (refs.size, invalid.size, refs.map (·.written))
  return quote contract

/-- info: true -/
#guard_msgs in
#eval
  let (emptyRefs, emptyInvalid) := Informal.ExternalCode.parseExternalCodeList none
  (externalCodeParseContract : Nat × Nat × Array Name) ==
      (2, 0, #[`Nat.add, `List.map]) &&
    emptyRefs.isEmpty && emptyInvalid.isEmpty

/-- info: true -/
#guard_msgs in
#eval
  show Lean.CoreM Bool from do
    let rendered? ← (Informal.renderDeclHtmlNodeDirect? ``Nat.add).run'
    let missing? ← (Informal.renderDeclHtmlNodeDirect? `No.Such.Declaration).run'
    pure <|
      match rendered?, missing? with
      | some rendered, none =>
          let html := rendered.asString
          !html.isEmpty && html.contains "bp_external_decl"
      | _, _ => false

end VersoBlueprintModuleTests.ExternalDeclRender
