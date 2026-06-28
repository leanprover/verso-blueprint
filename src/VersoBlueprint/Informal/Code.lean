/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoBlueprint.Compat
import VersoBlueprint.DependencyAnalysis
import VersoBlueprint.Environment
import VersoBlueprint.Informal.Block.Assets
import VersoBlueprint.Informal.Block
import VersoBlueprint.Informal.Block.Common
import VersoBlueprint.Informal.Block.Store
import VersoBlueprint.Informal.LeanCodePreview
import VersoBlueprint.Informal.CodeSummary
import VersoBlueprint.Informal.ExternalMarkupView
import VersoBlueprint.LabelNameParsing
import VersoBlueprint.Lean
import VersoBlueprint.Lib.ExtensionDecode
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

private def preservePreviewBlock (container : Verso.Genre.Manual.Block) : Bool :=
  container.name == ``Manual.InlineLean.Block.lean ||
    container.name == ``Manual.Block.lean

private partial def previewCodeBlocks
    (id : Verso.Multi.InternalId)
    (blocks : Array (Verso.Doc.Block Verso.Genre.Manual)) :
    Array (Verso.Doc.Block Verso.Genre.Manual) :=
  blocks.foldl (init := #[]) fun acc block =>
    acc ++
      match block with
      | .concat contents =>
        previewCodeBlocks id contents
      | .other container contents =>
        if preservePreviewBlock container then
          #[.other { container with id := some id } contents]
        else if contents.isEmpty then
          #[block]
        else
          previewCodeBlocks id contents
      | _ =>
        #[block]

block_extension Block.informalCode (data : InlineCodeData) where
  data := toJson data
  traverse id data _contents := do
    let some cdata ← ExtensionDecode.decode? (α := InlineCodeData) data
        (fun _ => s!"Malformed data: {data}")
      | pure none
    let label := cdata.label
    if let .some _d := Informal.TraversalIndex.InlineCode.object? (← get) label then
      pure none
    else
      if !cdata.statementUses.isEmpty || !cdata.proofUses.isEmpty then
        if let some existing := Informal.TraversalIndex.Nodes.storedData? (← get) label then
          let updated := {
            existing with
              statementUses := Data.UseRef.mergeByLabel existing.statementUses cdata.statementUses
              proofUses := Data.UseRef.mergeByLabel existing.proofUses cdata.proofUses
          }
          modify fun s => Informal.TraversalIndex.Nodes.saveData s label (toJson updated)
      let previewBlocks := previewCodeBlocks id _contents
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
      let some cdata ← ExtensionDecode.decode? (α := InlineCodeData) data
          (fun _ => s!"Malformed data: {data}")
        | pure .empty
      let { label, definedDefs, definedTheorems, statementUses := _, proofUses := _, foldCodeBlock, foldProofs } := cdata
      let s ← HtmlT.state
      let ctxt ← HtmlT.context
      let attrs := s.htmlId id
      let panelHeader :=
        match Informal.TraversalIndex.Nodes.data? s label with
        | some b =>
          let b := b.withResolvedNumberingInContext s ctxt
          codePanelHeader b (b.displayNumber s)
        | none => fallbackCodePanelHeader
      let getDeclHref (decl : Name) : Option String :=
        Resolve.resolveInlineLeanDeclHref? s decl
      let panelSummary :=
        renderPanelIndicator label
          {
            source := some (.inline { label, definedDefs, definedTheorems, foldCodeBlock, foldProofs })
          }
          getDeclHref
      let panelAttrs := attrs.push ("data-bp-proof-fold", if foldProofs then "on" else "off")
      let panelBody := .seq (← blocks.mapM goB)
      pure <| mkCodePanel panelHeader panelSummary.summaryTitle panelSummary.indicator panelBody panelAttrs
        (folded := foldCodeBlock)

structure CodeConfig where
  label : Data.Label
  leanLabel : Name
  autoDeps : Option Bool := none
  labelSyntax : Syntax := Syntax.missing

section
variable [Monad m] [MonadInfoTree m] [MonadResolveName m] [MonadLiftT CoreM m] [MonadEnv m]
    [MonadError m] [MonadOptions m] [MonadLog m] [AddMessageContext m]

def CodeConfig.parse : ArgParse m CodeConfig :=
  (fun (labelArg : Verso.ArgParse.WithSyntax String) autoDeps opts =>
    let label := LabelNameParsing.parse labelArg.val
    let leanLabel := LabelNameParsing.parse labelArg.val (some opts)
    {
      label
      leanLabel
      autoDeps
      labelSyntax := labelArg.syntax
    }) <$> .positional `label (.withSyntax .string)
      <*> .named' `autoDeps true
      <*> .lift "current elaboration options" getOptions

instance : FromArgs CodeConfig m where
  fromArgs := CodeConfig.parse

end

/-- How external markup code blocks should be rendered in the current document. -/
inductive ExternalMarkupDisplayMode where
  | hidden
  | summary
  | source
deriving Repr, Inhabited, BEq, ToJson, FromJson, Quote

def ExternalMarkupDisplayMode.parse? (raw : String) : Option ExternalMarkupDisplayMode :=
  match raw.trimAscii.toString.toLower with
  | "hidden" | "hide" | "none" => some .hidden
  | "summary" | "metadata" => some .summary
  | "source" | "raw" => some .source
  | _ => none

register_option verso.blueprint.externalMarkup.display : String := {
  defValue := "hidden"
  descr := "Default display mode for external markup blocks: `hidden` (default), `summary`, or `source`"
}

def ExternalMarkupDisplayMode.fromOptions (opts : Lean.Options) : ExternalMarkupDisplayMode :=
  match ExternalMarkupDisplayMode.parse? (verso.blueprint.externalMarkup.display.get opts) with
  | some mode => mode
  | none => .hidden

structure ExternalMarkupConfig where
  label? : Option Data.Label := none
  slot : String := Data.defaultExternalMarkupSlot
  path? : Option String := none
  startLine? : Option Nat := none
  startCharacter? : Option Nat := none
  endLine? : Option Nat := none
  endCharacter? : Option Nat := none
  display : Option ExternalMarkupDisplayMode := none

section
variable [Monad m] [MonadError m]

private def externalMarkupSlot : ValDesc m String := {
  description := "an external markup slot name"
  signature := CanMatch.Ident ∪ CanMatch.String
  get := fun
    | .name id =>
      pure id.getId.toString
    | .str s =>
      let slot := s.getString.trimAscii.toString
      if slot.isEmpty then
        throwErrorAt s "Expected a non-empty external markup slot"
      else
        pure slot
    | other =>
      throwError "Expected an external markup slot identifier or string, got {toMessageData other}"
}

private def externalMarkupDisplay : ValDesc m ExternalMarkupDisplayMode := {
  description := "an external markup display mode"
  signature := CanMatch.Ident ∪ CanMatch.String
  get := fun
    | .name id =>
      match ExternalMarkupDisplayMode.parse? id.getId.toString with
      | some mode => pure mode
      | none =>
          throwErrorAt id "Expected external markup display mode 'hidden', 'summary', or 'source'"
    | .str s =>
      match ExternalMarkupDisplayMode.parse? s.getString with
      | some mode => pure mode
      | none =>
          throwErrorAt s "Expected external markup display mode 'hidden', 'summary', or 'source'"
    | other =>
      throwError "Expected an external markup display mode identifier or string, got {toMessageData other}"
}

def ExternalMarkupConfig.parse : ArgParse m ExternalMarkupConfig :=
  (fun labelArg? slotArg? path? startLine? startCharacter? endLine? endCharacter? display? =>
    {
      label? := labelArg?.map (fun labelArg => LabelNameParsing.parse labelArg.val)
      slot := slotArg?.getD Data.defaultExternalMarkupSlot
      path? := path?.map (·.trimAscii.toString)
      startLine?
      startCharacter?
      endLine?
      endCharacter?
      display := display?
    }) <$> ((some <$> .positional `label (.withSyntax .string)) <|> pure none)
        <*> .named `slot externalMarkupSlot true
        <*> .named `path .string true
        <*> .named' `start_line true
        <*> .named' `start_character true
        <*> .named' `end_line true
        <*> .named' `end_character true
        <*> .named `display externalMarkupDisplay true

instance : FromArgs ExternalMarkupConfig m where
  fromArgs := ExternalMarkupConfig.parse

end

structure ExternalMarkupBlockData where
  label : Data.Label
  markup : Data.ExternalMarkup
  display : ExternalMarkupDisplayMode := .hidden
deriving Repr, Inhabited, FromJson, ToJson, Quote

block_extension Block.externalMarkup (data : ExternalMarkupBlockData) where
  data := toJson data
  traverse id data _contents := do
    let some cdata ← ExtensionDecode.decode? (α := ExternalMarkupBlockData) data
        (fun _ => s!"Malformed external markup data: {data}")
      | pure none
    let existingData := (Informal.TraversalIndex.ExternalMarkup.data? (← get) cdata.label).getD {
      label := cdata.label
    }
    let existing := existingData.markup
    match existing.find? cdata.markup.language cdata.markup.slot with
    | some value =>
        unless value == cdata.markup.value do
          Verso.reportError s!"Label {cdata.label} already has associated {cdata.markup.language} external markup in slot '{cdata.markup.slot}'"
    | none =>
      let updated : Data.ExternalMarkupData := {
        existingData with
        label := cdata.label
        markup := existing.insert cdata.markup
      }
      modify fun s => Informal.TraversalIndex.ExternalMarkup.saveId s cdata.label id
      modify fun s => Informal.TraversalIndex.ExternalMarkup.saveData s cdata.label (toJson updated)
    pure none
  toTeX := none
  extraCss := ({} : Std.HashSet CSS)
  extraJs := ([] : List String)
  toHtml :=
    open Verso.Doc.Html in
    some <| fun _goI _goB _id data _blocks => do
      let some cdata ← ExtensionDecode.decode? (α := ExternalMarkupBlockData) data
          (fun _ => s!"Malformed external markup data: {data}")
        | pure .empty
      pure <|
        match cdata.display with
        | .hidden => .empty
        | .summary => ExternalMarkupView.summaryHtml (ExternalMarkupView.displaySummary cdata.markup)
        | .source => ExternalMarkupView.sourceDetailsHtml cdata.markup

/-- Interpreting Embedded Lean Code blocks -/
private def leanImpl : CodeBlockExpanderOf CodeConfig
  | cfg, contents => do
    let leanCfg : Lean.LeanBlockConfig := { Lean.defaultConfig with name := some cfg.leanLabel }
    let res ← Lean.elabCommands leanCfg contents
    let codeBlock := res.block
    let definedDefs := res.definedDefs.map CodeDeclData.ofLiterateDef
    let definedTheorems := res.definedTheorems.map CodeDeclData.ofLiterateThm
    let mut inferredUseRefs : DependencyAnalysis.InferredUseRefs := {}
    let codeRef ← getRef
    Environment.registerCode cfg.label codeRef res.definedDefs res.definedTheorems
    if DependencyAnalysis.enabled (← getOptions) cfg.autoDeps then
      let decls := (res.definedDefs.map (·.name)) ++ (res.definedTheorems.map (·.name))
      let deps ← liftM <| DependencyAnalysis.inferDecls decls
      inferredUseRefs := deps.toUseRefs (currentLabel? := some cfg.label)
      liftM <| DependencyAnalysis.attachInferredUseRefs cfg.label codeRef inferredUseRefs
    let data : InlineCodeData := {
      label := cfg.label
      definedDefs
      definedTheorems
      statementUses := inferredUseRefs.statement
      proofUses := inferredUseRefs.proof
      foldCodeBlock := verso.blueprint.foldCodeBlocks.get (← getOptions)
      foldProofs := verso.blueprint.foldProofs.get (← getOptions)
    }
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

private def ExternalMarkupConfig.location? (cfg : ExternalMarkupConfig) :
    DocElabM (Option Data.ExternalMarkupLocation) := do
  match cfg.path?, cfg.startLine?, cfg.startCharacter?, cfg.endLine?, cfg.endCharacter? with
  | none, none, none, none, none => pure none
  | some path, some startLine, some startCharacter, some endLine, some endCharacter =>
      if path.isEmpty then
        throwError "External markup location path must be non-empty"
      if path.toList.head? == some '/' then
        throwError "External markup location path must be project-relative"
      if endLine < startLine || (endLine == startLine && endCharacter <= startCharacter) then
        throwError "External markup location range must be non-empty and end-exclusive"
      pure <| some {
        path
        range := {
          start := { line := startLine, character := startCharacter }
          «end» := { line := endLine, character := endCharacter }
        }
      }
  | _, _, _, _, _ =>
      throwError "External markup location requires all of '(path := ...)', '(start_line := ...)', '(start_character := ...)', '(end_line := ...)', and '(end_character := ...)'"

private def externalMarkupImpl
    (language : Data.ExternalMarkupLanguage) : CodeBlockExpanderOf ExternalMarkupConfig
  | cfg, contents => do
    let location? ← cfg.location?
    let raw := contents.getString
    let markup : Data.ExternalMarkup := {
      language
      slot := cfg.slot
      raw
      location := location?
    }
    match cfg.label? with
    | some label =>
      Environment.registerExternalMarkup label markup
      let display := cfg.display.getD <| ExternalMarkupDisplayMode.fromOptions (← getOptions)
      let data : ExternalMarkupBlockData := {
        label
        markup
        display
      }
      ``(Block.other (Block.externalMarkup $(quote data)) #[])
    | none =>
      ``(Block.concat #[])

@[code_block]
def tex : CodeBlockExpanderOf ExternalMarkupConfig
  | cfg, contents => do
    Profile.withDocElab "code_block" "tex" <| externalMarkupImpl .tex cfg contents

@[code_block]
def md : CodeBlockExpanderOf ExternalMarkupConfig
  | cfg, contents => do
    Profile.withDocElab "code_block" "md" <| externalMarkupImpl .markdown cfg contents

end Informal
