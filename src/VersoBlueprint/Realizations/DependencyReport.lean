/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Dependencies
import VersoBlueprint.Realizations.Report

/-! Direct accepted uses alongside supplied registry assessments. This installs
no prerequisites, recursive traversal or aggregate readiness calculation. -/

namespace Informal.Realizations.Report

open Lean Validation Translations Dependencies

private def selectedUse (registry : Registry) (edge : SelectedUse) : Json :=
  let selection := match edge.2 with
    | .ok key => Json.mkObj [
        ("requirement", toJson key), ("result", toJson (registry.resultForRequirement key))]
    | .error diagnostic => Json.mkObj [("diagnostic", toJson diagnostic)]
  Json.mkObj [("use", toJson edge.1), ("selection", selection)]

/-- Read accepted direct uses with their original axes/order/metadata, selecting
and assessing through existing APIs only. A selection failure is a diagnostic,
not a validation status. Source/view errors remain outer errors. Accepted source
presence does not imply any source validation is supplied in the nested registry.
This reports neither recursive dependency closure nor overall project readiness. -/
def ofSource (registry : Registry) (context : Context) (source : Name) :
    CoreM (Except Diagnostic Json) := do
  let uses ← match ← selectUses registry context source with
    | .ok uses => pure uses
    | .error diagnostic => return .error diagnostic
  return .ok <| Json.mkObj [
    ("source", toJson source), ("context", toJson context),
    ("registry", ofRegistry registry),
    ("uses", Json.mkObj [
      ("statement", toJson (uses.1.map (selectedUse registry))),
      ("proof", toJson (uses.2.map (selectedUse registry)))])]

end Informal.Realizations.Report
