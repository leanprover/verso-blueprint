/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import VersoManual.Bibliography
import VersoBlueprint.Compat
import VersoBlueprint.Commands.Common
import VersoBlueprint.Data
import VersoBlueprint.Informal.Block.Model
import VersoBlueprint.Informal.Block.Store
import VersoBlueprint.Lib.ExtensionDecode
import VersoBlueprint.Lib.HoverRender
import VersoBlueprint.Resolve
import VersoBlueprint.TraversalIndex

open Lean Elab Command
open Verso Doc Elab
open Verso.Genre Manual
open Verso.ArgParse

namespace Informal.Cite

open Verso.Genre.Manual.Bibliography

def citeAssetBundle : Informal.Commands.BlueprintAssetBundle :=
  Informal.Commands.inlinePreviewAssetBundle

syntax (name := bib) "bib" ppSpace str : attr

private def parseNameOrSimple (s : String) : Name :=
  let s := s.trimAscii.toString
  let n := s.toName
  if n.isAnonymous then Name.mkSimple s else n

private def parseBibLabel (s : String) : Name :=
  parseNameOrSimple s

def normalizeLabel (label : String) : String :=
  (parseBibLabel label).toString

/--
Stable slug used in bibliography fragment URLs and citation preview keys.

This intentionally keeps the historical lowercase, hyphen-separated bibliography
anchor form instead of `Informal.HtmlId.key`. Use the `HtmlId` encoder for
opaque generated element ids; citation anchors are user-visible URL fragments.
-/
def citationAnchorId (label : String) : String :=
  let base := normalizeLabel label
  base.foldl (init := "") fun acc c =>
    if c.isAlphanum then
      acc.push c.toLower
    else
      acc.push '-'

initialize bibExt : PersistentEnvExtension (Name × Name) (Name × Name) (Lean.NameMap Name) ←
  registerPersistentEnvExtension {
    mkInitial := pure {}
    addImportedFn := fun es => do
      let out := es.foldl (init := ({} : Lean.NameMap Name)) fun acc entry =>
        entry.foldl (init := acc) fun acc (label, decl) =>
          acc.insert label decl
      pure out
    addEntryFn := fun st (label, decl) =>
      st.insert label decl
    exportEntriesFn := fun st =>
      st.toArray
  }

def lookupDecl? (env : Environment) (label : String) : Option Name :=
  let key := parseBibLabel label
  (bibExt.getState env).find? key

def allBibEntries (env : Environment) : List (String × Name) :=
  let entries : Array (String × Name) :=
    (bibExt.getState env).toArray.map fun (label, decl) => (label.toString, decl)
  let entries := Array.qsort entries (fun a b => a.1 < b.1)
  Array.toList entries

private def labelFromAttr (stx : Syntax) : CoreM Name := do
  match stx with
  | `(attr| bib $lbl:str) => pure (parseBibLabel lbl.getString)
  | _ => throwError "invalid syntax for '[bib]' attribute"

open Lean in
initialize
  registerBuiltinAttribute {
    name := `bib
    ref := by exact decl_name%
    applicationTime := .afterCompilation
    add := fun decl stx kind => do
      unless kind == AttributeKind.global do
        throwError "invalid attribute '[bib]', must be global"
      unless ((← getEnv).getModuleIdxFor? decl).isNone do
        throwError "invalid attribute '[bib]', declaration is in an imported module"
      let label ← labelFromAttr stx
      let decl := decl.eraseMacroScopes
      let prev? := (bibExt.getState (← getEnv)).find? label
      if let some prev := prev? then
        unless prev == decl do
          throwError "duplicate '[bib]' label '{label}': already assigned to '{prev}'"
      modifyEnv fun env =>
        bibExt.addEntry env (label, decl)
    descr := "Registers a Citable declaration with a bibliography label for Informal citation roles"
  }

inductive CitePartKind where
  | chapter
  | section
  | theorem
  | proposition
  | lemma
  | corollary
  | page
  | equation
  | figure
deriving Inhabited, Repr, BEq, FromJson, ToJson, Quote

def CitePartKind.parse? (s : String) : Option CitePartKind :=
  match s.trimAscii.toString.toLower with
  | "chapter" | "ch" => some .chapter
  | "section" | "sec" => some .section
  | "theorem" | "thm" => some .theorem
  | "proposition" | "prop" => some .proposition
  | "lemma" | "lem" => some .lemma
  | "corollary" | "cor" => some .corollary
  | "page" | "p" | "pp" => some .page
  | "equation" | "eq" => some .equation
  | "figure" | "fig" => some .figure
  | _ => none

def CitePartKind.text : CitePartKind → String
  | .chapter => "Chapter"
  | .section => "Section"
  | .theorem => "Theorem"
  | .proposition => "Proposition"
  | .lemma => "Lemma"
  | .corollary => "Corollary"
  | .page => "p."
  | .equation => "Equation"
  | .figure => "Figure"

structure CiteConfig where
  citations : List (Verso.ArgParse.WithSyntax String)
  kind : Option CitePartKind := none
  index : Option String := none

section
variable [Monad m] [MonadInfoTree m] [MonadLiftT CoreM m] [MonadEnv m] [MonadError m] [MonadFileMap m]

private def stringOrName : ValDesc m String := {
  description := "citation label (identifier or string)"
  signature := .String ∪ .Ident
  get := fun
    | .str s => pure s.getString
    | .name n => pure n.getId.toString
    | other => throwError "Expected citation label, got {toMessageData other}"
}

private def citePartKind : ValDesc m CitePartKind := {
  description := "citation sub-part kind (`lemma`, `section`, `theorem`, ...)"
  signature := .String ∪ .Ident
  get := fun
    | .name n =>
      let key := n.getId.toString
      match CitePartKind.parse? key with
      | some kind => pure kind
      | none => throwError "Unknown citation kind '{key}'"
    | .str s =>
      let key := s.getString
      match CitePartKind.parse? key with
      | some kind => pure kind
      | none => throwError "Unknown citation kind '{key}'"
    | other => throwError "Expected citation kind, got {toMessageData other}"
}

private def citePartIndex : ValDesc m String := {
  description := "citation sub-part index (`8`, `4.2`, ...)"
  signature := .Num ∪ .String ∪ .Ident
  get := fun
    | .num n => pure (toString n.getNat)
    | .str s => pure s.getString
    | .name n => pure n.getId.toString
}

partial def CiteConfig.parse : ArgParse m CiteConfig :=
  CiteConfig.mk
    <$> many1 (.positional `citation (.withSyntax stringOrName))
    <*> .named `kind citePartKind true
    <*> .named `index citePartIndex true
where
  many1 p := (· :: ·) <$> p <*> .many p

instance : FromArgs CiteConfig m where
  fromArgs := CiteConfig.parse

end

private def fallbackDecl? (env : Environment) (label : String) : Option Name :=
  let n := parseBibLabel label
  if env.find? n |>.isSome then some n else none

def resolveCitation (stx : Syntax) (label : String) : DocElabM (String × Name) := do
  let env ← getEnv
  if let some decl := lookupDecl? env label then
    return (normalizeLabel label, decl)
  if let some decl := fallbackDecl? env label then
    return (normalizeLabel label, decl)
  throwErrorAt stx "Unknown bibliography label '{label}'"

inductive CitationStyle where
  | textual
  | parenthetical
  | here
deriving Inhabited, Repr, BEq, FromJson, ToJson, Quote

structure CiteItem where
  label : String
  citation : Citable
deriving FromJson, ToJson

/--
Serialized payload for one bibliography citation inline.

This keeps the citation targets plus any locator information (`kind` / `index`)
so traversal can later register reverse-usage metadata for the bibliography panel.
-/
structure CiteInlineData where
  citations : List CiteItem := []
  style : CitationStyle := .parenthetical
  kind : Option CitePartKind := none
  index : Option String := none
deriving Inhabited, FromJson, ToJson

/--
Manifest payload for one citation hover preview.

The preview is keyed by the rendered citation form and locator, not by the
inline occurrence that requested it, so repeated citations can share one
manifest entry without page-local template ownership.
-/
structure CitationPreviewData where
  item : CiteItem
  style : CitationStyle := .parenthetical
  kind : Option CitePartKind := none
  index : Option String := none
deriving FromJson, ToJson

/--
One numbered document location extracted from the current part-header stack.

`number` is already normalized to display text because the underlying Manual
numbering can be numeric or alphabetic (for example appendices).
-/
structure HeaderLocation where
  title : String
  number : Option String := none
deriving Inhabited, FromJson, ToJson

/--
Reference to the informal block surrounding a bibliography citation use site.

We store the labeled block identity plus its local counter so later HTML rendering
can re-resolve the final displayed theorem/definition/proof number using the
current numbering policy and the traversal state's per-label metadata.
-/
structure TheoremContext where
  label : Informal.Data.Label
  kind : Informal.Data.InProgressKind
  localCount : Nat
deriving Inhabited, FromJson, ToJson

/--
Structured location summary for a bibliography citation use.

This is intentionally stored as data rather than preformatted text so the final
"Cited from" panel can render numbering using the same block-numbering policy as
the main blueprint HTML.
-/
structure CitationSummary where
  chapter : Option HeaderLocation := none
  sectionLoc : Option HeaderLocation := none
  theoremCtx : Option TheoremContext := none
  documentName : Option String := none
deriving Inhabited, FromJson, ToJson

/--
One backlink from a bibliography entry to a concrete citation use site in the document.

`summary` captures the location context, while `kind` / `index` preserve any explicit
locator that the citation inline itself requested.
-/
structure CitationUse where
  href : String
  summary : CitationSummary := {}
  kind : Option CitePartKind := none
  index : Option String := none
deriving Inhabited, FromJson, ToJson

/--
Accumulated citation-use backlinks for one bibliography label.

The bibliography block reads this payload to populate the per-entry "Cited from"
list and deduplicates entries with `insertUnique`.
-/
structure CitationUsageData where
  uses : List CitationUse := []
deriving Inhabited, FromJson, ToJson

private def CitationUsageData.insertUnique (d : CitationUsageData) (u : CitationUse) : CitationUsageData :=
  if d.uses.any (fun e =>
      e.href == u.href
      && ToJson.toJson e.summary == ToJson.toJson u.summary
      && e.kind == u.kind
      && e.index == u.index) then
    d
  else
    { d with uses := d.uses ++ [u] }

private def updateCitationUsageData (u : CitationUse) (j : Json) : Json :=
  let d : CitationUsageData :=
    match fromJson? (α := CitationUsageData) j with
    | .ok data => data
    | .error _ => {}
  toJson (d.insertUnique u)

private def headerTitle (h : PartHeader) : String :=
  (h.metadata.bind (·.shortContextTitle) <|> h.metadata.bind (·.shortTitle)).getD h.titleString

private def headerLocations (headers : Array PartHeader) : Array HeaderLocation := Id.run do
  let mut out : Array HeaderLocation := #[]
  let mut nums : Array String := #[]
  for h in headers[1:] do
    if let some n := h.metadata.bind (·.assignedNumber) then
      nums := nums.push (toString n)
    let number? :=
      if nums.isEmpty then
        none
      else
        some (String.intercalate "." nums.toList)
    out := out.push { title := headerTitle h, number := number? }
  out

private def chapterText (h : HeaderLocation) : String :=
  match h.number with
  | some n => s!"Chapter {n}: {h.title}"
  | none => s!"Chapter: {h.title}"

private def sectionText (h : HeaderLocation) : String :=
  match h.number with
  | some n => s!"Section {n}: {h.title}"
  | none => s!"Section: {h.title}"

private def theoremContext? (ctxt : TraverseContext) : Option TheoremContext :=
  let rec go (ctx : List BlockContext) : Option TheoremContext :=
    match ctx with
    | [] => none
    | .other b :: rest =>
      if b.name.toString == "Informal.Block.informal" then
        match fromJson? (α := Informal.BlockData) b.data with
        | .ok d => some { label := d.label, kind := d.kind, localCount := d.count }
        | .error _ => go rest
      else
        go rest
    | _ :: rest => go rest
  go ctxt.blockContext.toList.reverse

/-- Render a stored citation-summary payload using the current traversal state. -/
def CitationSummary.text (summary : CitationSummary) (state : TraverseState) : String := Id.run do
  let mut parts : Array String := #[]
  if let some chapter := summary.chapter then
    parts := parts.push (chapterText chapter)
  if let some sectionLoc := summary.sectionLoc then
    parts := parts.push (sectionText sectionLoc)
  if let some theoremCtx := summary.theoremCtx then
    let block : Informal.BlockData := {
      label := theoremCtx.label
      kind := theoremCtx.kind
      count := theoremCtx.localCount
    }
    parts := parts.push (block.displayTitle state)
  if parts.isEmpty then
    summary.documentName.getD "Document root"
  else
    String.intercalate ", " parts.toList

private def usageSummary (ctxt : TraverseContext) : CitationSummary := Id.run do
  let hs := headerLocations ctxt.headers
  {
    chapter := hs[0]?
    sectionLoc := if hs.size > 1 then hs.back? else none
    theoremCtx := theoremContext? ctxt
    documentName := ctxt.path.back?
  }

private partial def inlineToPlain : Doc.Inline Manual → String
  | .text s | .code s | .math _ s => s
  | .bold xs | .emph xs | .concat xs | .other _ xs | .link xs _ =>
    xs.toList.foldl (init := "") fun acc x => acc ++ inlineToPlain x
  | .linebreak .. => " "
  | .footnote _ xs => xs.toList.foldl (init := "") fun acc x => acc ++ inlineToPlain x
  | .image alt _ => alt

private def authorText (c : Citable) : String :=
  let last (x : Doc.Inline Manual) := inlineToPlain (Bibliography.lastName x)
  match c.authors.toList with
  | [] => "?"
  | [a] => last a
  | [a, b] => s!"{last a} and {last b}"
  | a :: _ => s!"{last a} et al."

private def joinHtml (sep : Verso.Output.Html) (xs : List Verso.Output.Html) : Verso.Output.Html :=
  match xs with
  | [] => .empty
  | x :: rest => rest.foldl (init := x) fun acc y => acc ++ sep ++ y

def normalizedLocatorIndex (index : Option String) : Option String :=
  match index.map (·.trimAscii.toString) with
  | some i =>
    if i.isEmpty then Option.none else some i
  | Option.none => Option.none

def locatorText (kind : Option CitePartKind) (index : Option String) : Option String :=
  let index := normalizedLocatorIndex index
  match kind, index with
  | Option.none, Option.none => Option.none
  | some k, Option.none => some k.text
  | Option.none, some i => some i
  | some k, some i =>
    some s!"{k.text} {i}"

private def pieceText (style : CitationStyle) (c : Citable) : String :=
  let who := authorText c
  let year := c.year
  match style with
  | .textual => s!"{who} ({year})"
  | .parenthetical | .here => s!"{who}, {year}"

def citationPreviewKey (item : CiteItem) (style : CitationStyle)
    (kind : Option CitePartKind) (index : Option String) : String :=
  let styleKey :=
    match style with
    | .textual => "textual"
    | .parenthetical => "parenthetical"
    | .here => "here"
  let kindKey := kind.map (fun k => Informal.HoverRender.previewKey k.text) |>.getD "none"
  let indexKey := (normalizedLocatorIndex index).map Informal.HoverRender.previewKey |>.getD "none"
  s!"bp-cite-{citationAnchorId item.label}-{styleKey}-{kindKey}-{indexKey}"

def CitationPreviewData.key (data : CitationPreviewData) : String :=
  citationPreviewKey data.item data.style data.kind data.index

def citationPreviewTitle (item : CiteItem) : String :=
  s!"Bibliography: {item.label}"

def citationPreviewBody (entryHtml : Verso.Output.Html)
    (kind : Option CitePartKind) (index : Option String) :
    Verso.Output.Html :=
  open Verso.Output.Html in
  let locator? := locatorText kind index
  {{
    <div class="bp_bibliography_hover">
      <div class="bp_bibliography_hover_entry">
        {{entryHtml}}
      </div>
      {{match locator? with
        | some loc =>
          {{<div class="bp_bibliography_hover_meta">
              <span class="bp_bibliography_hover_meta_label">"Locator"</span>
              <span class="bp_bibliography_hover_meta_value">{{.text true loc}}</span>
            </div>}}
        | Option.none => .empty}}
    </div>
  }}

open Verso Doc Elab Genre Manual in
inline_extension Inline.bpCite (citations : List CiteItem) (style : CitationStyle := .parenthetical)
    (kind : Option CitePartKind := none) (index : Option String := none) where
  data := toJson ({ citations, style, kind, index } : CiteInlineData)
  traverse id data _contents := do
    let some cfg ← Informal.ExtensionDecode.decode? (α := CiteInlineData) data
        (fun _ => "Malformed data in Inline.bpCite.traverse")
      | return none
    let ctxt ← read
    let path := ctxt.path
    let tagBase :=
      match cfg.citations with
      | [] => "--bp-cite"
      | first :: _ => s!"--bp-cite-{citationAnchorId first.label}"
    let _ ← Verso.Genre.Manual.externalTag id path tagBase
    let href? := (← get).externalTags[id]? |>.map (·.relativeLink)
    let summary := usageSummary ctxt
    let locatorIndex := normalizedLocatorIndex cfg.index
    for item in cfg.citations do
      let previewData : CitationPreviewData := {
        item
        style := cfg.style
        kind := cfg.kind
        index := locatorIndex
      }
      let previewKey := previewData.key
      modify fun st =>
        let st := Informal.TraversalIndex.CitationPreviews.saveData st previewKey (toJson previewData)
        let st := Informal.TraversalIndex.CitationUsages.saveId st item.label id
        match href? with
        | some href =>
          Informal.TraversalIndex.CitationUsages.modifyData
            st
            item.label
            (updateCitationUsageData {
              href,
              summary,
              kind := cfg.kind,
              index := locatorIndex
            })
        | Option.none => st
    pure none
  extraCss := citeAssetBundle.css
  extraJs := citeAssetBundle.js
  toTeX :=
    open Verso.Output.TeX in
    some <| fun go _id data content => do
      let some cfg ← Informal.ExtensionDecode.decode? (α := CiteInlineData) data
          (fun _ => "Malformed data in Inline.bpCite.toTeX")
        | pure .empty
      let pieces := cfg.citations.map (fun item => pieceText cfg.style item.citation)
      let body := String.intercalate "; " pieces
      let loc? := locatorText cfg.kind cfg.index
      let textNote? ←
        if content.isEmpty then
          pure (Option.none : Option _)
        else
          some <$> content.mapM go
      let txt :=
        match cfg.style with
        | .parenthetical =>
          let core := match loc? with
            | Option.none => body
            | some loc => s!"{body}, {loc}"
          match textNote? with
          | Option.none => .raw s!"({core})"
          | some textNote => .raw s!"({core}, " ++ textNote ++ .raw ")"
        | .textual | .here =>
          let core := match loc? with
            | Option.none => body
            | some loc => s!"{body}, {loc}"
          match textNote? with
          | Option.none => .raw core
          | some textNote => .raw core ++ .raw ", " ++ textNote
      pure txt
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun goI id data content => do
      let some cfg ← Informal.ExtensionDecode.decode? (α := CiteInlineData) data
          (fun _ => "Malformed data in Inline.bpCite.toHtml")
        | pure .empty
      let st ← HtmlT.state
      let inPreviewRender ← Informal.HoverRender.inInlinePreviewRender
      let citeAnchorId? := st.externalTags[id]? |>.map (·.htmlId.toString)
      let wrapTarget (h : Output.Html) : Output.Html :=
        match citeAnchorId? with
        | some anchorId => {{<span id={{anchorId}}>{{h}}</span>}}
        | Option.none => h
      let mkLink (item : CiteItem) := do
        let base? :=
          match Resolve.resolveDomainHref? st Verso.Genre.Manual.sectionDomain "Contents--Blueprint-Bibliography" with
          | some href => some href
          | Option.none =>
            Informal.TraversalIndex.Bibliography.href? st item.label
        let href? := base?.map (fun href =>
          let cleanBase :=
            match href.splitOn "#" with
            | [] => href
            | first :: _ => first
          s!"{cleanBase}#bp-bib-{citationAnchorId item.label}")
        let txt := pieceText cfg.style item.citation
        let linkNode : Output.Html :=
          match href? with
          | some href => {{<a href={{href}}>{{.text true txt}}</a>}}
          | Option.none => {{<span>{{.text true txt}}</span>}}
        if inPreviewRender then
          pure linkNode
        else
          let previewKey := citationPreviewKey item cfg.style cfg.kind cfg.index
          let previewTarget := Informal.HoverRender.InlinePreviewTarget.manifestBacked
            previewKey (citationPreviewTitle item)
          pure <| Informal.HoverRender.inlinePreviewTargetNode linkNode previewTarget
      let links ← cfg.citations.mapM mkLink
      let body := joinHtml {{<span>"; "</span>}} links
      let locatorHtml? := (locatorText cfg.kind cfg.index).map (fun loc => {{<span>{{.text true loc}}</span>}})
      let htmlNote? : Option Html ←
        if content.isEmpty then
          pure Option.none
        else
          some <$> content.mapM goI
      match cfg.style with
      | .parenthetical =>
        let core :=
          match locatorHtml? with
          | Option.none => body
          | some loc => {{<span>{{body}} ", " {{loc}}</span>}}
        match htmlNote? with
        | Option.none => pure <| wrapTarget {{<span>"(" {{core}} ")"</span>}}
        | some htmlNote => pure <| wrapTarget {{<span>"(" {{core}} ", " {{htmlNote}} ")"</span>}}
      | .textual | .here =>
        let core :=
          match locatorHtml? with
          | Option.none => body
          | some loc => {{<span>{{body}} ", " {{loc}}</span>}}
        match htmlNote? with
        | Option.none => pure <| wrapTarget core
        | some htmlNote => pure <| wrapTarget {{<span>{{core}} ", " {{htmlNote}}</span>}}

end Informal.Cite

namespace Informal.TraversalIndex.CitationPreviews

/-- Decode every citation-preview store entry, preserving per-entry decode errors. -/
def entries (state : Verso.Genre.Manual.TraverseState) :
    Array (Except Informal.TraversalIndex.DecodeError
      (Informal.TraversalIndex.StoredEntry Informal.Cite.CitationPreviewData)) :=
  Informal.TraversalIndex.decodeStoreEntries state domainName

end Informal.TraversalIndex.CitationPreviews

namespace Informal.TraversalIndex.CitationUsages

/-- Decode citation-use backlinks for one bibliography label. -/
def data? (state : Verso.Genre.Manual.TraverseState) (label : String) :
    Option Informal.Cite.CitationUsageData := do
  let obj ← object? state label
  match Informal.TraversalIndex.decodeObjectData obj with
  | .error _ => none
  | .ok stored => some stored.data

end Informal.TraversalIndex.CitationUsages

namespace Informal

open Verso.Genre.Manual.Bibliography

private def mkItems (config : Cite.CiteConfig) : DocElabM (Array (TSyntax `term)) := do
  let citations ← config.citations.mapM (fun c => Cite.resolveCitation c.syntax c.val)
  citations.toArray.mapM fun (label, decl) =>
    `(Informal.Cite.CiteItem.mk $(quote label) $(mkIdent decl))

private def citeRoleImpl (style : Cite.CitationStyle) (config : Cite.CiteConfig)
    (extra : Array (TSyntax `inline)) : DocElabM Term := do
  let items ← mkItems config
  let inlines ← extra.mapM elabInline
  ``(Verso.Doc.Inline.other
    (Informal.Cite.Inline.bpCite
      ([$items,*] : List Informal.Cite.CiteItem)
      $(quote style)
      $(quote config.kind)
      $(quote config.index))
    #[$inlines,*])

@[role]
def citep : RoleExpanderOf Cite.CiteConfig
  | config, extra => citeRoleImpl .parenthetical config extra

@[role]
def citet : RoleExpanderOf Cite.CiteConfig
  | config, extra => citeRoleImpl .textual config extra

@[role]
def citehere : RoleExpanderOf Cite.CiteConfig
  | config, extra => citeRoleImpl .here config extra

end Informal
