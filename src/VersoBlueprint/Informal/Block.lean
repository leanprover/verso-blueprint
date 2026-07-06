/-
Copyright (c) 2025 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias, David Thrane Christiansen
-/

-- XXX VersoManual is not module yet
-- module

-- Blueprint library extending the Verso `Manual` genre.

import Lean.Elab.InfoTree.Types

import VersoManual

import VersoBlueprint.Compat
import VersoBlueprint.Commands.Common
import VersoBlueprint.Data
import VersoBlueprint.Environment
import VersoBlueprint.Informal.Block.Assets
import VersoBlueprint.Informal.Block.Common
import VersoBlueprint.Informal.Block.Config
import VersoBlueprint.Informal.Block.RelatedPanel
import VersoBlueprint.Informal.Block.Render
import VersoBlueprint.Informal.Block.Store
import VersoBlueprint.Informal.Block.Traversal
import VersoBlueprint.Informal.CodeSummary
import VersoBlueprint.Informal.ExternalCode
import VersoBlueprint.Informal.ExternalMarkupRender
import VersoBlueprint.Lib.ExtensionDecode
import VersoBlueprint.PreviewRender
import VersoBlueprint.Resolve
import VersoBlueprint.Source.Metadata
import VersoBlueprint.TeX
import VersoBlueprint.TraversalIndex
import VersoBlueprint.Profiling

set_option doc.verso true

open Verso Doc Elab
open Verso.Genre Manual
open Verso.ArgParse
open Verso.Output.Html
open Lean.Doc.Syntax
open Lean Elab

namespace Informal
open CodeSummary

/- "Informal" Verso objects:

  - An informal verso object is identified by a label, and lives in the `informal` Verso domain.
  - For IO (Informal Object), we associate a `Data` entry, which mainly captures other objects the IO depends on
  - Objects are declared via directives / code blocks
  - Dependencies are declared via the {uses ...}`...` role, which _must_ be inside a directive.

Elaboration, traversal, and rendering are standard, using {ref VersoManual} helpers for custom blocks and inlines.

-/

/- Informal custom blocks -/
block_extension Block.informal (data : BlockData) where
  -- for TOC
  -- localContentItem _ _ _ := none
  data := toJson data
  usePackages := Informal.TeX.standardMathUsePackages
  traverse id data _contents := do
    -- XXX: (maybe) lift the Except into the main monad error thread
    match ← ExtensionDecode.decode? (α := BlockData) data
        (fun err => s!"Malformed data ({err}): {data}") with
    | none =>
      pure none
    | some blockData =>
      let blockData := blockData.withTraversalNumberingContext (← read)
      registerTraversedBlockAssets id blockData _contents
      saveTraversedBlockData id blockData
      if let some sourceRef := blockData.sourceRef then
        match Informal.TraversalIndex.SourceRefs.data? (← get) blockData.label with
        | some existing =>
            unless existing == sourceRef do
              Verso.reportError s!"Label {blockData.label} already has conflicting source provenance"
        | none =>
            modify fun st => Informal.TraversalIndex.SourceRefs.saveData st blockData.label sourceRef
      return none
  toTeX := some <| fun _goI goB _id data blocks => do
      let .ok data := fromJson? (α := BlockData) data
        | Verso.reportError s!"Malformed data in Block.informal.toTeX: {data}"
          pure .empty
      let st ← Verso.Doc.TeX.state
      let data := data.withResolvedNumbering st
      let title := data.displayTitle st
      let body ← blocks.mapM goB
      pure <| Informal.TeX.quotedBlock title body
  extraCss := Informal.Block.Assets.blockCssAssets
  extraJs := Informal.Block.Assets.blockJsAssets
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun _goI goB id data blocks => do
      match ← ExtensionDecode.decode? (α := BlockData) data
          (fun err => s!"Malformed data ({err}): {data}") with
      | none =>
        pure .empty
      | some data =>
        let s ← HtmlT.state
        let ctxt ← HtmlT.context
        let data := data.withResolvedNumberingInContext s ctxt
        let relatedPanelContext := RelatedPanel.RelationContext.ofState s
        let markup :=
          (Informal.TraversalIndex.ExternalMarkup.data? s data.label).map (·.markup.toArray) |>.getD #[]
        let selectedMarkupAndContent? :=
          match data.kind with
          | .statement _ =>
              if blocks.isEmpty then
                Informal.ExternalMarkupRender.selectedContent? {} markup
              else
                none
          | .proof => none
        let sourceBackedAttrs :=
          match selectedMarkupAndContent? with
          | some (selectedMarkup, _) => Informal.ExternalMarkupRender.sourceBackedAttrs selectedMarkup
          | none => #[]
        let attrs := s.htmlId id ++ sourceBackedAttrs
        let codeHref := Informal.TraversalIndex.InlineCode.href? s data.label
        let codeData? : Option InlineCodeData ←
          pure <| Informal.TraversalIndex.InlineCode.data? s data.label
        let codeHint? :=
          match data.kind with
          | .proof => none
          | .statement _ => data.codeData
        let codeSource := BlockCodeData.ofHintAndInline codeHint? codeData?
        let externalDecls := codeHint?.map (·.externalDecls) |>.getD #[]
        let getDeclHref (decl : Name) : Option String :=
          Resolve.resolveInformalDeclHref? s data.label decl
        let getDeclAnchorAttrs (decl : Data.ExternalRef) : Array (String × String) :=
          Informal.TraversalIndex.ExternalDeclAnchors.htmlIdAttrs s data.label decl.canonical
        let cdata := {
          codeHref
          source := codeSource
        }
        let headingParts? : Option CodeSummary.RenderParts :=
          match data.kind with
          | .statement _ => some <| CodeSummary.renderParts data cdata getDeclHref
          | .proof => none
        let externalParts? : Option ExternalCode.RenderParts ←
          match data.kind with
          | .statement _ =>
            if externalDecls.isEmpty then
              pure none
            else
              let externalCdata : CodeSummary.ComputedData := {
                source := some (.external externalDecls)
              }
              let externalSummary := CodeSummary.renderPanelIndicator data.label externalCdata getDeclHref
              let panelHeader := codePanelHeader data (data.displayNumber s)
              some <$> ExternalCode.renderPartsWithPageHovers
                panelHeader
                externalSummary.summaryTitle
                externalSummary.indicator
                externalDecls
                getDeclHref
                getDeclAnchorAttrs
                (folded := data.foldCodeBlock)
          | .proof => pure none
        let externalPanel := (externalParts?.map (·.externalCodePanel)).getD .empty
        let content ←
          match selectedMarkupAndContent? with
          | some (_, selectedContent) => pure selectedContent
          | none => blocks.mapM goB
        let codeEntry := (headingParts?.map (·.codeEntry)).getD .empty
        let groupEntry ← RelatedPanel.renderGroupExtra relatedPanelContext data
        let usesEntry ← RelatedPanel.renderUsesExtra relatedPanelContext data
        let usedByEntry ← RelatedPanel.renderUsedByExtra relatedPanelContext data
        let markupEntry? :=
          renderExternalMarkupHeaderExtra? markup
        let foldInformalBlock :=
          match data.kind with
          | .proof => data.foldProofBlock
          | .statement _ => false
        let headerExtras : HeaderExtras :=
          match data.kind with
          | .proof =>
            {
              uses? := some <| HeaderExtra.uses usesEntry
            }
          | .statement _ =>
            {
              group? := groupEntry.map HeaderExtra.group
              uses? := some <| HeaderExtra.uses usesEntry
              usedBy? := some <| HeaderExtra.usedBy usedByEntry
              markup? := markupEntry?
              code? := some <| HeaderExtra.code codeEntry
            }
        return renderInformalBlockModel {
          data
          context := InformalBlockRenderContext.forBlock data
            (data.displayNumber s)
            (proofCaption? := some (data.displayTitle s))
            (attrs := attrs)
            (headerExtras := headerExtras)
            (folded := foldInformalBlock)
          content
          companionPanels := #[externalPanel]
        }

private structure ParsedDirectiveContents where
  sourceRef? : Option Source.Ref := none
  body : Array (TSyntax `block) := #[]

private def parseDirectiveSourceMetadata
    (cfg : Config) (contents : Array (TSyntax `block)) : DocElabM ParsedDirectiveContents := do
  let leading ← Source.Metadata.splitLeadingMetadata contents
  let sourceRef? ←
    match leading.term? with
    | some term =>
        let metadata ← Source.Metadata.evalNodeMetadataInput term
        if let some sourceRef := metadata.source? then
          let validationErrors := Source.Ref.validationErrors sourceRef
          for error in validationErrors do
            logErrorAt term m!"Label {cfg.label} has invalid source metadata: {toString error}"
          pure (some sourceRef)
        else
          pure none
    | none =>
        pure none
  let body ← Source.Metadata.visibleBlocksWithoutMetadata leading.body fun block =>
    logErrorAt block m!"Label {cfg.label} has a metadata block after visible content; Blueprint source metadata must be the first block inside the directive"
  pure { sourceRef?, body }

private def expanderImpl (kind : Data.NodeKind) (isProof : Bool := false) : DirectiveExpanderOf Config
  | cfg, contents => do
    let blockRef ← getRef
    let resolved ← cfg.resolveForDirective kind isProof
    let parsedContents ← parseDirectiveSourceMetadata cfg contents
    let label := resolved.label
    let accepted ← Environment.push
      label resolved.envKind resolved.codeHint resolved.parent resolved.priority
      resolved.owner resolved.tags resolved.effort resolved.prUrl resolved.statementUses
    let contents ← parsedContents.body.mapM elabBlock
    if !accepted then
      return ← ``(Block.concat #[$contents,*])
    let previewBlocks ← liftM <| Informal.evalElaboratedBlocks (contents.map (·.raw))
    Environment.setPreviewBlocks previewBlocks
    let count ← Environment.pop blockRef
    liftM <| DependencyAnalysis.attachInferredUseRefs label blockRef { proof := resolved.proofUses }
    let node? ← Environment.getNode? label
    let blockKind : Data.InProgressKind ←
      if isProof then
        pure .proof
      else
        let nodeKind ←
          match node? with
            | some node => pure node.kind
            | none =>
              logErrorAt resolved.labelSyntax m!"Internal error: missing node '{label}' after environment registration"
              pure kind
        pure <| .statement nodeKind
    let codeData :=
      match blockKind with
      | .proof => none
      | .statement _ =>
        let externalRefs := node?.map (·.externalRefs) |>.getD #[]
        BlockCodeData.ofExternalRefs externalRefs
    let statementPayload? := node?.bind (·.statement)
    let proofPayload? := node?.bind (·.proof)
    let statementUses := statementPayload?.map (·.deps) |>.getD #[]
    let proofUses := proofPayload?.map (·.deps) |>.getD #[]
    let owner := node?.bind (·.owner)
    let ownerInfo? ←
      match owner with
      | some owner => Environment.getAuthor? owner
      | none => pure none
    let opts ← getOptions
    let sourceLocation :=
      match ← Data.SourceLocation.ofSyntax? resolved.labelSyntax with
      | some location => Data.SourceLocationResult.found location
      | none =>
        Data.SourceLocationResult.unavailable s!"label source location unavailable for {label}"
    let data : BlockData := {
      kind := blockKind
      codeData
      sourceRef := parsedContents.sourceRef?
      label
      sourceLocation
      foldProofBlock := verso.blueprint.foldProofBlocks.get opts
      foldCodeBlock := verso.blueprint.foldCodeBlocks.get opts
      parent := node?.bind (·.parent)
      count
      numberingMode := numberingMode opts
      subNumberingPrefix := subNumberingPrefix opts
      subNumberingCounter := subNumberingCounter opts
      statementUses
      proofUses
      owner
      ownerDisplayName := ownerInfo?.map (·.displayName)
      ownerUrl := ownerInfo?.bind (·.url)
      ownerImageUrl := ownerInfo?.bind (·.imageUrl)
      tags := node?.map (·.tags) |>.getD #[]
      effort := node?.bind (·.effort)
      priority := node?.bind (·.priority)
      prUrl := node?.bind (·.prUrl)
    }
    ``(Block.other (Block.informal $(quote data)) #[$contents,*])

private def directiveName (kind : Data.NodeKind) (isProof : Bool): String :=
  if isProof then "proof" else (toString kind).toLower

private def expander (kind : Data.NodeKind) (isProof : Bool := false) : DirectiveExpanderOf Config
  | cfg, contents => do
    let label := (directiveName kind isProof)
    Profile.withDocElab "directive" label <|
      (expanderImpl kind isProof) cfg contents

@[directive] def «definition» := expander .definition
@[directive] def «proposition» := expander .proposition
@[directive] def «lemma_» := expander .lemma
@[directive] def «theorem» := expander .theorem
@[directive] def «corollary» := expander .corollary
@[directive] def «proof» := expander .lemma (isProof := true)

end Informal
