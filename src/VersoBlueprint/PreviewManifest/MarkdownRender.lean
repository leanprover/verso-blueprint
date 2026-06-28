/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Html

namespace Informal.PreviewManifest

/--
Interpreter-safe renderer for source-only Markdown fragments.

This intentionally covers the standard Markdown constructs that are useful for
import review without calling native Markdown/MD4C bindings. Raw HTML is always
escaped so the generated cache fragment can be inserted as trusted HTML.
-/
private def markdownEscape (text : String) : String :=
  VersoBlueprint.Html.escapeText text

private def markdownLines (raw : String) : Array String :=
  (((raw.replace "\r\n" "\n").replace "\r" "\n").splitOn "\n").toArray

private def trimLine (line : String) : String :=
  line.trimAscii.toString

private def trimLineStart (line : String) : String :=
  line.trimAsciiStart.toString

private def lineIsBlank (line : String) : Bool :=
  (trimLine line).isEmpty

private def stripPrefixString? (pref line : String) : Option String :=
  line.dropPrefix? pref |>.map (·.toString)

private def stripIndentedCodeLine (line : String) : String :=
  if let some rest := stripPrefixString? "    " line then
    rest
  else if let some rest := stripPrefixString? "\t" line then
    rest
  else
    line

private def startsIndentedCode (line : String) : Bool :=
  line.startsWith "    " || line.startsWith "\t"

private partial def splitUntilCharAux (needle : Char) (acc : List Char) :
    List Char → Option (List Char × List Char)
  | [] => none
  | c :: rest =>
      if c == needle then
        some (acc.reverse, rest)
      else
        splitUntilCharAux needle (c :: acc) rest

private def splitUntilChar? (needle : Char) (chars : List Char) : Option (List Char × List Char) :=
  splitUntilCharAux needle [] chars

private partial def splitUntilDoubleStarAux (acc : List Char) :
    List Char → Option (List Char × List Char)
  | [] => none
  | '*' :: '*' :: rest => some (acc.reverse, rest)
  | c :: rest => splitUntilDoubleStarAux (c :: acc) rest

private def splitUntilDoubleStar? (chars : List Char) : Option (List Char × List Char) :=
  splitUntilDoubleStarAux [] chars

private partial def takePlainInlineAux (acc : List Char) :
    List Char → List Char × List Char
  | [] => (acc.reverse, [])
  | '`' :: rest => (acc.reverse, '`' :: rest)
  | chars@('*' :: '*' :: _) => (acc.reverse, chars)
  | c :: rest => takePlainInlineAux (c :: acc) rest

private def takePlainInline (chars : List Char) : List Char × List Char :=
  takePlainInlineAux [] chars

private partial def renderMarkdownInlineChars : List Char → String
  | [] => ""
  | '`' :: rest =>
      match splitUntilChar? '`' rest with
      | some (code, after) =>
          s!"<code>{markdownEscape (String.ofList code)}</code>{renderMarkdownInlineChars after}"
      | none => markdownEscape "`" ++ renderMarkdownInlineChars rest
  | '*' :: '*' :: rest =>
      match splitUntilDoubleStar? rest with
      | some (strong, after) =>
          s!"<strong>{renderMarkdownInlineChars strong}</strong>{renderMarkdownInlineChars after}"
      | none => markdownEscape "**" ++ renderMarkdownInlineChars rest
  | chars =>
      let (plain, after) := takePlainInline chars
      markdownEscape (String.ofList plain) ++ renderMarkdownInlineChars after

private def renderMarkdownInline (text : String) : String :=
  renderMarkdownInlineChars text.toList

private def joinHtml (items : Array String) : String :=
  String.join items.toList

private def renderCodeBlock (lines : Array String) : String :=
  s!"<pre><code>{markdownEscape (String.intercalate "\n" lines.toList)}</code></pre>"

private def headingLevel? (line : String) : Option (Nat × String) := do
  let trimmed := trimLineStart line
  let hashes := String.ofList <| trimmed.toList.takeWhile (· == '#')
  let level := hashes.length
  if level == 0 || level > 6 then
    none
  else
    let rest ← trimmed.dropPrefix? hashes
    let rest := rest.toString
    let text ← stripPrefixString? " " rest
    some (level, text)

private def isFenceLine (line : String) : Option Char :=
  let trimmed := trimLineStart line
  if trimmed.startsWith "```" then
    some '`'
  else if trimmed.startsWith "~~~" then
    some '~'
  else
    none

private def closesFence (fence : Char) (line : String) : Bool :=
  let trimmed := trimLineStart line
  match fence with
  | '`' => trimmed.startsWith "```"
  | '~' => trimmed.startsWith "~~~"
  | _ => false

private def listItemText? (line : String) : Option String :=
  let trimmed := trimLineStart line
  (stripPrefixString? "- " trimmed) <|>
    (stripPrefixString? "* " trimmed) <|>
    (stripPrefixString? "+ " trimmed)

private def blockquoteText? (line : String) : Option String := do
  let trimmed := trimLineStart line
  let rest ← stripPrefixString? ">" trimmed
  pure <| (stripPrefixString? " " rest).getD rest

private def splitTableCells (line : String) : Array String :=
  let cells := (trimLine line).splitOn "|"
  let cells :=
    match cells with
    | "" :: rest => rest
    | other => other
  let cells :=
    match cells.reverse with
    | "" :: rest => rest.reverse
    | other => other.reverse
  cells.toArray.map trimLine

private def isTableSeparatorCell (cell : String) : Bool :=
  let trimmed := trimLine cell
  let stripped := String.ofList <| trimmed.toList.filter fun c => c != ':' && c != '-' && c != ' '
  !trimmed.isEmpty && stripped.isEmpty && trimmed.contains '-'

private def isTableSeparatorLine (line : String) : Bool :=
  let cells := splitTableCells line
  !cells.isEmpty && cells.all isTableSeparatorCell

private def isBlockStart (line : String) : Bool :=
  (lineIsBlank line) ||
    (headingLevel? line).isSome ||
    (isFenceLine line).isSome ||
    (startsIndentedCode line) ||
    (listItemText? line).isSome ||
    (blockquoteText? line).isSome

private def tableRowHtml (tag : String) (cells : Array String) : String :=
  let rendered := cells.map fun cell =>
    s!"<{tag}>{renderMarkdownInline cell}</{tag}>"
  s!"<tr>{joinHtml rendered}</tr>"

private partial def renderMarkdownBlocks (lines : Array String) (start : Nat := 0) :
    String × Nat := Id.run do
  let mut html := #[]
  let mut i := start
  while h : i < lines.size do
    let line := lines[i]
    if lineIsBlank line then
      i := i + 1
    else if let some fence := isFenceLine line then
      i := i + 1
      let mut body := #[]
      while h : i < lines.size do
        let current := lines[i]
        if closesFence fence current then
          i := i + 1
          break
        else
          body := body.push current
          i := i + 1
      html := html.push <| renderCodeBlock body
    else if startsIndentedCode line then
      let mut body := #[]
      while h : i < lines.size do
        let current := lines[i]
        if startsIndentedCode current || lineIsBlank current then
          body := body.push <| stripIndentedCodeLine current
          i := i + 1
        else
          break
      html := html.push <| renderCodeBlock body
    else if let some (level, text) := headingLevel? line then
      html := html.push s!"<h{level}>{renderMarkdownInline text}</h{level}>"
      i := i + 1
    else if let some _ := blockquoteText? line then
      let mut quoted := #[]
      while h : i < lines.size do
        match blockquoteText? lines[i] with
        | some text =>
            quoted := quoted.push text
            i := i + 1
        | none => break
      let (inner, _) := renderMarkdownBlocks quoted
      html := html.push s!"<blockquote>{inner}</blockquote>"
    else if let some _ := listItemText? line then
      let mut items := #[]
      while h : i < lines.size do
        match listItemText? lines[i] with
        | some text =>
            items := items.push s!"<li>{renderMarkdownInline text}</li>"
            i := i + 1
        | none => break
      html := html.push s!"<ul>{joinHtml items}</ul>"
    else if i + 1 < lines.size && (trimLine line).contains '|' &&
        isTableSeparatorLine lines[i + 1]! then
      let headCells := splitTableCells line
      i := i + 2
      let mut bodyRows := #[]
      while h : i < lines.size do
        let current := lines[i]
        if lineIsBlank current || !(trimLine current).contains '|' then
          break
        else
          bodyRows := bodyRows.push <| tableRowHtml "td" (splitTableCells current)
          i := i + 1
      html := html.push <|
        s!"<table><thead>{tableRowHtml "th" headCells}</thead><tbody>{joinHtml bodyRows}</tbody></table>"
    else
      let mut paragraph := #[]
      while h : i < lines.size do
        let current := lines[i]
        if isBlockStart current then
          break
        else if i + 1 < lines.size && (trimLine current).contains '|' &&
            isTableSeparatorLine lines[i + 1]! then
          break
        else
          paragraph := paragraph.push (trimLine current)
          i := i + 1
      if paragraph.isEmpty then
        html := html.push s!"<p>{renderMarkdownInline line}</p>"
        i := i + 1
      else
        html := html.push s!"<p>{renderMarkdownInline (String.intercalate " " paragraph.toList)}</p>"
  (joinHtml html, i)

/--
Render a conservative, interpreter-safe Markdown subset to trusted HTML.

This exists to keep generated preview data compatible with `lake env lean --run`
until upstream MD4Lean rendering is available in interpreted generator mains.
-/
def renderExternalMarkdownHtml (raw : String) : String :=
  let (html, _) := renderMarkdownBlocks (markdownLines raw)
  html

end Informal.PreviewManifest
