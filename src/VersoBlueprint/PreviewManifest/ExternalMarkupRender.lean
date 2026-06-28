/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoBlueprint.Data
import VersoBlueprint.Html
import VersoBlueprint.Informal.Block.Model
import VersoBlueprint.Informal.Block.Render
import VersoBlueprint.Informal.ExternalMarkupView

namespace Informal.PreviewManifest

open Verso.Genre Manual

private def externalMarkupRenderCss : String := r##"
.bp_external_markup_node .bp_external_markup_notice {
  margin: 0 0 0.65rem;
  padding: 0.42rem 0.55rem;
  border: 1px solid var(--bp-color-status-warning-border, #f59e0b);
  border-radius: var(--bp-radius-md, 0.375rem);
  background: var(--bp-color-status-warning-surface, #fffbeb);
  color: var(--bp-color-status-warning-text, #92400e);
  font-size: 0.82rem;
  font-weight: 600;
}

.bp_external_markup_source {
  overflow: auto;
  white-space: pre-wrap;
  border: 1px solid var(--bp-color-border-soft, #e2e8f0);
  border-radius: var(--bp-radius-md, 0.375rem);
  background: var(--bp-color-surface-muted, #f8fafc);
  padding: 0.65rem 0.75rem;
  font-size: 0.86rem;
  line-height: 1.45;
}

.bp_external_markup_source code {
  white-space: inherit;
}

.bp_external_markdown_body {
  display: flow-root;
}

.bp_external_markdown_body > :first-child,
.bp_external_markdown_body > :first-child > :first-child {
  margin-top: 0;
}

.bp_external_markdown_body > :last-child,
.bp_external_markdown_body > :last-child > :last-child {
  margin-bottom: 0;
}

.bp_external_markdown_body pre {
  overflow: auto;
}
"##

def externalMarkupRenderHtmlAssets : HtmlAssets :=
  { extraCss := [externalMarkupRenderCss] }

/-- Generated HTML strategy for markup-only Blueprint nodes. -/
inductive ExternalMarkupRenderMode where
  /-- Export semantic manifest entries only, matching the original source-witness behavior. -/
  | none
  /-- Render the selected external source as escaped source text. -/
  | source
  /-- Render Markdown source with Blueprint's Lean-side renderer; render other sources as source text. -/
  | markdown
deriving Inhabited, Repr, DecidableEq

def ExternalMarkupRenderMode.parse? (raw : String) : Option ExternalMarkupRenderMode :=
  match raw.trimAscii.toString.toLower with
  | "none" | "off" | "hidden" => some .none
  | "source" | "raw" => some .source
  | "markdown" | "md" => some .markdown
  | _ => none

def ExternalMarkupRenderMode.cliValues : String :=
  "markdown, source, none"

/-- Preferred language/slot when choosing one source attachment for generated HTML. -/
structure ExternalMarkupPreference where
  language : Informal.Data.ExternalMarkupLanguage
  slot : String
deriving Inhabited, Repr

def defaultExternalMarkupPreferences : Array ExternalMarkupPreference :=
  #[
    { language := .markdown, slot := "statement" },
    { language := .markdown, slot := Informal.Data.defaultExternalMarkupSlot },
    { language := .tex, slot := "statement" },
    { language := .tex, slot := Informal.Data.defaultExternalMarkupSlot }
  ]

/--
Options for Lean-side HTML fragments generated from markup-only external
sources.

The default gives source-only Markdown projects a rendered preview while still
marking the body as source-backed and remaining compatible with interpreted
`lean --run` generators. Set `mode := .none` to keep manifest-only entries with
no generated HTML cache fragment.
-/
structure ExternalMarkupRenderConfig where
  mode : ExternalMarkupRenderMode := .markdown
  /-- Include a visible note that generated HTML came from external source, not native Verso. -/
  showSourceNotice : Bool := true
  preferences : Array ExternalMarkupPreference := defaultExternalMarkupPreferences
deriving Inhabited, Repr

private def sameExternalMarkupLanguage
    (a b : Informal.Data.ExternalMarkupLanguage) : Bool :=
  match a, b with
  | .tex, .tex => true
  | .markdown, .markdown => true
  | _, _ => false

private def externalMarkupMatchesPreference
    (markup : Informal.Data.ExternalMarkup) (preference : ExternalMarkupPreference) : Bool :=
  sameExternalMarkupLanguage markup.language preference.language && markup.slot == preference.slot

def selectedExternalMarkup?
    (cfg : ExternalMarkupRenderConfig)
    (markup : Array Informal.Data.ExternalMarkup) : Option Informal.Data.ExternalMarkup :=
  let nonempty := markup.filter fun item => !item.raw.trimAscii.toString.isEmpty
  (cfg.preferences.findSome? fun preference =>
    nonempty.find? fun item => externalMarkupMatchesPreference item preference) <|> nonempty[0]?

private def externalMarkupNoticeHtml (markup : Informal.Data.ExternalMarkup) : Verso.Output.Html :=
  let text :=
    s!"Rendered from {Informal.ExternalMarkupView.sourceSummary markup}; no native Verso body is available."
  Verso.Output.Html.tag "p"
    #[("class", "bp_external_markup_notice"), ("role", "note")]
    (VersoBlueprint.Html.text text)

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

private def startsDoubleStar : List Char → Bool
  | '*' :: '*' :: _ => true
  | _ => false

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

private def renderStandardMarkdownHtml (raw : String) : String :=
  let (html, _) := renderMarkdownBlocks (markdownLines raw)
  html

private def renderMarkdownBody? (raw : String) : Option Verso.Output.Html := do
  let html := renderStandardMarkdownHtml raw
  some <| Verso.Output.Html.tag "div" #[("class", "bp_external_markdown_body")]
    (Verso.Output.Html.text false html)

private def renderExternalMarkupBody?
    (cfg : ExternalMarkupRenderConfig)
    (markup : Informal.Data.ExternalMarkup) : Option Verso.Output.Html :=
  match cfg.mode with
  | .none => none
  | .source => some <| Informal.ExternalMarkupView.sourcePreHtml markup
  | .markdown =>
      match markup.language with
      | .markdown => renderMarkdownBody? markup.raw <|> some (Informal.ExternalMarkupView.sourcePreHtml markup)
      | .tex => some <| Informal.ExternalMarkupView.sourcePreHtml markup

def renderExternalMarkupEntryHtml
    (cfg : ExternalMarkupRenderConfig)
    (blockData : Informal.BlockData)
    (headingCaption headingLabel : String)
    (markup : Informal.Data.ExternalMarkup) : Option String := do
  let body ← renderExternalMarkupBody? cfg markup
  let content :=
    if cfg.showSourceNotice then
      #[externalMarkupNoticeHtml markup, body]
    else
      #[body]
  let html := Informal.renderInformalBlockModel {
    data := blockData
    context := Informal.InformalBlockRenderContext.forBlock blockData headingLabel
      (statementCaption? := some headingCaption)
      (attrs := #[
        ("data-bp-source-backed", "true"),
        ("data-bp-external-markup-language", markup.language.key),
        ("data-bp-external-markup-slot", markup.slot)
      ])
    content
    wrapperClass? := some "bp_preview_data_node_blueprint bp_external_markup_node"
  }
  some <| Verso.Output.Html.asString html

end Informal.PreviewManifest
