/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoBlueprint.Environment
import VersoBlueprint.Informal.Block.Assets
import VersoBlueprint.Informal.Block
import VersoBlueprint.Informal.Block.Common
import VersoBlueprint.Informal.Block.Store
import VersoBlueprint.Informal.LeanCodePreview
import VersoBlueprint.Informal.CodeSummary
import VersoBlueprint.LabelNameParsing
import VersoBlueprint.Lean
import VersoBlueprint.Profiling
import VersoBlueprint.Resolve
import VersoBlueprint.TraversalIndex

open Verso Doc Elab
open Verso.Genre Manual
open Verso.ArgParse
open Lean Lean.Elab
open Lean.Doc.Syntax

namespace Informal
open CodeSummary

private partial def previewCodeBlocks
    (blocks : Array (Verso.Doc.Block Verso.Genre.Manual)) :
    Array (Verso.Doc.Block Verso.Genre.Manual) :=
  blocks.foldl (init := #[]) fun acc block =>
    acc ++
      match block with
      | .concat contents =>
        previewCodeBlocks contents
      | .other _ contents =>
        if contents.isEmpty then
          #[block]
        else
          previewCodeBlocks contents
      | _ =>
        #[block]

block_extension Block.informalCode (data : InlineCodeData) where
  data := toJson data
  traverse id data _contents := do
    let .ok cdata@{ label, definedDefs := _, definedTheorems := _, foldProofs := _ } := fromJson? (α := InlineCodeData) data
      | logError s!"Malformed data: {data}"
        pure none
    if let .some _d := Informal.TraversalIndex.InlineCode.object? (← get) label then
      pure none
    else
      let previewBlocks := previewCodeBlocks _contents
      let previewTargets :=
        (cdata.definedDefs.map (·.name)) ++ (cdata.definedTheorems.map (·.name))
      for target in previewTargets do
        let previewKey := Informal.TraversalIndex.LeanCodePreviews.lookupKey target
        let previewData := toJson (LeanCodePreview.Entry.ofInlineBlocks target previewBlocks)
        let existingPreview? := Informal.TraversalIndex.LeanCodePreviews.object? (← get) previewKey
        modify fun s => Informal.TraversalIndex.LeanCodePreviews.saveData s previewKey previewData
        if existingPreview?.isNone then
          let path ← (·.path) <$> read
          let _ ← Verso.Genre.Manual.externalTag id path s!"--lean-code-preview-{previewKey}"
          modify fun s => Informal.TraversalIndex.LeanCodePreviews.saveId s previewKey id
      let path ← (·.path) <$> read
      let _ ← Verso.Genre.Manual.externalTag id path s!"--informal-code-{label}"
      modify λ s => Informal.TraversalIndex.InlineCode.saveId s label id
      modify λ s => Informal.TraversalIndex.InlineCode.saveData s label (toJson cdata)
      pure none
  toTeX := none
  extraCss := Informal.Block.Assets.codeCssAssets
  extraJs := ([] : List String)
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun _goI goB id data blocks => do
      let .ok { label, definedDefs, definedTheorems, foldProofs } := fromJson? (α := InlineCodeData) data
        | HtmlT.logError s!"Malformed data: {data}"
          pure .empty
      let s ← HtmlT.state
      let ctxt ← HtmlT.context
      let attrs := s.htmlId id
      let panelHeader :=
        match Informal.TraversalIndex.Nodes.data? s label with
        | some b =>
          let b := b.withResolvedNumbering s (numberedPartPrefix? ctxt)
          codePanelHeader b (b.displayNumber s)
        | none => fallbackCodePanelHeader
      let getDeclHref (decl : Name) : Option String :=
        Resolve.resolveInlineLeanDeclHref? s decl
      let panelSummary :=
        renderPanelIndicator label
          {
            source := some (.inline { label, definedDefs, definedTheorems, foldProofs })
          }
          getDeclHref
      let panelAttrs := attrs.push ("data-bp-proof-fold", if foldProofs then "on" else "off")
      let panelBody := .seq (← blocks.mapM goB)
      pure <| mkCodePanel panelHeader panelSummary.summaryTitle panelSummary.indicator panelBody panelAttrs

structure CodeConfig where
  label : Data.Label
  leanLabel : Name
  labelSyntax : Syntax := Syntax.missing

section
variable [Monad m] [MonadError m] [MonadOptions m]

def CodeConfig.parse : ArgParse m CodeConfig :=
  (fun (labelArg : Verso.ArgParse.WithSyntax String) opts =>
    let label := LabelNameParsing.parse labelArg.val
    let leanLabel := LabelNameParsing.parse labelArg.val (some opts)
    {
      label
      leanLabel
      labelSyntax := labelArg.syntax
    }) <$> .positional `label (.withSyntax .string)
      <*> .lift "current elaboration options" getOptions

instance : FromArgs CodeConfig m where
  fromArgs := CodeConfig.parse

end

structure TexConfig where
  label? : Option Data.Label := none
  slot : String := Data.defaultTexSourceSlot

section
variable [Monad m] [MonadError m]

private def texSlot : ValDesc m String := {
  description := "a tex witness slot name"
  signature := CanMatch.Ident ∪ CanMatch.String
  get := fun
    | .name id =>
      pure id.getId.toString
    | .str s =>
      let slot := s.getString.trimAscii.toString
      if slot.isEmpty then
        throwErrorAt s "Expected a non-empty tex witness slot"
      else
        pure slot
    | other =>
      throwError "Expected a tex witness slot identifier or string, got {toMessageData other}"
}

def TexConfig.parse : ArgParse m TexConfig :=
  (fun labelArg? slotArg? =>
    {
      label? := labelArg?.map (fun labelArg => LabelNameParsing.parse labelArg.val)
      slot := slotArg?.getD Data.defaultTexSourceSlot
    }) <$> ((some <$> .positional `label (.withSyntax .string)) <|> pure none)
        <*> .named `slot texSlot true

instance : FromArgs TexConfig m where
  fromArgs := TexConfig.parse

end

/-- Interpreting Embedded Lean Code blocks -/
private def leanImpl : CodeBlockExpanderOf CodeConfig
  | cfg, contents => do
    let leanCfg : Lean.LeanBlockConfig := { Lean.defaultConfig with name := some cfg.leanLabel }
    let res ← Lean.elabCommands leanCfg contents
    let codeBlock := res.block
    let definedDefs := res.definedDefs.map CodeDeclData.ofLiterateDef
    let definedTheorems := res.definedTheorems.map CodeDeclData.ofLiterateThm
    let data : InlineCodeData := {
      label := cfg.label
      definedDefs
      definedTheorems
      foldProofs := verso.blueprint.foldProofs.get (← getOptions)
    }
    let codeRef ← getRef
    Environment.registerCode cfg.label codeRef res.definedDefs res.definedTheorems
    ``(Block.other (Block.informalCode $(quote data)) #[$codeBlock])

@[code_block]
def lean : CodeBlockExpanderOf CodeConfig
  | cfg, contents => do
    Profile.withDocElab "code_block" "lean" <| leanImpl cfg contents

/-- Internal Lean setup blocks: executed but not rendered and not tracked as blueprint code blocks. -/
private def internalImpl : CodeBlockExpanderOf Unit
  | _, contents => do
    let leanCfg : Lean.LeanBlockConfig := { Lean.defaultConfig with «show» := false, name := none }
    let _ ← Lean.elabCommands leanCfg contents
    ``(Block.concat #[])

@[code_block]
def internal : CodeBlockExpanderOf Unit
  | cfg, contents => do
    Profile.withDocElab "code_block" "internal" <| internalImpl cfg contents

private def rocqImpl : CodeBlockExpanderOf Unit
  | _cfg, contents => do
    ``(Block.code $contents)

@[code_block]
def rocq : CodeBlockExpanderOf Unit
  | cfg, contents => do
    Profile.withDocElab "code_block" "rocq" <| rocqImpl cfg contents

private def texImpl : CodeBlockExpanderOf TexConfig
  | cfg, contents => do
    match cfg.label? with
    | some label =>
      Environment.registerTexSource label cfg.slot { raw := contents.getString }
    | none =>
      pure ()
    ``(Block.concat #[])

@[code_block]
def tex : CodeBlockExpanderOf TexConfig
  | cfg, contents => do
    Profile.withDocElab "code_block" "tex" <| texImpl cfg contents

end Informal
