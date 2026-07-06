/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoBlueprint.Compat
import VersoBlueprint.Commands.Common
import VersoBlueprint.Data
import VersoBlueprint.Environment
import VersoBlueprint.Informal.Block
import VersoBlueprint.Informal.Block.Store
import VersoBlueprint.Informal.LabelArg
import VersoBlueprint.Informal.UseConfig
import VersoBlueprint.Lib.ExtensionDecode
import VersoBlueprint.Lib.HoverRender
import VersoBlueprint.PreviewCache
import VersoBlueprint.Profiling
import VersoBlueprint.TraversalIndex

open Verso Doc Elab
open Verso.Genre Manual
open Verso.ArgParse
open Lean Lean.Elab
open Lean.Doc.Syntax

namespace Informal

def usesAssetBundle : Informal.Commands.BlueprintAssetBundle :=
  Informal.Commands.inlinePreviewAssetBundle

/--
Arguments accepted by the inline `{uses ...}` role.

This role renders a reference and registers a dependency edge from the enclosing
block. Its `origin` and `intent` options share the same metadata semantics as
block-level `(uses_origin := ...)` and `(uses_intent := ...)`.
-/
structure UsesConfig where
  label : Data.Label
  labelSyntax : Syntax := Syntax.missing
  origin : Data.UseOrigin := .manual
  invalidOrigin : Option String := none
  intent : Data.UseIntent := .regular
  invalidIntent : Option String := none

/--
Arguments accepted by the inline `{bpref ...}` role.

`bpref` renders the same kind of hoverable Blueprint reference as `{uses ...}`,
but deliberately does not accept dependency metadata or register a use edge.
-/
structure BprefConfig where
  label : Data.Label
  labelSyntax : Syntax := Syntax.missing

section
variable [Monad m] [MonadError m]

def UsesConfig.parse : ArgParse m UsesConfig :=
  (fun (labelArg : Verso.ArgParse.WithSyntax String) origin intent =>
    let parsedLabel := LabelArg.parse labelArg
    let metadata := UseConfig.parseMetadata origin intent
    {
      label := parsedLabel.label
      labelSyntax := parsedLabel.labelSyntax
      origin := metadata.origin
      invalidOrigin := metadata.invalidOrigin
      intent := metadata.intent
      invalidIntent := metadata.invalidIntent
    }) <$> .positional `label (.withSyntax .string)
        <*> .named `origin .string true <*> .named `intent .string true

instance : FromArgs UsesConfig m where
  fromArgs := UsesConfig.parse

def BprefConfig.parse : ArgParse m BprefConfig :=
  (fun (labelArg : Verso.ArgParse.WithSyntax String) =>
    let parsedLabel := LabelArg.parse labelArg
    {
      label := parsedLabel.label
      labelSyntax := parsedLabel.labelSyntax
    }) <$> .positional `label (.withSyntax .string)

instance : FromArgs BprefConfig m where
  fromArgs := BprefConfig.parse

end

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
  let previewTarget := Informal.HoverRender.InlinePreviewTarget.withLookupKey
    pid ptitle pkey
  Informal.HoverRender.inlinePreviewTargetNode node previewTarget

inline_extension Inline.informal (data : InlineData) where
  data := toJson data
  traverse _id data _contents := do
    let some _ ← ExtensionDecode.decode? (α := InlineData) data
        (fun _ => s!"Malformed data in Inline.informal traversal: {data}")
      | pure none
    pure none
  extraCss := usesAssetBundle.css
  extraJs := usesAssetBundle.js
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun goI _id data inlines => do
      let some { label, block } ← ExtensionDecode.decode? (α := InlineData) data
          (fun _ => "Malformed data in Inline.informal traversal")
        | pure .empty
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

private def nodeRefTerm (label : Data.Label) (contents : Array (TSyntax `inline)) : DocElabM Term := do
    let contents ← contents.mapM elabInline
    let node ← Environment.getNode? label
    let data : InlineData := { label, block := node.map (fun n => n.toBlockInfo label) }
    ``(Inline.other (Inline.informal $(quote data)) #[$contents,*])

@[role]
def uses : RoleExpanderOf UsesConfig
  | cfg, contents => do
    Profile.withDocElab "role" "uses" <| do
      if let some raw := cfg.invalidOrigin then
        logErrorAt cfg.labelSyntax m!"uses reference to {cfg.label} has invalid '(origin := \"{raw}\")'; expected one of {UseConfig.allowedOriginValues}"
      if let some raw := cfg.invalidIntent then
        logErrorAt cfg.labelSyntax m!"uses reference to {cfg.label} has invalid '(intent := \"{raw}\")'; expected one of {UseConfig.allowedIntentValues}"
      let term ← nodeRefTerm cfg.label contents
      let useRef ← getRef
      Environment.addUse useRef {
        label := cfg.label
        origin := cfg.origin
        intent := cfg.intent
      }
      pure term

/-- Reference a Blueprint node without registering a dependency edge. -/
@[role]
def bpref : RoleExpanderOf BprefConfig
  | cfg, contents => do
    Profile.withDocElab "role" "bpref" <| nodeRefTerm cfg.label contents

end Informal
