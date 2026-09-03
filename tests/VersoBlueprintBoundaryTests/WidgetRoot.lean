/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

meta import VersoBlueprint.Widget

namespace VersoBlueprintBoundaryTests.WidgetRoot

/-- info: true -/
#guard_msgs in
#eval
  let params : GraphParams := {
    title := "Module widget"
    label := "module.widget"
    previewHtml := Lean.Json.null
    dot := "digraph {}"
  }
  params.title == "Module widget" &&
    params.label == "module.widget" &&
    params.dot == "digraph {}" &&
    blueprintWidget.javascript != ""

end VersoBlueprintBoundaryTests.WidgetRoot
