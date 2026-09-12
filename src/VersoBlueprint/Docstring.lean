/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public meta import Lean.DocString.Extension
public meta import VersoManual

public meta section

namespace Informal.Docstring

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

/-- Structural genre used to render elaborated Lean docstrings. -/
@[expose] def elaboratedDocstringGenre : Verso.Doc.Genre where
  PartMetadata := Empty
  Block := Lean.ElabBlock
  Inline := Lean.ElabInline
  TraverseContext := Unit
  TraverseState := Unit

private instance : Verso.Doc.TraverseBlock elaboratedDocstringGenre := {}

private instance : Verso.Doc.Html.GenreHtml elaboratedDocstringGenre Id where
  part _ metadata := nomatch metadata
  -- Declaration panels have no Blueprint traversal context. Use the fallback
  -- children supplied by each Lean docstring extension.
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

Custom extension wrappers use their fallback children. Blueprint math receives
the same classes and TeX prelude
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
