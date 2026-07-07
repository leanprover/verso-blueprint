/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Verso.Output.TeX

namespace Informal.TeX

open Verso.Output.TeX

def standardMathUsePackages : List String := [
  "\\usepackage{amsmath}",
  "\\usepackage{amssymb}",
  "\\usepackage{mathtools}"
]

def standardMathFallbackPreamble : String :=
  String.intercalate "\n" [
    "\\providecommand{\\R}{\\mathbb{R}}",
    "\\providecommand{\\N}{\\mathbb{N}}",
    "\\providecommand{\\Z}{\\mathbb{Z}}",
    "\\providecommand{\\C}{\\mathbb{C}}"
  ]

def withStandardMathFallbacks (preamble : String) : String :=
  if preamble.trimAscii.isEmpty then
    standardMathFallbackPreamble
  else
    preamble ++ "\n" ++ standardMathFallbackPreamble

def boldHeading (title : String) (body : Verso.Output.TeX := .empty) : Verso.Output.TeX :=
  .seq #[
    .raw "\\par\\noindent",
    .command "textbf" #[] #[.text title],
    .raw "\\par\n",
    body
  ]

def boldHeadingBlocks (title : String) (body : Array Verso.Output.TeX) : Verso.Output.TeX :=
  boldHeading title (.seq body)

def quotedBlock (title : String) (body : Array Verso.Output.TeX) : Verso.Output.TeX :=
  boldHeading title (.environment "quote" #[] #[] body)

def verbatimBlock (title source : String) : Verso.Output.TeX :=
  boldHeading title (.environment "verbatim" #[] #[] #[.raw source])

end Informal.TeX
