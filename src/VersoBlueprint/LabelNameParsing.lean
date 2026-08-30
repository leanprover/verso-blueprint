/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Lean.Data.Options

public section

namespace Informal.LabelNameParsing

open Lean

public register_option verso.blueprint.trimTeXLabelPrefix : Bool := {
  defValue := false
  descr := "Trim TeX-style prefixes for informal-label-derived Lean names (`thm:foo` -> `foo`)"
}

/-- Return the suffix of a TeX-style `prefix:suffix` label when present and non-empty. -/
private def texStyleSuffix? (s : String) : Option String :=
  match s.splitOn ":" with
  | [] => none
  | _ :: [] => none
  | pref :: suffixParts =>
    let suffix := String.intercalate ":" suffixParts
    if pref.isEmpty || suffix.isEmpty then
      none
    else
      some suffix

/-- Trim TeX-style `prefix:suffix` labels to `suffix`; non-matching inputs are unchanged. -/
private def trimTeXStylePrefix (s : String) : String :=
  (texStyleSuffix? s).getD s

/-- Whether TeX-style label trimming is enabled in the provided option set. -/
private def trimTeXStylePrefixEnabled (opts : Lean.Options) : Bool :=
  opts.get
    verso.blueprint.trimTeXLabelPrefix.name
    verso.blueprint.trimTeXLabelPrefix.defValue

/-- Conditionally trim TeX-style prefixes according to `verso.blueprint.trimTeXLabelPrefix`. -/
private def maybeTrimTeXStylePrefix (opts : Lean.Options) (s : String) : String :=
  if trimTeXStylePrefixEnabled opts then
    trimTeXStylePrefix s
  else
    s

/--
Parse an informal label as blueprint metadata.
- Without `opts`, parsing is raw (`Name.mkSimple`) with no preprocessing.
- With `opts`, TeX-style prefix policy is applied before `Name.mkSimple`.
This keeps label semantics and avoids namespace-dot parsing.
-/
def parse (s : String) (opts : Option Lean.Options := none) : Name :=
  let parsed :=
    match opts with
    | some opts => maybeTrimTeXStylePrefix opts s
    | none => s
  Name.mkSimple parsed

end Informal.LabelNameParsing
