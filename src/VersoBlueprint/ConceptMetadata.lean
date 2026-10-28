/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Lean.Data.Json
import Lean.Data.Lsp
import Verso.Instances.Deriving

namespace Informal.Data

open Lean

/-- Structural ordering; display spelling is not an identity encoding for names. -/
instance : Ord Name := ⟨Name.cmp⟩

deriving instance Lean.ToJson for Lean.DeclarationRange
deriving instance Lean.FromJson for Lean.DeclarationRange

open Syntax in
instance : Lean.Quote Lean.Position where
  quote p := mkCApp ``Lean.Position.mk #[quote p.line, quote p.column]

deriving instance DecidableEq for Lean.Lsp.Position
deriving instance DecidableEq for Lean.Lsp.Range

open Syntax in
instance : Lean.Quote Lean.Lsp.Position where
  quote p := mkCApp ``Lean.Lsp.Position.mk #[quote p.line, quote p.character]

open Syntax in
instance : Lean.Quote Lean.Lsp.Range where
  quote r := mkCApp ``Lean.Lsp.Range.mk #[quote r.start, quote r.«end»]

open Syntax in
instance : Lean.Quote Lean.DeclarationRange where
  quote r := mkCApp ``Lean.DeclarationRange.mk
    #[quote r.pos, quote r.charUtf16, quote r.endPos, quote r.endCharUtf16]

set_option doc.verso true
-- set_option pp.rawOnError true

-- informal object labels are names for now, but that could change
def Label := Name
deriving Ord, Repr, Inhabited, DecidableEq, ToString, ToMessageData, ToJson, FromJson, Quote

/-- Readable public spelling shared by manifest queries and capture validation.
String-authored labels retain their original punctuation rather than Lean quotes. -/
def Label.publicString : Name → String
  | .str .anonymous s => s
  | name => name.toString

/-- Append a Blueprint label only when it is not already present. -/
def Label.pushUnique (labels : Array Label) (label : Label) : Array Label :=
  if labels.contains label then labels else labels.push label

def LabelMap A := NameMap A

instance [Repr A] : Repr (LabelMap A) := inferInstanceAs <| Repr (NameMap A)

abbrev Parent := Label

abbrev AuthorId := Label

/-- Source location attached to a semantic manifest entry. -/
structure SourceLocation where
  /-- Source path for this entry. -/
  path : String
  /-- Source range, using LSP zero-based UTF-16 coordinates. -/
  range : Lean.Lsp.Range
  /-- Optional browser-openable source URL, such as a repository link. -/
  href : Option String := none
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

namespace SourceLocation

def ofSyntax? {m}
    [Monad m] [MonadFileMap m] [MonadLog m]
    (stx : Syntax) : m (Option SourceLocation) := do
  let some range := stx.getRange?
    | return none
  let fileName ← getFileName
  if fileName.isEmpty || fileName.startsWith "<" then
    return none
  let fileMap ← getFileMap
  return some {
    path := fileName
    range := fileMap.utf8RangeToLspRange range
  }

end SourceLocation

/--
Explicit source-location lookup result.

Manifest entries always carry a result so missing source information is visible
to clients instead of being silently absent.
-/
structure SourceLocationResult where
  /-- Whether source location lookup succeeded. -/
  ok : Bool
  /-- Concrete source location when {lit}`ok` is true. -/
  location : Option SourceLocation := none
  /-- Human-readable reason when {lit}`ok` is false. -/
  error : Option String := none
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

namespace SourceLocationResult

def found (location : SourceLocation) : SourceLocationResult :=
  { ok := true, location := some location, error := none }

def unavailable (message : String) : SourceLocationResult :=
  { ok := false, location := none, error := some message }

end SourceLocationResult

/-- Where a declared dependency edge came from. -/
inductive UseOrigin where
  /-- The edge was written explicitly by a Blueprint author. -/
  | manual
  /-- The edge was inserted by tooling or another automatic process. -/
  | automatic
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

/-- Parse the documented dependency-origin strings accepted by Blueprint syntax. -/
def UseOrigin.parse? (raw : String) : Option UseOrigin :=
  match raw.trimAscii.toString.toLower with
  | "manual" => some .manual
  | "automatic" => some .automatic
  | _ => none

instance : ToString UseOrigin where
  toString
    | .manual => "manual"
    | .automatic => "automatic"

/-- The semantic role of a declared dependency edge. -/
inductive UseIntent where
  /-- An ordinary dependency edge. This is the default intent. -/
  | regular
  /-- A supporting edge that is useful but not part of the main logical path. -/
  | auxiliary
  /-- A dependency on a technical lemma or implementation detail. -/
  | technical
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

/-- Parse the documented dependency-intent strings accepted by Blueprint syntax. -/
def UseIntent.parse? (raw : String) : Option UseIntent :=
  match raw.trimAscii.toString.toLower with
  | "regular" => some .regular
  | "auxiliary" => some .auxiliary
  | "technical" => some .technical
  | _ => none

instance : ToString UseIntent where
  toString
    | .regular => "regular"
    | .auxiliary => "auxiliary"
    | .technical => "technical"

/--
Structured metadata for one declared dependency edge between informal nodes.

{lit}`origin` records whether the edge was user-authored or introduced by automation.
{lit}`intent` classifies regular, auxiliary, and technical dependency edges.
-/
structure UseRef where
  /-- Target informal node label. -/
  label : Label
  /-- Whether the edge was user-authored or introduced by automation. -/
  origin : UseOrigin := .manual
  /-- Semantic classification for this dependency edge. -/
  intent : UseIntent := .regular
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

def UseRef.labels (uses : Array UseRef) : Array Label :=
  uses.map (·.label)

/--
Merge duplicate dependency refs for the same label.

An explicit manual edge is preferred over an inferred automatic duplicate.
Otherwise, the existing ref is kept so order and earlier metadata remain stable.
-/
def UseRef.mergeSameLabel (current incoming : UseRef) : UseRef :=
  match current.origin, incoming.origin with
  | .automatic, .manual => incoming
  | _, _ => current

def UseRef.pushMergeByLabel (uses : Array UseRef) (useRef : UseRef) : Array UseRef :=
  if uses.any (·.label == useRef.label) then
    uses.map fun current =>
      if current.label == useRef.label then
        current.mergeSameLabel useRef
      else
        current
  else
    uses.push useRef

def UseRef.mergeByLabel (current incoming : Array UseRef) : Array UseRef :=
  incoming.foldl UseRef.pushMergeByLabel current

structure AuthorInfo where
  displayName : String
  url : Option String := none
  imageUrl : Option String := none
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

inductive NodeKind where
  | definition
  | proposition
  | lemma
  | theorem
  | corollary
deriving Ord, Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

instance : ToString NodeKind where
  toString
    | .definition => "Definition"
    | .proposition => "Proposition"
    | .lemma => "Lemma"
    | .theorem => "Theorem"
    | .corollary => "Corollary"

def NodeKind.isTheoremLike : NodeKind → Bool
  | .proposition | .lemma | .theorem | .corollary => true
  | .definition => false

inductive InProgressKind where
  | statement (kind : NodeKind)
  | proof
deriving Inhabited, Repr, ToJson, FromJson, Quote

/-- Shared concept metadata, independent of source language and validation.
Both accepted registration metadata and the canonical model use this record. -/
structure NodeMetadata where
  kind : NodeKind := .lemma
  /-- An author-supplied kind takes precedence over classification inferred from Lean code. -/
  kindIsExplicit : Bool := false
  count : Nat := 0
  parent : Option Parent := none -- Optional parent group for summaries/graphs
  priority : Option String := none -- Optional author-provided triage hint
  owner : Option AuthorId := none
  tags : Array String := #[]
  effort : Option String := none
  prUrl : Option String := none
  issueUrl : Option String := none
deriving Ord, Repr, Inhabited, BEq, DecidableEq, ToJson, FromJson

/-- Concept metadata authored in one registration. Source and dependency inputs
belong to explicit realization/facet destinations in that registration. -/
structure NodeContribution where
  kind : Option NodeKind := none
  count : Nat := 0
  parent : Option Parent := none
  owner : Option AuthorId := none
  tags : Array String := #[]
  effort : Option String := none
  prUrl : Option String := none
  issueUrl : Option String := none
  deriving Repr, Inhabited

end Informal.Data
