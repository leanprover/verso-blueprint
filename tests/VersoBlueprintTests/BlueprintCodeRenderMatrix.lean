/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintCodeRenderMatrix

open Lean
open Informal
open Informal.Data
open Verso.VersoBlueprintTests.Blueprint.Support

private def provedExternalRef (name : Lean.Name) (kind : Data.NodeKind := .definition) : Data.ExternalRef :=
  {
    (Data.ExternalRef.ofName name) with
      provedStatus := .proved
      present := true
      kind
  }

private def sorryExternalRef (name : Lean.Name) (kind : Data.NodeKind := .theorem) : Data.ExternalRef :=
  {
    (Data.ExternalRef.ofName name) with
      present := true
      kind
      provedStatus := .incomplete { knownSorry := #[{ location := .proof, refs? := some 1 }] }
  }

private def axiomExternalRef (name : Lean.Name) (kind : Data.NodeKind := .theorem) : Data.ExternalRef :=
  {
    (Data.ExternalRef.ofName name) with
      present := true
      kind
      provedStatus := .axiomLike
  }

private def missingExternalRef (name : Lean.Name) (kind : Data.NodeKind := .definition) : Data.ExternalRef :=
  {
    (Data.ExternalRef.ofName name) with
      present := false
      kind
  }

private def renderFailedExternalRef (name : Lean.Name) (kind : Data.NodeKind := .theorem) : Data.ExternalRef :=
  {
    (Data.ExternalRef.ofName name) with
      present := true
      kind
      provedStatus := .proved
      render := .error (.exception name "synthetic render failure")
  }

private def statementData (label : Name) (kind : Data.NodeKind) (source : Option BlockCodeData) : BlockData :=
  {
    kind := kind
    codeData := source
    label
    count := 1
  }

private def inlineCode (declStatus : Data.ProvedStatus) : InlineCodeBlocks :=
  #[{
    blockId := `matrix.inline
    label := `inline.status
    definedDefs := #[{ name := `Inline.status, provedStatus := declStatus }]
  }]

private def codeEntryHtml (label : Name) (kind : Data.NodeKind) (source : Option BlockCodeData) : String :=
  let data := statementData label kind source
  (CodeSummary.renderParts data { source } (fun _ => none)).codeEntry.asString

private def codeEntryHtmlWithAssessment (label : Name) (kind : Data.NodeKind)
    (source : Option BlockCodeData) (assessment : Realizations.NodeAssessment) : String :=
  let data := { (statementData label kind source) with assessment := some assessment }
  (CodeSummary.renderParts data { source } (fun _ => none)).codeEntry.asString

private def panelIndicatorHtml (label : Name) (source : BlockCodeData) : String :=
  (CodeSummary.renderPanelIndicator label { source := some source } (fun _ => none)).indicator.asString

/-- info: true -/
#guard_msgs in
#eval!
  let inlineProvedHtml := codeEntryHtml `inline.proved .definition (some { literateDeclarations := (inlineCode .proved).literateDeclarations })
  let inlineSorryHtml := codeEntryHtml `inline.sorry .definition (some { literateDeclarations := (inlineCode (.incomplete { knownSorry := #[{ location := .proof, refs? := some 1 }] })).literateDeclarations })
  let inlineAxiomHtml := codeEntryHtml `inline.axiom .definition (some { literateDeclarations := (inlineCode .axiomLike).literateDeclarations })
  hasSubstr inlineProvedHtml "bp_code_link_status_warning" &&
    hasSubstr inlineSorryHtml "bp_code_link_status_warning" &&
    hasSubstr inlineAxiomHtml "bp_code_link_status_warning" &&
    hasSubstr inlineProvedHtml "Validation unavailable" &&
    hasSubstr inlineProvedHtml "bp_code_status_symbol" &&
    hasSubstr inlineProvedHtml ">?</span>" &&
    hasSubstr (codeEntryHtml `inline.absent .definition none) "bp_code_link_status_absent"

/-- info: true -/
#guard_msgs in
#eval!
  hasSubstr
      (codeEntryHtml `external.missing .definition (some { externalDecls := #[missingExternalRef `Ext.missing] }))
      "bp_code_link_status_warning"

/-- info: true -/
#guard_msgs in
#eval!
  hasSubstr
      (codeEntryHtml `external.axiom .theorem (some { externalDecls := #[axiomExternalRef `Ext.axiom] }))
      "bp_code_link_status_warning"

/-- info: true -/
#guard_msgs in
#eval!
  let externalRenderFailHtml := codeEntryHtml `external.render_fail .theorem (some { externalDecls := #[renderFailedExternalRef `Ext.renderFail] })
  hasSubstr externalRenderFailHtml "bp_code_link_status_warning" &&
    hasSubstr externalRenderFailHtml "bp_code_render_warning_badge" &&
    appearsBefore externalRenderFailHtml "bp_code_render_warning_badge" "bp_code_status_symbol"

-- This MOCK transport assessment is test data, not provider success. It controls
-- the heading while declaration display snapshots remain visibly separate.
/-- info: true -/
#guard_msgs in
#eval!
  let blocks := #[{
    blockId := `matrix.siblings
    label := `matrix.siblings
    definedTheorems := #[
      { name := `Matrix.checked, provedStatus := .proved },
      { name := `Matrix.unselected, provedStatus := .proved }]
  }]
  let source : BlockCodeData := .ofInlineBlocks blocks
  let assessment : Realizations.NodeAssessment := {
    hasNativeDeclarations := true
    hasAxiomLike := false
    nativeStatementComplete := true
    nativeProofComplete := false
    requiredComplete := false
    statementDependenciesComplete := true
    proofDependenciesComplete := false
    details := Json.mkObj [("fixture", Json.str "MOCK: transport only; not provider success")]
  }
  let heading := codeEntryHtmlWithAssessment `matrix.siblings .theorem (some source) assessment
  let panel := panelIndicatorHtml `matrix.siblings source
  hasSubstr heading "native proof: unfinished" &&
    hasSubstr heading "required Blueprint validation: unfinished" &&
    hasSubstr panel "Associated Lean declarations (source snapshots; display only; validation shown in heading)" &&
    hasSubstr panel "complete source snapshot; realization validation is shown in the heading" &&
    hasSubstr panel "not realization validation"

/-- info: true -/
#guard_msgs in
#eval!
  let externalOkHtml := panelIndicatorHtml `external.ok { externalDecls := #[provedExternalRef `Ext.ok .definition] }
  let externalSorryHtml := panelIndicatorHtml `external.sorry { externalDecls := #[sorryExternalRef `Ext.sorry .theorem] }
  let externalMissingHtml := panelIndicatorHtml `external.missing { externalDecls := #[missingExternalRef `Ext.missing .definition] }
  let externalAxiomHtml := panelIndicatorHtml `external.axiom { externalDecls := #[axiomExternalRef `Ext.axiom .theorem] }
  let externalRenderFailHtml := panelIndicatorHtml `external.render_fail { externalDecls := #[renderFailedExternalRef `Ext.renderFail .theorem] }
  hasSubstr externalOkHtml "bp_external_status_badge_summary bp_external_status_ok" &&
    hasSubstr externalSorryHtml "bp_external_status_badge_summary bp_external_status_sorry" &&
    hasSubstr externalMissingHtml "bp_external_status_badge_summary bp_external_status_missing" &&
    hasSubstr externalAxiomHtml "bp_code_decl_status_axiom" &&
    !hasSubstr externalRenderFailHtml "bp_code_render_warning_badge" &&
    !hasSubstr externalRenderFailHtml "bp_render_warning_badge" &&
    hasSubstr externalRenderFailHtml "synthetic render failure"

-- A heading summarizes the union, even when literate code has its own panel.
#eval show IO Unit from do
  let source : BlockCodeData := {
    literateDeclarations := (inlineCode .proved).literateDeclarations
    externalDecls := #[sorryExternalRef `Ext.mixed .theorem] }
  let html := codeEntryHtml `mixed .theorem (some source)
  unless hasSubstr html "bp_code_link_status_warning" && hasSubstr html "Ext.mixed" &&
      source.literateDeclarations.declarations.all (fun decl => hasSubstr html decl.name.toString) do
    throw <| IO.userError "Mixed associations lost a declaration or hid its incomplete status"

-- The inline and external declaration snapshots still merge for display, but
-- their old status payload cannot complete the heading without a capture.
#eval show IO Unit from do
  let blocks := inlineCode .proved
  let declaration := blocks.declarations[0]!
  let external := missingExternalRef declaration.name
  let source : BlockCodeData := { literateDeclarations := blocks.literateDeclarations, externalDecls := #[external] }
  let summary := source.summaryLiterateDeclarations
  let inlineStatus? := summary.definedDefs[0]?.map (·.provedStatus)
  let heading := codeEntryHtml `missing.snapshot .definition (some source)
  let panel := panelIndicatorHtml `missing.snapshot source
  unless inlineStatus? == some .missing &&
      hasSubstr heading "Validation unavailable" && hasSubstr heading "[missing declaration]" &&
      hasSubstr panel "bp_external_status_badge_summary bp_external_status_missing" do
    throw <| IO.userError "Source snapshots did not stay display-only while the captured heading stayed unavailable"

end Verso.VersoBlueprintTests.BlueprintCodeRenderMatrix
