/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public section

namespace Informal.DirectiveArgParsing

/--
Split a comma-separated directive argument into trimmed, non-empty pieces.

Verso directive arguments do not currently have a list-valued syntax, so several
Blueprint options accept compact comma-separated strings.
-/
def splitCommaSeparatedList (s : String) : Array String :=
  s.splitOn ","
  |>.toArray
  |>.map (·.trimAscii.toString)
  |>.filter (fun p => !p.isEmpty)

end Informal.DirectiveArgParsing
