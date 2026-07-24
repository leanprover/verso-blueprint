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

mutual

private partial def inlineToHtml
    (texPrelude : String)
    (inline : Lean.Doc.Inline Lean.ElabInline) : Verso.Output.Html :=
  match inline with
  | .text text => .text true text
  | .emph content => .tag "em" #[] (.seq <| content.map (inlineToHtml texPrelude))
  | .bold content => .tag "strong" #[] (.seq <| content.map (inlineToHtml texPrelude))
  | .code code => .tag "code" #[] (.text true code)
  | .math mode source =>
    .tag "code" (mathAttrs mode texPrelude) (.text true source)
  | .linebreak text => .text false text
  | .link content url =>
    .tag "a" #[("href", url)] (.seq <| content.map (inlineToHtml texPrelude))
  | .footnote name content =>
    .tag "details" #[("class", "footnote")] <|
      .seq #[
        .tag "summary" #[] (.text true s!"[{name}]"),
        .seq <| content.map (inlineToHtml texPrelude)
      ]
  | .image alt url => .tag "img" #[("src", url), ("alt", alt)] .empty
  | .concat content => .seq <| content.map (inlineToHtml texPrelude)
  -- Keep the same fallback policy as Manual-block conversion.
  | .other _ content => .seq <| content.map (inlineToHtml texPrelude)

private partial def listItemToHtml
    (texPrelude : String)
    (item : Lean.Doc.ListItem (Lean.Doc.Block Lean.ElabInline Lean.ElabBlock)) :
    Verso.Output.Html :=
  .tag "li" #[] (.seq <| item.contents.map (blockToHtml texPrelude))

private partial def descItemToHtml
    (texPrelude : String)
    (item :
      Lean.Doc.DescItem
        (Lean.Doc.Inline Lean.ElabInline)
        (Lean.Doc.Block Lean.ElabInline Lean.ElabBlock)) :
    Verso.Output.Html :=
  .seq #[
    .tag "dt" #[] (.seq <| item.term.map (inlineToHtml texPrelude)),
    .tag "dd" #[] (.seq <| item.desc.map (blockToHtml texPrelude))
  ]

private partial def blockToHtml
    (texPrelude : String)
    (block : Lean.Doc.Block Lean.ElabInline Lean.ElabBlock) :
    Verso.Output.Html :=
  match block with
  | .para contents =>
    .tag "p" #[] (.seq <| contents.map (inlineToHtml texPrelude))
  | .code content => .tag "pre" #[] (.text true content)
  | .ul items => .tag "ul" #[] (.seq <| items.map (listItemToHtml texPrelude))
  | .ol start items =>
    .tag "ol" #[("start", toString (max start 0))]
      (.seq <| items.map (listItemToHtml texPrelude))
  | .dl items => .tag "dl" #[] (.seq <| items.map (descItemToHtml texPrelude))
  | .blockquote items =>
    .tag "blockquote" #[] (.seq <| items.map (blockToHtml texPrelude))
  | .concat content => .seq <| content.map (blockToHtml texPrelude)
  -- Keep the same fallback policy as Manual-block conversion.
  | .other _ content => .seq <| content.map (blockToHtml texPrelude)

end

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
  let text := .seq <| doc.text.map (blockToHtml texPrelude)
  let subsections := .seq <| doc.subsections.map (partToHtml texPrelude)
  .seq #[text, subsections]
where
  partToHtml
      (texPrelude : String)
      (part : Lean.Doc.Part Lean.ElabInline Lean.ElabBlock Empty) :
      Verso.Output.Html :=
    let title :=
      if part.title.isEmpty then
        .empty
      else
        .tag "p" #[] <|
          .tag "strong" #[] (.seq <| part.title.map (inlineToHtml texPrelude))
    let content := .seq <| part.content.map (blockToHtml texPrelude)
    let children := .seq <| part.subParts.map (partToHtml texPrelude)
    .seq #[title, content, children]

end Informal.Docstring
