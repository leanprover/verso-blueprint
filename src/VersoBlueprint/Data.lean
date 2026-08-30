/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Lean
public import Lean.Data.Json
public import Lean.Data.Lsp
public import SubVerso.Examples.Env
public import VersoManual
public import VersoBlueprint.ExternalDeclRender.Data
meta import Verso.Instances.Deriving
meta import VersoBlueprint.ExternalDeclRender.Data

public section

namespace Informal.Data

open Lean

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
@[expose] def Label := Name
deriving Repr, Inhabited, DecidableEq, ToString, ToMessageData, ToJson, FromJson, Quote

/-- Append a Blueprint label only when it is not already present. -/
def Label.pushUnique (labels : Array Label) (label : Label) : Array Label :=
  if labels.contains label then labels else labels.push label

@[expose] def LabelMap A := NameMap A

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
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

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

/-- Where an incompleteness marker appears in a declaration. -/
inductive SorryWhere where
  | statement
  | proof
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

/--
Structured metadata for one incomplete location in a declaration.
{lit}`refs?` stores the number of references when known.
-/
structure SorryInfo where
  location : SorryWhere
  refs? : Option Nat := none
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

/--
Formalization/proof status for a declaration.
-/
inductive ProvedStatus where
  | proved
  /-- Declaration reference could not be resolved/present at snapshot time. -/
  | missing
  | axiomLike
  | containsSorry (info : Array SorryInfo)
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

/-- Information about a code block, including Lean-level analysis -/
structure LiterateDef where
  name : Name
  commandStx : Syntax := .missing
  commandIndex : Nat := 0
  commandLines : Nat := 1
  provedStatus : ProvedStatus := .proved
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
environment lookup and duplicate detection.
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
  provedStatus : ProvedStatus := .proved
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

inductive CodeRef where
  /-
  Blueprint code references can currently come from two sources:
  1. An inline Lean block processed by Verso/Lean integration (`.literate`).
  2. A regular Lean declaration tagged with `@[blueprint]` or
     `@[blueprint "..."]` (`.external`, origin `.blueprintAttr`).
     A `(lean := "...")` directive reference to Lean code we do not directly control
     also lands in `.external` (origin `.directiveLean`).

  Name ownership model:
  - informal object labels are blueprint-owned metadata;
  - `(lean := "...")` declaration names are Lean-owned and must not be rewritten by blueprint label policies.

  External-definition metadata should be attached to `ExternalRef` or a sibling
  external-declaration record. The `.external` names themselves remain Lean
  declaration names, not Blueprint labels.
  -/
  | external (decls : Array ExternalRef)
  | literate (code : Code)
deriving Repr, Inhabited

private def pushNameUnique (names : Array Name) (name : Name) : Array Name :=
  let name := name.eraseMacroScopes
  if names.contains name then names else names.push name

def Code.definedDeclNames (code : Code) : Array Name :=
  (code.definedDefs.map (·.name) ++ code.definedTheorems.map (·.name)).foldl
    pushNameUnique #[]

def CodeRef.leanDecls : CodeRef → Array Name
  | .external refs =>
    refs.foldl (init := #[]) fun acc ref =>
      if ref.present then
        pushNameUnique acc ref.canonical
      else
        acc
  | .literate code => code.definedDeclNames

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

/-- An assembled body and the declarations needed to validate its dependencies. -/
structure InformalData extends InformalBody where
  /-- One declaration per label and authority; manual precedence never erases validation evidence. -/
  useDeclarations : Array UseRef := #[]
deriving Repr, Inhabited

def InformalData.hasBody (data : InformalData) : Bool := data.toInformalBody.hasBody

/-- Effective dependency edges, with manual metadata taking precedence. -/
def InformalData.deps (data : InformalData) : Array UseRef :=
  UseRef.mergeByLabel #[] data.useDeclarations

def InformalData.dependencyLabels (data : InformalData) : Array Label :=
  data.deps.map (·.label)

structure Node where
  kind : NodeKind := .lemma
  /-- An author-supplied kind takes precedence over classification inferred from Lean code. -/
  kindIsExplicit : Bool := false
  count : Nat := 0
  statement : Option InformalData := none -- Informal Object statement
  proof : Option InformalData := none -- Informal Object proof
  /-- External associations, unique by canonical declaration in registration order. -/
  externalRefs : Array ExternalRef := #[]
  /-- Whether accepted selected evidence includes a Blueprint-attribute association.
  This capability is independent of the snapshot retained for each declaration. -/
  blueprintAttributeAttachments : Bool := false
  /-- Every associated literate block, in registration order. -/
  literateCodes : Array Code := #[]
  rustCode : Option RustInlineCode := none -- Informal object associated Rust code
  externalMarkup : ExternalMarkupSet := {} -- Raw external markup keyed by language and slot
  parent : Option Parent := none -- Optional parent group for summaries/graphs
  priority : Option String := none -- Optional author-provided triage hint
  owner : Option AuthorId := none
  tags : Array String := #[]
  effort : Option String := none
  prUrl : Option String := none
deriving Repr, Inhabited

/--
Only fields supplied by one registration. Dependencies are independent of body
additions; adding code or dependencies cannot reclassify an authored statement.
-/
structure NodeContribution where
  /-- Explicit kind from a statement directive, including an empty placeholder. -/
  kind : Option NodeKind := none
  count : Nat := 0
  statementBody : Option InformalBody := none
  proofBody : Option InformalBody := none
  statementUses : Array UseRef := #[]
  proofUses : Array UseRef := #[]
  leanCode : Array CodeRef := #[]
  rustCode : Option RustInlineCode := none
  externalMarkup : ExternalMarkupSet := {}
  parent : Option Parent := none
  priority : Option String := none
  owner : Option AuthorId := none
  tags : Array String := #[]
  effort : Option String := none
  prUrl : Option String := none
deriving Repr, Inhabited

/-- External references carried by the selected association field. -/
def NodeContribution.externalReferences (contribution : NodeContribution) : Array ExternalRef :=
  contribution.leanCode.foldl (init := #[]) fun refs code =>
    match code with
    | .external more => refs ++ more
    | .literate _ => refs

/-- Selected fields require a producer-identified contribution record. -/
def NodeContribution.hasSelectedFields (contribution : NodeContribution) : Bool :=
  contribution.priority.isSome || !contribution.externalReferences.isEmpty

/-- Stable canonical union; build an ephemeral index once for this incoming group. -/
private def mergeExternalRefs (current incoming : Array ExternalRef) : Array ExternalRef := Id.run do
  let mut positions : NameMap Nat := {}
  for i in [:current.size] do
    positions := positions.insert current[i]!.canonical i
  let mut refs := current
  for ref in incoming do
    let ref := { ref with canonical := ref.canonical.eraseMacroScopes }
    match positions.get? ref.canonical with
    | some i =>
      if !refs[i]!.present && ref.present then refs := refs.set! i ref
    | none =>
      positions := positions.insert ref.canonical refs.size
      refs := refs.push ref
  return refs

/-- External summary entries not already supplied by a compiled literate declaration. -/
def Node.summaryExternalRefs (node : Node) : Array ExternalRef :=
  let names := node.literateCodes.foldl (init := ({} : NameSet)) fun names code =>
    code.definedDeclNames.foldl (fun names name => names.insert name) names
  node.externalRefs.filter fun ref => !names.contains ref.canonical.eraseMacroScopes

def Node.leanDecls (node : Node) : Array Name :=
  let external := node.externalRefs.foldl (init := #[]) fun acc ref =>
    if ref.present then pushNameUnique acc ref.canonical else acc
  node.literateCodes.foldl (init := external) fun acc code =>
    code.definedDeclNames.foldl pushNameUnique acc

def Node.hasAssociatedCode (node : Node) : Bool :=
  !node.externalRefs.isEmpty || !node.literateCodes.isEmpty

def Node.hasStatementBody (node : Node) : Bool := node.statement.any (·.hasBody)

def Node.hasProofBody (node : Node) : Bool := node.proof.any (·.hasBody)

/-- Infer the fallback uniformly from all Lean associations, including literate blocks. -/
private def inferredNodeKind (external : Array ExternalRef) (literate : Array Code) : NodeKind :=
  if external.any (·.kind.isTheoremLike) || literate.any (! ·.definedTheorems.isEmpty) then
    .theorem
  else if !external.isEmpty || literate.any (! ·.definedDefs.isEmpty) then
    .definition
  else .lemma

end Informal.Data
