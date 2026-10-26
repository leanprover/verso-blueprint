/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintExternalHeadingStatus

open Lean
open Informal
open Informal.Data
open Verso.VersoBlueprintTests.Blueprint.Support

private def inlineProofGapStatus : Data.ProvedStatus :=
  .incomplete { knownSorry := #[{ location := .proof, refs? := some 1 }] }

private def missingExternalRef (name : Lean.Name) : Data.ExternalRef :=
  {
    (Data.ExternalRef.ofName name) with
      present := false
      kind := .definition
  }

private def proofGapExternalRef (name : Lean.Name) : Data.ExternalRef :=
  {
    (Data.ExternalRef.ofName name) with
      present := true
      kind := .theorem
      provedStatus := .incomplete { knownSorry := #[{ location := .proof, refs? := some 1 }] }
  }

private def renderFailedExternalRef (name : Lean.Name) : Data.ExternalRef :=
  {
    (Data.ExternalRef.ofName name) with
      present := true
      kind := .theorem
      provedStatus := .proved
      render := .error (.exception name "synthetic render failure")
  }

private def unavailableHeading (rendered : CodeSummary.RenderParts) : Bool :=
  match rendered.statusMark with
  | some mark => mark.status == .incomplete {} &&
      mark.title.contains "Validation unavailable" && mark.symbolOverride? == some "?"
  | none => false

-- A cached declaration status alone cannot fill an occurrence's assessment.
/-- info: true -/
#guard_msgs in
#eval!
  let data : BlockData := {
    kind := .theorem
    codeData := some { externalDecls := #[proofGapExternalRef `Ext.thm.unassessed] }
    label := `status.theorem.unassessed
    count := 1
  }
  unavailableHeading (CodeSummary.renderParts data { source := data.codeData } (fun _ => none))

-- Empty source data stays distinct from a source-backed but unassessed heading.
/-- info: true -/
#guard_msgs in
#eval!
  let data : BlockData := { kind := .theorem, label := `status.theorem.empty, count := 1 }
  (CodeSummary.renderParts data {} (fun _ => none)).statusMark.isNone

/-- info: true -/
#guard_msgs in
#eval!
  let data : BlockData := {
    kind := .theorem
    codeData := some { externalDecls := #[proofGapExternalRef `Ext.thm.proof_only] }
    label := `status.theorem.external
    count := 1
  }
  let cdata : CodeSummary.ComputedData := {
    source := data.codeData
  }
  unavailableHeading (CodeSummary.renderParts data cdata (fun _ => none))

/-- info: true -/
#guard_msgs in
#eval!
  let ref : Data.ExternalRef := {
    (proofGapExternalRef `Ext.def.proof_only) with
      kind := .definition
  }
  let data : BlockData := {
    kind := .definition
    codeData := some { externalDecls := #[ref] }
    label := `status.definition.external
    count := 1
  }
  let cdata : CodeSummary.ComputedData := {
    source := data.codeData
  }
  unavailableHeading (CodeSummary.renderParts data cdata (fun _ => none))

/-- info: true -/
#guard_msgs in
#eval!
  let codeData : InlineCodeData := {
    blockId := `status.inline.panel.block
    label := `status.inline.panel
    definedDefs := #[{ name := `inlineDef, provedStatus := .proved }]
    definedTheorems := #[{ name := `inlineThm, provedStatus := inlineProofGapStatus }]
  }
  let headingData : BlockData := {
    kind := .definition
    codeData := some (BlockCodeData.ofInlineBlocks #[codeData])
    label := `status.inline.panel
    count := 1
  }
  let headingHtml := (CodeSummary.renderParts headingData { source := some (BlockCodeData.ofInlineBlocks #[codeData]) } (fun _ => none)).codeEntry.asString
  let parts := CodeSummary.renderPanelIndicator
    `status.inline.panel
    { source := some (BlockCodeData.ofInlineBlocks #[codeData]) }
    (fun _ => none)
  let html := parts.indicator.asString
  hasSubstr parts.summaryTitle "status.inline.panel" &&
  hasSubstr parts.summaryTitle "inlineThm [sorry in proof]" &&
  hasSubstr headingHtml "L∃∀N" &&
  hasSubstr headingHtml "class=\"bp_code_decl_item\"" &&
  hasSubstr headingHtml "Associated Lean declarations" &&
  hasSubstr html "bp_code_progress" &&
  hasSubstr html "class=\"bp_code_decl_item\"" &&
  hasSubstr html "inlineDef" &&
  hasSubstr html "inlineThm" &&
  hasSubstr html ">[complete]</span>" &&
  hasSubstr html ">[sorry in proof]</span>"

/-- info: true -/
#guard_msgs in
#eval!
  let decls := #[
    proofGapExternalRef `Ext.external.proof_gap,
    missingExternalRef `Ext.external.missing
  ]
  let parts := CodeSummary.renderPanelIndicator
    `status.external.panel
    { source := some { externalDecls := decls } }
    (fun _ => none)
  let headingData : BlockData := {
    kind := .theorem
    codeData := some { externalDecls := decls }
    label := `status.external.panel
    count := 1
  }
  let headingHtml := (CodeSummary.renderParts headingData { source := some { externalDecls := decls } } (fun _ => none)).codeEntry.asString
  let html := parts.indicator.asString
  hasSubstr parts.summaryTitle "Lean declarations (1/2 present)" &&
  hasSubstr headingHtml "L∃∀N" &&
  hasSubstr headingHtml "class=\"bp_code_decl_item\"" &&
  hasSubstr html "bp_external_status_badge" &&
  hasSubstr html "class=\"bp_code_decl_item\"" &&
  hasSubstr html "Ext.external.proof_gap" &&
  hasSubstr html "Ext.external.missing" &&
  hasSubstr html ">[sorry in proof]</span>" &&
  hasSubstr html ">[missing declaration]</span>"

/-- info: true -/
#guard_msgs in
#eval!
  let decls := #[renderFailedExternalRef `Ext.external.render_fail]
  let headingData : BlockData := {
    kind := .theorem
    codeData := some { externalDecls := decls }
    label := `status.external.render_fail
    count := 1
  }
  let cdata : CodeSummary.ComputedData := {
    source := headingData.codeData
  }
  let rendered := CodeSummary.renderParts headingData cdata (fun _ => none)
  let panelParts := CodeSummary.renderPanelIndicator `status.external.render_fail cdata (fun _ => none)
  match rendered.statusMark with
  | some _ =>
    unavailableHeading rendered &&
    !hasSubstr rendered.codeEntry.asString "bp_code_link_status_proved" &&
    hasSubstr rendered.codeEntry.asString "bp_code_render_warning_badge" &&
    appearsBefore rendered.codeEntry.asString "bp_code_render_warning_badge" "bp_code_status_symbol" &&
    hasSubstr rendered.codeEntry.asString "render failed for 1 declaration" &&
    hasSubstr rendered.codeEntry.asString "Render diagnostics" &&
    hasSubstr rendered.codeEntry.asString "synthetic render failure" &&
    !hasSubstr panelParts.indicator.asString "bp_code_render_warning_badge" &&
    hasSubstr panelParts.summaryTitle "render failed for 1 declaration"
  | none => false

/-- info: true -/
#guard_msgs in
#eval!
  let status : ProvedStatus := .incomplete { knownSorry := #[
    { location := .statement, origin := .dependency },
    { location := .unknown, origin := .unknown }] }
  let ref : ExternalRef := { (ExternalRef.ofName `Hidden.typeOnly) with provedStatus := status }
  let data : BlockData := {
    kind := .theorem, label := `hidden.typeOnly, count := 1, codeData := some { externalDecls := #[ref] } }
  unavailableHeading (CodeSummary.renderParts data { source := data.codeData } (fun _ => none))

/-- info: true -/
#guard_msgs in
#eval!
  let direct : ProvedStatus := .incomplete { knownSorry := #[{ location := .proof, refs? := some 2 }] }
  let inherited : ProvedStatus := .incomplete { knownSorry := #[{ location := .proof, origin := .dependency }] }
  let refs := #[
    { (ExternalRef.ofName `Direct) with provedStatus := direct },
    { (ExternalRef.ofName `Inherited) with provedStatus := inherited }]
  let data : BlockData := {
    kind := .theorem, label := `mixed.origins, count := 1, codeData := some { externalDecls := refs } }
  unavailableHeading (CodeSummary.renderParts data { source := data.codeData } (fun _ => none))

-- Synthetic provider outcomes remain inventory; without an admitted capture they
-- cannot supply a heading assessment.
/-- info: true -/
#guard_msgs in
#eval!
  let check (status : ProvedStatus) :=
    let ref : ExternalRef := { (ExternalRef.ofName `Hidden.clean) with provedStatus := status }
    let data : BlockData := {
      kind := .theorem, label := `hidden.clean, count := 1,
      codeData := some { externalDecls := #[ref] } }
    unavailableHeading (CodeSummary.renderParts data { source := data.codeData } (fun _ => none))
  let hidden : ProvedStatus := .incomplete { unverified := #[{
    location := .proof, declaration := `Hidden.clean, reason := .bodyUnavailable }] }
  check hidden &&
    check (.incomplete {}) &&
    check .missing &&
    check (.incomplete {
      knownSorry := #[{ location := .statement, origin := .dependency }],
      unverified := #[{ location := .proof, declaration := `Hidden.clean, reason := .bodyUnavailable }] }) &&
    hidden.presentation.summaryText == "unverified" &&
    hidden.presentation.externalPanelText == "unverified" &&
    !hidden.hasKnownSorry

end Verso.VersoBlueprintTests.BlueprintExternalHeadingStatus
