/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.TeX.Cleanup
import VersoBlueprint.TeX.Pdf
meta import VersoBlueprint.TeX.Cleanup
meta import VersoBlueprint.TeX.Pdf

namespace VersoBlueprintModuleTests.TeXRuntime

example (opts : Informal.TeX.Pdf.PdfOptions) (cfg : Verso.Genre.Manual.Config) :
    Verso.BuildLogT IO Unit :=
  Informal.TeX.Pdf.compile opts cfg

/-- info: true -/
#guard_msgs in
#eval
  let source := String.intercalate "\n" [
    "\\documentclass{book}",
    "\\title{Module Contract}",
    "$$outside",
    "\\begin{LeanVerbatim}",
    "",
    "#check Nat",
    "",
    "\\end{LeanVerbatim}"
  ]
  let (updated, error?) :=
    Informal.TeX.Cleanup.patchSourceWithPreamble source (some "% Module prelude")
  let pdf : Informal.TeX.Pdf.PdfOptions := {
    enabled := true
    engine := "tectonic"
    runs := 3
  }
  error?.isNone &&
    updated.contains "\n% Module prelude\n\\title{Module Contract}" &&
    updated.contains "\noutside\n" &&
    updated.contains "\\begin{LeanVerbatim}\n#check Nat\n\\end{LeanVerbatim}" &&
    pdf.enabled && pdf.engine == "tectonic" && pdf.runs == 3

end VersoBlueprintModuleTests.TeXRuntime
