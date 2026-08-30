/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.MathLint
import VersoBlueprint.Macros
import VersoBlueprint.TeX
meta import VersoBlueprint.MathLint
meta import VersoBlueprint.Macros
meta import VersoBlueprint.TeX

namespace VersoBlueprintModuleTests.MathLeaves

open Lean

/-- info: true -/
#guard_msgs in
#eval
  let rawSource := "a\\\\b"
  let rawRangeOk :=
    match Informal.MathLint.inlineCodeRawRangeOfDecodedSpan? rawSource { start := 1, length := 1 } with
    | some (start, stop) => start.extract rawSource stop == "\\\\"
    | none => false
  let preambleOk :=
    Informal.TeX.withStandardMathFallbacks "" == Informal.TeX.standardMathFallbackPreamble
  let tableOk :=
    (Informal.Macros.texPreludeTableJs "\\newcommand{\\R}{\\mathbb{R}}").contains
      "window.bpTexPreludeTable"
  rawRangeOk && preambleOk && tableOk

/-- info: true -/
#guard_msgs in
#eval
  show Lean.CoreM Bool from do
    pure (Informal.Macros.texPreludeExt.getState (← getEnv)).chunks.isEmpty

end VersoBlueprintModuleTests.MathLeaves
