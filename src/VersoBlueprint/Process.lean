/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Init.System.IO

public section

namespace Informal.Process

/--
Run a command and return trimmed stdout when the command succeeds and produces
non-empty output.

Callers use this for best-effort metadata probes, so failures and missing
commands are represented as `none`.
-/
def runTrimmedCommand? (cmd : String) (args : Array String) : IO (Option String) := do
  try
    let out ← IO.Process.output { cmd, args }
    if out.exitCode == 0 then
      let text := out.stdout.trimAscii.toString
      if text.isEmpty then
        pure none
      else
        pure (some text)
    else
      pure none
  catch _ =>
    pure none

end Informal.Process
