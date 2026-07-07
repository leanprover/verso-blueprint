/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Std.Data.HashSet
import VersoManual
import VersoBlueprint.Math

namespace Informal.TeX.Cleanup

open Lean Verso Doc
open Verso.Genre Manual

private def insertNonempty (items : Std.HashSet String) (item : String) : Std.HashSet String :=
  if item.trimAscii.isEmpty then items else items.insert item

private partial def collectBpMathTeXPreludesInline
    (items : Std.HashSet String) : Doc.Inline Manual → Std.HashSet String
  | .text .. | .code .. | .math .. | .linebreak .. | .image .. => items
  | .emph inlines | .bold inlines | .concat inlines =>
      inlines.foldl collectBpMathTeXPreludesInline items
  | .link inlines _ | .footnote _ inlines =>
      inlines.foldl collectBpMathTeXPreludesInline items
  | .other inline inlines =>
      let items := inlines.foldl collectBpMathTeXPreludesInline items
      if inline.name == ``Informal.Math.Inline.bpMath then
        match fromJson? (α := Informal.Math.BpMathData) inline.data with
        | .ok data => insertNonempty items (Informal.TeX.withStandardMathFallbacks data.texPrelude)
        | .error _ => items
      else
        items

private partial def collectBpMathTeXPreludesBlock
    (items : Std.HashSet String) : Doc.Block Manual → Std.HashSet String
  | .para inlines => inlines.foldl collectBpMathTeXPreludesInline items
  | .code .. => items
  | .blockquote blocks | .concat blocks | .other _ blocks =>
      blocks.foldl collectBpMathTeXPreludesBlock items
  | .ul listItems | .ol _ listItems =>
      listItems.foldl (init := items) fun items item =>
        item.contents.foldl collectBpMathTeXPreludesBlock items
  | .dl descItems =>
      descItems.foldl (init := items) fun items item =>
        let items := item.term.foldl collectBpMathTeXPreludesInline items
        item.desc.foldl collectBpMathTeXPreludesBlock items

private partial def collectBpMathTeXPreludesPart
    (items : Std.HashSet String) (part : Part Manual) : Std.HashSet String :=
  let items := part.title.foldl collectBpMathTeXPreludesInline items
  let items := part.content.foldl collectBpMathTeXPreludesBlock items
  part.subParts.foldl collectBpMathTeXPreludesPart items

def blueprintTeXPreambleInsertion (text : Part Manual) : Option String :=
  let preludes := collectBpMathTeXPreludesPart {} text |>.toArray
  if preludes.isEmpty then
    none
  else
    let preludes := preludes.qsort (· < ·)
    some <| String.intercalate "\n" <|
      ["% Blueprint TeX prelude"] ++ preludes.toList ++ ["% End Blueprint TeX prelude"]

def insertBeforeFirst (source marker insertion : String) : Option String :=
  match source.splitOn marker with
  | before :: after :: rest =>
      some <| before ++ insertion ++ marker ++ String.intercalate marker (after :: rest)
  | _ => none

private def lineMatches (line marker : String) : Bool :=
  line.trimAscii.toString == marker

private def beginsEnvironment (line env : String) : Bool :=
  let line := line.trimAscii.toString
  let marker := "\\begin{" ++ env ++ "}"
  line == marker || line.startsWith (marker ++ "[")

private def verbatimEndMarker? (line : String) : Option String :=
  if beginsEnvironment line "LeanVerbatim" then
    some "\\end{LeanVerbatim}"
  else if beginsEnvironment line "FileVerbatim" then
    some "\\end{FileVerbatim}"
  else if beginsEnvironment line "verbatim" then
    some "\\end{verbatim}"
  else if beginsEnvironment line "Verbatim" then
    some "\\end{Verbatim}"
  else
    none

private def isWhitespaceLine (line : String) : Bool :=
  line.trimAscii.isEmpty

def trimWhitespaceEdgeLines (lines : List String) : List String :=
  let lines := lines.dropWhile isWhitespaceLine
  (lines.reverse.dropWhile isWhitespaceLine).reverse

private partial def takeThroughLine (marker : String) :
    List String → Option (List String × String × List String)
  | [] => none
  | line :: rest =>
      if lineMatches line marker then
        some ([], line, rest)
      else
        match takeThroughLine marker rest with
        | none => none
        | some (body, endLine, rest) => some (line :: body, endLine, rest)

private partial def stripLineStartDisplayFencesLines : List String → List String
  | [] => []
  | line :: rest =>
      match verbatimEndMarker? line with
      | some endMarker =>
          match takeThroughLine endMarker rest with
          | some (body, endLine, after) =>
              line :: body ++ endLine :: stripLineStartDisplayFencesLines after
          | none =>
              line :: rest
      | none =>
          let line := if line.startsWith "$$" then (line.drop 2).toString else line
          line :: stripLineStartDisplayFencesLines rest

def stripLineStartDisplayFences (source : String) : String :=
  String.intercalate "\n" <| stripLineStartDisplayFencesLines (source.splitOn "\n")

private def compactVerbatimBegin? (line : String) : Option String :=
  if lineMatches line "\\begin{LeanVerbatim}" then
    some "\\end{LeanVerbatim}"
  else if lineMatches line "\\begin{FileVerbatim}" then
    some "\\end{FileVerbatim}"
  else
    none

private partial def compactVerbatimBlocksLines : List String → List String
  | [] => []
  | line :: rest =>
      match compactVerbatimBegin? line with
      | some endMarker =>
          match takeThroughLine endMarker rest with
          | some (body, endLine, after) =>
              line :: trimWhitespaceEdgeLines body ++ endLine :: compactVerbatimBlocksLines after
          | none =>
              line :: compactVerbatimBlocksLines rest
      | none =>
          line :: compactVerbatimBlocksLines rest

def compactVerbatimBlocks (source : String) : String :=
  String.intercalate "\n" <| compactVerbatimBlocksLines (source.splitOn "\n")

private def diagnosticDecorationDefinitionReplacements : List (String × String) := [
  (
    "\\newcommand{\\errorDecorate}[1]{\\coloredwave{errorColor}{#1}}",
    "\\newcommand{\\errorDecorate}[1]{#1}"
  ),
  (
    "\\newcommand{\\infoDecorate}[1]{\\coloredwave{infoColor}{#1}}",
    "\\newcommand{\\infoDecorate}[1]{#1}"
  ),
  (
    "\\newcommand{\\warningDecorate}[1]{\\coloredwave{warningColor}{#1}}",
    "\\newcommand{\\warningDecorate}[1]{#1}"
  )
]

def simplifyDiagnosticDecorations (source : String) : String :=
  diagnosticDecorationDefinitionReplacements.foldl
    (fun source replacement => source.replace replacement.1 replacement.2)
    source

def patchSourceBase (source : String) : String :=
  simplifyDiagnosticDecorations <| compactVerbatimBlocks <| stripLineStartDisplayFences source

def patchSourceWithPreamble (source : String) (insertion? : Option String) :
    String × Option String :=
  let source := patchSourceBase source
  match insertion? with
  | none => (source, none)
  | some insertion =>
      let marker := "\n\\title{"
      match insertBeforeFirst source marker ("\n" ++ insertion) with
      | some updated => (updated, none)
      | none => (source, some "marker not found")

def patchSource (source : String) (text : Part Manual) : String × Option String :=
  patchSourceWithPreamble source (blueprintTeXPreambleInsertion text)

def patchFile (cfg : Verso.Genre.Manual.Config)
    (text : Part Manual) : BuildLogT IO Unit := do
  let texPath := cfg.destination / "tex" / "main.tex"
  unless ← texPath.pathExists do
    return
  let original ← IO.FS.readFile texPath
  let (updated, error?) := patchSource original text
  if let some error := error? then
    Verso.reportError s!"Could not insert Blueprint TeX prelude in {texPath}: {error}"
  unless updated == original do
    IO.FS.writeFile texPath updated

end Informal.TeX.Cleanup
