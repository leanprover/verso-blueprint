/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso
import VersoManual
import VersoBlueprint.Data
import VersoBlueprint.Informal.LeanCodePreviewKey
import VersoBlueprint.Lib.HoverRender

namespace Informal.LeanCodeLink

open Lean
open Verso.Output.Html

/--
`LeanCodeLink` is the narrow HTML helper for links that target Lean
declarations/definitions and should carry an HTML-cache-backed hover preview.

It intentionally does not compute blueprint/code-status summaries; that remains
the responsibility of `Informal.CodeSummary`.
-/
private def previewLookupKey (decl : Name) : String :=
  Informal.LeanCodePreviewKey.lookupKey decl

private def previewTarget
    (decl : Name) (previewTitle : String) (lookupKey? : Option String := none) :
    Informal.HoverRender.InlinePreviewTarget :=
  let lookupKey := lookupKey?.getD (previewLookupKey decl)
  {
    triggerId := s!"bp-lean-code-{Informal.HoverRender.previewKey lookupKey}"
    title := previewTitle
    lookupKey? := some lookupKey
  }

private def renderLinkNode
    (node : Verso.Output.Html) (href? : Option String)
    (className : String) (title? : Option String) : Verso.Output.Html :=
  let attrs :=
    if className.isEmpty then
      #[]
    else
      #[("class", className)]
  let attrs :=
    match title? with
    | some title => attrs.push ("title", title)
    | none => attrs
  match href? with
  | some href => .tag "a" (attrs.push ("href", href)) node
  | none => .tag "span" attrs node

def renderResolved
    (decl : Name)
    (node : Verso.Output.Html)
    (className : String := "")
    (href? : Option String := none)
    (linkTitle? : Option String := none)
    (previewTitle : String := s!"Lean declaration {decl}")
    (previewLookupKey? : Option String := none) : Verso.Output.Html :=
  let linkNode := renderLinkNode node href? className linkTitle?
  Informal.HoverRender.inlinePreviewTargetNode
    linkNode
    (previewTarget decl previewTitle previewLookupKey?)

end Informal.LeanCodeLink
