/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoManual
public import MD4Lean
public import VersoBlueprint.Data
public import VersoBlueprint.Html
public import VersoBlueprint.Informal.ExternalMarkupView

public section

namespace Informal.ExternalMarkupRender

open Verso.Genre Manual

def css : String := r##"
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

def htmlAssets : HtmlAssets :=
  { extraCss := [css] }

/-- Generated HTML strategy for bodyless Blueprint nodes backed by external markup. -/
inductive Mode where
  /-- Export semantic manifest entries only, matching the original source-witness behavior. -/
  | none
  /-- Render the selected external source as escaped source text. -/
  | source
  /-- Render Markdown source with MD4Lean; render other sources as source text. -/
  | markdown
deriving Inhabited, Repr, DecidableEq

def Mode.parse? (raw : String) : Option Mode :=
  match raw.trimAscii.toString.toLower with
  | "none" | "off" | "hidden" => some .none
  | "source" | "raw" => some .source
  | "markdown" | "md" => some .markdown
  | _ => none

def Mode.cliValues : String :=
  "markdown, source, none"

/-- Preferred language/slot when choosing one source attachment for generated HTML. -/
structure Preference where
  language : Informal.Data.ExternalMarkupLanguage
  slot : String
deriving Inhabited, Repr

def defaultPreferences : Array Preference :=
  #[
    { language := .markdown, slot := "statement" },
    { language := .markdown, slot := Informal.Data.defaultExternalMarkupSlot },
    { language := .tex, slot := "statement" },
    { language := .tex, slot := Informal.Data.defaultExternalMarkupSlot }
  ]

/--
Options for Lean-side HTML fragments generated from external markup sources.

The default gives bodyless Markdown-backed nodes a rendered preview while still
marking the body as source-backed. Set `mode := .none` to keep manifest-only
entries with no generated HTML cache fragment.
-/
structure Config where
  mode : Mode := .markdown
  /-- Include a visible note that generated HTML came from external source, not native Verso. -/
  showSourceNotice : Bool := true
  preferences : Array Preference := defaultPreferences
deriving Inhabited, Repr

private def sameLanguage
    (a b : Informal.Data.ExternalMarkupLanguage) : Bool :=
  match a, b with
  | .tex, .tex => true
  | .markdown, .markdown => true
  | _, _ => false

private def matchesPreference
    (markup : Informal.Data.ExternalMarkup) (preference : Preference) : Bool :=
  sameLanguage markup.language preference.language && markup.slot == preference.slot

def selected?
    (cfg : Config)
    (markup : Array Informal.Data.ExternalMarkup) : Option Informal.Data.ExternalMarkup :=
  let nonempty := markup.filter fun item => !item.raw.trimAscii.toString.isEmpty
  (cfg.preferences.findSome? fun preference =>
    nonempty.find? fun item => matchesPreference item preference) <|> nonempty[0]?

/-- Data attributes attached to generated bodies whose visible text comes from external source. -/
def sourceBackedAttrs (markup : Informal.Data.ExternalMarkup) : Array (String × String) :=
  #[
    ("data-bp-source-backed", "true"),
    ("data-bp-external-markup-language", markup.language.key),
    ("data-bp-external-markup-slot", markup.slot)
  ]

def noticeHtml (markup : Informal.Data.ExternalMarkup) : Verso.Output.Html :=
  let text :=
    s!"Rendered from {Informal.ExternalMarkupView.sourceSummary markup}; no native Verso body is available."
  Verso.Output.Html.tag "p"
    #[("class", "bp_external_markup_notice"), ("role", "note")]
    (VersoBlueprint.Html.text text)

private def renderMarkdownBody? (raw : String) : Option Verso.Output.Html := do
  let html ← MD4Lean.renderHtml raw
  some <| Verso.Output.Html.tag "div" #[("class", "bp_external_markdown_body")]
    (Verso.Output.Html.text false html)

def body?
    (cfg : Config)
    (markup : Informal.Data.ExternalMarkup) : Option Verso.Output.Html :=
  match cfg.mode with
  | .none => none
  | .source => some <| Informal.ExternalMarkupView.sourcePreHtml markup
  | .markdown =>
      match markup.language with
      | .markdown => renderMarkdownBody? markup.raw <|> some (Informal.ExternalMarkupView.sourcePreHtml markup)
      | .tex => some <| Informal.ExternalMarkupView.sourcePreHtml markup

def content?
    (cfg : Config)
    (markup : Informal.Data.ExternalMarkup) : Option (Array Verso.Output.Html) := do
  let body ← body? cfg markup
  if cfg.showSourceNotice then
    some #[noticeHtml markup, body]
  else
    some #[body]

def selectedContent?
    (cfg : Config)
    (markup : Array Informal.Data.ExternalMarkup) :
    Option (Informal.Data.ExternalMarkup × Array Verso.Output.Html) := do
  let selected ← selected? cfg markup
  let content ← content? cfg selected
  some (selected, content)

end Informal.ExternalMarkupRender
