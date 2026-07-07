/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.TeX.Cleanup

namespace Verso.VersoBlueprintTests.BlueprintTeXCleanup

open Informal.TeX.Cleanup

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    stripLineStartDisplayFences "$$as required.\ntext\n$$ x\n  $$kept" ==
      "as required.\ntext\n x\n  $$kept"

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let source := String.intercalate "\n" [
      "$$outside",
      "\\begin{LeanVerbatim}",
      "$$inside",
      "\\end{LeanVerbatim}",
      "\\begin{verbatim}",
      "$$alsoInside",
      "\\end{verbatim}"
    ]
    stripLineStartDisplayFences source ==
      String.intercalate "\n" [
        "outside",
        "\\begin{LeanVerbatim}",
        "$$inside",
        "\\end{LeanVerbatim}",
        "\\begin{verbatim}",
        "$$alsoInside",
        "\\end{verbatim}"
      ]

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    compactVerbatimBlocks
        "before\n\\begin{LeanVerbatim}\n\n  \n#check Nat\n\n\\end{LeanVerbatim}\nafter" ==
      "before\n\\begin{LeanVerbatim}\n#check Nat\n\\end{LeanVerbatim}\nafter"

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    compactVerbatimBlocks
        "\\begin{FileVerbatim}\n\nfirst\n\nsecond\n\n\\end{FileVerbatim}" ==
      "\\begin{FileVerbatim}\nfirst\n\nsecond\n\\end{FileVerbatim}"

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let source := String.intercalate "\n" [
      "\\newcommand{\\errorDecorate}[1]{\\coloredwave{errorColor}{#1}}",
      "\\newcommand{\\infoDecorate}[1]{\\coloredwave{infoColor}{#1}}",
      "\\newcommand{\\warningDecorate}[1]{\\coloredwave{warningColor}{#1}}"
    ]
    let updated := simplifyDiagnosticDecorations source
    updated.contains "\\newcommand{\\errorDecorate}[1]{#1}" &&
      updated.contains "\\newcommand{\\infoDecorate}[1]{#1}" &&
      updated.contains "\\newcommand{\\warningDecorate}[1]{#1}" &&
      !updated.contains "\\coloredwave{errorColor}{#1}" &&
      !updated.contains "\\coloredwave{infoColor}{#1}" &&
      !updated.contains "\\coloredwave{warningColor}{#1}"

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let source := "\\documentclass{book}\n\\title{Demo}\n\\begin{document}"
    let (updated, error?) := patchSourceWithPreamble source (some "% Blueprint TeX prelude")
    error?.isNone &&
      updated.contains "\n% Blueprint TeX prelude\n\\title{Demo}"

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let (updated, error?) := patchSourceWithPreamble "no title marker" (some "% prelude")
    updated == "no title marker" && error? == some "marker not found"

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let source := String.intercalate "\n" [
      "\\documentclass{book}",
      "\\newcommand{\\warningDecorate}[1]{\\coloredwave{warningColor}{#1}}",
      "\\title{Demo}",
      "$$as required.",
      "\\begin{LeanVerbatim}",
      "",
      "#check Nat",
      "",
      "\\end{LeanVerbatim}"
    ]
    let (updated, error?) := patchSourceWithPreamble source (some "% prelude")
    error?.isNone &&
      updated.contains "\\newcommand{\\warningDecorate}[1]{#1}" &&
      updated.contains "\n% prelude\n\\title{Demo}" &&
      updated.contains "\nas required.\n" &&
      updated.contains "\\begin{LeanVerbatim}\n#check Nat\n\\end{LeanVerbatim}"

end Verso.VersoBlueprintTests.BlueprintTeXCleanup
