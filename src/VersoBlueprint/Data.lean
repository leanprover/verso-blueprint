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

structure InformalData where
  stx : Syntax
  /-- Structured dependency edges declared from this informal payload. -/
  deps : Array UseRef := #[]
  previewBlocks : Array (Verso.Doc.Block Verso.Genre.Manual) := #[]
  elabStx : Array Syntax := #[] -- Syntax is going to have type Verso.Block ...
deriving Repr, Inhabited

def InformalData.hasBody (data : InformalData) : Bool :=
  !data.previewBlocks.isEmpty || !data.elabStx.isEmpty

def InformalData.dependencyLabels (data : InformalData) : Array Label :=
  data.deps.map (·.label)

structure Node where
  kind : NodeKind := .lemma
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

/-- Map of labels to Node data -/
def Data := LabelMap Node
deriving Repr, Inhabited

/-- We can state a theorem if all its deps are done, and the theorem isn't "not ready" -/
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

def Data.parentChildren (data : Data) : LabelMap (Array Label) :=
  data.foldl (init := (Std.TreeMap.empty : LabelMap (Array Label))) fun acc child node =>
    match node.parent with
    | none => acc
    | some parent =>
      let children := acc.getD parent #[]
      acc.insert parent (children.push child)

section

variable [Monad m] [MonadLog m] [AddMessageContext m] [MonadOptions m]

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

private def Node.withCodeRef (node : Node) (codeRef : CodeRef) : Node :=
  {
    node with
      leanCode := mergeAssociatedCodeRefs node.leanCode codeRef
  }

private def mergeRustCode (label : Label) (current : Option RustInlineCode) (incoming : RustInlineCode) :
    m (Option RustInlineCode) := do
  match current with
  | none => return some incoming
  | some _ =>
    logError m!"Label {label} already has associated Rust code"
    return current

private def mergeParent (label : Label) (current incoming : Option Parent) : m (Option Parent) := do
  match current, incoming with
  | none, none => return none
  | some parent, none => return some parent
  | none, some parent => return some parent
  | some currentParent, some incomingParent =>
    if currentParent = incomingParent then
      logWarning m!"Label {label} repeats '(parent := \"{currentParent}\")'; keeping the same parent"
      return some currentParent
    else
      logError m!"Label {label} declares conflicting parents: existing '{currentParent}', new '{incomingParent}'"
      return some currentParent

private def mergePriority (label : Label) (current incoming : Option String) : m (Option String) := do
  match current, incoming with
  | none, none => return none
  | some priority, none => return some priority
  | none, some priority => return some priority
  | some currentPriority, some incomingPriority =>
    if currentPriority = incomingPriority then
      logWarning m!"Label {label} repeats '(priority := \"{currentPriority}\")'; keeping the same priority"
      return some currentPriority
    else
      logError m!"Label {label} declares conflicting priorities: existing '{currentPriority}', new '{incomingPriority}'"
      return some currentPriority

private def mergeOwner (label : Label) (current incoming : Option AuthorId) : m (Option AuthorId) := do
  match current, incoming with
  | none, none => return none
  | some owner, none => return some owner
  | none, some owner => return some owner
  | some currentOwner, some incomingOwner =>
    if currentOwner = incomingOwner then
      logWarning m!"Label {label} repeats '(owner := \"{currentOwner}\")'; keeping the same owner"
      return some currentOwner
    else
      logError m!"Label {label} declares conflicting owners: existing '{currentOwner}', new '{incomingOwner}'"
      return some currentOwner

private def mergeEffort (label : Label) (current incoming : Option String) : m (Option String) := do
  match current, incoming with
  | none, none => return none
  | some effort, none => return some effort
  | none, some effort => return some effort
  | some currentEffort, some incomingEffort =>
    if currentEffort = incomingEffort then
      logWarning m!"Label {label} repeats '(effort := \"{currentEffort}\")'; keeping the same effort"
      return some currentEffort
    else
      logError m!"Label {label} declares conflicting effort values: existing '{currentEffort}', new '{incomingEffort}'"
      return some currentEffort

private def mergePrUrl (label : Label) (current incoming : Option String) : m (Option String) := do
  match current, incoming with
  | none, none => return none
  | some url, none => return some url
  | none, some url => return some url
  | some currentUrl, some incomingUrl =>
    if currentUrl = incomingUrl then
      logWarning m!"Label {label} repeats '(pr_url := \"{currentUrl}\")'; keeping the same URL"
      return some currentUrl
    else
      logError m!"Label {label} declares conflicting PR URLs: existing '{currentUrl}', new '{incomingUrl}'"
      return some currentUrl

private def mergeTags (current incoming : Array String) : Array String :=
  incoming.foldl (init := current) fun acc tag =>
    if acc.contains tag then acc else acc.push tag

private def fillBodylessPayload (current incoming : InformalData) : InformalData :=
  { incoming with deps := UseRef.mergeByLabel current.deps incoming.deps }

private def fillPayload? (current? : Option InformalData) (incoming : InformalData) :
    Option InformalData :=
  match current? with
  | none => some incoming
  | some current =>
    if current.hasBody then
      none
    else
      some (fillBodylessPayload current incoming)

private def Data.nextCount (data : Data) : Nat :=
  data.foldl (init := 0) (fun count _label node => max count node.count) + 1

private def Node.countOrNext (node : Node) (nextCount : Nat) : Nat :=
  if node.count == 0 then nextCount else node.count

private def mergeExternalMarkup (label : Label)
    (current : ExternalMarkupSet) (incoming : ExternalMarkup)
    : m ExternalMarkupSet := do
  let key := incoming.key
  if current.contains key then
    logError m!"Label {label} already has associated {key.language} external markup in slot '{key.slot}'"
    return current
  else
    return current.insert incoming

def Data.registerCodeRef (data : Data) (label : Label) (codeRef : CodeRef) : m Data := do
  match data.get? label with
  | none =>
    return data.insert label (({} : Node).withCodeRef codeRef)
  | some node =>
    return data.insert label (node.withCodeRef codeRef)

def Data.register (data : Data) (label : Label) (kind : InProgressKind) (payload : InformalData)
    (codeHint : Option CodeRef := none) (parent : Option Parent := none) (priority : Option String := none)
    (owner : Option AuthorId := none) (tags : Array String := #[]) (effort : Option String := none)
    (prUrl : Option String := none) : m Data := do
  let applyHints (node : Node) : m Node := do
    let node :=
      match codeHint with
      | none => node
      | some hint => node.withCodeRef hint
    let parent ← mergeParent label node.parent parent
    let priority ← mergePriority label node.priority priority
    let owner ← mergeOwner label node.owner owner
    let effort ← mergeEffort label node.effort effort
    let prUrl ← mergePrUrl label node.prUrl prUrl
    let tags := mergeTags node.tags tags
    return { node with parent, priority, owner, tags, effort, prUrl }
  let nextCount := data.nextCount
  match data.get? label, kind with
  -- First statement for a fresh label.
  | none, .statement nodeKind =>
    let count := nextCount
    let node ← applyHints {
      statement := some payload
      count
      kind := nodeKind
    }
    return data.insert label node
  -- Proof without a corresponding statement is weird, ignore?
  | none, .proof =>
    logError m!"No statement for proof with label {label}"
    return data
  -- Late statement fill for an existing placeholder node.
  | some node, .statement nodeKind =>
    match fillPayload? node.statement payload with
    | some statement =>
      let count := node.countOrNext nextCount
      let node ← applyHints {
        node with
          kind := nodeKind
          count
          statement := some statement
      }
      return data.insert label node
    | none =>
      -- logError m!"Duplicated entry for {label}"
      return data
  -- Register proof for an existing statement.
  | some node, .proof =>
    if node.statement.isNone then
      logError m!"Cannot register proof for {label}: statement dependencies are missing"
      return data
    else
      match fillPayload? node.proof payload with
      | some proof =>
        let node ← applyHints {
          node with
            proof := some proof
        }
        return data.insert label node
      | none =>
        -- logError m!"{label} already has a proof"
        return data

/-- Register Lean code and code metadata for an informal object label. -/
def Data.registerCode (data : Data) (label : Label) (code : Syntax)
    (definedDefs : Array LiterateDef := #[]) (definedTheorems : Array LiterateThm := #[]) : m Data := do
  let literate : CodeRef := .literate { stx := code, definedDefs, definedTheorems }
  match data.get? label with
  | none =>
    return data.insert label (({} : Node).withCodeRef literate)
  | some node =>
    return data.insert label (node.withCodeRef literate)

def Data.registerRustCode (data : Data) (label : Label) (code : RustInlineCode) : m Data := do
  match data.get? label with
  | none =>
    return data.insert label { rustCode := some code }
  | some node =>
    let rustCode ← mergeRustCode label node.rustCode code
    return data.insert label { node with rustCode }

/-- Register external markup for an informal object label. -/
def Data.registerExternalMarkup (data : Data) (label : Label) (markup : ExternalMarkup) : m Data := do
  match data.get? label with
  | none =>
    return data.insert label { externalMarkup := ({} : ExternalMarkupSet).insert markup }
  | some node =>
    let externalMarkup ← mergeExternalMarkup label node.externalMarkup markup
    return data.insert label { node with externalMarkup }

/-- Infotree entry corresponding to a node in the blueprint graph. -/
structure NodeInfo where
  label : Label
  kind : Data.InProgressKind
deriving TypeName, Repr

def NodeInfo.save [Monad m] [Elab.MonadInfoTree m]
    (stx : Syntax) (label : Label) (kind : Data.InProgressKind) : m Unit := do
  Elab.pushInfoLeaf <| .ofCustomInfo { stx := stx, value := Dynamic.mk ({ label, kind } : NodeInfo) }

end
