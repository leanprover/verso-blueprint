/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Lean.Data.Json
import VersoManual
import VersoBlueprint.DocGenNameRender

namespace Informal.Data

open Lean

deriving instance Lean.ToJson for Lean.DeclarationRange
deriving instance Lean.FromJson for Lean.DeclarationRange

open Syntax in
instance : Lean.Quote Lean.Position where
  quote p := mkCApp ``Lean.Position.mk #[quote p.line, quote p.column]

open Syntax in
instance : Lean.Quote Lean.DeclarationRange where
  quote r := mkCApp ``Lean.DeclarationRange.mk
    #[quote r.pos, quote r.charUtf16, quote r.endPos, quote r.endCharUtf16]

set_option doc.verso true
-- set_option pp.rawOnError true

-- informal object labels are names for now, but that could change
@[expose]
def Label := Name
deriving Repr, Inhabited, DecidableEq, ToString, ToMessageData, ToJson, FromJson, Quote

@[expose] def LabelMap A := NameMap A

instance [Repr A] : Repr (LabelMap A) := inferInstanceAs <| Repr (NameMap A)

@[expose]
abbrev Parent := Label

@[expose]
abbrev AuthorId := Label

structure AuthorInfo where
  displayName : String
  url : Option String := none
  imageUrl : Option String := none
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

open Syntax in
instance : Quote AuthorInfo where
  quote info := mkCApp ``AuthorInfo.mk #[quote info.displayName, quote info.url, quote info.imageUrl]

inductive NodeKind where
  | definition
  | lemma
  | theorem
  | corollary
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

instance : ToString NodeKind where
  toString
    | .definition => "Definition"
    | .lemma => "Lemma"
    | .theorem => "Theorem"
    | .corollary => "Corollary"

def NodeKind.isTheoremLike : NodeKind → Bool
  | .lemma | .theorem | .corollary => true
  | .definition => false

inductive InProgressKind where
  | statement (kind : NodeKind)
  | proof
deriving Inhabited, Repr, ToJson, FromJson

open Syntax in
instance : Quote NodeKind where
  quote
    | .definition => mkCApp ``NodeKind.definition #[]
    | .lemma => mkCApp ``NodeKind.lemma #[]
    | .theorem => mkCApp ``NodeKind.theorem #[]
    | .corollary => mkCApp ``NodeKind.corollary #[]

open Syntax in
instance : Quote InProgressKind where
  quote
    | .statement kind => mkCApp ``InProgressKind.statement #[quote kind]
    | .proof => mkCApp ``InProgressKind.proof #[]

/-- Where an incompleteness marker appears in a declaration. -/
inductive SorryWhere where
  | statement
  | proof
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

open Syntax in
instance : Quote SorryWhere where
  quote
    | .statement => mkCApp ``SorryWhere.statement #[]
    | .proof => mkCApp ``SorryWhere.proof #[]

/--
Structured metadata for one incomplete location in a declaration.
{lit}`refs?` stores the number of references when known.
-/
structure SorryInfo where
  location : SorryWhere
  refs? : Option Nat := none
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

open Syntax in
instance : Quote SorryInfo where
  quote s := mkCApp ``SorryInfo.mk #[quote s.location, quote s.refs?]

/--
Formalization/proof status for a declaration.
-/
inductive ProvedStatus where
  | proved
  /-- Declaration reference could not be resolved/present at snapshot time. -/
  | missing
  | axiomLike
  | containsSorry (info : Array SorryInfo)
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

open Syntax in
instance : Quote ProvedStatus where
  quote
    | .proved => mkCApp ``ProvedStatus.proved #[]
    | .missing => mkCApp ``ProvedStatus.missing #[]
    | .axiomLike => mkCApp ``ProvedStatus.axiomLike #[]
    | .containsSorry info => mkCApp ``ProvedStatus.containsSorry #[quote info]

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

/-- Raw TeX source associated with a blueprint label. -/
structure TexSource where
  raw : String
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

/-- Default slot for labeled {lit}`tex` witness blocks that omit `(slot := ...)`. -/
def defaultTexSourceSlot : String := "default"

inductive ExternalOrigin where
  | directiveLean
  | blueprintAttr
deriving Repr, Inhabited, DecidableEq

instance : Lean.ToJson ExternalOrigin where
  toJson
    | .directiveLean => .str "d"
    | .blueprintAttr => .str "a"

instance : Lean.FromJson ExternalOrigin where
  fromJson?
    | .str "d" => return .directiveLean
    | .str "a" => return .blueprintAttr
    | .str "directiveLean" => return .directiveLean
    | .str "blueprintAttr" => return .blueprintAttr
    | other => throw s!"expected ExternalOrigin, got {other.compress}"

open Syntax in
instance : Quote ExternalOrigin where
  quote
    | .directiveLean => mkCApp ``ExternalOrigin.directiveLean #[]
    | .blueprintAttr => mkCApp ``ExternalOrigin.blueprintAttr #[]

inductive ExternalDeclProvenance where
  | inWorkspace (moduleName : Name) (sourcePath : String)
  | outWorkspace (moduleName : Name) (sourcePath? : Option String := none)
  | unknown
deriving Repr, Inhabited, DecidableEq

instance : Lean.ToJson ExternalDeclProvenance where
  toJson
    | .inWorkspace moduleName sourcePath =>
      .arr #[.str "iw", Lean.ToJson.toJson moduleName, Lean.ToJson.toJson sourcePath]
    | .outWorkspace moduleName sourcePath? =>
      .arr #[.str "ow", Lean.ToJson.toJson moduleName, Lean.ToJson.toJson sourcePath?]
    | .unknown =>
      .arr #[.str "u"]

instance : Lean.FromJson ExternalDeclProvenance where
  fromJson?
    | .arr arr => do
      let some tag := arr[0]? | throw "expected external provenance tag"
      match (← Lean.FromJson.fromJson? tag : String) with
      | "iw" =>
        let some moduleName := arr[1]? | throw "expected in-workspace module"
        let some sourcePath := arr[2]? | throw "expected in-workspace source path"
        return .inWorkspace (← Lean.FromJson.fromJson? moduleName) (← Lean.FromJson.fromJson? sourcePath)
      | "ow" =>
        let some moduleName := arr[1]? | throw "expected out-workspace module"
        let some sourcePath := arr[2]? | throw "expected out-workspace source path"
        return .outWorkspace (← Lean.FromJson.fromJson? moduleName) (← Lean.FromJson.fromJson? sourcePath)
      | "u" => return .unknown
      | other => throw s!"unknown external provenance tag {other}"
    | v@(.obj _) => do
      if let .ok moduleName := v.getObjValAs? Name "inWorkspace" then
        return .inWorkspace moduleName (← v.getObjValAs? String "sourcePath")
      else if let .ok moduleName := v.getObjValAs? Name "outWorkspace" then
        return .outWorkspace moduleName (← v.getObjValAs? (Option String) "sourcePath")
      else
        return .unknown
    | other => throw s!"expected ExternalDeclProvenance, got {other.compress}"

open Syntax in
instance : Quote ExternalDeclProvenance where
  quote
    | .inWorkspace moduleName sourcePath =>
      mkCApp ``ExternalDeclProvenance.inWorkspace #[quote moduleName, quote sourcePath]
    | .outWorkspace moduleName sourcePath? =>
      mkCApp ``ExternalDeclProvenance.outWorkspace #[quote moduleName, quote sourcePath?]
    | .unknown =>
      mkCApp ``ExternalDeclProvenance.unknown #[]

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
deriving Repr, Inhabited, DecidableEq

instance : Lean.ToJson ExternalDeclLookupError where
  toJson
    | .notPresentAtRegistration => .str "npr"
    | .notFoundInEnvironment => .str "nfe"

instance : Lean.FromJson ExternalDeclLookupError where
  fromJson?
    | .str "npr" => return .notPresentAtRegistration
    | .str "nfe" => return .notFoundInEnvironment
    | .str "notPresentAtRegistration" => return .notPresentAtRegistration
    | .str "notFoundInEnvironment" => return .notFoundInEnvironment
    | other => throw s!"expected ExternalDeclLookupError, got {other.compress}"

open Syntax in
instance : Quote ExternalDeclLookupError where
  quote
    | .notPresentAtRegistration =>
      mkCApp ``ExternalDeclLookupError.notPresentAtRegistration #[]
    | .notFoundInEnvironment =>
      mkCApp ``ExternalDeclLookupError.notFoundInEnvironment #[]

def ExternalDeclLookupError.message : ExternalDeclLookupError → String
  | .notPresentAtRegistration => "name was not present during directive/code-block registration"
  | .notFoundInEnvironment => "name is not present in current environment"

abbrev ExternalDeclRender := Except Informal.DocGenRenderError String

instance : ToJson ExternalDeclRender where
  toJson
    | .ok html => .arr #[.str "ok", Lean.ToJson.toJson html]
    | .error error => .arr #[.str "err", Lean.ToJson.toJson error]

instance : FromJson ExternalDeclRender where
  fromJson?
    | .arr arr => do
      let some tag := arr[0]? | throw "expected external render tag"
      let some payload := arr[1]? | throw "expected external render payload"
      match (← Lean.FromJson.fromJson? tag : String) with
      | "ok" => return .ok (← Lean.FromJson.fromJson? payload)
      | "err" => return .error (← Lean.FromJson.fromJson? payload)
      | other => throw s!"unknown external render tag {other}"
    | .obj obj =>
      match obj.get? "ok", obj.get? "error" with
      | some ok, none => return .ok (← fromJson? ok)
      | none, some err => return .error (← fromJson? err)
      | _, _ => throw "expected object with exactly one of fields 'ok' or 'error'"
    | _ => throw "expected object"

instance : Lean.Quote ExternalDeclRender where
  quote
    | .ok html => Syntax.mkApp (mkCIdent ``Except.ok) #[(Lean.quote html)]
    | .error error => Syntax.mkApp (mkCIdent ``Except.error) #[(Lean.quote error)]

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
deriving Repr, Inhabited

instance : Lean.ToJson ExternalRef where
  toJson ref := .arr #[
    Lean.ToJson.toJson ref.written,
    Lean.ToJson.toJson ref.canonical,
    Lean.ToJson.toJson ref.origin,
    Lean.ToJson.toJson ref.present,
    Lean.ToJson.toJson ref.provedStatus,
    Lean.ToJson.toJson ref.provenance,
    Lean.ToJson.toJson ref.range?,
    Lean.ToJson.toJson ref.selectionRange?,
    Lean.ToJson.toJson ref.kind,
    Lean.ToJson.toJson ref.sourceHref?,
    Lean.ToJson.toJson ref.render
  ]

instance : Lean.FromJson ExternalRef where
  fromJson? v := do
  match v with
    | .arr arr => do
      let some written := arr[0]? | throw "expected written name"
      let some canonical := arr[1]? | throw "expected canonical name"
      let some origin := arr[2]? | throw "expected origin"
      let some present := arr[3]? | throw "expected presence flag"
      let some provedStatus := arr[4]? | throw "expected proved status"
      let some provenance := arr[5]? | throw "expected provenance"
      let some range? := arr[6]? | throw "expected declaration range"
      let some selectionRange? := arr[7]? | throw "expected selection range"
      let some kind := arr[8]? | throw "expected node kind"
      let some sourceHref? := arr[9]? | throw "expected source href"
      let some render := arr[10]? | throw "expected render payload"
      return {
        written := ← Lean.FromJson.fromJson? written
        canonical := ← Lean.FromJson.fromJson? canonical
        origin := ← Lean.FromJson.fromJson? origin
        present := ← Lean.FromJson.fromJson? present
        provedStatus := ← Lean.FromJson.fromJson? provedStatus
        provenance := ← Lean.FromJson.fromJson? provenance
        range? := ← Lean.FromJson.fromJson? range?
        selectionRange? := ← Lean.FromJson.fromJson? selectionRange?
        kind := ← Lean.FromJson.fromJson? kind
        sourceHref? := ← Lean.FromJson.fromJson? sourceHref?
        render := ← Lean.FromJson.fromJson? render
      }
    | _ =>
      return {
        written := ← v.getObjValAs? Name "written"
        canonical := ← v.getObjValAs? Name "canonical"
        origin := ← v.getObjValAs? ExternalOrigin "origin"
        present := ← v.getObjValAs? Bool "present"
        provedStatus := ← v.getObjValAs? ProvedStatus "provedStatus"
        provenance := ← v.getObjValAs? ExternalDeclProvenance "provenance"
        range? := ← v.getObjValAs? (Option Lean.DeclarationRange) "range?"
        selectionRange? := ← v.getObjValAs? (Option Lean.DeclarationRange) "selectionRange?"
        kind := ← v.getObjValAs? NodeKind "kind"
        sourceHref? := ← v.getObjValAs? (Option String) "sourceHref?"
        render := ← v.getObjValAs? ExternalDeclRender "render"
      }

open Syntax in
instance : Quote ExternalRef where
  quote ref := mkCApp ``ExternalRef.mk
    #[ quote ref.written
     , quote ref.canonical
     , quote ref.origin
     , quote ref.present
     , quote ref.provedStatus
     , quote ref.provenance
     , quote ref.range?
     , quote ref.selectionRange?
     , quote ref.kind
     , quote ref.sourceHref?
     , quote ref.render
     ]

def ExternalRef.ofName (name : Name) (origin : ExternalOrigin := .directiveLean) : ExternalRef :=
  { written := name, canonical := name.eraseMacroScopes, origin, kind := .definition }

structure RustInlineCode where
  raw : String
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

open Syntax in
instance : Quote RustInlineCode where
  quote code := mkCApp ``RustInlineCode.mk #[quote code.raw]

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

  TODO (external-definitions task): complete and encode the intended behavior from
  the "We'd like to:" portion of the design spec.
  -/
  | external (decls : Array ExternalRef)
  | literate (code : Code)
deriving Repr, Inhabited

structure InformalData where
  stx : Syntax
  deps : Array Label := #[]
  previewBlocks : Array (Verso.Doc.Block Verso.Genre.Manual) := #[]
  elabStx : Array Syntax := #[] -- Syntax is going to have type Verso.Block ...
deriving Repr, Inhabited

structure Node where
  kind : NodeKind := .lemma
  count : Nat := 0
  statement : Option InformalData := none -- Informal Object statement
  proof : Option InformalData := none -- Informal Object proof
  code : Option CodeRef := none -- Informal Object associated code status
  rustCode : Option RustInlineCode := none -- Informal object associated Rust code
  texSources : Array (String × TexSource) := #[] -- Raw TeX witnesses keyed by slot
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

def Data.parentChildren (data : Data) : LabelMap (Array Label) :=
  data.foldl (init := (Std.TreeMap.empty : LabelMap (Array Label))) fun acc child node =>
    match node.parent with
    | none => acc
    | some parent =>
      let children := acc.getD parent #[]
      acc.insert parent (children.push child)

section

variable [Monad m] [MonadLog m] [AddMessageContext m] [MonadOptions m]

private def mergeCodeRef (label : Label) (current : Option CodeRef) (incoming : CodeRef) : m (Option CodeRef) := do
  match current, incoming with
  | none, incoming => return some incoming
  | some (.external _), .external _ =>
    logError m!"Label {label} has multiple external Lean reference declarations; external merging is not supported"
    return current
  | some (.literate _), .literate _ =>
    logError m!"Label {label} already has code"
    return current
  | some (.external _), .literate code =>
    logError m!"Label {label} has both '(lean := ...)' and an associated Lean code block; preferring inline code"
    return some (.literate code)
  | some (.literate _), .external _ =>
    logError m!"Label {label} has both an associated Lean code block and '(lean := ...)'; preferring inline code"
    return current

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

private def mergeTexSource (label : Label) (slot : String)
    (current : Array (String × TexSource)) (incoming : TexSource)
    : m (Array (String × TexSource)) := do
  if current.any (fun entry => entry.1 == slot) then
    logError m!"Label {label} already has an associated TeX witness in slot '{slot}'"
    return current
  else
    return current.push (slot, incoming)

def Data.registerCodeRef (data : Data) (label : Label) (codeRef : CodeRef) : m Data := do
  match data.get? label with
  | none =>
    return data.insert label { code := some codeRef }
  | some node =>
    let code ← mergeCodeRef label node.code codeRef
    return data.insert label { node with code }

def Data.register (data : Data) (label : Label) (kind : InProgressKind) (payload : InformalData)
    (codeHint : Option CodeRef := none) (parent : Option Parent := none) (priority : Option String := none)
    (owner : Option AuthorId := none) (tags : Array String := #[]) (effort : Option String := none)
    (prUrl : Option String := none) : m Data := do
  let applyHints (node : Node) : m Node := do
    let code ←
      match codeHint with
      | none => pure node.code
      | some hint => mergeCodeRef label node.code hint
    let parent ← mergeParent label node.parent parent
    let priority ← mergePriority label node.priority priority
    let owner ← mergeOwner label node.owner owner
    let effort ← mergeEffort label node.effort effort
    let prUrl ← mergePrUrl label node.prUrl prUrl
    let tags := mergeTags node.tags tags
    return { node with code, parent, priority, owner, tags, effort, prUrl }
  let nextCount := data.size + 1
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
    if node.statement.isNone then
      let count := if node.count == 0 then nextCount else node.count
      let node ← applyHints {
        node with
          kind := nodeKind
          count
          statement := some payload
      }
      return data.insert label node
    else
      -- logError m!"Duplicated entry for {label}"
      return data
  -- Register proof for an existing statement.
  | some node, .proof =>
    if node.proof.isSome then
      -- logError m!"{label} already has a proof"
      return data
    else if node.statement.isNone then
      logError m!"Cannot register proof for {label}: statement dependencies are missing"
      return data
    else
      let node ← applyHints {
        node with
          proof := some payload
      }
      return data.insert label node

/-- Register Lean code and code metadata for an informal object label. -/
def Data.registerCode (data : Data) (label : Label) (code : Syntax)
    (definedDefs : Array LiterateDef := #[]) (definedTheorems : Array LiterateThm := #[]) : m Data := do
  let literate : CodeRef := .literate { stx := code, definedDefs, definedTheorems }
  match data.get? label with
  | none =>
    return data.insert label { code := some literate }
  | some node =>
    let code ← mergeCodeRef label node.code literate
    return data.insert label { node with code }

def Data.registerRustCode (data : Data) (label : Label) (code : RustInlineCode) : m Data := do
  match data.get? label with
  | none =>
    return data.insert label { rustCode := some code }
  | some node =>
    let rustCode ← mergeRustCode label node.rustCode code
    return data.insert label { node with rustCode }

/-- Register raw TeX source for an informal object label. -/
def Data.registerTexSource (data : Data) (label : Label) (slot : String) (texSource : TexSource) : m Data := do
  match data.get? label with
  | none =>
    return data.insert label { texSources := #[(slot, texSource)] }
  | some node =>
    let texSources ← mergeTexSource label slot node.texSources texSource
    return data.insert label { node with texSources }

end
