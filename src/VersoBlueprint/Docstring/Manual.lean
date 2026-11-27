/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual.Markdown
import VersoBlueprint.Docstring.Compiled
import VersoBlueprint.Docstring.References
import VersoBlueprint.Math

namespace Informal.Docstring

open Lean

private abbrev ManualInline := Verso.Doc.Inline Verso.Genre.Manual
private abbrev ManualBlock := Verso.Doc.Block Verso.Genre.Manual

mutual

private partial def inlineToManual
    (inl : Lean.Doc.Inline Lean.ElabInline) : StateT (Array Data.UseRef) CoreM ManualInline := do
  match inl with
  | .text s => return .text s
  | .emph content => return .emph (← content.mapM inlineToManual)
  | .bold content => return .bold (← content.mapM inlineToManual)
  | .code s => return .code s
  | .math .inline s => Informal.Math.mkBpMathInline .inline s
  | .math .display s => Informal.Math.mkBpMathInline .display s
  | .linebreak s => return .linebreak s
  | .link content url => return .link (← content.mapM inlineToManual) url
  | .footnote name content => return .footnote name (← content.mapM inlineToManual)
  | .image alt url => return .image alt url
  | .concat content => return .concat (← content.mapM inlineToManual)
  | .other extension content =>
    let content ← content.mapM inlineToManual
    if let .custom payload := extension then
      if let some reference := payload.get? Reference then
        if let .inr dependency := reference.target then
          -- Preserve every dependency observation for the contribution reducer.
          modify fun deps => deps.push dependency
        return nodeReference reference.label (if reference.hasCustomText then content else #[])
    return .concat content

private partial def listItemToManual
    (item : Lean.Doc.ListItem (Lean.Doc.Block Lean.ElabInline Lean.ElabBlock)) :
    StateT (Array Data.UseRef) CoreM (Verso.Doc.ListItem ManualBlock) := do
  return .mk (← item.contents.mapM blockToManual)

private partial def descItemToManual
    (item :
      Lean.Doc.DescItem
        (Lean.Doc.Inline Lean.ElabInline)
        (Lean.Doc.Block Lean.ElabInline Lean.ElabBlock)) :
    StateT (Array Data.UseRef) CoreM (Verso.Doc.DescItem ManualInline ManualBlock) := do
  return .mk (← item.term.mapM inlineToManual) (← item.desc.mapM blockToManual)

private partial def blockToManual
    (block : Lean.Doc.Block Lean.ElabInline Lean.ElabBlock) :
    StateT (Array Data.UseRef) CoreM ManualBlock := do
  match block with
  | .para contents => return .para (← contents.mapM inlineToManual)
  | .code content => return .code content
  | .ul items => return .ul (← items.mapM listItemToManual)
  | .ol start items => return .ol start (← items.mapM listItemToManual)
  | .dl items => return .dl (← items.mapM descItemToManual)
  | .blockquote items => return .blockquote (← items.mapM blockToManual)
  -- Extensions without a Manual adapter retain their converted child content.
  | .concat content | .other _ content => return .concat (← content.mapM blockToManual)

end

/--
Convert an elaborated Verso docstring into the Manual blocks used by an
attribute-owned Blueprint statement.

The conversion preserves structural nodes and Blueprint references, collecting
statement dependencies without a directive stack. Other custom extensions use
their fallback children. Link destinations and numbering are resolved in traversal.
-/
partial def versoDocstringToManualBlocks
    (doc : Lean.VersoDocString) : CoreM (Array ManualBlock × Array Data.UseRef) :=
  (do
    let mut blocks ← doc.text.mapM blockToManual
    for part in doc.subsections do
      blocks := blocks ++ (← partToManualBlocks part)
    pure blocks).run #[]
where
  partToManualBlocks
      (part : Lean.Doc.Part Lean.ElabInline Lean.ElabBlock Empty) :
      StateT (Array Data.UseRef) CoreM (Array ManualBlock) := do
    let mut out : Array ManualBlock := #[]
    if !part.title.isEmpty then
      let title ← part.title.mapM inlineToManual
      out := out.push (.para #[.bold title])
    out := out ++ (← part.content.mapM blockToManual)
    for child in part.subParts do
      out := out ++ (← partToManualBlocks child)
    pure out

/-- Presentation from a compiled direct docstring. Capture separately verifies
source selection and decides whether an adopted statement can be displayed. -/
def statementBlocks (internalDoc : String ⊕ Lean.VersoDocString) :
    CoreM (Array ManualBlock × Array Data.UseRef × Name) := do
  match internalDoc with
  | .inl doc => do
    let doc := doc.trimAscii.toString
    if doc.isEmpty then return (#[], #[], `markdown)
    let fallback : Array ManualBlock := #[.para #[.text doc]]
    let some ast := MD4Lean.parse doc | return (fallback, #[], `markdown)
    let blocks := ast.blocks.mapM fun block =>
      Verso.Genre.Manual.Markdown.blockFromMarkdown' block
        (handleHeaders := Verso.Genre.Manual.Markdown.strongEmphHeaders')
    return (blocks.toOption.getD fallback, #[], `markdown)
  | .inr doc => do
    let (blocks, deps) ← versoDocstringToManualBlocks doc
    return (blocks, deps, `verso)

/-- Decode the serialized Manual AST used at the final document term boundary. -/
def decodePersistedManualBlock (jsonText : String) : Except String ManualBlock :=
  Json.parse jsonText >>= fromJson?

/-- Validate imported blocks before emitting their closed reconstruction terms. -/
public meta def persistedManualBlockTermFromJson (jsonText : String) : CoreM (TSyntax `term) := do
  match decodePersistedManualBlock jsonText with
  | .error error => throwError "Blueprint persisted statement block could not be decoded: {error}"
  | .ok _ =>
    `((Informal.Docstring.decodePersistedManualBlock $(quote jsonText)).toOption.get!)

public meta def persistedManualBlockTerms (blocks : Array ManualBlock) :
    CoreM (Array (TSyntax `term)) :=
  blocks.mapM fun block => persistedManualBlockTermFromJson (toJson block).compress

end Informal.Docstring
