/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Lean
public import VersoManual.Bibliography
public import VersoBlueprint.Data
public import VersoBlueprint.Lib.HoverRender

public section

namespace Informal.Cite

open Lean
open Verso.Genre.Manual.Bibliography

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
  | some k, some i => some s!"{k.text} {i}"

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

end Informal.Cite
