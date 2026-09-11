/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Lean.Data.Json
import Lean.Data.Lsp
import VersoManual
import VersoBlueprint.ExternalDeclRender

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
def Label := Name
deriving Repr, Inhabited, DecidableEq, ToString, ToMessageData, ToJson, FromJson, Quote

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
deriving Repr, Inhabited, ToJson, FromJson, Quote

def ExternalRef.ofName (name : Name) (origin : ExternalOrigin := .directiveLean) : ExternalRef :=
  { written := name, canonical := name.eraseMacroScopes, origin, kind := .definition }

structure RustInlineCode where
  raw : String
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson, Quote

inductive CodeRef where
  /-
  Blueprint code references can currently come from two sources:
  1. An inline Lean block processed by Verso/Lean integration (`.literate`).
  2. A regular Lean declaration tagged with `@[blueprint "..."]` (`.external`, origin `.blueprintAttr`).
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

def CodeRef.externalRefs : CodeRef → Array ExternalRef
  | .external refs => refs
  | .literate _ => #[]

def CodeRef.literateCodes : CodeRef → Array Code
  | .external _ => #[]
  | .literate code => #[code]

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
  elabStx : Array Syntax := #[] -- Syntax is going to have type Verso.Block ...
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
  /-- Lean code associations for this informal object. -/
  leanCode : Array CodeRef := #[]
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

/-- Map of labels to Node data -/
def Data := LabelMap Node
deriving Repr, Inhabited

/-- The empty Blueprint node database. -/
def Data.empty : Data := Std.TreeMap.empty

private def pushExternalRefUnique (refs : Array ExternalRef) (ref : ExternalRef) : Array ExternalRef :=
  let canonical := ref.canonical.eraseMacroScopes
  if refs.any (fun current => current.canonical.eraseMacroScopes == canonical) then
    refs.map fun current =>
      if current.canonical.eraseMacroScopes == canonical && !current.present && ref.present then
        { ref with canonical }
      else
        current
  else
    refs.push { ref with canonical }

def Node.externalRefs (node : Node) : Array ExternalRef :=
  node.leanCode.foldl (init := #[]) fun acc codeRef =>
    codeRef.externalRefs.foldl pushExternalRefUnique acc

def Node.literateCodes (node : Node) : Array Code :=
  node.leanCode.foldl (init := #[]) fun acc codeRef =>
    acc ++ codeRef.literateCodes

def Node.leanDecls (node : Node) : Array Name :=
  node.leanCode.foldl (init := #[]) fun acc codeRef =>
    codeRef.leanDecls.foldl pushNameUnique acc

def Node.hasAssociatedCode (node : Node) : Bool :=
  !node.leanCode.isEmpty

def Node.hasStatementBody (node : Node) : Bool := node.statement.any (·.hasBody)

def Node.hasProofBody (node : Node) : Bool := node.proof.any (·.hasBody)

/-- Infer the fallback uniformly from all Lean associations, including literate blocks. -/
private def inferredNodeKind (code : Array CodeRef) : NodeKind := Id.run do
  let mut kind := NodeKind.lemma
  for ref in code do
    match ref with
    | .external decls =>
      for decl in decls do
        if decl.kind.isTheoremLike then return .theorem
        kind := .definition
    | .literate block =>
      if !block.definedTheorems.isEmpty then return .theorem
      if !block.definedDefs.isEmpty then kind := .definition
  return kind

def Data.parentChildren (data : Data) : LabelMap (Array Label) :=
  data.foldl (init := (Std.TreeMap.empty : LabelMap (Array Label))) fun acc child node =>
    match node.parent with
    | none => acc
    | some parent =>
      let children := acc.getD parent #[]
      acc.insert parent (children.push child)

private def mergeAssociatedCodeRefs (current : Array CodeRef) (incoming : CodeRef) : Array CodeRef :=
  match incoming with
  | .external incomingRefs =>
    let currentExternalRefs :=
      current.foldl (init := #[]) fun refs codeRef =>
        codeRef.externalRefs.foldl pushExternalRefUnique refs
    let externalRefs := incomingRefs.foldl pushExternalRefUnique currentExternalRefs
    let nonExternal := current.filter fun
      | .external _ => false
      | .literate _ => true
    if externalRefs.isEmpty then
      nonExternal
    else
      nonExternal.push (.external externalRefs)
  | .literate code =>
    current.push (.literate code)

/-- Next declaration number for a statement introduced in the current environment. -/
def Data.nextCount (data : Data) : Nat :=
  data.foldl (init := 0) (fun count _label node => max count node.count) + 1

private abbrev MergeM := StateM (Array String)

private def conflict (message : String) : MergeM Unit :=
  modify (·.push message)

/-- Equal scalar metadata is idempotent; distinct values are always a conflict. -/
private def mergeMetadata [BEq α] [ToString α] (label : Label) (field : String)
    (current incoming : Option α) : MergeM (Option α) := do
  match current, incoming with
  | none, _ => return incoming
  | _, none => return current
  | some existing, some value =>
    if existing != value then
      conflict s!"Label {label} declares conflicting {field}: existing '{existing}', new '{value}'"
    return current

/-- Retain one declaration per authority, checking even metadata hidden by manual precedence. -/
private def mergeUses (label : Label) (side : String)
    (current incoming : Array UseRef) : MergeM (Array UseRef) := do
  let mut uses := current
  for ref in incoming do
    if let some previous := uses.find? (fun previous =>
        previous.label == ref.label && previous.origin == ref.origin) then
      if previous.intent != ref.intent then
        conflict s!"Label {label} declares conflicting {side} dependency intents for '{ref.label}' ({ref.origin}): existing '{previous.intent}', new '{ref.intent}'"
    else
      uses := uses.push ref
  return uses

private def mergePayload (label : Label) (side : String)
    (current : Option InformalData) (body : Option InformalBody)
    (incomingUses : Array UseRef) : MergeM (Option InformalData) := do
  let useDeclarations ← mergeUses label side (current.map (·.useDeclarations) |>.getD #[]) incomingUses
  let currentBody := current.map (·.toInformalBody)
  if (currentBody.any (·.hasBody)) && (body.any (·.hasBody)) then
    conflict s!"Label {label} already has a {side}"
  let selected := if body.any (·.hasBody) then body else currentBody <|> body
  match selected with
  | some body => return some { toInformalBody := body, useDeclarations }
  | none =>
    return if useDeclarations.isEmpty then none else some { stx := .missing, useDeclarations }

private def mergeContribution (label : Label) (node : Node)
    (incoming : NodeContribution) : MergeM Node := do
  let statement ← mergePayload label "statement" node.statement incoming.statementBody incoming.statementUses
  let proof ← mergePayload label "proof" node.proof incoming.proofBody incoming.proofUses
  let mut rustCode := node.rustCode
  if let some code := incoming.rustCode then
    if rustCode.isSome then
      conflict s!"Label {label} already has associated Rust code"
    else
      rustCode := some code
  let mut externalMarkup := node.externalMarkup
  for markup in incoming.externalMarkup.toArray do
    let key := markup.key
    if externalMarkup.contains key then
      conflict s!"Label {label} already has associated {key.language} external markup in slot '{key.slot}'"
    else
      externalMarkup := externalMarkup.insert markup
  let parent ← mergeMetadata label "parents" node.parent incoming.parent
  let priority ← mergeMetadata label "priorities" node.priority incoming.priority
  let owner ← mergeMetadata label "owners" node.owner incoming.owner
  let effort ← mergeMetadata label "effort values" node.effort incoming.effort
  let prUrl ← mergeMetadata label "PR URLs" node.prUrl incoming.prUrl
  let leanCode := incoming.leanCode.foldl mergeAssociatedCodeRefs node.leanCode
  let kindIsExplicit := node.kindIsExplicit || incoming.kind.isSome
  let kind ← match incoming.kind with
    | some kind =>
      if node.kindIsExplicit && node.kind != kind then
        conflict s!"Label {label} declares conflicting statement kinds: existing '{node.kind}', new '{kind}'"
      pure kind
    | none => pure <| if node.kindIsExplicit then node.kind else inferredNodeKind leanCode
  return {
    kind, kindIsExplicit
    count := if node.count == 0 then incoming.count else node.count
    statement, proof, rustCode, externalMarkup, parent, priority, owner, effort, prUrl
    leanCode
    tags := incoming.tags.foldl (fun tags tag => if tags.contains tag then tags else tags.push tag) node.tags
  }

/--
Pure, atomic registration shared by local elaboration and import replay. Failed
registrations expose diagnostics, never a partially updated node.
-/
def Node.applyContributions (label : Label) (node : Node)
    (contributions : Array NodeContribution) : Except (Array String) Node :=
  let (node, errors) := (contributions.foldlM (mergeContribution label) node).run #[]
  if errors.isEmpty then .ok node else .error errors

end Informal.Data
