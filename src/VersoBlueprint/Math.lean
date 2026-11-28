/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import VersoManual
import VersoBlueprint.Lib.ExtensionDecode
import VersoBlueprint.MathLint
import VersoBlueprint.Macros
import VersoBlueprint.TeX

open Verso Doc Elab
open Verso.Genre Manual

namespace Informal.Math

open Lean Elab Syntax
open Lean.Doc.Syntax

instance : Quote MathMode where
  quote
    | .inline => mkCApp ``Lean.Doc.MathMode.inline #[]
    | .display => mkCApp ``Lean.Doc.MathMode.display #[]

structure BpMathData where
  mode : MathMode
  source : String
  texPrelude : String := ""
deriving FromJson, ToJson, Repr, Quote

private def mathClasses (mode : MathMode) : String :=
  "bp_math " ++ match mode with
    | .inline => "inline"
    | .display => "display"

private def displayMathEnvironments : List String := [
  "align",
  "align*",
  "alignat",
  "alignat*",
  "equation",
  "equation*",
  "flalign",
  "flalign*",
  "gather",
  "gather*",
  "multline",
  "multline*"
]

private def isDisplayMathSource (source : String) : Bool :=
  let source := source.trimAscii.toString
  source.startsWith "\\[" ||
    displayMathEnvironments.any fun env =>
      source.startsWith ("\\begin{" ++ env ++ "}")

/-- Narrow the warning site from the whole math literal down to the offending source slice when possible. -/
private def lintWarningRef? [Monad m] [MonadFileMap m]
    (ref : TSyntax `str) (failure : Informal.MathLint.Failure) : m (Option Syntax) := do
  let some sourceSpan := (match failure.site with
    | .source source _katexInput => some source
    | _ => none)
    | return none
  let fileMap ← getFileMap
  let some range := ref.raw.getRange?
    | return none
  let rawSource := range.start.extract fileMap.source range.stop
  let some (localStart, localStop) := Informal.MathLint.inlineCodeRawRangeOfDecodedSpan? rawSource sourceSpan
    | return none
  let start := range.start.offsetBy localStart
  let stop := range.start.offsetBy localStop
  return some <| Syntax.ofRange { start, stop }

/-- Run the KaTeX lint check during elaboration and log a warning immediately instead of waiting for final HTML render. -/
private def lintBpMathTerm [Monad m] [MonadLiftT IO m] [MonadOptions m]
    [MonadRef m] [MonadLog m] [AddMessageContext m] [MonadFileMap m]
    (ref : TSyntax `str) (mode : MathMode) (source texPrelude : String) : m Unit := do
  unless Informal.MathLint.enabled (← getOptions) do
    return
  let lintMode :=
    match mode with
    | .inline => Informal.MathLint.Mode.inline
    | .display => Informal.MathLint.Mode.display
  match ← liftM <| Informal.MathLint.lint? { mode := lintMode, source, texPrelude } with
  | some failure =>
    let warningRef ← lintWarningRef? ref failure
    logWarningAt (warningRef.getD ref) failure.toMessageData
  | none => pure ()

private def mathHtmlAssets (texPrelude : String) : HtmlAssets :=
  {
    extraJs := [
      Informal.Macros.texPreludeTableJs texPrelude,
      Informal.Macros.blueprintMathJs
    ]
  }

inline_extension Inline.bpMath (data : BpMathData) where
  data := toJson data
  usePackages := Informal.TeX.standardMathUsePackages
  traverse _id data _contents := do
    let some { texPrelude, .. } ← Informal.ExtensionDecode.decode? (α := BpMathData) data
        (fun _ => s!"Malformed blueprint math payload during traversal: {data}")
      | pure none
    modify fun st =>
      st.modifyHtmlAssets fun assets =>
        assets.combine (mathHtmlAssets texPrelude)
    pure none
  toTeX :=
    open Verso.Output.TeX in
    some <| fun _go _id data _contents => do
      let some { mode, source, .. } ← Informal.ExtensionDecode.decode? (α := BpMathData) data
          (fun _ => s!"Malformed blueprint math payload: {data}")
        | pure .empty
      pure <| match mode with
        | .inline => .raw s!"${source}$"
        | .display =>
            if isDisplayMathSource source then
              .raw s!"\n{source.trimAscii.toString}\n"
            else
              .raw s!"\\[{source}\\]"
  toHtml :=
    open Verso.Doc.Html in
    some <| fun _goI _id data _contents => do
      let some { mode, source, texPrelude } ← Informal.ExtensionDecode.decode? (α := BpMathData) data
          (fun _ => s!"Malformed blueprint math payload: {data}")
        | pure .empty
      let attrs :=
        if texPrelude.isEmpty then
          #[("class", mathClasses mode)]
        else
          #[("class", mathClasses mode), ("data-bp-tex-prelude-id", "default")]
      pure <| .tag "code" attrs (.text true source)

/-- Manual extension node shared by authored math and converted docstrings. -/
def bpMathInline (data : BpMathData) : Verso.Doc.Inline Verso.Genre.Manual :=
  .other (Inline.bpMath data) #[]

def mkBpMathInline [Monad m] [MonadEnv m] (mode : MathMode) (source : String) :
    m (Verso.Doc.Inline Verso.Genre.Manual) := do
  let texPrelude ← Informal.Macros.getTexPrelude
  pure (bpMathInline { mode, source, texPrelude })

/-- Emit an immediate warning before packaging a Manual math node. -/
def mkBpMathInlineTermLinted [Monad m] [MonadEnv m] [MonadQuotation m]
    [MonadLiftT IO m] [MonadOptions m] [MonadRef m] [MonadLog m] [AddMessageContext m]
    [MonadFileMap m]
    (ref : TSyntax `str) (mode : MathMode) (source : String) : m (TSyntax `term) := do
  let texPrelude ← Informal.Macros.getTexPrelude
  lintBpMathTerm ref mode source texPrelude
  let data : BpMathData := { mode, source, texPrelude }
  ``(bpMathInline $(quote data))

@[inline_expander Lean.Doc.Syntax.inline_math]
public meta def _root_.Informal.Math.inlineMathExpand : InlineExpander
  | `(inline| \math code( $s )) =>
    mkBpMathInlineTermLinted s .inline s.getString
  | _ => Lean.Elab.throwUnsupportedSyntax

@[inline_expander Lean.Doc.Syntax.display_math]
public meta def _root_.Informal.Math.displayMathExpand : InlineExpander
  | `(inline| \displaymath code( $s )) =>
    mkBpMathInlineTermLinted s .display s.getString
  | _ => Lean.Elab.throwUnsupportedSyntax

end Informal.Math
