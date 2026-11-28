/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso
import VersoManual
import VersoBlueprint.Informal.Block.Model
import VersoBlueprint.ProvedStatus

namespace Informal

open Verso Doc Elab
open Verso.Genre Manual
open Lean Elab

def renderErrorMessage? : Data.ExternalDeclRender → Option String
  | .ok _ => none
  | .error error => some error.message

structure ExternalRenderFailure where
  decl : Data.ExternalRef
  message : String
deriving Repr, Inhabited

def externalRenderFailure? (decl : Data.ExternalRef) : Option ExternalRenderFailure := do
  if !decl.present then
    none
  else
    let message ← renderErrorMessage? decl.render
    some { decl, message }

def externalRenderFailures (decls : Array Data.ExternalRef) : Array ExternalRenderFailure :=
  decls.filterMap externalRenderFailure?

def externalRenderFailureCount (decls : Array Data.ExternalRef) : Nat :=
  (externalRenderFailures decls).size

def externalRenderFailureSummaryText (count : Nat) : String :=
  if count == 1 then
    "render failed for 1 declaration"
  else
    s!"render failed for {count} declarations"

def appendExternalRenderFailureSummary (title : String) (count : Nat) : String :=
  if count == 0 then
    title
  else
    s!"{title}; {externalRenderFailureSummaryText count}"

structure BlockStatusMark where
  status : Data.ProvedStatus := .incomplete {}
  /-- One plain sentence saying what the status means for this block. -/
  lead : String := ""
  /-- The lead followed by the validation details, for tooltips. -/
  title : String
  symbolOverride? : Option String := none
  /-- Own Lean code checks, but other required validation, such as a prerequisite, is unfinished. -/
  requirementsOpen : Bool := false
deriving Repr, Inhabited

def BlockStatusMark.text (s : BlockStatusMark) : String :=
  match s.symbolOverride? with
  | some txt => txt
  | none => s.status.presentation.statusMarkSymbol

def codeHoverListItem (body : Output.Html) : Output.Html :=
  open Verso.Output.Html in
  {{<li>{{body}}</li>}}

def codeHoverEmptyItem (text : String) : Output.Html :=
  open Verso.Output.Html in
  {{<li class="bp_code_hover_none">{{.text true text}}</li>}}

def codeHoverSection (title : String) (items : Array Output.Html) : Output.Html :=
  open Verso.Output.Html in
  {{
    <div class="bp_code_hover_section">
      <span class="bp_code_hover_label">{{.text true title}}</span>
      <ul class="bp_code_hover_list">
        {{.seq items}}
      </ul>
    </div>
  }}

/--
The caption of a code panel: "Lean code for Theorem 1.1.4". A panel that directly
follows the block it belongs to is joined to it on the page, and then reads just
"Lean"; `ownerLabel?` is how the page tells which block that is.
-/
structure CodePanelHeader where
  language : String := "Lean"
  /-- The block the code belongs to, as readers see it, such as "Theorem 1.1.4". -/
  owner? : Option String := none
  /-- The owning block's label, matching its wrapper's `data-bp-owner`. -/
  ownerLabel? : Option String := none
  /-- A caption that replaces "<language> code for <owner>" entirely. -/
  caption? : Option String := none
deriving Repr, Inhabited

def codePanelHeaderFor (languageName : String) (display : NodeDisplay) : CodePanelHeader :=
  { language := languageName, owner? := some display.title, ownerLabel? := some s!"{display.label}" }

def fallbackCodePanelHeaderFor (languageName : String) : CodePanelHeader :=
  { language := languageName }

def codePanelHeader (display : NodeDisplay) : CodePanelHeader :=
  codePanelHeaderFor "Lean" display

/-- Preserve the proof facet of declarations that contribute to the node. -/
def proofReferencesPanelHeader (ownerLabel? : Option String := none) : CodePanelHeader := {
  caption? := some "Lean declarations attached to this proof"
  ownerLabel?
}

def fallbackCodePanelHeader : CodePanelHeader :=
  fallbackCodePanelHeaderFor "Lean"

register_option verso.blueprint.foldProofs : Bool := {
  defValue := true
  descr := "Enable proof folding in VersoBlueprint Lean code blocks (hide text after `by` behind a toggle)"
}

register_option verso.blueprint.foldProofBlocks : Bool := {
  defValue := false
  descr := "Render VersoBlueprint proof blocks as collapsed details blocks"
}

register_option verso.blueprint.foldCodeBlocks : Bool := {
  defValue := false
  descr := "Render VersoBlueprint Lean, Rust, and external code panels as collapsed details blocks"
}

/-- A registration can know the declaration is present before its Lean proof
status is available. Keep waiting distinct from an inspected coverage gap. -/
def declarationStatusPresentation (status : Option Data.ProvedStatus) (present : Bool) :
    Data.ProvedStatusPresentation :=
  if !present then
    Data.ProvedStatus.presentation .missing
  else if let some status := status then
    status.presentation
  else {
    summaryText := "awaiting capture"
    externalPanelText := "awaiting capture"
    externalHeaderText := "awaiting capture"
    codeDeclClass := "bp_code_decl_status_awaiting"
    externalDeclClass := "bp_external_decl_awaiting"
    codeEntryClassSuffix := "awaiting"
    codeEntrySymbol := "…"
    statusMarkSymbol := "…" }

def externalCodeEntryTitle (found total missing withGaps : Nat) : String :=
  if missing > 0 then
    s!"Lean declarations ({found}/{total} present)"
  else if withGaps > 0 then
    s!"Lean declarations (all present: {found}/{total}; incomplete: {withGaps})"
  else
    s!"Lean declarations (all present: {found}/{total})"

def mkCodePanel
    (header : CodePanelHeader) (summaryTitle : String)
    (indicator body : Output.Html)
    (attrs : Array (String × String) := #[])
    (folded : Bool := false) : Output.Html :=
  open Verso.Output.Html in
  let attrs :=
    if folded then attrs else attrs.push ("open", "open")
  let wrapperAttrs := #[("class", "bp_wrapper bp_code_panel_wrapper")] ++
    (header.ownerLabel?.map (("data-bp-owner", ·))).toArray
  let caption : Output.Html := match header.caption?, header.owner? with
    | some caption, _ => .text true caption
    | none, some owner =>
      {{ {{.text true header.language}}<span class="bp_code_for">{{.text true s!" code for {owner}"}}</span> }}
    | none, none => .text true s!"{header.language} code"
  .tag "div" wrapperAttrs {{
    <details class="bp_code_block bp_code_panel" {{attrs}}>
      <summary class="bp_heading lemma_thmheading" title={{summaryTitle}}>
        <span class="bp_heading_title_row">
          <span class="bp_caption lemma_thmcaption bp_code_summary_text">{{caption}}</span>
        </span>
        {{indicator}}
      </summary>
      {{body}}
    </details>
  }}

end Informal
