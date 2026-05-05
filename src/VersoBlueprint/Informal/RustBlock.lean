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
import VersoBlueprint.Profiling
import VersoBlueprint.Rust
import VersoBlueprint.TraversalIndex

open Verso Doc Elab
open Verso.Genre Manual
open Lean Lean.Elab

namespace Informal

block_extension Block.informalRustCode (data : Informal.Rust.InlineCodeData) where
  data := toJson data
  traverse id data _contents := do
    let .ok cdata := fromJson? (α := Informal.Rust.InlineCodeData) data
      | logError s!"Malformed Rust data: {data}"
        pure none
    if let some _ := (← get).getDomainObject? Informal.Rust.informalRustCodeDomain cdata.label.toString then
      pure none
    else
      let path ← (·.path) <$> read
      let _ ← Verso.Genre.Manual.externalTag id path s!"--informal-rust-code-{cdata.label}"
      modify fun s => s.saveDomainObject Informal.Rust.informalRustCodeDomain cdata.label.toString id
      modify fun s => s.saveDomainObjectData Informal.Rust.informalRustCodeDomain cdata.label.toString (toJson cdata)
      pure none
  toTeX := none
  extraCss := Informal.Block.Assets.codeCssAssets ++ [Informal.Rust.css]
  extraJs := ([] : List String)
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun _goI _goB id data _blocks => do
      let .ok cdata := fromJson? (α := Informal.Rust.InlineCodeData) data
        | HtmlT.logError s!"Malformed Rust code data: {data}"
          pure .empty
      let s ← HtmlT.state
      let ctxt ← HtmlT.context
      let attrs := s.htmlId id
      let panelHeader :=
        match Informal.TraversalIndex.Nodes.data? s cdata.label with
        | some b =>
          let b := b.withResolvedNumbering s (numberedPartPrefix? ctxt)
          let caption :=
            match b.kind with
            | .proof => "Rust code for proof"
            | .statement nodeKind => s!"Rust code for {nodeKind}"
          { (codePanelHeader b (b.displayNumber s)) with caption }
        | none => { fallbackCodePanelHeader with caption := "Rust code" }
      let body := Informal.Rust.highlightHtml cdata.raw
      pure <| mkCodePanel panelHeader s!"Rust code for {cdata.label}" .empty body attrs
        (folded := cdata.foldCodeBlock)

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
