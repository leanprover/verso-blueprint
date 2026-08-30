/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoBlueprint.Data
public import VersoBlueprint.Html

public section

namespace Informal.ExternalMarkupView

/-- Compact source-range text for external markup locations. -/
def locationText? (location? : Option Informal.Data.ExternalMarkupLocation) :
    Option String := do
  let location ← location?
  let start := location.range.start
  let stop := location.range.«end»
  some s!"{location.path}:{start.line}:{start.character}-{stop.line}:{stop.character}"

private def appendLocation (base : String) (location? : Option Informal.Data.ExternalMarkupLocation) :
    String :=
  match locationText? location? with
  | none => base
  | some location => s!"{base}: {location}"

/-- Human-facing summary for an external markup block rendered at its source location. -/
def displaySummary (markup : Informal.Data.ExternalMarkup) : String :=
  appendLocation
    s!"External {markup.language.displayName} markup ({markup.slot})"
    markup.location

/-- Human-facing summary for a selected source-backed preview fragment. -/
def sourceSummary (markup : Informal.Data.ExternalMarkup) : String :=
  appendLocation
    s!"external {markup.language.displayName} source ({markup.slot})"
    markup.location

/-- Summary-only rendered external-markup source witness. -/
def summaryHtml (summary : String) : Verso.Output.Html :=
  Verso.Output.Html.tag "p"
    #[("class", "bp_external_markup_summary")]
    (VersoBlueprint.Html.text summary)

/-- Escaped source block shared by source displays and source-backed preview fragments. -/
def sourcePreHtml (markup : Informal.Data.ExternalMarkup) : Verso.Output.Html :=
  let code := Verso.Output.Html.tag "code"
    #[("class", s!"language-{markup.language.key}")]
    (VersoBlueprint.Html.text markup.raw)
  Verso.Output.Html.tag "pre"
    #[("class", s!"bp_external_markup_source bp_external_markup_source_{markup.language.key}")]
    code

/-- Source-displaying external-markup witness at its original source position. -/
def sourceDetailsHtml (markup : Informal.Data.ExternalMarkup) : Verso.Output.Html :=
  let summaryHtml := Verso.Output.Html.tag "summary" #[]
    (VersoBlueprint.Html.text (displaySummary markup))
  Verso.Output.Html.tag "details" #[("class", "bp_external_markup")]
    (Verso.Output.Html.seq #[summaryHtml, sourcePreHtml markup])

end Informal.ExternalMarkupView
