/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import VersoBlueprint.Data
import VersoBlueprint.Resolve

namespace Informal.Rust

open Lean
open Verso.Output.Html

def informalRustCodeDomain : Name := Resolve.informalRustCodeDomainName

structure InlineCodeData where
  label : Data.Label
  raw : String
  foldCodeBlock : Bool := false
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

open Syntax in
instance : Quote InlineCodeData where
  quote data := mkCApp ``InlineCodeData.mk #[quote data.label, quote data.raw, quote data.foldCodeBlock]

def css : String := r##"
.bp_rust_code {
  color: var(--bp-color-text-strong);
  background: var(--bp-color-surface-muted);
}

.bp_rust_kw {
  color: #7c2d12;
  font-weight: 700;
}

.bp_rust_ty {
  color: #0f766e;
  font-weight: 600;
}

.bp_rust_num {
  color: #166534;
}

.bp_rust_str {
  color: #9f1239;
}

.bp_rust_comment {
  color: #64748b;
  font-style: italic;
}
"##

private def keywordSet : List String := [
  "as", "async", "await", "break", "const", "continue", "crate", "else",
  "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let",
  "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self",
  "Self", "static", "struct", "super", "trait", "true", "type", "unsafe",
  "use", "where", "while"
]

private def builtinTypeSet : List String := [
  "bool", "char", "i8", "i16", "i32", "i64", "i128", "isize",
  "u8", "u16", "u32", "u64", "u128", "usize", "f32", "f64", "str"
]

private def isIdentStart (c : Char) : Bool :=
  c.isAlpha || c == '_'

private def isIdentRest (c : Char) : Bool :=
  c.isAlphanum || c == '_'

private def tokenNode (cls txt : String) : Verso.Output.Html :=
  if cls.isEmpty then
    Verso.Output.Html.text true txt
  else
    Verso.Output.Html.tag "span" #[("class", cls)] (Verso.Output.Html.text true txt)

private def classifyIdent (txt : String) : String :=
  if keywordSet.contains txt then
    "bp_rust_kw"
  else if builtinTypeSet.contains txt then
    "bp_rust_ty"
  else
    ""

private def isNumberStart (c : Char) : Bool :=
  c.isDigit

private def isNumberRest (c : Char) : Bool :=
  c.isDigit || c == '_' || c.isAlpha

private def scanWhile (source : String) (start : String.Pos.Raw) (p : Char → Bool) : String.Pos.Raw :=
  Id.run do
    let mut pos := start
    while !pos.atEnd source do
      let c := pos.get source
      if p c then
        pos := pos.next source
      else
        break
    return pos

private def scanComment (source : String) (start : String.Pos.Raw) : String.Pos.Raw :=
  Id.run do
    let mut pos := start
    while !pos.atEnd source do
      let c := pos.get source
      if c == '\n' then
        break
      pos := pos.next source
    return pos

private def scanString (source : String) (start : String.Pos.Raw) : String.Pos.Raw :=
  Id.run do
    let mut pos := start.next source
    let mut escaped := false
    while !pos.atEnd source do
      let c := pos.get source
      pos := pos.next source
      if escaped then
        escaped := false
      else if c == '\\' then
        escaped := true
      else if c == '"' then
        break
    return pos

def highlightHtml (source : String) : Verso.Output.Html :=
  Id.run do
    let mut pos : String.Pos.Raw := 0
    let mut out : Array Verso.Output.Html := #[]
    while !pos.atEnd source do
      let c := pos.get source
      let nextPos :=
        if pos.atEnd source then pos else pos.next source
      if c == '/' && !nextPos.atEnd source && nextPos.get source == '/' then
        let stop := scanComment source pos
        out := out.push <| tokenNode "bp_rust_comment" (pos.extract source stop)
        pos := stop
      else if c == '"' then
        let stop := scanString source pos
        out := out.push <| tokenNode "bp_rust_str" (pos.extract source stop)
        pos := stop
      else if isIdentStart c then
        let stop := scanWhile source pos isIdentRest
        let txt := pos.extract source stop
        out := out.push <| tokenNode (classifyIdent txt) txt
        pos := stop
      else if isNumberStart c then
        let stop := scanWhile source pos isNumberRest
        out := out.push <| tokenNode "bp_rust_num" (pos.extract source stop)
        pos := stop
      else
        out := out.push <| Verso.Output.Html.text true (pos.extract source nextPos)
        pos := nextPos
    return Verso.Output.Html.tag "pre" #[("class", "bp_external_decl_stmt hl rust block bp_rust_code")] (Verso.Output.Html.seq out)

end Informal.Rust
