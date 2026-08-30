/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

meta import VersoBlueprint.ExternalDeclRender

namespace VersoBlueprintModuleTests.ExternalDeclRender

open Lean

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
