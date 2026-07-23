/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoSlides
import Verso.Doc.Elab
import VersoBlueprint.Informal.Block.Assets
import VersoBlueprint.Informal.Block.Store
import VersoBlueprint.Informal.Block.Traversal
import VersoBlueprint.Informal.LeanCodePreview
import VersoBlueprint.Environment
import VersoBlueprint.Graft.Assets
import VersoBlueprint.Graft.Node
import VersoBlueprint.Graft.Render
import VersoBlueprint.PreviewManifest.BlockRender
import VersoBlueprint.Lib.ExtensionDecode
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

private def pushDistinctHtml (bodies : Array Html) (body : Html) : Array Html :=
  let html := body.asString
  if bodies.any (fun existing => existing.asString == html) then
    bodies
  else
    bodies.push body

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
    (key : String) :
    Doc.Html.HtmlT Verso.Genre.Manual m (Option Html) := do
  match Informal.TraversalIndex.LeanCodePreviews.decodedEntry? state key with
  | none =>
      Verso.reportError s!"Blueprint graft: missing Lean-code preview {key}"
      pure none
  | some (.error err) =>
      Verso.reportError s!"Blueprint graft: malformed Lean-code preview {key}: {err.message}"
      pure none
  | some (.ok stored) =>
      match stored.data.source with
      | .inlineBlocks blocks _sourceLocation => some <$> renderManualBlocks goB blocks
      | .externalDecl decl => pure <| some <| Informal.ExternalCode.renderPreviewHtml #[decl]

private def renderLeanCodeBodies
    [Monad m]
    [MonadBuildLog (Doc.Html.HtmlT Verso.Genre.Manual m)]
    (goB : Doc.Block Verso.Genre.Manual → Doc.Html.HtmlT Verso.Genre.Manual m Html)
    (state : TraverseState)
    (entry : Informal.PreviewManifest.Entry) :
    Doc.Html.HtmlT Verso.Genre.Manual m (Array Html) := do
  let mut bodies := #[]
  for key in entry.leanCodePreviewKeys do
    match ← renderLeanCodePreviewBody? goB state key with
    | none => pure ()
    | some body =>
        if body.asString.trimAscii.isEmpty then
          pure ()
        else
          bodies := pushDistinctHtml bodies body
  pure bodies

private def renderManualGraftNode
    [Monad m]
    [MonadBuildLog (Doc.Html.HtmlT Verso.Genre.Manual m)]
    (goB : Doc.Block Verso.Genre.Manual → Doc.Html.HtmlT Verso.Genre.Manual m Html)
    (cfg : Informal.Graft.BlueprintNodeConfig) :
    Doc.Html.HtmlT Verso.Genre.Manual m Html := do
  let node := cfg.toNode
  let state ← Doc.Html.HtmlT.state
  match Informal.PreviewManifest.findTraversalBlockEntry? state node.key with
  | none =>
      pure <| Html.tag "div" (manualNodeAttrs node) <|
        renderNotice "bp_graft_node_notice" "error" "Blueprint node not found"
          node.selectionDescription
  | some (preview, entry) =>
      if !preview.hasRenderedBody && entry.leanCodePreviewKeys.isEmpty then
        pure <| Html.tag "div" (manualNodeAttrs node) <|
          renderNotice "bp_graft_node_notice" "error"
            "Blueprint node has no cached content" node.key
      else
        let body ←
          if preview.hasRenderedBody then
            renderManualBlocks goB preview.renderedBody.blocks
          else
            pure .empty
        let codeBodies ←
          if node.compact then
            pure #[]
          else
            renderLeanCodeBodies goB state entry
        let content : Informal.PreviewManifest.BlockRender.RenderedContent := {
          body
          codeBodies
        }
        pure <| Informal.Graft.renderNodeWithContent
          manualManifestRenderConfig
          node
          entry
          content
          (Informal.PreviewManifest.groupRelationForEntry? state entry)

/-
Invisible source block that moves an imported `@[blueprint]` node from the
persistent environment into the current document's traversal indexes.

The visible output still goes through the ordinary graft renderer. Keeping the
materializer limited to an empty destination anchor gives attribute-owned nodes
the same numbering, relations, previews, and generated-data path as authored
Blueprint blocks.
-/
open Verso Doc Elab Genre Manual in
block_extension Block.blueprintAttributeNodeSource (data : Informal.BlockData) where
  data := toJson data
  usePackages := Informal.TeX.standardMathUsePackages
  traverse id data contents := do
    let some blockData ←
        Informal.ExtensionDecode.decode?
          (α := Informal.BlockData)
          data
          (fun err => s!"Malformed attribute-owned Blueprint node data ({err}): {data}")
      | pure none
    let blockData := blockData.withTraversalNumberingContext (← read)
    Informal.registerTraversedBlockAssets id blockData contents
    Informal.saveTraversedBlockData id blockData
    pure none
  toTeX := some <| fun _goI _goB _id _data _blocks => pure .empty
  toHtml := some <| fun _goI _goB id _data _blocks => do
    let state ← Doc.Html.HtmlT.state
    pure <| Html.tag "span"
      (state.htmlId id ++ #[
        ("class", "bp_attribute_node_anchor"),
        ("aria-hidden", "true")
      ])
      .empty

open Verso Doc Elab Genre Manual in
block_extension Block.blueprintGraftNode (cfg : Informal.Graft.BlueprintNodeConfig) where
  data := toJson cfg
  usePackages := Informal.TeX.standardMathUsePackages
  traverse _ _ _ := pure none
  toTeX :=
    open Verso.Output.TeX in
    some <| fun _goI _goB _id _data _blocks =>
      pure <| .text "This Blueprint graft node is available in the HTML output."
  extraCss := manualGraftAssetBundle.css
  extraJs := manualGraftAssetBundle.js
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun _goI goB _id data _blocks => do
      let some cfg ←
          Informal.ExtensionDecode.decode?
            (α := Informal.Graft.BlueprintNodeConfig)
            data
            (fun err => s!"Malformed Blueprint graft node data ({err}): {data}")
        | pure .empty
      renderManualGraftNode goB cfg

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

private def nodeIsBlueprintAttributeOwned (node : Informal.Data.Node) : Bool :=
  node.externalRefs.any fun ref => ref.origin == .blueprintAttr

/--
Reconstruct one persisted Manual block inside the consuming document.

Attribute-owned nodes may have bodies that were already elaborated in their
defining module. Encoding those values through Manual's typed JSON instances
lets the generated materializer feed them back through ordinary traversal
without running a synthetic document elaborator or introducing another body
schema.
-/
public def persistedManualBlockFromJson (jsonText : String) : Verso.Doc.Block Verso.Genre.Manual :=
  match Lean.Json.parse jsonText >>= Lean.fromJson? with
  | .ok block => block
  | .error err =>
    .para #[.text s!"Blueprint persisted statement block could not be decoded: {err}"]

private meta def persistedManualBlockTerm
    (block : Verso.Doc.Block Verso.Genre.Manual) : DocElabM (TSyntax `term) := do
  let jsonText := Lean.toJson block |>.compress
  `(Informal.Graft.persistedManualBlockFromJson $(quote jsonText))

private meta def attributeNodeBlockData?
    (cfg : Informal.Graft.BlueprintNodeConfig) :
    DocElabM (Option (Informal.BlockData × Array Syntax)) := do
  let graftNode := cfg.toNode
  let label := Informal.LabelNameParsing.parse graftNode.label
  let some node ← Informal.Environment.getNode? label
    | return none
  if !nodeIsBlueprintAttributeOwned node then
    return none
  let statementStxs ←
    match node.statement with
    | none => pure #[]
    | some statement =>
      if statement.previewBlocks.isEmpty then
        pure statement.elabStx
      else
        statement.previewBlocks.mapM fun block =>
          return (← persistedManualBlockTerm block).raw
  let ownerInfo? ←
    match node.owner with
    | some owner => Informal.Environment.getAuthor? owner
    | none => pure none
  let opts ← getOptions
  let sourceLocation :=
    match ← Informal.Data.SourceLocation.ofSyntax? (← getRef) with
    | some location => Informal.Data.SourceLocationResult.found location
    | none =>
      Informal.Data.SourceLocationResult.unavailable
        s!"placement source location unavailable for {label}"
  let blockData : Informal.BlockData := {
    kind := .statement node.kind
    codeData := Informal.BlockCodeData.ofExternalRefs node.externalRefs
    label
    sourceLocation
    foldProofBlock := verso.blueprint.foldProofBlocks.get opts
    foldCodeBlock := verso.blueprint.foldCodeBlocks.get opts
    parent := node.parent
    count := node.count
    numberingMode := Informal.numberingMode opts
    subNumberingPrefix := Informal.subNumberingPrefix opts
    subNumberingCounter := Informal.subNumberingCounter opts
    statementUses := node.statement.map (·.deps) |>.getD #[]
    proofUses := node.proof.map (·.deps) |>.getD #[]
    owner := node.owner
    ownerDisplayName := ownerInfo?.map (·.displayName)
    ownerUrl := ownerInfo?.bind (·.url)
    ownerImageUrl := ownerInfo?.bind (·.imageUrl)
    tags := node.tags
    effort := node.effort
    priority := node.priority
    prUrl := node.prUrl
  }
  pure <| some (blockData, statementStxs)

private meta def manualBlueprintNodeBlock
    (cfg : Informal.Graft.BlueprintNodeConfig) : DocElabM Term := do
  let graft ←
    ``(Verso.Doc.Block.other
        (Informal.Graft.Block.blueprintGraftNode $(quote cfg))
        #[])
  let some (blockData, statementStxs) ← attributeNodeBlockData? cfg
    | return graft
  let statementTerms : Array (TSyntax `term) := statementStxs.map fun stx => ⟨stx⟩
  ``(Verso.Doc.Block.concat #[
      Verso.Doc.Block.other
        (Informal.Graft.Block.blueprintAttributeNodeSource $(quote blockData))
        #[$statementTerms,*],
      $graft
    ])

public meta def blueprintNodeBlock (cfg : Informal.Graft.BlueprintNodeConfig) :
    DocElabM Term := do
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
