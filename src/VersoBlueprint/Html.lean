/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Verso.Output.Html

public section

namespace VersoBlueprint.Html

open Verso.Output

/--
Escape plain text for insertion into HTML text content.

This intentionally returns raw escaped text because the current Verso
`Html.text true` renderer escapes `<` and `>` but not `&`. Use this helper only
for text content that must preserve literal ampersands faithfully.
-/
def escapeText (text : String) : String :=
  ((text.replace "&" "&amp;").replace "<" "&lt;").replace ">" "&gt;"

/-- Plain HTML text content escaped with `escapeText`. -/
def text (text : String) : Html :=
  Verso.Output.Html.text false <| escapeText text

/--
Append an HTML node unless an existing node renders to the same string.

Use this for structured head snippets where `Html` does not provide a semantic
equality instance but repeated asset installation should remain idempotent.
-/
def pushIfRenderedMissing (values : Array Html) (value : Html) : Array Html :=
  let valueString := Html.asString value
  if values.any (fun item => Html.asString item == valueString) then
    values
  else
    values.push value

end VersoBlueprint.Html
