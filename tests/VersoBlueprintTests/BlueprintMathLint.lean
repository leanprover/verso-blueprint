/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint

namespace Verso.VersoBlueprintTests.BlueprintMathLint

open Informal

private def extractedRaw? (rawSource : String) (span : Informal.MathLint.Span) : Option String := do
  let (start, stop) ← Informal.MathLint.inlineCodeRawRangeOfDecodedSpan? rawSource span
  pure <| start.extract rawSource stop

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

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    extractedRaw? r#"\`x"# { start := 0, length := 1 } == some r#"\`"#

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    extractedRaw? r#"\\x"# { start := 0, length := 1 } == some r#"\\"#

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    extractedRaw? r#"\alpha"# { start := 0, length := 6 } == some r#"\alpha"#

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
