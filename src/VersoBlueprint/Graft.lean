/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoManual
public import VersoSlides
public import Verso.Doc.Elab
import VersoBlueprint.Informal.Block.Assets
import VersoBlueprint.Informal.Block.Traversal
import VersoBlueprint.Informal.LeanCodePreview
import VersoBlueprint.Attribute.Placement
public import VersoBlueprint.Graft.Assets
public import VersoBlueprint.Graft.Node
public import VersoBlueprint.Graft.Render
import VersoBlueprint.PreviewManifest.BlockRender
import VersoBlueprint.Lib.ExtensionDecode
import VersoBlueprint.Slides.Node
import VersoBlueprint.TeX
public meta import VersoManual
public meta import VersoSlides
public meta import Verso.Doc.Elab
public meta import VersoBlueprint.Graft.Node
public meta import VersoBlueprint.Slides.Node

public section

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
  match Informal.TraversalIndex.LeanCodePreviews.decodedEntry? state key with
  | none =>
      Verso.reportError s!"Blueprint graft: missing Lean-code preview {key}"
      pure none
  | some (.error err) =>
      Verso.reportError s!"Blueprint graft: malformed Lean-code preview {key}: {err.message}"
      pure none
  | some (.ok stored) =>
      let body ← match stored.data.source with
        | .inlineBlocks _label blocks _sourceLocation => renderManualBlocks goB blocks
        | .externalDecl decl =>
          pure (Informal.ExternalCode.renderPreviewHtml #[decl]
            (Informal.Resolve.resolveInformalDeclHref? state label)
            (fun decl => Informal.TraversalIndex.ExternalDeclAnchors.htmlIdAttrs state id decl.canonical))
      pure <| some (body, Informal.PreviewManifest.leanCodePreviewData state stored.data)

private def renderLeanCodeBodies
    [Monad m]
    [MonadBuildLog (Doc.Html.HtmlT Verso.Genre.Manual m)]
    (goB : Doc.Block Verso.Genre.Manual → Doc.Html.HtmlT Verso.Genre.Manual m Html)
    (state : TraverseState)
    (id : Verso.Multi.InternalId)
    (entry : Informal.PreviewManifest.Entry) :
    Doc.Html.HtmlT Verso.Genre.Manual m (Array Html × Informal.BlockCodeData) := do
  let mut bodies := #[]
  let mut facts := {}
  for key in entry.leanCodePreviewKeys do
    match ← renderLeanCodePreviewBody? goB state id entry.label key with
    | none => pure ()
    | some (body, codeData) =>
        if body.asString.trimAscii.isEmpty || bodies.any (fun existing => existing.asString == body.asString) then
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
  match Informal.PreviewManifest.findTraversalBlockEntry? state node.key with
  | none =>
      pure <| Html.tag "div" (manualNodeAttrs node) <|
        renderNotice "bp_graft_node_notice" "error" "Blueprint node not found"
          node.selectionDescription
  | some (preview, entry) =>
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
            renderLeanCodeBodies goB state id entry
        let content : Informal.PreviewManifest.BlockRender.RenderedContent := {
          body
          codeBodies
          codeData
        }
        pure <| Informal.Graft.renderNodeWithContent
          { manualManifestRenderConfig with
            nodeAttrs := fun node => state.htmlId id ++ manualNodeAttrs node }
          node
          entry
          content
          (Informal.PreviewManifest.groupRelationForEntry? state entry)

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
      if let some (preview, entry) :=
          Informal.PreviewManifest.findTraversalBlockEntry? (← get) placement.config.toNode.key then
        for key in entry.leanCodePreviewKeys do
          if let some (.ok stored) := Informal.TraversalIndex.LeanCodePreviews.decodedEntry? (← get) key then
            if let .externalDecl decl := stored.data.source then
              Informal.registerExternalDeclAnchors id preview.label #[decl]
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

open Verso Doc Elab Genre Manual in
block_extension Block.blueprintGraftSideBySide (cfg : Informal.Graft.SideBySideConfig) where
  data := toJson cfg
  usePackages := Informal.TeX.standardMathUsePackages
  traverse _ _ _ := pure none
  toTeX := some <| fun _goI goB _id _data blocks => blocks.mapM goB
  extraCss := manualGraftAssetBundle.css
  extraJs := manualGraftAssetBundle.js
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun _goI goB _id data blocks => do
      let cfg ←
        match ←
            Informal.ExtensionDecode.decode?
              (α := Informal.Graft.SideBySideConfig)
              data
              (fun err => s!"Malformed Blueprint graft side-by-side data ({err}): {data}") with
        | some cfg => pure cfg
        | Option.none => pure {}
      let content ← blocks.mapM goB
      pure <| Html.tag "div" cfg.attrs (Html.seq content)

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

public meta def blueprintSideBySide : DirectiveExpanderOf Informal.Graft.SideBySideConfig
  | cfg, stxs => do
      let contents ← stxs.mapM elabBlock
      if ← inManualGenre then
        ``(Verso.Doc.Block.other
            (Informal.Graft.Block.blueprintGraftSideBySide $(quote cfg))
            #[$contents,*])
      else if ← inSlidesGenre then
        let attrs := Informal.Slides.sideBySideAttrs cfg
        ``(Verso.Doc.Block.other
            (VersoSlides.BlockExt.wrap $(quote attrs))
            #[$contents,*])
      else
        throwError "Blueprint side-by-side grafts are only available in Manual and Slides documents"

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
Lay out Blueprint graft nodes side by side. Child blocks are ordinary
`{blueprint_node ...}` commands and keep their own options.
-/
@[directive]
public meta def blueprint_side_by_side : DirectiveExpanderOf Informal.Graft.SideBySideConfig :=
  Informal.Graft.blueprintSideBySide
