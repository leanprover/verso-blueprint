/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.ConceptMetadata
import VersoManual
import VersoBlueprint.ExternalDeclRender

/-! Provider/source/render primitives. This module installs no Blueprint state
and contains no node representation or completion evaluator. -/

namespace Informal.Data

open Lean
set_option doc.verso true

/-- Where an incompleteness marker appears in a declaration. -/
inductive SorryWhere where
  | statement
  | proof
  /-- A combined footprint proves a gap but cannot attribute it to an axis. -/
  | unknown
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

inductive SorryOrigin where
  | direct
  | dependency
  /-- The available evidence does not distinguish a local hole from a dependency. -/
  | unknown
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

/--
One observed axis/origin of incompleteness. Unknowns are evidence limits,
not assertions that either axis contains a direct hole.
{lit}`refs?` stores the number of local source references when known.
-/
structure SorryInfo where
  location : SorryWhere
  refs? : Option Nat := none
  origin : SorryOrigin := .direct
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

/-- Why absence of holes could not be verified from the checked environment. -/
inductive VerificationReason where
  | bodyUnavailable
  | declarationUnavailable
  | uncheckedExpression
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

/-- Missing verification information, distinct from an observed sorry term. -/
structure VerificationGap where
  location : SorryWhere := .unknown
  declaration : Name := .anonymous
  reason : VerificationReason := .declarationUnavailable
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

/-- Known holes and missing verification can coexist on independent axes. -/
structure IncompletenessInfo where
  knownSorry : Array SorryInfo := #[]
  unverified : Array VerificationGap := #[]
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

/--
Formalization/proof status for a declaration.
-/
inductive ProvedStatus where
  | proved
  /-- Declaration reference could not be resolved/present at snapshot time. -/
  | missing
  | axiomLike
  /-- A known gap or insufficient coverage to certify absence of gaps. -/
  | incomplete : IncompletenessInfo → ProvedStatus
deriving Repr, DecidableEq, ToJson, FromJson, Quote

instance : Inhabited ProvedStatus := ⟨.incomplete {}⟩

/-- Merge duplicate observations by axis *and* origin. Counts are lower bounds
from overlapping snapshots, so take their maximum instead of adding them. -/
def SorryInfo.mergeEvidence (items : Array SorryInfo) : Array SorryInfo :=
  items.foldl (init := #[]) fun acc item =>
    match acc.findIdx? (fun old => old.location == item.location && old.origin == item.origin) with
    | none => acc.push item
    | some index => acc.modify index fun old =>
      { old with refs? := max old.refs? item.refs? }

/-- Preserve unknown coverage before combining incomplete snapshots. -/
def IncompletenessInfo.withCoverageFallback (info : IncompletenessInfo) : IncompletenessInfo :=
  if info.knownSorry.isEmpty && info.unverified.isEmpty then { info with unverified := #[{}] }
  else info

/-- Conservative union. Verified snapshots are neutral; known evidence and
verification gaps survive merging, including an empty incomplete payload. -/
def ProvedStatus.mergeConservative : ProvedStatus → ProvedStatus → ProvedStatus
  | .missing, _ | _, .missing => .missing
  | .axiomLike, _ | _, .axiomLike => .axiomLike
  | .proved, b => b
  | a, .proved => a
  | .incomplete a, .incomplete b =>
    let a := a.withCoverageFallback
    let b := b.withCoverageFallback
    .incomplete {
      knownSorry := SorryInfo.mergeEvidence (a.knownSorry ++ b.knownSorry),
      unverified := (a.unverified ++ b.unverified).foldl (fun acc gap =>
        if acc.contains gap then acc else acc.push gap) #[] }

/-- Canonical declaration status union, independent of the selected display source. -/
def ProvedStatus.indexByName (observations : Array (Name × ProvedStatus)) : NameMap ProvedStatus :=
  observations.foldl (init := {}) fun statuses (name, status) =>
    let name := name.eraseMacroScopes
    statuses.insert name ((statuses.getD name .proved).mergeConservative status)

/-- Information about a code block, including Lean-level analysis -/
structure LiterateDef where
  name : Name
  commandStx : Syntax := .missing
  commandIndex : Nat := 0
  commandLines : Nat := 1
  provedStatus : ProvedStatus := .incomplete {}
  typeSorryRefs : Array Syntax := #[]
deriving Repr, Inhabited

structure LiterateThm extends LiterateDef where
  proofSorryRefs : Array Syntax := #[]
deriving Repr, Inhabited

def ConstantInfo.blueprintNodeKind? : ConstantInfo → Option NodeKind
  | .defnInfo _ => some .definition
  | .thmInfo _ => some .theorem
  | .axiomInfo _ => none
  | .opaqueInfo _ => none
  | .quotInfo _ => none
  | .inductInfo _ => some .definition
  | .ctorInfo _ => none
  | .recInfo _ => none

def ConstantInfo.blueprintKindText : ConstantInfo → String
  | .defnInfo _ => "definition"
  | .thmInfo _ => "theorem"
  | .axiomInfo _ => "axiom"
  | .opaqueInfo _ => "opaque"
  | .quotInfo _ => "quotient"
  | .inductInfo _ => "inductive"
  | .ctorInfo _ => "constructor"
  | .recInfo _ => "recursor"

structure Code where
  stx : Syntax
  definedDefs : Array LiterateDef := #[]
  definedTheorems : Array LiterateThm := #[]
deriving Repr, Inhabited

/-- External markup languages that can be attached to a Blueprint label. -/
inductive ExternalMarkupLanguage where
  | tex
  | markdown
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

def ExternalMarkupLanguage.displayName : ExternalMarkupLanguage → String
  | .tex => "TeX"
  | .markdown => "Markdown"

def ExternalMarkupLanguage.key : ExternalMarkupLanguage → String
  | .tex => "tex"
  | .markdown => "markdown"

instance : ToString ExternalMarkupLanguage where
  toString := ExternalMarkupLanguage.key

/-- Project-relative source location for imported external markup. -/
structure ExternalMarkupLocation where
  path : String
  range : Lean.Lsp.Range
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

/-- Key for external markup attached to a Blueprint label. -/
structure ExternalMarkupKey where
  language : ExternalMarkupLanguage
  slot : String
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

def ExternalMarkupKey.compare (a b : ExternalMarkupKey) : Ordering :=
  Ord.compare a.language.key b.language.key |>.then <| Ord.compare a.slot b.slot

instance : Ord ExternalMarkupKey where
  compare := ExternalMarkupKey.compare

/-- External markup payload associated with one language/slot key. -/
structure ExternalMarkupValue where
  raw : String
  location : Option ExternalMarkupLocation := none
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

/-- Manifest/display record for one external markup attachment. -/
structure ExternalMarkup where
  language : ExternalMarkupLanguage
  slot : String
  raw : String
  location : Option ExternalMarkupLocation := none
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

/-- Default slot for labeled external-markup witness blocks that omit `(slot := ...)`. -/
def defaultExternalMarkupSlot : String := "default"

/-- Ordered, unique external markup attachments keyed by language and slot. -/
structure ExternalMarkupSet where
  entries : Std.TreeMap ExternalMarkupKey ExternalMarkupValue := {}
deriving Repr, Inhabited

def ExternalMarkup.key (markup : ExternalMarkup) : ExternalMarkupKey := {
  language := markup.language
  slot := markup.slot
}

def ExternalMarkup.value (markup : ExternalMarkup) : ExternalMarkupValue := {
  raw := markup.raw
  location := markup.location
}

def ExternalMarkupSet.isEmpty (markup : ExternalMarkupSet) : Bool :=
  markup.entries.isEmpty

def ExternalMarkupSet.find? (markup : ExternalMarkupSet)
    (language : ExternalMarkupLanguage) (slot : String) : Option ExternalMarkupValue :=
  markup.entries.get? { language, slot }

def ExternalMarkupSet.contains (markup : ExternalMarkupSet) (key : ExternalMarkupKey) : Bool :=
  markup.entries.contains key

def ExternalMarkupSet.insert (markup : ExternalMarkupSet) (entry : ExternalMarkup) :
    ExternalMarkupSet :=
  { entries := markup.entries.insert entry.key entry.value }

def ExternalMarkupSet.toArray (markup : ExternalMarkupSet) : Array ExternalMarkup :=
  Id.run do
    let mut out := #[]
    for (key, value) in markup.entries do
      out := out.push {
        language := key.language
        slot := key.slot
        raw := value.raw
        location := value.location
      }
    out

instance : ToJson ExternalMarkupSet where
  toJson markup := toJson markup.toArray

instance : FromJson ExternalMarkupSet where
  fromJson? json := do
    let entries ← fromJson? (α := Array ExternalMarkup) json
    let mut markup : ExternalMarkupSet := {}
    for entry in entries do
      let key := entry.key
      if markup.contains key then
        throw s!"duplicate external markup entry for language '{key.language}' and slot '{key.slot}'"
      markup := markup.insert entry
    pure markup

/-- Traversal payload for all external markup associated with one Blueprint label. -/
structure ExternalMarkupData where
  label : Label
  markup : ExternalMarkupSet := {}
deriving Repr, Inhabited, ToJson, FromJson

inductive ExternalOrigin where
  | directiveLean
  | blueprintAttr
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

inductive ExternalDeclProvenance where
  | inWorkspace (moduleName : Name) (sourcePath : String)
  | outWorkspace (moduleName : Name) (sourcePath? : Option String := none)
  | unknown
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

def ExternalDeclProvenance.moduleName? : ExternalDeclProvenance → Option Name
  | .inWorkspace moduleName _ => some moduleName
  | .outWorkspace moduleName _ => some moduleName
  | .unknown => none

def ExternalDeclProvenance.sourcePath? : ExternalDeclProvenance → Option String
  | .inWorkspace _ sourcePath => some sourcePath
  | .outWorkspace _ sourcePath? => sourcePath?
  | .unknown => none

def ExternalDeclProvenance.label : ExternalDeclProvenance → String
  | .inWorkspace _ _ => "in workspace"
  | .outWorkspace _ _ => "out workspace"
  | .unknown => "unknown provenance"

inductive ExternalDeclLookupError where
  | notPresentAtRegistration
  | notFoundInEnvironment
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

def ExternalDeclLookupError.message : ExternalDeclLookupError → String
  | .notPresentAtRegistration => "name was not present during directive/code-block registration"
  | .notFoundInEnvironment => "name is not present in current environment"

deriving instance ToJson, FromJson for Except

instance [Quote ε] [Quote α] : Quote (Except ε α) where
  quote
    | .ok value => Syntax.mkApp (mkCIdent ``Except.ok) #[quote value]
    | .error error => Syntax.mkApp (mkCIdent ``Except.error) #[quote error]

abbrev ExternalDeclRender := Except Informal.ExternalDeclRenderError Informal.ExternalDeclRenderedHtml

instance : DecidableEq ExternalDeclRender
  | .ok a, .ok b =>
    if h : a = b then .isTrue (h ▸ rfl) else .isFalse (fun eq => h (Except.ok.inj eq))
  | .error a, .error b =>
    if h : a = b then .isTrue (h ▸ rfl) else .isFalse (fun eq => h (Except.error.inj eq))
  | .ok _, .error _ => .isFalse (by intro h; cases h)
  | .error _, .ok _ => .isFalse (by intro h; cases h)

/--
Reference to an external declaration mentioned by a blueprint node.
{lit}`written` preserves the user spelling, while {lit}`canonical` is scope-erased for
environment lookup and duplicate detection. Declaration names are Lean-owned;
Blueprint label policies must not rewrite them.
-/
structure ExternalRef where
  written : Name
  canonical : Name
  origin : ExternalOrigin := .directiveLean
  /--
  Whether this declaration was present in the Lean environment at the time the
  reference was registered from blueprint markup.
  -/
  present : Bool := true
  /--
  Snapshot of proof/completeness status at registration time.
  -/
  provedStatus : ProvedStatus := .incomplete {}
  /--
  Snapshot of declaration provenance metadata.
  -/
  provenance : ExternalDeclProvenance := .unknown
  /--
  Snapshot of declaration source ranges (if known at registration time).
  -/
  range? : Option Lean.DeclarationRange := none
  selectionRange? : Option Lean.DeclarationRange := none
  /--
  Snapshot of declaration kind and optional source link.
  -/
  kind : NodeKind := .definition
  sourceHref? : Option String := none
  /--
  Snapshot of the direct external rendering outcome.
  -/
  render : ExternalDeclRender := .error (.moduleUnavailable canonical)
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

def ExternalRef.ofName (name : Name) (origin : ExternalOrigin := .directiveLean) : ExternalRef :=
  { written := name, canonical := name.eraseMacroScopes, origin, kind := .definition }

structure RustInlineCode where
  raw : String
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

def pushUniqueNativeName (names : Array Name) (name : Name) : Array Name :=
  let name := name.eraseMacroScopes
  if names.contains name then names else names.push name

def Code.definedDeclNames (code : Code) : Array Name :=
  (code.definedDefs.map (·.name) ++ code.definedTheorems.map (·.name)).foldl
    pushUniqueNativeName #[]

structure InformalBody where
  stx : Syntax
  previewBlocks : Array (Verso.Doc.Block Verso.Genre.Manual) := #[]
  /--
  Manual block term syntax retained when the producing phase cannot evaluate it
  into typed preview blocks, as with a docstring on an imported Blueprint
  attribute.
  -/
  elabStx : Array Syntax := #[]
deriving Repr, Inhabited

def InformalBody.hasBody (data : InformalBody) : Bool :=
  !data.previewBlocks.isEmpty || !data.elabStx.isEmpty

/-- Stable canonical union; build an ephemeral index once for this incoming group. -/
def ExternalRef.mergeSnapshots (current incoming : Array ExternalRef) : Array ExternalRef := Id.run do
  let mut positions : NameMap Nat := {}
  let mut refs := #[]
  for ref in current ++ incoming do
    let ref := { ref with canonical := ref.canonical.eraseMacroScopes }
    match positions.get? ref.canonical with
    | some i =>
      let previous := refs[i]!
      let selected := if !previous.present && ref.present then ref else previous
      refs := refs.set! i { selected with
        provedStatus := ProvedStatus.mergeConservative previous.provedStatus ref.provedStatus }
    | none =>
      positions := positions.insert ref.canonical refs.size
      refs := refs.push ref
  return refs

end Informal.Data
