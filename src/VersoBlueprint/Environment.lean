/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean.CoreM
import Lean.EnvExtension
import VersoManual
import VersoBlueprint.Data

namespace Informal.Environment

open Lean
open Informal.Data

/--
Elaboration-time builder for a node that is currently open on the directive
stack.

This intentionally stays separate from `Data.Node`: it carries directive-stack
metadata and typed preview blocks before the final persisted semantic node can
be assembled.
-/
structure InProgress where
  label : Label
  kind : Data.InProgressKind := .proof
  codeHint : Option CodeRef := none
  parent : Option Parent := none
  priority : Option String := none
  owner : Option AuthorId := none
  tags : Array String := #[]
  effort : Option String := none
  prUrl : Option String := none
  deps : Array UseRef := #[]
  previewBlocks : Array (Verso.Doc.Block Verso.Genre.Manual) := #[]
deriving Inhabited, Repr

inductive ImportedConflictKind where
  | node
  | group
  | author
deriving Inhabited, Repr, DecidableEq

structure ImportedConflict where
  kind : ImportedConflictKind
  label : Name
  reasons : Array String := #[]
  modules : Array Name := #[]
deriving Inhabited, Repr, DecidableEq

/--
Persisted semantic state collected during elaboration.

Rendered traversal stores project from this state and add site-local facts such
as numbering, hrefs, preview ids, and HTML-cache keys. Keep those traversal
facts out of this environment extension unless they become stable semantic
data.
-/
structure State where
  data : Data := Data.empty
  /-- The module that first introduced each label, inherited by later extensions. -/
  nodeOrigins : NameMap Name := {}
  /-- Modules supplying the accepted fields, retained for conflict diagnostics. -/
  nodeModules : NameMap (Array Name) := {}
  /-- Only registrations made in this module, in registration order per label. -/
  localContributions : NameMap (Array NodeContribution) := {}
  groups : NameMap String := {}
  localGroups : NameMap String := {}
  authors : NameMap AuthorInfo := {}
  localAuthors : NameMap AuthorInfo := {}
  leanNameLabels : NameMap (Array Label) := {}
  importedConflicts : Array ImportedConflict := #[]
  importedConflictsReported : Bool := false
  stack : List InProgress := []
deriving Inhabited, Repr

private def ImportedConflictKind.rank : ImportedConflictKind → Nat
  | .node => 0
  | .group => 1
  | .author => 2

def ImportedConflict.message (conflict : ImportedConflict) : String :=
  let heading := match conflict.kind with
    | .node => s!"Conflicting imported blueprint contributions for label '{conflict.label}'"
    | .group => s!"Duplicate imported blueprint group label '{conflict.label}'"
    | .author => s!"Duplicate imported blueprint author id '{conflict.label}'"
  let reasons := conflict.reasons.foldl (fun message reason => message ++ "\n" ++ reason) heading
  if conflict.modules.isEmpty then reasons else
    reasons ++ "\nContributing modules: " ++ String.intercalate ", " (conflict.modules.toList.map toString)

private def pushUnique [BEq α] (values : Array α) (value : α) : Array α :=
  if values.contains value then values else values.push value

private def pushImportedConflict (conflicts : Array ImportedConflict)
    (kind : ImportedConflictKind) (label : Name)
    (reasons : Array String := #[]) (modules : Array Name := #[]) : Array ImportedConflict :=
  let sortModules (modules : Array Name) := modules.qsort (fun a b => a.toString < b.toString)
  if conflicts.any (fun conflict => conflict.kind == kind && conflict.label == label) then
    conflicts.map fun conflict =>
      if conflict.kind == kind && conflict.label == label then
        { conflict with
          reasons := reasons.foldl pushUnique conflict.reasons
          modules := sortModules (modules.foldl pushUnique conflict.modules) }
      else conflict
  else
    conflicts.push { kind, label, reasons, modules := sortModules modules }

private def sortImportedConflicts (conflicts : Array ImportedConflict) : Array ImportedConflict :=
  conflicts.qsort fun a b =>
    ImportedConflictKind.rank a.kind < ImportedConflictKind.rank b.kind ||
      (ImportedConflictKind.rank a.kind == ImportedConflictKind.rank b.kind &&
        a.label.toString < b.label.toString)

inductive Entry where
  | node (label origin contributor : Name) (contributions : Array NodeContribution)
  | group (label : Name) (header : String)
  | author (label : Name) (info : AuthorInfo)
deriving Inhabited, Repr

private def pushLabelUnique (labels : Array Label) (label : Label) : Array Label :=
  if labels.contains label then labels else labels.push label

private def addLeanDeclLabel
    (leanNameLabels : NameMap (Array Label)) (decl label : Name) : NameMap (Array Label) :=
  let decl := decl.eraseMacroScopes
  let labels := leanNameLabels.getD decl #[]
  leanNameLabels.insert decl (pushLabelUnique labels label)

private def addNodeLeanDeclLabels
    (leanNameLabels : NameMap (Array Label)) (label : Name) (node : Node) :
    NameMap (Array Label) :=
  node.leanDecls.foldl (init := leanNameLabels) fun acc decl =>
    addLeanDeclLabel acc decl label

/-- Commit all node stores together only after the shared reducer accepts the registration. -/
private def State.addNode (state : State) (label origin contributor : Name)
    (contributions : Array NodeContribution) (isLocal : Bool) : Except (Array String) State := do
  if let some previousOrigin := state.nodeOrigins.get? label then
    if previousOrigin != origin then
      throw #[s!"Label {label} was independently introduced in '{previousOrigin}' and '{origin}'"]
  let node ← (state.data.getD label {}).applyContributions label contributions
  return { state with
    data := state.data.insert label node
    nodeOrigins := state.nodeOrigins.insert label origin
    nodeModules := state.nodeModules.insert label
      (pushUnique (state.nodeModules.getD label #[]) contributor)
    leanNameLabels := addNodeLeanDeclLabels state.leanNameLabels label node
    localContributions := if isLocal then
      state.localContributions.insert label
        (state.localContributions.getD label #[] ++ contributions)
      else state.localContributions }

private def State.addEntry (state : State) (entry : Entry) (isLocal : Bool) : State :=
  match entry with
  | .node label origin contributor contributions =>
    match state.addNode label origin contributor contributions isLocal with
    | .ok state => state
    | .error reasons =>
      { state with
        importedConflicts := pushImportedConflict state.importedConflicts .node label
          reasons (pushUnique (state.nodeModules.getD label #[]) contributor) }
  | .group label header =>
    if state.groups.contains label then
      { state with importedConflicts := pushImportedConflict state.importedConflicts .group label }
    else
      { state with
        groups := state.groups.insert label header
        localGroups := if isLocal then state.localGroups.insert label header else state.localGroups }
  | .author label info =>
    if state.authors.contains label then
      { state with importedConflicts := pushImportedConflict state.importedConflicts .author label }
    else
      { state with
        authors := state.authors.insert label info
        localAuthors := if isLocal then state.localAuthors.insert label info else state.localAuthors }

initialize informalExt : PersistentEnvExtension Entry Entry State ←
  registerPersistentEnvExtension {
    mkInitial := pure {}
    addEntryFn state entry := state.addEntry entry true
    addImportedFn entries := do
      let state := entries.foldl (init := ({} : State)) fun state entries =>
        entries.foldl (init := state) fun state entry => state.addEntry entry false
      pure { state with importedConflicts := sortImportedConflicts state.importedConflicts }
    -- Export only local contributions, retaining the original label's module.
    exportEntriesFnEx env := fun state =>
      let compact (payload : InformalBody) :=
        if payload.previewBlocks.isEmpty then payload else { payload with elabStx := #[] }
      let nodeEntries := state.localContributions.toArray.map fun (name, contributions) =>
        let contributions := contributions.map fun contribution =>
          { contribution with
            statementBody := contribution.statementBody.map compact
            proofBody := contribution.proofBody.map compact }
        match state.nodeOrigins.get? name with
        | some origin => Entry.node name origin env.mainModule contributions
        | none => panic! s!"Blueprint invariant violated: local contributions for {name} have no origin"
      let groupEntries := state.localGroups.toArray.map fun (label, header) =>
        Entry.group label header
      let authorEntries := state.localAuthors.toArray.map fun (label, info) =>
        Entry.author label info
      OLeanEntries.uniform (nodeEntries ++ groupEntries ++ authorEntries)
  }

section EnvOps

variable [Monad m] [MonadEnv m] [MonadLog m] [AddMessageContext m] [MonadOptions m]

def modify (f : State -> State) : m Unit :=
  modifyEnv (informalExt.modifyState · f)

def modifyM (f : State -> m State) : m Unit := do
  let st := informalExt.getState (← getEnv)
  let st ← f st
  modifyEnv (informalExt.setState · st)

def importedConflicts : m (Array ImportedConflict) := do
  return (informalExt.getState (← getEnv)).importedConflicts

def reportImportedConflicts : m Unit := do
  modifyM fun state => do
    if state.importedConflictsReported || state.importedConflicts.isEmpty then
      return state
    for conflict in state.importedConflicts do
      logError conflict.message
    return { state with importedConflictsReported := true }

/-- Apply and persist only the locally supplied fields of a node registration. -/
def contribute (label : Label) (contribution : NodeContribution) : m Unit := do
  reportImportedConflicts
  let mainModule ← getMainModule
  modifyM fun state => do
    match state.addNode label (state.nodeOrigins.getD label mainModule) mainModule #[contribution] true with
    | .ok state => return state
    | .error reasons =>
      for reason in reasons do logError reason
      return state

def checkLabelAndNesting (label : Label) (kind : Data.InProgressKind) : m Bool := do
  let { data, stack, .. } := informalExt.getState (← getEnv)
  match (kind, data.get? label, stack.isEmpty) with
  | (.statement _, none, true) => return true
  | (.statement _, some node, true) =>
    let statementCanBeFilled :=
      match node.statement with
      | none => true
      | some statement => !statement.hasBody
    if statementCanBeFilled then
      return true
    else do
      logError m!"Label {label} already defined"
      return false
  | (.proof, some node, true) =>
    let proofCanBeFilled :=
      match node.proof with
      | none => true
      | some proof => !proof.hasBody
    if !proofCanBeFilled then
      logError m!"Label {label} already has a proof"
      return false
    else if node.statement.isNone then
      logError m!"Cannot add proof for {label}: statement/dependencies are missing"
      return false
    else
      return true
  | (.proof, none, true) =>
    logError m!"Cannot find proof for label {label}"
    return false
  | (_, _, false) =>
    logError m!"Cannot declare nested definitions"
    return false

-- stack operators, to associate {uses} role to the currently opened label
def push (label : Label) (kind : Data.InProgressKind)
    (codeHint : Option CodeRef := none) (parent : Option Parent := none) (priority : Option String := none)
    (owner : Option AuthorId := none) (tags : Array String := #[]) (effort : Option String := none)
    (prUrl : Option String := none) (useRefs : Array UseRef := #[]) : m Bool := do
  reportImportedConflicts
  let ok ← checkLabelAndNesting label kind
  if !ok then
    return false
  modify fun data =>
    let pdata := { label, kind, codeHint, parent, priority, owner, tags, effort, prUrl, deps := useRefs }
    { data with stack := pdata :: data.stack }
  return true

/-- When unwinding a nested declaration, discard only the nested frame and keep `data` unchanged. -/
def State.popNested? (state : State) : Option State :=
  match state.stack with
  | _ :: stack =>
    if stack.isEmpty then
      none
    else
      some { state with stack }
  | [] => none

def pop (ref : Syntax) : m Nat := do
  let state := informalExt.getState (← getEnv)
  let label? := state.stack.head?.map (·.label)
  if let some nested := state.popNested? then
    modify fun _ => nested
  else
    match state.stack with
    | [] => logError m!"Internal Error: closing non-opened directive"
    | cur :: stack =>
      let payload : InformalBody := {
        stx := ref
        previewBlocks := cur.previewBlocks
      }
      let contribution : NodeContribution := {
        kind := match cur.kind with | .statement kind => some kind | .proof => none
        count := match cur.kind with | .statement _ => state.data.nextCount | .proof => 0
        statementBody := match cur.kind with | .statement _ => some payload | .proof => none
        proofBody := match cur.kind with | .statement _ => none | .proof => some payload
        statementUses := match cur.kind with | .statement _ => cur.deps | .proof => #[]
        proofUses := match cur.kind with | .statement _ => #[] | .proof => cur.deps
        leanCode := cur.codeHint.toArray
        parent := cur.parent
        priority := cur.priority
        owner := cur.owner
        tags := cur.tags
        effort := cur.effort
        prUrl := cur.prUrl
      }
      contribute cur.label contribution
      modify fun state => { state with stack }
  let state := informalExt.getState (← getEnv)
  match label? with
  | some label =>
    return (state.data.get? label).map (·.count) |>.getD state.data.size
  | none => return state.data.size

def peek : m (Option InProgress) := do
  return (informalExt.getState (← getEnv)).stack.head?

def stack : m (List InProgress) := do
  return (informalExt.getState (← getEnv)).stack

def addUse (stx : Syntax) (useRef : UseRef) : m Unit := do
  match (informalExt.getState (← getEnv)).stack with
  | [] =>
    logErrorAt stx m!"uses declaration outside an informal enviroment"
    pure ()
  | cur :: rest =>
    let cur := {
      cur with
        deps := cur.deps.push useRef
    }
    let stack := cur :: rest
    modify fun state => { state with stack }

def addDep (stx : Syntax) (dep : Name) : m Unit := do
  addUse stx { label := dep }

def setPreviewBlocks (blocks : Array (Verso.Doc.Block Verso.Genre.Manual)) : m Unit := do
  match (informalExt.getState (← getEnv)).stack with
  | [] => pure ()
  | cur :: rest =>
    let cur := { cur with previewBlocks := blocks }
    modify fun state => { state with stack := cur :: rest }

def registerCode (label : Label) (code : Syntax)
    (definedDefs : Array LiterateDef := #[]) (definedTheorems : Array LiterateThm := #[]) : m Unit :=
  contribute label { leanCode := #[.literate { stx := code, definedDefs, definedTheorems }] }

def registerRustCode (label : Label) (code : RustInlineCode) : m Unit :=
  contribute label { rustCode := some code }

def registerExternalMarkup (label : Label) (markup : ExternalMarkup) : m Unit :=
  contribute label { externalMarkup := ({} : ExternalMarkupSet).insert markup }

def getNode? (label : Label) : m (Option Node) := do
  return (informalExt.getState (← getEnv)).data.get? label

def labelsForLeanDecl (decl : Name) : m (Array Label) := do
  return (informalExt.getState (← getEnv)).leanNameLabels.getD decl.eraseMacroScopes #[]

def registerGroup (label : Label) (header : String) : m Unit := do
  reportImportedConflicts
  let header := header.trimAscii.toString
  modifyM fun state => do
    match state.groups.get? label with
    | none =>
      return {
        state with
        groups := state.groups.insert label header
        localGroups := state.localGroups.insert label header
      }
    | some currentHeader =>
      if currentHeader = header then
        logWarning m!"Group {label} is declared multiple times with the same header; keeping '{currentHeader}'"
      else
        logError m!"Group {label} has conflicting headers: existing '{currentHeader}', new '{header}'"
      return state

def getAuthor? (label : AuthorId) : m (Option AuthorInfo) := do
  return (informalExt.getState (← getEnv)).authors.get? label

def registerAuthor (label : AuthorId) (info : AuthorInfo) : m Unit := do
  reportImportedConflicts
  let info := {
    info with
      displayName := info.displayName.trimAscii.toString
      url := info.url.map (·.trimAscii.toString)
      imageUrl := info.imageUrl.map (·.trimAscii.toString)
  }
  modifyM fun state => do
    match state.authors.get? label with
    | none =>
      return {
        state with
        authors := state.authors.insert label info
        localAuthors := state.localAuthors.insert label info
      }
    | some currentInfo =>
      if currentInfo = info then
        logWarning m!"Author {label} is declared multiple times with the same metadata; keeping '{currentInfo.displayName}'"
      else
        logError m!"Author {label} has conflicting metadata definitions"
      return state

end EnvOps
