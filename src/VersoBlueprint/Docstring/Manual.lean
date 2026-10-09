/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public meta import VersoBlueprint.Docstring.References
public meta import VersoBlueprint.Math

public meta section

namespace Informal.Docstring

open Lean

mutual

private partial def inlineToManualStx
    (inl : Lean.Doc.Inline Lean.ElabInline) : StateT (Array Data.UseRef) CoreM (TSyntax `term) := do
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
  | .other extension content =>
    let content ← content.mapM inlineToManualStx
    if let .custom payload := extension then
      if let some reference := payload.get? Reference then
        if let .inr dependency := reference.target then
          -- Preserve validation evidence; only the shared contribution reducer
          -- may deduplicate declarations or reject conflicting intents.
          modify fun deps => deps.push dependency
        return ← nodeReferenceTerm reference.label
          (if reference.hasCustomText then content else #[])
    `(Verso.Doc.Inline.concat #[$content,*])

private partial def listItemToManualStx
    (item : Lean.Doc.ListItem (Lean.Doc.Block Lean.ElabInline Lean.ElabBlock)) :
    StateT (Array Data.UseRef) CoreM (TSyntax `term) := do
  let contents ← item.contents.mapM blockToManualStx
  `(Verso.Doc.ListItem.mk #[$contents,*])

private partial def descItemToManualStx
    (item :
      Lean.Doc.DescItem
        (Lean.Doc.Inline Lean.ElabInline)
        (Lean.Doc.Block Lean.ElabInline Lean.ElabBlock)) :
    StateT (Array Data.UseRef) CoreM (TSyntax `term) := do
  let term ← item.term.mapM inlineToManualStx
  let desc ← item.desc.mapM blockToManualStx
  `(Verso.Doc.DescItem.mk #[$term,*] #[$desc,*])

private partial def blockToManualStx
    (block : Lean.Doc.Block Lean.ElabInline Lean.ElabBlock) :
    StateT (Array Data.UseRef) CoreM (TSyntax `term) := do
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

The conversion preserves structural nodes and Blueprint references, collecting
statement dependencies without a directive stack. Other custom extensions use
their fallback children. Link destinations and numbering are resolved in traversal.
-/
partial def versoDocstringToManualBlocksStx
    (doc : Lean.VersoDocString) : CoreM (Array (TSyntax `term) × Array Data.UseRef) :=
  (do
    let mut blocks ← doc.text.mapM blockToManualStx
    for part in doc.subsections do
      blocks := blocks ++ (← partToManualBlocksStx part)
    pure blocks).run #[]
where
  partToManualBlocksStx
      (part : Lean.Doc.Part Lean.ElabInline Lean.ElabBlock Empty) :
      StateT (Array Data.UseRef) CoreM (Array (TSyntax `term)) := do
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

end Informal.Docstring
