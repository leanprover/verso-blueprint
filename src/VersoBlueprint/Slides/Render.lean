/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Verso.Output.Html
public import VersoBlueprint.Graft.Render
import VersoBlueprint.PreviewManifest.BlockRender
import VersoBlueprint.Slides.Node

public section

namespace Informal.Slides

open Verso.Output
open Verso.Output.Html

private def slideManifestBlockConfig : Informal.PreviewManifest.BlockRender.RenderConfig :=
  {
    wrapperClass := "bp_slide_node_blueprint"
    codeBodyClass := "bp_slide_code_body"
    titleRowAttrs? := fun entry =>
      entry.href.map fun href =>
        #[ ("class", "bp_slide_node_heading_link")
         , ("data-bp-slide-link", "blueprint")
         , ("href", href)
         , ("target", "bp-slide-blueprint")
         , ("rel", "noopener")
         , ("title", "Open Blueprint node")
         ]
    relationPanels := {
      wrapClass := fun kind => "bp_relation_wrap bp_slide_" ++ kind.key ++ "_wrap"
      panelAttrs := fun kind => #[("data-bp-slide-panel", kind.key)]
      idPrefix := fun kind entry =>
        match kind with
        | .group => s!"bp-slide-group-{entry.label}"
        | .uses => "bp-slide-uses"
        | .usedBy => "bp-slide-used-by"
    }
  }

private def slideNodeAttrs (node : Informal.Graft.BlueprintNode) : Array (String × String) :=
  renderedBlueprintNodeAttrs node

private def renderMissingNode (node : Informal.Graft.BlueprintNode) (title detail : String) : Html :=
  .tag "div" (slideNodeAttrs node) <|
    Informal.Graft.renderNotice "bp_slide_node_notice" "error" title detail

private def slideManifestRenderConfig : Informal.Graft.ManifestRenderConfig :=
  {
    blockRenderConfig := slideManifestBlockConfig
    nodeAttrs := slideNodeAttrs
    renderMissingNode := renderMissingNode
    manifestUnavailableDetail :=
      "Pass previewManifest? to slidesMainWithBlueprintPreviews so Blueprint slide nodes can be rendered during slide generation."
  }

public def renderBlueprintSlideNode
    (ctx : Informal.Graft.RenderContext)
    (node : Informal.Graft.BlueprintNode) : IO Html := do
  Informal.Graft.renderNodeFromManifestCache slideManifestRenderConfig ctx node

end Informal.Slides
