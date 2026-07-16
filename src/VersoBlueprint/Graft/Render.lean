/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Verso.Output.Html
import VersoBlueprint.Graft.Node
import VersoBlueprint.PreviewManifest
import VersoBlueprint.PreviewManifest.BlockRender

namespace Informal.Graft

open Verso.Output
open Verso.Output.Html

public structure RenderContext where
  manifestIndex? : Option Informal.PreviewManifest.Index := none
  htmlCacheIndex : Informal.PreviewManifest.HtmlCache.Index := {}
  logError : String → IO Unit := fun _ => pure ()

namespace RenderContext

public def ofPreviewData?
    (manifest? : Option Informal.PreviewManifest.File)
    (htmlCache? : Option Informal.PreviewManifest.HtmlCache.File := none)
    (logError : String → IO Unit := fun _ => pure ()) : RenderContext :=
  let htmlCache := htmlCache?.getD {}
  {
    manifestIndex? := manifest?.map (·.index)
    htmlCacheIndex := htmlCache.index
    logError
  }

public def renderedContent?
    (ctx : RenderContext)
    (node : BlueprintNode)
    (entry : Informal.PreviewManifest.Entry) :
    IO (Option Informal.PreviewManifest.BlockRender.RenderedContent) := do
  match ctx.htmlCacheIndex.findHtml? entry.key with
  | none =>
      ctx.logError s!"Blueprint HTML cache: missing rendered body for {entry.key}"
      pure none
  | some bodyHtml =>
      let codeBodies :=
        if node.compact then
          #[]
        else
          (ctx.htmlCacheIndex.codeHtmlBodies entry).map
            Informal.PreviewManifest.BlockRender.htmlFragment
      pure <| some {
        body := Informal.PreviewManifest.BlockRender.htmlFragment bodyHtml
        codeBodies
      }

end RenderContext

public def renderNotice (baseClass kind title detail : String) : Html :=
  {{
    <div class={{baseClass ++ " " ++ baseClass ++ "_" ++ kind}}>
      <strong>{{Html.ofString title}}</strong><br/>
      {{Html.ofString detail}}
    </div>
  }}

private def defaultRenderMissingNode (node : BlueprintNode) (title detail : String) : Html :=
  .tag "div" node.renderedAttrs <|
    renderNotice "bp_graft_node_notice" "error" title detail

public structure ManifestRenderConfig where
  blockRenderConfig : Informal.PreviewManifest.BlockRender.RenderConfig := {}
  nodeAttrs : BlueprintNode → Array (String × String) := (·.renderedAttrs)
  renderMissingNode : BlueprintNode → String → String → Html := defaultRenderMissingNode
  manifestUnavailableDetail : String :=
    "Provide a Blueprint preview manifest and rendered-fragment cache before rendering graft nodes."

/--
Render a graft node when the semantic manifest entry and already-rendered body
content are both available.

This is the shared assembly point for same-document Manual grafts and
manifest/cache-backed generated consumers.
-/
public def renderNodeWithContent
    (cfg : ManifestRenderConfig)
    (node : BlueprintNode)
    (entry : Informal.PreviewManifest.Entry)
    (content : Informal.PreviewManifest.BlockRender.RenderedContent)
    (group? : Option Informal.PreviewManifest.GroupRelation := none) : Html :=
  .tag "div" (cfg.nodeAttrs node) <|
    Informal.PreviewManifest.BlockRender.renderWithRenderedContent
      cfg.blockRenderConfig
      entry
      content
      group?
      {
        displayLabelOverride? := node.displayLabel?
        compact := node.compact
        showHeader := node.showHeader
      }

public def renderNodeFromManifestCache
    (cfg : ManifestRenderConfig)
    (ctx : RenderContext)
    (node : BlueprintNode) : IO Html := do
  match ctx.manifestIndex? with
  | none =>
    pure <| cfg.renderMissingNode node "Preview manifest unavailable"
      cfg.manifestUnavailableDetail
  | some index =>
    match index.findEntry? node.key with
    | none =>
        pure <| cfg.renderMissingNode node "Blueprint node not found" node.selectionDescription
    | some entry =>
        match ← ctx.renderedContent? node entry with
        | none =>
            pure <| cfg.renderMissingNode node "Blueprint HTML cache entry not found" entry.key
        | some content =>
            pure <| renderNodeWithContent cfg node entry content (index.groupForEntry? entry)

public def readBlueprintManifest (path : System.FilePath) :
    IO Informal.PreviewManifest.File :=
  Informal.PreviewManifest.readFile path

public def readBlueprintHtmlCache (path : System.FilePath) :
    IO Informal.PreviewManifest.HtmlCache.File :=
  Informal.PreviewManifest.HtmlCache.readFile path

end Informal.Graft
