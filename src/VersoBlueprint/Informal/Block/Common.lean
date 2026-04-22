/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso
import VersoManual
import VersoBlueprint.Data
import VersoBlueprint.ProvedStatus
import VersoBlueprint.Resolve

namespace Informal

open Verso Doc Elab
open Verso.Genre Manual
open Lean Elab

inductive NumberingMode where
  | sub
  | global
  | local
deriving Repr, Inhabited, BEq, FromJson, ToJson, Quote

def NumberingMode.parse? (raw : String) : Option NumberingMode :=
  match raw.trimAscii.toString.toLower with
  | "sub" | "chapter" | "section" | "subnumber" | "sub-number" => some .sub
  | "global" => some .global
  | "local" => some .local
  | _ => none

register_option verso.blueprint.numbering : String := {
  defValue := "sub"
  descr := "Numbering mode for blueprint informal blocks: `sub` (default; prefix with numbered part path), `global`, or `local`"
}

def numberingMode (opts : Lean.Options) : NumberingMode :=
  match NumberingMode.parse? (verso.blueprint.numbering.get opts) with
  | some mode => mode
  | none => .sub

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

structure CodeDeclData where
  name : Name
  commandIndex : Nat := 0
  weight : Nat := 1
  provedStatus : Data.ProvedStatus := .proved
deriving Repr, Inhabited, Quote

instance : Lean.ToJson CodeDeclData where
  toJson data := .arr #[
    Lean.ToJson.toJson data.name,
    Lean.ToJson.toJson data.commandIndex,
    Lean.ToJson.toJson data.weight,
    Lean.ToJson.toJson data.provedStatus
  ]

instance : Lean.FromJson CodeDeclData where
  fromJson? v := do
    match v with
    | .arr arr =>
      let some name := arr[0]? | throw "expected code declaration name"
      let some commandIndex := arr[1]? | throw "expected code declaration command index"
      let some weight := arr[2]? | throw "expected code declaration weight"
      let some provedStatus := arr[3]? | throw "expected code declaration status"
      return {
        name := ← Lean.FromJson.fromJson? name
        commandIndex := ← Lean.FromJson.fromJson? commandIndex
        weight := ← Lean.FromJson.fromJson? weight
        provedStatus := ← Lean.FromJson.fromJson? provedStatus
      }
    | _ =>
      return {
        name := ← v.getObjValAs? Name "name"
        commandIndex := ← v.getObjValAs? Nat "commandIndex"
        weight := ← v.getObjValAs? Nat "weight"
        provedStatus := ← v.getObjValAs? Data.ProvedStatus "provedStatus"
      }

def CodeDeclData.ofLiterateDef (d : Data.LiterateDef) : CodeDeclData :=
  {
    name := d.name
    commandIndex := d.commandIndex
    weight := max d.commandLines 1
    provedStatus := d.provedStatus
  }

def CodeDeclData.ofLiterateThm (d : Data.LiterateThm) : CodeDeclData :=
  {
    name := d.name
    commandIndex := d.commandIndex
    weight := max d.commandLines 1
    provedStatus := d.provedStatus
  }

structure InlineCodeData where
  label : Data.Label
  definedDefs : Array CodeDeclData := #[]
  definedTheorems : Array CodeDeclData := #[]
  foldProofs : Bool := true
deriving Repr, Inhabited, Quote

instance : Lean.ToJson InlineCodeData where
  toJson data := .arr #[
    Lean.ToJson.toJson data.label,
    Lean.ToJson.toJson data.definedDefs,
    Lean.ToJson.toJson data.definedTheorems,
    Lean.ToJson.toJson data.foldProofs
  ]

instance : Lean.FromJson InlineCodeData where
  fromJson? v := do
    match v with
    | .arr arr =>
      let some label := arr[0]? | throw "expected inline code label"
      let some definedDefs := arr[1]? | throw "expected inline definitions"
      let some definedTheorems := arr[2]? | throw "expected inline theorems"
      let some foldProofs := arr[3]? | throw "expected foldProofs flag"
      return {
        label := ← Lean.FromJson.fromJson? label
        definedDefs := ← Lean.FromJson.fromJson? definedDefs
        definedTheorems := ← Lean.FromJson.fromJson? definedTheorems
        foldProofs := ← Lean.FromJson.fromJson? foldProofs
      }
    | _ =>
      return {
        label := ← v.getObjValAs? Data.Label "label"
        definedDefs := ← v.getObjValAs? (Array CodeDeclData) "definedDefs"
        definedTheorems := ← v.getObjValAs? (Array CodeDeclData) "definedTheorems"
        foldProofs := ← v.getObjValAs? Bool "foldProofs"
      }

/--
Resolved block-level code semantics used by informal block rendering.

This unifies directive hints and inline code payloads (`InlineCodeData`)
for the HTML phase:
- `inline` takes precedence whenever code-block data exists,
- otherwise we fall back to optional external declaration hints.
-/
inductive BlockCodeData where
  /-- Inline/literate code block associated with this label. -/
  | inline (code : InlineCodeData)
  /-- External Lean declarations associated with this label. -/
  | external (decls : Array Data.ExternalRef)
deriving Repr, Inhabited, Quote

instance : Lean.ToJson BlockCodeData where
  toJson
    | .inline code => .arr #[.str "i", Lean.ToJson.toJson code]
    | .external decls => .arr #[.str "e", Lean.ToJson.toJson decls]

instance : Lean.FromJson BlockCodeData where
  fromJson? v := do
    match v with
    | .arr arr =>
      let some tag := arr[0]? | throw "expected block code-data tag"
      let some payload := arr[1]? | throw "expected block code-data payload"
      match (← Lean.FromJson.fromJson? tag : String) with
      | "i" => .inline <$> Lean.FromJson.fromJson? payload
      | "e" => .external <$> Lean.FromJson.fromJson? payload
      | other => throw s!"unknown block code-data tag {other}"
    | .obj obj =>
      match obj.get? "inline", obj.get? "external" with
      | some code, none => .inline <$> Lean.FromJson.fromJson? code
      | none, some decls => .external <$> Lean.FromJson.fromJson? decls
      | _, _ => throw "expected object with exactly one of fields 'inline' or 'external'"
    | _ => throw "expected block code-data payload"

/-- Projection from environment-level `Data.CodeRef` into JSON-safe block payload hints. -/
def BlockCodeData.ofCodeRefHint (codeRef? : Option Data.CodeRef) : Option BlockCodeData :=
  match codeRef? with
  | some (.external decls) => some (.external decls)
  | _ => none

/-- Resolve inline precedence at render time by combining optional hint + inline payload. -/
def BlockCodeData.ofHintAndInline (hint? : Option BlockCodeData) (inline? : Option InlineCodeData)
    : Option BlockCodeData :=
  match inline? with
  | some code => some (.inline code)
  | Option.none => hint?

def BlockCodeData.inlineData? : BlockCodeData → Option InlineCodeData
  | .inline code => some code
  | _ => Option.none

def BlockCodeData.externalDecls : BlockCodeData → Array Data.ExternalRef
  | .external decls => decls
  | _ => #[]

structure BlockStatusMark where
  status : Data.ProvedStatus := .proved
  title : String
  symbolOverride? : Option String := none
deriving Repr, Inhabited

def BlockStatusMark.text (s : BlockStatusMark) : String :=
  match s.symbolOverride? with
  | some txt => txt
  | none =>
    match s.status with
    | .proved => "✓"
    | .missing => "✗"
    | .axiomLike => "⚠"
    | .containsSorry _ => "✗"

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

structure BlockData where
  kind : Data.InProgressKind := .proof
  /-- Optional code hint used for statement blocks (`.proof` always ignores this). -/
  codeData : Option BlockCodeData := none
  label : Data.Label
  parent : Option Data.Parent := none
  count : Nat
  numberingMode : NumberingMode := .sub
  /--
  Top-level rendered part prefix assigned during traversal (for example `3` or `A`).

  This is stored as `String` rather than `Manual.Numbering` because it is a
  render-facing cache: the upstream part numbering may be numeric or alphabetic,
  and all downstream consumers need here is the final display prefix that should
  appear in cross-page references and HTML labels.
  -/
  partPrefix : Option String := none
  /-- Document-order global index assigned during traversal. -/
  globalCount : Option Nat := none
  /-- Statement-side `{uses ...}` dependencies declared for this labeled block. -/
  statementDeps : Array Data.Label := #[]
  /-- Proof-side `{uses ...}` dependencies declared for this labeled block. -/
  proofDeps : Array Data.Label := #[]
  owner : Option Data.AuthorId := none
  ownerDisplayName : Option String := none
  ownerUrl : Option String := none
  ownerImageUrl : Option String := none
  tags : Array String := #[]
  effort : Option String := none
  priority : Option String := none
  prUrl : Option String := none
deriving Quote

instance : Lean.ToJson BlockData where
  toJson data := .arr #[
    Lean.ToJson.toJson data.kind,
    Lean.ToJson.toJson data.codeData,
    Lean.ToJson.toJson data.label,
    Lean.ToJson.toJson data.parent,
    Lean.ToJson.toJson data.count,
    Lean.ToJson.toJson data.numberingMode,
    Lean.ToJson.toJson data.partPrefix,
    Lean.ToJson.toJson data.globalCount,
    Lean.ToJson.toJson data.statementDeps,
    Lean.ToJson.toJson data.proofDeps,
    Lean.ToJson.toJson data.owner,
    Lean.ToJson.toJson data.ownerDisplayName,
    Lean.ToJson.toJson data.ownerUrl,
    Lean.ToJson.toJson data.ownerImageUrl,
    Lean.ToJson.toJson data.tags,
    Lean.ToJson.toJson data.effort,
    Lean.ToJson.toJson data.priority,
    Lean.ToJson.toJson data.prUrl
  ]

instance : Lean.FromJson BlockData where
  fromJson? v := do
    match v with
    | .arr arr =>
      let some kind := arr[0]? | throw "expected kind"
      let some codeData := arr[1]? | throw "expected code-data"
      let some label := arr[2]? | throw "expected label"
      let some parent := arr[3]? | throw "expected parent"
      let some count := arr[4]? | throw "expected count"
      let some numberingMode := arr[5]? | throw "expected numbering mode"
      let some partPrefix := arr[6]? | throw "expected part prefix"
      let some globalCount := arr[7]? | throw "expected global count"
      let some statementDeps := arr[8]? | throw "expected statement deps"
      let some proofDeps := arr[9]? | throw "expected proof deps"
      let some owner := arr[10]? | throw "expected owner"
      let some ownerDisplayName := arr[11]? | throw "expected owner display name"
      let some ownerUrl := arr[12]? | throw "expected owner URL"
      let some ownerImageUrl := arr[13]? | throw "expected owner image URL"
      let some tags := arr[14]? | throw "expected tags"
      let some effort := arr[15]? | throw "expected effort"
      let some priority := arr[16]? | throw "expected priority"
      let some prUrl := arr[17]? | throw "expected PR URL"
      return {
        kind := ← Lean.FromJson.fromJson? kind
        codeData := ← Lean.FromJson.fromJson? codeData
        label := ← Lean.FromJson.fromJson? label
        parent := ← Lean.FromJson.fromJson? parent
        count := ← Lean.FromJson.fromJson? count
        numberingMode := ← Lean.FromJson.fromJson? numberingMode
        partPrefix := ← Lean.FromJson.fromJson? partPrefix
        globalCount := ← Lean.FromJson.fromJson? globalCount
        statementDeps := ← Lean.FromJson.fromJson? statementDeps
        proofDeps := ← Lean.FromJson.fromJson? proofDeps
        owner := ← Lean.FromJson.fromJson? owner
        ownerDisplayName := ← Lean.FromJson.fromJson? ownerDisplayName
        ownerUrl := ← Lean.FromJson.fromJson? ownerUrl
        ownerImageUrl := ← Lean.FromJson.fromJson? ownerImageUrl
        tags := ← Lean.FromJson.fromJson? tags
        effort := ← Lean.FromJson.fromJson? effort
        priority := ← Lean.FromJson.fromJson? priority
        prUrl := ← Lean.FromJson.fromJson? prUrl
      }
    | _ =>
      return {
        kind := ← v.getObjValAs? Data.InProgressKind "kind"
        codeData := ← v.getObjValAs? (Option BlockCodeData) "codeData"
        label := ← v.getObjValAs? Data.Label "label"
        parent := ← v.getObjValAs? (Option Data.Parent) "parent"
        count := ← v.getObjValAs? Nat "count"
        numberingMode := ← v.getObjValAs? NumberingMode "numberingMode"
        partPrefix := ← v.getObjValAs? (Option String) "partPrefix"
        globalCount := ← v.getObjValAs? (Option Nat) "globalCount"
        statementDeps := ← v.getObjValAs? (Array Data.Label) "statementDeps"
        proofDeps := ← v.getObjValAs? (Array Data.Label) "proofDeps"
        owner := ← v.getObjValAs? (Option Data.AuthorId) "owner"
        ownerDisplayName := ← v.getObjValAs? (Option String) "ownerDisplayName"
        ownerUrl := ← v.getObjValAs? (Option String) "ownerUrl"
        ownerImageUrl := ← v.getObjValAs? (Option String) "ownerImageUrl"
        tags := ← v.getObjValAs? (Array String) "tags"
        effort := ← v.getObjValAs? (Option String) "effort"
        priority := ← v.getObjValAs? (Option String) "priority"
        prUrl := ← v.getObjValAs? (Option String) "prUrl"
      }

/--
Slim traversal-store payload for Blueprint node metadata.

Unlike `BlockData`, this intentionally excludes `codeData`. Code-specific
render/runtime payloads belong to dedicated traversal indexes rather than the
main semantic node index.
-/
structure StoredBlockData where
  kind : Data.InProgressKind := .proof
  label : Data.Label
  parent : Option Data.Parent := none
  count : Nat
  numberingMode : NumberingMode := .sub
  partPrefix : Option String := none
  globalCount : Option Nat := none
  statementDeps : Array Data.Label := #[]
  proofDeps : Array Data.Label := #[]
  owner : Option Data.AuthorId := none
  ownerDisplayName : Option String := none
  ownerUrl : Option String := none
  ownerImageUrl : Option String := none
  tags : Array String := #[]
  effort : Option String := none
  priority : Option String := none
  prUrl : Option String := none
deriving Quote

instance : Lean.ToJson StoredBlockData where
  toJson data := .arr #[
    toJson data.kind,
    toJson data.label,
    toJson data.parent,
    toJson data.count,
    toJson data.numberingMode,
    toJson data.partPrefix,
    toJson data.globalCount,
    toJson data.statementDeps,
    toJson data.proofDeps,
    toJson data.owner,
    toJson data.ownerDisplayName,
    toJson data.ownerUrl,
    toJson data.ownerImageUrl,
    toJson data.tags,
    toJson data.effort,
    toJson data.priority,
    toJson data.prUrl
  ]

instance : Lean.FromJson StoredBlockData where
  fromJson? v := do
    let arr ← v.getArr?
    let some kind := arr[0]? | throw "expected kind"
    let some label := arr[1]? | throw "expected label"
    let some parent := arr[2]? | throw "expected parent"
    let some count := arr[3]? | throw "expected count"
    let some numberingMode := arr[4]? | throw "expected numbering mode"
    let some partPrefix := arr[5]? | throw "expected part prefix"
    let some globalCount := arr[6]? | throw "expected global count"
    let some statementDeps := arr[7]? | throw "expected statement deps"
    let some proofDeps := arr[8]? | throw "expected proof deps"
    let some owner := arr[9]? | throw "expected owner"
    let some ownerDisplayName := arr[10]? | throw "expected owner display name"
    let some ownerUrl := arr[11]? | throw "expected owner URL"
    let some ownerImageUrl := arr[12]? | throw "expected owner image URL"
    let some tags := arr[13]? | throw "expected tags"
    let some effort := arr[14]? | throw "expected effort"
    let some priority := arr[15]? | throw "expected priority"
    let some prUrl := arr[16]? | throw "expected PR URL"
    return {
      kind := ← fromJson? kind
      label := ← fromJson? label
      parent := ← fromJson? parent
      count := ← fromJson? count
      numberingMode := ← fromJson? numberingMode
      partPrefix := ← fromJson? partPrefix
      globalCount := ← fromJson? globalCount
      statementDeps := ← fromJson? statementDeps
      proofDeps := ← fromJson? proofDeps
      owner := ← fromJson? owner
      ownerDisplayName := ← fromJson? ownerDisplayName
      ownerUrl := ← fromJson? ownerUrl
      ownerImageUrl := ← fromJson? ownerImageUrl
      tags := ← fromJson? tags
      effort := ← fromJson? effort
      priority := ← fromJson? priority
      prUrl := ← fromJson? prUrl
    }

def BlockData.toStoredData (data : BlockData) : StoredBlockData := {
  kind := data.kind
  label := data.label
  parent := data.parent
  count := data.count
  numberingMode := data.numberingMode
  partPrefix := data.partPrefix
  globalCount := data.globalCount
  statementDeps := data.statementDeps
  proofDeps := data.proofDeps
  owner := data.owner
  ownerDisplayName := data.ownerDisplayName
  ownerUrl := data.ownerUrl
  ownerImageUrl := data.ownerImageUrl
  tags := data.tags
  effort := data.effort
  priority := data.priority
  prUrl := data.prUrl
}

def StoredBlockData.toBlockData (data : StoredBlockData)
    (codeData : Option BlockCodeData := none) : BlockData := {
  kind := data.kind
  codeData
  label := data.label
  parent := data.parent
  count := data.count
  numberingMode := data.numberingMode
  partPrefix := data.partPrefix
  globalCount := data.globalCount
  statementDeps := data.statementDeps
  proofDeps := data.proofDeps
  owner := data.owner
  ownerDisplayName := data.ownerDisplayName
  ownerUrl := data.ownerUrl
  ownerImageUrl := data.ownerImageUrl
  tags := data.tags
  effort := data.effort
  priority := data.priority
  prUrl := data.prUrl
}

structure CodePanelHeader where
  caption : String
  number? : Option String := none
deriving Repr, Inhabited

def codePanelHeader (data : BlockData) (numberText : String) : CodePanelHeader :=
  match data.kind with
  | .proof => { caption := "Lean code for proof" }
  | .statement nodeKind =>
    {
      caption := s!"Lean code for {nodeKind}"
      number? := some numberText
    }

def fallbackCodePanelHeader : CodePanelHeader := {
  caption := "Lean code"
}

register_option verso.blueprint.foldProofs : Bool := {
  defValue := true
  descr := "Enable proof folding in VersoBlueprint Lean code blocks (hide text after `by` behind a toggle)"
}

def provedStatusHasSorry (status : Data.ProvedStatus) : Bool :=
  status.isIncomplete

def provedStatusLocationText (status : Data.ProvedStatus) : String :=
  status.sorryLocationText

def provedStatusContainsSorry (status : Data.ProvedStatus) : Bool :=
  status.containsExplicitSorry

def provedStatusSummaryText (status : Data.ProvedStatus) : String :=
  match status with
  | .missing => "missing declaration"
  | .axiomLike => "axiom-like (no body)"
  | .containsSorry _ => s!"sorry {provedStatusLocationText status}"
  | .proved => "unknown"

def externalDeclHasGap (decl : Data.ExternalRef) : Bool :=
  decl.present && provedStatusHasSorry decl.provedStatus

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
    (attrs : Array (String × String) := #[]) : Output.Html :=
  open Verso.Output.Html in
  {{
    <div class="bp_wrapper bp_code_panel_wrapper">
      <details class="bp_code_block bp_code_panel" {{attrs}}>
        <summary class="bp_heading lemma_thmheading" title={{summaryTitle}}>
          <span class="bp_caption lemma_thmcaption bp_code_summary_text">{{.text true header.caption}}</span>
          {{if let some number := header.number? then
              {{<span class="bp_label lemma_thmlabel bp_code_summary_label">{{.text true number}}</span>}}
            else
              .empty}}
          {{progressBar}}
        </summary>
        {{body}}
      </details>
    </div>
  }}

end Informal
