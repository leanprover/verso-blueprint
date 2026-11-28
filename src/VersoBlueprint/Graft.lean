/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoSlides
import Verso.Doc.Elab
import VersoBlueprint.Informal.Block.Assets
import VersoBlueprint.Informal.Block.Traversal
import VersoBlueprint.Informal.LeanCodePreview
import VersoBlueprint.Attribute.Placement
import VersoBlueprint.Graft.Assets
import VersoBlueprint.Graft.Node
import VersoBlueprint.Graft.Render
import VersoBlueprint.PreviewManifest.BlockRender
import VersoBlueprint.Lib.ExtensionDecode
import VersoBlueprint.Lib.PreviewResources
import VersoBlueprint.Slides.Node
import VersoBlueprint.TeX

set_option doc.verso true

namespace Informal.Graft

open Lean
open Verso Doc Elab
open Verso.Genre Manual
open Verso.Output
open Verso.Output.Html

def manualGraftAssetBundle : Informal.Commands.BlueprintAssetBundle :=
  Informal.Block.Assets.blockAssetBundle.withCss Informal.Graft.cssAssets

private def manualNodeClass (node : Informal.Graft.BlueprintNode) : String :=
  if node.compact then
    "bp_graft_node bp_graft_manifest_node bp_graft_node_compact"
  else
    "bp_graft_node bp_graft_manifest_node"

private def manualNodeAttrs (node : Informal.Graft.BlueprintNode) :
    Array (String × String) :=
  setClassAttr node.renderedAttrs (manualNodeClass node)

private def manualBlockRenderConfig : Informal.PreviewManifest.BlockRender.RenderConfig :=
  {
    wrapperClass := "bp_graft_node_blueprint"
    codeBodyClass := "bp_graft_code_body"
    relationPanels := {
      wrapClass := fun kind => "bp_relation_wrap bp_graft_" ++ kind.key ++ "_wrap"
      idPrefix := fun kind entry =>
        match kind with
        | .group => s!"bp-graft-group-{entry.label}"
        | .uses => "bp-graft-uses"
        | .usedBy => "bp-graft-used-by"
    }
  }

private def manualManifestRenderConfig : Informal.Graft.ManifestRenderConfig :=
  {
    blockRenderConfig := manualBlockRenderConfig
    nodeAttrs := manualNodeAttrs
  }

private def renderManualBlocks
    [Monad m]
    (goB : Doc.Block Verso.Genre.Manual → Doc.Html.HtmlT Verso.Genre.Manual m Html)
    (blocks : Array (Doc.Block Verso.Genre.Manual)) :
    Doc.Html.HtmlT Verso.Genre.Manual m Html := do
  Html.seq <$> blocks.mapM goB

private def renderLeanCodePreviewBody?
    [Monad m]
    [MonadBuildLog (Doc.Html.HtmlT Verso.Genre.Manual m)]
    (goB : Doc.Block Verso.Genre.Manual → Doc.Html.HtmlT Verso.Genre.Manual m Html)
    (state : TraverseState)
    (id : Verso.Multi.InternalId)
    (label : Name)
    (key : String) :
    Doc.Html.HtmlT Verso.Genre.Manual m (Option (Html × Informal.BlockCodeData)) := do
  let some panel ← ExtensionDecode.report? (RenderingResolution.codePanelByKey state key)
    | pure none
  let body ← match panel.preview.source with
    | .inlineBlocks _label blocks _sourceLocation => renderManualBlocks goB blocks
    | .externalDecl decl =>
      pure (Informal.ExternalCode.renderPreviewHtml #[decl]
        (Informal.Resolve.resolveInformalDeclHref? state label)
        (fun decl => Informal.TraversalIndex.ExternalDeclAnchors.htmlIdAttrs state id decl.canonical))
  pure <| some (body, panel.facts)

private def renderLeanCodeBodies
    [Monad m]
    [MonadBuildLog (Doc.Html.HtmlT Verso.Genre.Manual m)]
    (goB : Doc.Block Verso.Genre.Manual → Doc.Html.HtmlT Verso.Genre.Manual m Html)
    (state : TraverseState)
    (id : Verso.Multi.InternalId)
    (resolved : RenderingResolution.Facet) :
    Doc.Html.HtmlT Verso.Genre.Manual m (Array Html × Informal.BlockCodeData) := do
  let mut bodies := #[]
  let mut facts := {}
  for key in RenderingResolution.codePreviewKeys state resolved do
    match ← renderLeanCodePreviewBody? goB state id resolved.preview.label key with
    | none => pure ()
    | some (body, codeData) =>
        if PreviewResources.htmlIsBlank body then
          pure ()
        else
          bodies := bodies.push body
          facts := facts.append codeData
  pure (bodies, facts)

private def renderManualGraftNode
    [Monad m]
    [MonadBuildLog (Doc.Html.HtmlT Verso.Genre.Manual m)]
    (goB : Doc.Block Verso.Genre.Manual → Doc.Html.HtmlT Verso.Genre.Manual m Html)
    (id : Verso.Multi.InternalId)
    (placement : Placement) :
    Doc.Html.HtmlT Verso.Genre.Manual m Html := do
  let node := placement.config.toNode
  let state ← Doc.Html.HtmlT.state
  match RenderingResolution.facetByKey? state node.key with
  | .error error =>
      Verso.reportError error
      pure <| Html.tag "div" (manualNodeAttrs node) <|
        renderNotice "bp_graft_node_notice" "error" "Invalid Blueprint node" error
  | .ok none =>
      pure <| Html.tag "div" (manualNodeAttrs node) <|
        renderNotice "bp_graft_node_notice" "error" "Blueprint node not found"
          node.selectionDescription
  | .ok (some resolved) =>
      let preview := resolved.preview
      let entry := Informal.PreviewManifest.blockEntryOfFacet state resolved
      let entry := { entry with
        foldProofBlock := placement.foldProofBlock.getD entry.foldProofBlock
        foldCodeBlock := placement.foldCodeBlock.getD entry.foldCodeBlock }
      let externalBody? := if preview.facet == .statement then
        Informal.ExternalMarkupRender.previewBody? {} entry.externalMarkup else none
      if !preview.hasRenderedBody && entry.leanCodePreviewKeys.isEmpty && externalBody?.isNone then
        pure <| Html.tag "div" (manualNodeAttrs node) <|
          renderNotice "bp_graft_node_notice" "error"
            "Blueprint node has no cached content" node.key
      else
        let body ← if preview.hasRenderedBody then renderManualBlocks goB preview.blocks
          else pure (externalBody?.getD .empty)
        let (codeBodies, codeData) ←
          if !placement.showsCode then
            pure (#[], {})
          else
            renderLeanCodeBodies goB state id resolved
        let content : Informal.PreviewManifest.BlockRender.RenderedContent := {
          assessment := resolved.data.assessment
          body
          codeBodies
          codeData := withFacetExternalChecks codeData resolved.data.codeData
        }
        pure <| Informal.Graft.renderNodeWithContent
          { manualManifestRenderConfig with
            nodeAttrs := fun node => state.htmlId id ++ manualNodeAttrs node }
          node
          entry
          content
          (Informal.PreviewManifest.groupRelationForEntry? state entry)
          (fun label => (Informal.TraversalIndex.Nodes.capturedData? state label).map
            Informal.CodeSummary.blockStatusVisual)

/- A placement registers only destinations emitted by its visible renderer. -/
open Verso Doc Elab Genre Manual in
block_extension Block.blueprintGraftNode (placement : Informal.Graft.Placement) where
  data := toJson placement
  usePackages := Informal.TeX.standardMathUsePackages
  traverse id data contents := do
    let some placement ← Informal.ExtensionDecode.decode?
        (α := Informal.Graft.Placement) data
        (fun err => s!"Malformed Blueprint placement ({err}): {data}")
      | pure none
    if let some occurrence := placement.statement then
      Informal.registerTraversedBlock id occurrence contents
        (showsCode := placement.showsCode)
    if placement.showsCode then
      -- Forward placements can precede the selected facet during traversal.
      -- Required content is checked by the renderer after traversal completes.
      if let .ok (some resolved) :=
          RenderingResolution.facetByKey? (← get) placement.config.toNode.key then
        for key in RenderingResolution.codePreviewKeys (← get) resolved do
          if let .ok code := RenderingResolution.codePanelByKey (← get) key then
            if let .externalDecl decl := code.preview.source then
              Informal.registerExternalDeclAnchors id resolved.preview.label #[decl]
    pure none
  toTeX :=
    open Verso.Output.TeX in
    some <| fun _goI _goB _id _data _blocks =>
      pure <| .text "This Blueprint graft node is available in the HTML output."
  extraCss := manualGraftAssetBundle.css
  extraJs := manualGraftAssetBundle.js
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun _goI goB id data _blocks => do
      let some placement ← Informal.ExtensionDecode.decode?
          (α := Informal.Graft.Placement) data
          (fun err => s!"Malformed Blueprint placement ({err}): {data}")
        | pure .empty
      renderManualGraftNode goB id placement

private meta def currentGenreIs (genreTerm : Term) : DocElabM Bool := do
  let current := (← readThe DocElabContext).genre
  let expected ← Lean.Elab.Term.elabTerm genreTerm (some (.const ``Verso.Doc.Genre []))
  Lean.Meta.isDefEq current expected

public meta def inManualGenre : DocElabM Bool := do
  currentGenreIs (← `(Verso.Genre.Manual))

private meta def inSlidesGenre : DocElabM Bool := do
  currentGenreIs (← `(VersoSlides.Slides))

private meta def manualBlueprintNodeBlock
    (cfg : Informal.Graft.BlueprintNodeConfig) : DocElabM Term := do
  let (placement, body) ← elaboratePlacement cfg
  ``(Verso.Doc.Block.other
      (Informal.Graft.Block.blueprintGraftNode $(quote placement))
      #[$body,*])

public meta def blueprintNodeBlock (cfg : Informal.Graft.BlueprintNodeConfig) :
    DocElabM Term := do
  Informal.Environment.reportImportedConflicts
  if ← inManualGenre then
    manualBlueprintNodeBlock cfg
  else if ← inSlidesGenre then
    Informal.Slides.blueprintNodeBlock cfg
  else
    throwError "Blueprint graft nodes are only available in Manual and Slides documents"

public meta def blueprintSideBySide : DirectiveExpanderOf Informal.Slides.SideBySideConfig
  | cfg, stxs => do
      unless ← inSlidesGenre do
        throwError "`blueprint_side_by_side` is only available in Slides decks; \
          in Manual documents, place `\{blueprint_node}` commands one after another"
      let contents ← stxs.mapM elabBlock
      ``(Verso.Doc.Block.other
          (VersoSlides.BlockExt.wrap $(quote cfg.attrs))
          #[$contents,*])

end Informal.Graft

open Verso Doc Elab

/--
Render a Blueprint preview node by label in either a Manual document or a Slides
deck.
-/
@[block_command]
public meta def blueprint_node : BlockCommandOf Informal.Graft.BlueprintNodeConfig
  | cfg => Informal.Graft.blueprintNodeBlock cfg

/--
Lay out Blueprint graft nodes side by side on a slide. Child blocks are ordinary
`{blueprint_node ...}` commands and keep their own options. Only Slides decks
accept this directive.
-/
@[directive]
public meta def blueprint_side_by_side : DirectiveExpanderOf Informal.Slides.SideBySideConfig :=
  Informal.Graft.blueprintSideBySide
