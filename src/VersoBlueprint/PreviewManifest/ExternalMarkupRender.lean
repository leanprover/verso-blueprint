/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoBlueprint.Data
import VersoBlueprint.Informal.Block.Model
import VersoBlueprint.Informal.Block.Render
import VersoBlueprint.Informal.ExternalMarkupRender

namespace Informal.PreviewManifest

open Verso.Genre Manual

def renderExternalMarkupEntryHtml
    (cfg : Informal.ExternalMarkupRender.Config)
    (blockData : Informal.BlockData)
    (headingCaption headingLabel : String)
    (selectedMarkup : Informal.Data.ExternalMarkup)
    (headerMarkup : Array Informal.Data.ExternalMarkup := #[selectedMarkup])
    (sourceRefs : Array Informal.Source.Ref := #[]) : Option String := do
  let content ← Informal.ExternalMarkupRender.content? cfg selectedMarkup
  let html := Informal.renderInformalBlockModel {
    data := blockData
    context := Informal.InformalBlockRenderContext.forBlock blockData headingLabel
      (statementCaption? := some headingCaption)
      (attrs := Informal.ExternalMarkupRender.sourceBackedAttrs selectedMarkup)
      (headerExtras := {
        markup? := Informal.renderExternalMarkupHeaderExtra? headerMarkup
      })
      (sourceRefs := sourceRefs)
    content
    wrapperClass? := some "bp_preview_data_node_blueprint bp_external_markup_node"
  }
  some <| Verso.Output.Html.asString html

end Informal.PreviewManifest
