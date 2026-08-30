/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.PreviewManifest.ExternalMarkupRender
meta import VersoBlueprint.PreviewManifest.ExternalMarkupRender

namespace VersoBlueprintModuleTests.PreviewExternalMarkupRender

open Lean

/-- info: true -/
#guard_msgs in
#eval
  let blockData : Informal.BlockData := {
    label := Name.mkSimple "moduleExternalMarkup"
    count := 1
  }
  let markup : Informal.Data.ExternalMarkup := {
    language := .markdown
    slot := "statement"
    raw := "# Strict module markup"
  }
  match Informal.PreviewManifest.renderExternalMarkupEntryHtml
      ({ mode := .source, showSourceNotice := false } : Informal.ExternalMarkupRender.Config)
      blockData "Proof" "1" markup with
  | none => false
  | some html =>
      html.contains "bp_preview_data_node_blueprint" &&
        html.contains "bp_external_markup_node" &&
        html.contains "data-bp-source-backed=\"true\"" &&
        html.contains "# Strict module markup"

end VersoBlueprintModuleTests.PreviewExternalMarkupRender
