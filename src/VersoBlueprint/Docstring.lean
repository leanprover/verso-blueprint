/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean.DocString.Extension
import VersoManual
import VersoBlueprint.Math

namespace Informal.Docstring

open Lean

mutual

private partial def inlineToManualStx
    (inl : Lean.Doc.Inline Lean.ElabInline) : CoreM (TSyntax `term) := do
  match inl with
  | .text s => `(Verso.Doc.Inline.text $(quote s))
  | .emph content =>
    let content ← content.mapM inlineToManualStx
    `(Verso.Doc.Inline.emph #[$content,*])
  | .bold content =>
    let content ← content.mapM inlineToManualStx
    `(Verso.Doc.Inline.bold #[$content,*])
  | .code s => `(Verso.Doc.Inline.code $(quote s))
  | .math .inline s => Informal.Math.mkBpMathInlineTerm .inline s
  | .math .display s => Informal.Math.mkBpMathInlineTerm .display s
  | .linebreak s => `(Verso.Doc.Inline.linebreak $(quote s))
  | .link content url =>
    let content ← content.mapM inlineToManualStx
    `(Verso.Doc.Inline.link #[$content,*] $(quote url))
  | .footnote name content =>
    let content ← content.mapM inlineToManualStx
    `(Verso.Doc.Inline.footnote $(quote name) #[$content,*])
  | .image alt url => `(Verso.Doc.Inline.image $(quote alt) $(quote url))
  | .concat content =>
    let content ← content.mapM inlineToManualStx
    `(Verso.Doc.Inline.concat #[$content,*])
  -- Extensions without a Manual adapter retain their converted child content.
  | .other _ content =>
    let content ← content.mapM inlineToManualStx
    `(Verso.Doc.Inline.concat #[$content,*])

private partial def listItemToManualStx
    (item : Lean.Doc.ListItem (Lean.Doc.Block Lean.ElabInline Lean.ElabBlock)) :
    CoreM (TSyntax `term) := do
  let contents ← item.contents.mapM blockToManualStx
  `(Verso.Doc.ListItem.mk #[$contents,*])

private partial def descItemToManualStx
    (item :
      Lean.Doc.DescItem
        (Lean.Doc.Inline Lean.ElabInline)
        (Lean.Doc.Block Lean.ElabInline Lean.ElabBlock)) :
    CoreM (TSyntax `term) := do
  let term ← item.term.mapM inlineToManualStx
  let desc ← item.desc.mapM blockToManualStx
  `(Verso.Doc.DescItem.mk #[$term,*] #[$desc,*])

private partial def blockToManualStx
    (block : Lean.Doc.Block Lean.ElabInline Lean.ElabBlock) :
    CoreM (TSyntax `term) := do
  match block with
  | .para contents =>
    let contents ← contents.mapM inlineToManualStx
    `(Verso.Doc.Block.para #[$contents,*])
  | .code content => `(Verso.Doc.Block.code $(quote content))
  | .ul items =>
    let items ← items.mapM listItemToManualStx
    `(Verso.Doc.Block.ul #[$items,*])
  | .ol start items =>
    let items ← items.mapM listItemToManualStx
    `(Verso.Doc.Block.ol $(quote start) #[$items,*])
  | .dl items =>
    let items ← items.mapM descItemToManualStx
    `(Verso.Doc.Block.dl #[$items,*])
  | .blockquote items =>
    let items ← items.mapM blockToManualStx
    `(Verso.Doc.Block.blockquote #[$items,*])
  | .concat content =>
    let content ← content.mapM blockToManualStx
    `(Verso.Doc.Block.concat #[$content,*])
  -- Extensions without a Manual adapter retain their converted child content.
  | .other _ content =>
    let content ← content.mapM blockToManualStx
    `(Verso.Doc.Block.concat #[$content,*])

end

/--
Convert an elaborated Verso docstring into the Manual blocks used by an
attribute-owned Blueprint statement.

The conversion preserves standard structural nodes and deliberately flattens
custom extensions whose semantics are not available in the Manual genre.
-/
partial def versoDocstringToManualBlocksStx
    (doc : Lean.VersoDocString) : CoreM (Array (TSyntax `term)) := do
  let mut blocks ← doc.text.mapM blockToManualStx
  for part in doc.subsections do
    blocks := blocks ++ (← partToManualBlocksStx part)
  pure blocks
where
  partToManualBlocksStx
      (part : Lean.Doc.Part Lean.ElabInline Lean.ElabBlock Empty) :
      CoreM (Array (TSyntax `term)) := do
    let mut out : Array (TSyntax `term) := #[]
    if !part.title.isEmpty then
      let title ← part.title.mapM inlineToManualStx
      let titleBold ← `(Verso.Doc.Inline.bold #[$title,*])
      let titleBlock ← `(Verso.Doc.Block.para #[$titleBold])
      out := out.push titleBlock
    out := out ++ (← part.content.mapM blockToManualStx)
    for child in part.subParts do
      out := out ++ (← partToManualBlocksStx child)
    pure out

private def mathAttrs (mode : Lean.Doc.MathMode) (texPrelude : String) :
    Array (String × String) :=
  let classes :=
    "bp_math " ++ match mode with
      | .inline => "inline"
      | .display => "display"
  if texPrelude.isEmpty then
    #[("class", classes)]
  else
    #[("class", classes), ("data-bp-tex-prelude", texPrelude)]

private def elaboratedDocstringGenre : Verso.Doc.Genre where
  PartMetadata := Empty
  Block := Lean.ElabBlock
  Inline := Lean.ElabInline
  TraverseContext := Unit
  TraverseState := Unit

private instance : Verso.Doc.TraverseBlock elaboratedDocstringGenre := {}

private instance : Verso.Doc.Html.GenreHtml elaboratedDocstringGenre Id where
  part _ metadata := nomatch metadata
  -- Docstring extensions do not carry rendering behavior once elaborated outside
  -- their owning genre, so retain their standard children.
  block _ blockHtml _ contents := .seq <$> contents.mapM blockHtml
  inline inlineHtml _ contents := .seq <$> contents.mapM inlineHtml

private def inlineToHtml
    (inline : Lean.Doc.Inline Lean.ElabInline) : Verso.Output.Html :=
  let action :=
    elaboratedDocstringGenre.toHtml (m := Id)
      {} () () {} {} {} (show Verso.Doc.Inline elaboratedDocstringGenre from inline)
  (action.run .empty).1

private def blockToHtml
    (block : Lean.Doc.Block Lean.ElabInline Lean.ElabBlock) : Verso.Output.Html :=
  let action :=
    elaboratedDocstringGenre.toHtml (m := Id)
      {} () () {} {} {} (show Verso.Doc.Block elaboratedDocstringGenre from block)
  (action.run .empty).1

private def rewriteMathHtml
    (texPrelude : String) (html : Verso.Output.Html) : Verso.Output.Html :=
  html.visitM (m := Id) (tag := fun name attrs contents =>
    if name == "code" && attrs.contains ("class", "math inline") then
      some (.tag name (mathAttrs .inline texPrelude) contents)
    else if name == "code" && attrs.contains ("class", "math display") then
      some (.tag name (mathAttrs .display texPrelude) contents)
    else
      none)

/--
Render the standard structural subset of an elaborated Verso docstring as
static HTML for external declaration panels.

Custom extension wrappers are flattened to their children, matching statement
materialization. Blueprint math receives the same classes and TeX prelude
metadata as normal Blueprint math nodes.
-/
partial def versoDocstringToHtml
    (doc : Lean.VersoDocString) (texPrelude : String := "") :
    Verso.Output.Html :=
  let text := .seq <| doc.text.map blockToHtml
  let subsections := .seq <| doc.subsections.map partToHtml
  rewriteMathHtml texPrelude <| .seq #[text, subsections]
where
  partToHtml
      (part : Lean.Doc.Part Lean.ElabInline Lean.ElabBlock Empty) :
      Verso.Output.Html :=
    let title :=
      if part.title.isEmpty then
        .empty
      else
        .tag "p" #[] <|
          .tag "strong" #[] (.seq <| part.title.map inlineToHtml)
    let content := .seq <| part.content.map blockToHtml
    let children := .seq <| part.subParts.map partToHtml
    .seq #[title, content, children]

end Informal.Docstring
