/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoManual
public import VersoBlueprint.Data
public import VersoBlueprint.Informal.Block.Assets
public import VersoBlueprint.Informal.Block
public import VersoBlueprint.Informal.Block.Common
public import VersoBlueprint.Informal.Block.Store
public import VersoBlueprint.Informal.LeanCodePreview
public import VersoBlueprint.Informal.Code.Data
public import VersoBlueprint.Informal.CodeSummary
public import VersoBlueprint.Informal.ExternalMarkupView
public import VersoBlueprint.Lean
public import VersoBlueprint.Lib.ExtensionDecode
public import VersoBlueprint.Resolve
public import VersoBlueprint.TeX
public import VersoBlueprint.TraversalIndex
public meta import VersoManual
public meta import VersoBlueprint.Data
public meta import VersoBlueprint.DependencyAnalysis
public meta import VersoBlueprint.Environment
public meta import VersoBlueprint.Informal.Block
public meta import VersoBlueprint.Informal.Block.Common
public meta import VersoBlueprint.Informal.Code.Data
public meta import VersoBlueprint.LabelNameParsing
public meta import VersoBlueprint.Lean
public meta import VersoBlueprint.Profiling

public section

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
  usePackages := Informal.TeX.standardMathUsePackages
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
      let declarations := cdata.declarations
      if !declarations.isEmpty then
        let previewKey := Informal.TraversalIndex.LeanCodePreviews.lookupInlineKey label
        let sourceLocation :=
          match declarations[0]? with
          | some decl => decl.sourceLocation
          | none =>
              Informal.Data.SourceLocationResult.unavailable
                "inline Lean preview source location unavailable"
        let previewData := toJson
          (LeanCodePreview.Entry.ofInlineBlocks label previewBlocks sourceLocation)
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
  toTeX := some <| fun _goI goB _id data blocks => do
      let title ←
        match fromJson? (α := InlineCodeData) data with
        | .ok cdata => pure s!"Lean code for {cdata.label}"
        | .error err =>
          Verso.reportError s!"Malformed data in Block.informalCode.toTeX ({err}): {data}"
          pure "Lean code"
      let body ← blocks.mapM goB
      pure <| Informal.TeX.boldHeadingBlocks title body
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

meta section

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

end

block_extension Block.externalMarkup (data : ExternalMarkupBlockData) where
  data := toJson data
  usePackages := Informal.TeX.standardMathUsePackages
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
  toTeX :=
    open Verso.Output.TeX in
    some <| fun _goI _goB _id data _blocks => do
      let .ok cdata := fromJson? (α := ExternalMarkupBlockData) data
        | Verso.reportError s!"Malformed external markup data in Block.externalMarkup.toTeX: {data}"
          pure .empty
      let summary := ExternalMarkupView.displaySummary cdata.markup
      match cdata.display with
      | .hidden => pure .empty
      | .summary => pure <| .text summary
      | .source =>
        pure <| Informal.TeX.verbatimBlock summary cdata.markup.raw
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

meta section

private def inlineDeclSourceLocation (declName : Name) (stx : Syntax) : DocElabM Data.SourceLocationResult := do
  match ← Data.SourceLocation.ofSyntax? stx with
  | some location => pure <| Data.SourceLocationResult.found location
  | none =>
      pure <| Data.SourceLocationResult.unavailable
        s!"inline Lean declaration source location unavailable for {declName}"

/-- Interpreting Embedded Lean Code blocks -/
private def leanImpl : CodeBlockExpanderOf CodeConfig
  | cfg, contents => do
    let leanCfg : Lean.LeanBlockConfig := { Lean.defaultConfig with name := some cfg.leanLabel }
    let res ← Lean.elabCommands leanCfg contents
    let codeBlock := res.block
    let definedDefs ← res.definedDefs.mapM fun decl => do
      let sourceLocation ← inlineDeclSourceLocation decl.name decl.commandStx
      pure <| CodeDeclData.ofLiterateDef decl sourceLocation
    let definedTheorems ← res.definedTheorems.mapM fun decl => do
      let sourceLocation ← inlineDeclSourceLocation decl.name decl.commandStx
      pure <| CodeDeclData.ofLiterateThm decl sourceLocation
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

end

end Informal
