/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Lean
public import Verso
public import VersoManual
public import VersoBlueprint.Informal.Block.Model
public import VersoBlueprint.ProvedStatus

public section

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
  status : Data.ProvedStatus := .proved
  title : String
  symbolOverride? : Option String := none
deriving Repr, Inhabited

def BlockStatusMark.text (s : BlockStatusMark) : String :=
  match s.symbolOverride? with
  | some txt => txt
  | none => s.status.presentation.statusMarkSymbol

def BlockStatusMark.toHtml (s : BlockStatusMark) : Output.Html :=
  open Verso.Output.Html in
  {{ <span class="bp_status_mark" title={{s.title}}>{{.text true s.text}}</span> }}

def codeHoverListItem (body : Output.Html) : Output.Html :=
  open Verso.Output.Html in
  {{<li>{{body}}</li>}}

def codeHoverTextItem (text : String) : Output.Html :=
  open Verso.Output.Html in
  let body : Output.Html := .text true text
  codeHoverListItem body

def codeHoverEmptyItem (text : String) : Output.Html :=
  open Verso.Output.Html in
  {{<li class="bp_code_hover_none">{{.text true text}}</li>}}

def codeHoverCodeItem (text : String) : Output.Html :=
  open Verso.Output.Html in
  let body : Output.Html := {{<code>{{.text true text}}</code>}}
  codeHoverListItem body

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

structure CodePanelHeader where
  caption : String
  number? : Option String := none
deriving Repr, Inhabited

def codePanelHeaderFor (languageName : String) (data : BlockData) (numberText : String) :
    CodePanelHeader :=
  match data.kind with
  | .proof => { caption := s!"{languageName} code for proof" }
  | .statement nodeKind =>
    {
      caption := s!"{languageName} code for {nodeKind}"
      number? := some numberText
    }

def fallbackCodePanelHeaderFor (languageName : String) : CodePanelHeader := {
  caption := s!"{languageName} code"
}

def codePanelHeader (data : BlockData) (numberText : String) : CodePanelHeader :=
  codePanelHeaderFor "Lean" data numberText

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

def externalDeclHasGap (decl : Data.ExternalRef) : Bool :=
  decl.present && decl.provedStatus.isIncomplete

def externalCodeEntryTitle (found total missing withGaps : Nat) : String :=
  if missing > 0 then
    s!"Lean declarations ({found}/{total} present)"
  else if withGaps > 0 then
    s!"Lean declarations (all present: {found}/{total}; incomplete: {withGaps})"
  else
    s!"Lean declarations (all present: {found}/{total})"

def mkCodePanel
    (header : CodePanelHeader) (summaryTitle : String)
    (progressBar body : Output.Html)
    (attrs : Array (String × String) := #[])
    (folded : Bool := false) : Output.Html :=
  open Verso.Output.Html in
  let attrs :=
    if folded then attrs else attrs.push ("open", "open")
  {{
    <div class="bp_wrapper bp_code_panel_wrapper">
      <details class="bp_code_block bp_code_panel" {{attrs}}>
        <summary class="bp_heading lemma_thmheading" title={{summaryTitle}}>
          <span class="bp_heading_title_row">
            <span class="bp_caption lemma_thmcaption bp_code_summary_text">{{.text true header.caption}}</span>
            {{if let some number := header.number? then
                {{<span class="bp_label lemma_thmlabel bp_code_summary_label">{{.text true number}}</span>}}
              else
                .empty}}
          </span>
          {{progressBar}}
        </summary>
        {{body}}
      </details>
    </div>
  }}

end Informal
