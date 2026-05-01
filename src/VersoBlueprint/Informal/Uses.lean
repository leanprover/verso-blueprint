/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoBlueprint.Commands.Common
import VersoBlueprint.Environment
import VersoBlueprint.Informal.Block
import VersoBlueprint.Informal.Block.Store
import VersoBlueprint.Lib.HoverRender
import VersoBlueprint.PreviewCache
import VersoBlueprint.Profiling
import VersoBlueprint.TraversalIndex

open Verso Doc Elab
open Verso.Genre Manual
open Lean Lean.Elab
open Lean.Doc.Syntax

namespace Informal

structure InlineData where
  label : Data.Label
  block : Option BlockData
deriving FromJson, ToJson, Quote

private def blockHoverTitle
    (state : Verso.Genre.Manual.TraverseState) (block : BlockData) : String :=
  block.displayTitle state

def usePreviewId (label : Data.Label) (block : BlockData) : String :=
  let facet := PreviewCache.Facet.ofInProgressKind block.kind
  s!"bp-uses-{Informal.HoverRender.previewKey (toString label)}-{facet.suffix}"

def usePreviewLookupKey (label : Data.Label) (block : BlockData) : String :=
  PreviewCache.key label (PreviewCache.Facet.ofInProgressKind block.kind)

private def wrapUseLinkPreview (node : Verso.Output.Html)
    (state : Verso.Genre.Manual.TraverseState)
    (label : Data.Label) (block : BlockData) :
    Verso.Output.Html :=
  let pid := usePreviewId label block
  let pkey := usePreviewLookupKey label block
  let ptitle := blockHoverTitle state block
  Informal.HoverRender.inlinePreviewNode
    node pid ptitle
    (previewLookupKey? := some pkey)
    (previewFallbackLabel? := some s!"{label}")

inline_extension Inline.informal (data : InlineData) where
  data := toJson data
  traverse _id data _contents := do
    let .ok _ := fromJson? (α := InlineData) data
      | logError s!"Malformed data in Inline.informal traversal: {data}"
        pure none
    pure none
  extraCss := Informal.Commands.withInlinePreviewCssAssets
  extraJs := Informal.Commands.withInlinePreviewJsAssets [] []
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun goI _id data inlines => do
      let .ok { label, block } := fromJson? (α := InlineData) data
        | HtmlT.logError "Malformed data in Inline.informal traversal"
          pure .empty
      let st ← HtmlT.state
      let storedBlock? := resolveStoredBlockData? st label
      let resolvedBlock : Option BlockData :=
        match block, storedBlock? with
        | some b, some stored =>
          some {
            b with
            partPrefix := b.partPrefix <|> stored.partPrefix
            globalCount := b.globalCount <|> stored.globalCount
          }
        | none, some stored => some stored
        | some b, none => some b
        | none, none => none
      let href : Option String :=
        Informal.TraversalIndex.Nodes.href? st label
      let renderedInlines ← inlines.mapM goI
      match resolvedBlock with
      | none =>
        if inlines.isEmpty then
          return {{ <span> "[??]" </span> }}
        else
          return {{ <span> {{renderedInlines}} </span> }}
      | some block =>
        let block := block.withResolvedNumbering st
        let labelText := s!"{label}"
        let plainContent : Verso.Output.Html :=
          if inlines.isEmpty then
            let titleText := blockHoverTitle st block
            if let some href := href then
              {{<a href={{href}} title={{labelText}}>{{titleText}}</a>}}
            else
              {{<span title={{labelText}}>{{titleText}}</span>}}
          else if let some href := href then
            {{<a href={{href}} title={{labelText}}>{{renderedInlines}}</a>}}
          else
            renderedInlines
        let hovered := wrapUseLinkPreview plainContent st label block
        return {{<span>{{hovered}}</span>}}
  toTeX := none

private def Data.Node.toBlockInfo (node : Data.Node) (label : Data.Label) : BlockData :=
  {
    kind := .statement node.kind
    label
    count := node.count
    owner := node.owner
    tags := node.tags
    effort := node.effort
    priority := node.priority
    prUrl := node.prUrl
  }

private def usesImpl : RoleExpanderOf Config
  | cfg, contents => do
    let contents ← contents.mapM elabInline
    let label := cfg.label
    let node ← Environment.getNode? label
    let useRef ← getRef
    Environment.addDep useRef label
    let data : InlineData := { label, block := node.map (fun n => n.toBlockInfo label) }
    ``(Inline.other (Inline.informal $(quote data)) #[$contents,*])

@[role]
def uses : RoleExpanderOf Config
  | cfg, contents => do
    Profile.withDocElab "role" "uses" <| usesImpl cfg contents

end Informal
