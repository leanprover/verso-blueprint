/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoBlueprint.Environment
import VersoBlueprint.Informal.Block.Assets
import VersoBlueprint.Informal.Block.Common
import VersoBlueprint.Informal.Block.Store
import VersoBlueprint.Informal.Code
import VersoBlueprint.Lib.ExtensionDecode
import VersoBlueprint.Profiling
import VersoBlueprint.Informal.RustPanel
import VersoBlueprint.TeX
import VersoBlueprint.TraversalIndex

open Verso Doc Elab
open Verso.Genre Manual
open Lean Lean.Elab

namespace Informal

def rustBlockAssetBundle : Informal.Commands.BlueprintAssetBundle :=
  Informal.Block.Assets.codeAssetBundle.withCss [Informal.Rust.css]

block_extension Block.informalRustCode (data : Informal.Rust.InlineCodeData) where
  data := toJson data
  usePackages := Informal.TeX.standardMathUsePackages
  traverse id data _contents := do
    let some cdata ← ExtensionDecode.decode? (α := Informal.Rust.InlineCodeData) data
        (fun _ => s!"Malformed Rust data: {data}")
      | pure none
    if let some _ := Informal.TraversalIndex.RustInlineCode.object? (← get) cdata.label then
      pure none
    else
      let path ← (·.path) <$> read
      let _ ← Verso.Genre.Manual.externalTag id path s!"--informal-rust-code-{cdata.label}"
      modify fun s => Informal.TraversalIndex.RustInlineCode.saveId s cdata.label id
      modify fun s => Informal.TraversalIndex.RustInlineCode.saveData s cdata.label cdata
      pure none
  toTeX := some <| fun _goI _goB _id data _blocks => do
      let some cdata ← ExtensionDecode.decode? (α := Informal.Rust.InlineCodeData) data
          (fun _ => s!"Malformed Rust code data: {data}")
        | pure .empty
      let title := s!"Rust code for {cdata.label}"
      pure <| Informal.TeX.verbatimBlock title cdata.raw
  extraCss := rustBlockAssetBundle.css
  extraJs := rustBlockAssetBundle.js
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun _goI _goB id data _blocks => do
      let some cdata ← ExtensionDecode.decode? (α := Informal.Rust.InlineCodeData) data
          (fun _ => s!"Malformed Rust code data: {data}")
        | pure .empty
      let s ← HtmlT.state
      let ctxt ← HtmlT.context
      let attrs := s.htmlId id
      let panelHeader :=
        match Informal.TraversalIndex.Nodes.data? s cdata.label with
        | some b =>
          let b := b.withResolvedNumberingInContext s ctxt
          Informal.Rust.codePanelHeader b (b.displayNumber s)
        | none => Informal.Rust.fallbackCodePanelHeader
      pure <| Informal.Rust.renderRawCodePanel panelHeader s!"Rust code for {cdata.label}" cdata.raw
        attrs (folded := cdata.foldCodeBlock)

private def rustImpl : CodeBlockExpanderOf Informal.CodeConfig
  | cfg, contents => do
    let data : Informal.Rust.InlineCodeData := {
      label := cfg.label
      raw := contents.getString
      foldCodeBlock := verso.blueprint.foldCodeBlocks.get (← getOptions)
    }
    Environment.registerRustCode cfg.label { raw := contents.getString }
    ``(Block.other (Block.informalRustCode $(quote data)) #[])

@[code_block]
def rust : CodeBlockExpanderOf Informal.CodeConfig
  | cfg, contents => do
    Profile.withDocElab "code_block" "rust" <| rustImpl cfg contents

end Informal
