/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import MD4Lean
import VersoManual
import VersoBlueprint.Data
import VersoBlueprint.Html
import VersoBlueprint.Informal.Block.Model
import VersoBlueprint.Informal.Block.Render

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

.bp_external_markdown_body > :first-child {
  margin-top: 0;
}

.bp_external_markdown_body > :last-child {
  margin-bottom: 0;
}

.bp_external_markdown_body h1,
.bp_external_markdown_body h2,
.bp_external_markdown_body h3,
.bp_external_markdown_body h4,
.bp_external_markdown_body h5,
.bp_external_markdown_body h6 {
  margin: 0.75rem 0 0.35rem;
  line-height: 1.25;
}

.bp_external_markdown_body h1 {
  font-size: 1.22rem;
}

.bp_external_markdown_body h2 {
  font-size: 1.12rem;
}

.bp_external_markdown_body h3,
.bp_external_markdown_body h4,
.bp_external_markdown_body h5,
.bp_external_markdown_body h6 {
  font-size: 1rem;
}

.bp_external_markdown_body p {
  margin: 0.45rem 0;
}

.bp_external_markdown_body ul,
.bp_external_markdown_body ol {
  margin: 0.45rem 0 0.45rem 1.15rem;
  padding: 0;
}

.bp_external_markdown_body blockquote {
  margin: 0.55rem 0;
  padding-left: 0.8rem;
  border-left: 0.16rem solid var(--bp-color-border-soft, #e2e8f0);
  color: var(--bp-color-text-muted, #475569);
}

.bp_external_markdown_body pre {
  overflow: auto;
  border: 1px solid var(--bp-color-border-soft, #e2e8f0);
  border-radius: var(--bp-radius-md, 0.375rem);
  background: var(--bp-color-surface-muted, #f8fafc);
  padding: 0.65rem 0.75rem;
  font-size: 0.86rem;
  line-height: 1.45;
}

.bp_external_markdown_body code {
  padding: 0.02rem 0.18rem;
  border-radius: 0.22rem;
  background: var(--bp-color-surface-muted, #f8fafc);
}

.bp_external_markdown_body pre code {
  padding: 0;
  border-radius: 0;
  background: transparent;
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
  /-- Render Markdown source with MD4Lean/MD4C; render other sources as source text. -/
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
marking the body as source-backed. Set `mode := .none` to keep manifest-only
entries with no generated HTML cache fragment.
-/
structure ExternalMarkupRenderConfig where
  mode : ExternalMarkupRenderMode := .markdown
  warn : Bool := true
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

private def externalMarkupLocationText? (location? : Option Informal.Data.ExternalMarkupLocation) :
    Option String := do
  let location ← location?
  some s!"{location.path}:{location.range.start.line}:{location.range.start.character}-{location.range.«end».line}:{location.range.«end».character}"

private def externalMarkupSelectionSummary (markup : Informal.Data.ExternalMarkup) : String :=
  let base := s!"external {markup.language.displayName} source ({markup.slot})"
  match externalMarkupLocationText? markup.location with
  | some location => s!"{base}: {location}"
  | none => base

private def externalMarkupNoticeHtml (markup : Informal.Data.ExternalMarkup) : Verso.Output.Html :=
  let text :=
    s!"Rendered from {externalMarkupSelectionSummary markup}; no native Verso body is available."
  Verso.Output.Html.tag "p"
    #[("class", "bp_external_markup_notice"), ("role", "note")]
    (VersoBlueprint.Html.text text)

private def externalMarkupSourceHtml (markup : Informal.Data.ExternalMarkup) : Verso.Output.Html :=
  let code := Verso.Output.Html.tag "code"
    #[("class", s!"language-{markup.language.key}")]
    (VersoBlueprint.Html.text markup.raw)
  Verso.Output.Html.tag "pre"
    #[("class", s!"bp_external_markup_source bp_external_markup_source_{markup.language.key}")]
    code

private def renderMarkdownBody? (raw : String) : Option Verso.Output.Html := do
  let html ← MD4Lean.renderHtml raw
  some <| Verso.Output.Html.tag "div" #[("class", "bp_external_markdown_body")]
    (Verso.Output.Html.text false html)

private def renderExternalMarkupBody?
    (cfg : ExternalMarkupRenderConfig)
    (markup : Informal.Data.ExternalMarkup) : Option Verso.Output.Html :=
  match cfg.mode with
  | .none => none
  | .source => some <| externalMarkupSourceHtml markup
  | .markdown =>
      match markup.language with
      | .markdown => renderMarkdownBody? markup.raw <|> some (externalMarkupSourceHtml markup)
      | .tex => some <| externalMarkupSourceHtml markup

def renderExternalMarkupEntryHtml
    (cfg : ExternalMarkupRenderConfig)
    (blockData : Informal.BlockData)
    (headingCaption headingLabel : String)
    (markup : Informal.Data.ExternalMarkup) : Option String := do
  let body ← renderExternalMarkupBody? cfg markup
  let content :=
    if cfg.warn then
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
