/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint

namespace Verso.VersoBlueprintTests.BlueprintMathLint

open Informal

/--
Extract the source text that a math span maps to. `lines` gives each code line's text and the
offset where it starts in `source`.
-/
private def extractedRaw? (source : String) (lines : Array (String × Nat))
    (span : Informal.MathLint.Span) : Option String := do
  let lines := lines.map fun (text, start) => (text, (⟨start⟩ : String.Pos.Raw))
  let (start, stop) ← Informal.MathLint.codeLinesRawRangeOfDecodedSpan? lines span
  pure <| start.extract source stop

private def localNodeAvailable : IO Bool := do
  try
    let out ← IO.Process.output { cmd := "node", args := #["--version"] }
    pure (out.exitCode == 0)
  catch _ =>
    pure false

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let source := r#"\undefinedmacro"#
    let nodeAvailable ← localNodeAvailable
    let report ← Informal.MathLint.lint? {
      mode := .inline
      source
    }
    pure <|
      if !nodeAvailable then
        true
      else
        match report with
        | some failure =>
          failure.reason.contains "Undefined control sequence" &&
          failure.site == .source { start := 0, length := source.length } { start := 0, length := source.length }
        | none => false

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let report ← Informal.MathLint.lint? {
      mode := .inline
      source := r#"\foo + 1"#
      texPrelude := r#"\newcommand{\foo}{\mathsf{Foo}}"#
    }
    pure report.isNone

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let nodeAvailable ← localNodeAvailable
    let tasks ← (List.range 8).mapM fun i =>
      IO.asTask <| Informal.MathLint.lint? {
        mode := .inline
        source := r#"\undefinedmacro"# ++ toString i
      }
    let reports ← tasks.mapM fun task => IO.ofExcept task.get
    pure <| !nodeAvailable || reports.all (·.isSome)

-- Lean 4.36 inline code has no escapes: `\n` and `\\` occupy two source characters each.
/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let source := r#"\nu + \undefinedmacro"#
    extractedRaw? source #[(source, 0)] { start := 6, length := 15 } == some r#"\undefinedmacro"#

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let source := r#"a \\ \bad"#
    extractedRaw? source #[(source, 0)] { start := 5, length := 4 } == some r#"\bad"#

-- The docstring indentation between lines is not part of the code, so the second line's
-- columns start after it.
/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let source := "a +\n  " ++ r#"\bad"#
    let lines := #[("a +\n", 0), (r#"\bad"#, 6)]
    extractedRaw? source lines { start := 4, length := 4 } == some r#"\bad"# &&
      extractedRaw? source lines { start := 0, length := 4 } == some "a +\n" &&
      extractedRaw? source lines { start := 2, length := 3 } == some "+\n  \\"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let nodeAvailable ← localNodeAvailable
    let failure? ← Informal.MathLint.lint? {
      mode := .inline
      source := r#"\frac{a}{"#
    }
    pure <| if !nodeAvailable then true else
      match failure? with
      | some failure =>
        failure.site == .source { start := 9, length := 0 } { start := 9, length := 0 }
      | none => false

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let nodeAvailable ← localNodeAvailable
    let failure? ← Informal.MathLint.lint? {
      mode := .display
      source := r#"\foo + 1"#
      texPrelude := r#"\newcommand{\foo}{\mathsf{Foo}"#
    }
    pure <| if !nodeAvailable then true else
      match failure? with
      | some failure =>
        failure.reason.contains "expected '}'" &&
        match failure.site with
        | .prelude { start, length } => start > 0 && length == 0
        | _ => false
      | none => false

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let invalidPrelude := r#"\newcommand{\foo}{\mathsf{Foo}"#
    let nodeAvailable ← localNodeAvailable
    let first ← Informal.MathLint.lint? {
      mode := .inline
      source := r#"\foo + 1"#
      texPrelude := invalidPrelude
    }
    let second ← Informal.MathLint.lint? {
      mode := .inline
      source := r#"\foo + 2"#
      texPrelude := invalidPrelude
    }
    pure <| !nodeAvailable || (first.isSome && first == second)

end Verso.VersoBlueprintTests.BlueprintMathLint
