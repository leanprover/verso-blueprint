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
  localData : NameMap Node := {}
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
  match conflict.kind with
  | .node => s!"Duplicate imported blueprint node label '{conflict.label}'"
  | .group => s!"Duplicate imported blueprint group label '{conflict.label}'"
  | .author => s!"Duplicate imported blueprint author id '{conflict.label}'"

private def pushImportedConflict (conflicts : Array ImportedConflict)
    (kind : ImportedConflictKind) (label : Name) : Array ImportedConflict :=
  let conflict : ImportedConflict := { kind, label }
  if conflicts.contains conflict then conflicts else conflicts.push conflict

private def sortImportedConflicts (conflicts : Array ImportedConflict) : Array ImportedConflict :=
  conflicts.qsort fun a b =>
    ImportedConflictKind.rank a.kind < ImportedConflictKind.rank b.kind ||
      (ImportedConflictKind.rank a.kind == ImportedConflictKind.rank b.kind &&
        a.label.toString < b.label.toString)

inductive Entry where
  | node (label : Name) (node : Node)
  | group (label : Name) (header : String)
  | author (label : Name) (info : AuthorInfo)
deriving Inhabited, Repr

private def pushLabelUnique (labels : Array Label) (label : Label) : Array Label :=
  if labels.contains label then labels else labels.push label

private def nodeLeanDecls (node : Node) : Array Name :=
  node.leanDecls

private def addLeanDeclLabel
    (leanNameLabels : NameMap (Array Label)) (decl label : Name) : NameMap (Array Label) :=
  let decl := decl.eraseMacroScopes
  let labels := leanNameLabels.getD decl #[]
  leanNameLabels.insert decl (pushLabelUnique labels label)

private def addNodeLeanDeclLabels
    (leanNameLabels : NameMap (Array Label)) (label : Name) (node : Node) :
    NameMap (Array Label) :=
  (nodeLeanDecls node).foldl (init := leanNameLabels) fun acc decl =>
    addLeanDeclLabel acc decl label

private def addRegisteredNodeLeanDeclLabels
    (leanNameLabels : NameMap (Array Label)) (data : Data) (label : Name) :
    NameMap (Array Label) :=
  match data.get? label with
  | some node => addNodeLeanDeclLabels leanNameLabels label node
  | none => leanNameLabels

private def removeLeanDeclLabel
    (leanNameLabels : NameMap (Array Label)) (label : Name) : NameMap (Array Label) :=
  leanNameLabels.foldl (init := ({} : NameMap (Array Label))) fun acc decl labels =>
    let labels := labels.filter (· != label)
    if labels.isEmpty then
      acc
    else
      acc.insert decl labels

private def reindexRegisteredNodeLeanDeclLabels
    (leanNameLabels : NameMap (Array Label)) (data : Data) (label : Name) :
    NameMap (Array Label) :=
  addRegisteredNodeLeanDeclLabels (removeLeanDeclLabel leanNameLabels label) data label

private def State.commitDataForLabel (state : State) (label : Name) (data : Data) : State :=
  let localData :=
    match data.get? label with
    | some node => state.localData.insert label node
    | none => state.localData
  let leanNameLabels := reindexRegisteredNodeLeanDeclLabels state.leanNameLabels data label
  { state with data, localData, leanNameLabels }

initialize informalExt : PersistentEnvExtension Entry Entry State ←
  registerPersistentEnvExtension {
    mkInitial := pure {}
    addEntryFn state := fun
      | .node label node =>
        { state with
          data := state.data.insert label node
          localData := state.localData.insert label node
          leanNameLabels := addNodeLeanDeclLabels state.leanNameLabels label node
        }
      | .group label header =>
        { state with
          groups := state.groups.insert label header
          localGroups := state.localGroups.insert label header
        }
      | .author label info =>
        { state with
          authors := state.authors.insert label info
          localAuthors := state.localAuthors.insert label info
        }
    addImportedFn entries := do
      let (data, groups, authors, leanNameLabels, importedConflicts) := entries.foldl
          (init := (
            ({} : NameMap Node),
            ({} : NameMap String),
            ({} : NameMap AuthorInfo),
            ({} : NameMap (Array Label)),
            (#[] : Array ImportedConflict)
          )) fun acc entry =>
        entry.foldl (init := acc) fun (dataAcc, groupAcc, authorAcc, leanNameAcc, conflictsAcc) item =>
          match item with
          | .node label node =>
            if dataAcc.contains label then
              (dataAcc, groupAcc, authorAcc, leanNameAcc, pushImportedConflict conflictsAcc .node label)
            else
              let leanNameAcc := addNodeLeanDeclLabels leanNameAcc label node
              (dataAcc.insert label node, groupAcc, authorAcc, leanNameAcc, conflictsAcc)
          | .group label header =>
            if groupAcc.contains label then
              (dataAcc, groupAcc, authorAcc, leanNameAcc, pushImportedConflict conflictsAcc .group label)
            else
              (dataAcc, groupAcc.insert label header, authorAcc, leanNameAcc, conflictsAcc)
          | .author label info =>
            if authorAcc.contains label then
              (dataAcc, groupAcc, authorAcc, leanNameAcc, pushImportedConflict conflictsAcc .author label)
            else
              (dataAcc, groupAcc, authorAcc.insert label info, leanNameAcc, conflictsAcc)
      pure { data, groups, authors, leanNameLabels, importedConflicts := sortImportedConflicts importedConflicts }
    -- Prefer typed preview blocks and strip redundant term syntax before export.
    exportEntriesFnEx env := fun state =>
      let nodeEntries := state.localData.toArray.map fun (name, node) =>
        let statement := node.statement.map fun s =>
          if s.previewBlocks.isEmpty then s else { s with elabStx := #[] }
        let proof := node.proof.map fun p =>
          if p.previewBlocks.isEmpty then p else { p with elabStx := #[] }
        Entry.node name { node with statement, proof }
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

def modifyDataForLabel (label : Label) (f : Data -> m Data) : m Unit := do
  modifyM fun state => do
    let data ← f state.data
    return state.commitDataForLabel label data

def importedConflicts : m (Array ImportedConflict) := do
  return (informalExt.getState (← getEnv)).importedConflicts

def reportImportedConflicts : m Unit := do
  modifyM fun state => do
    if state.importedConflictsReported || state.importedConflicts.isEmpty then
      return state
    for conflict in state.importedConflicts do
      logError conflict.message
    return { state with importedConflictsReported := true }

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

def getCount : m Nat := do
  return (informalExt.getState (← getEnv)).data.size

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
  let label? := (informalExt.getState (← getEnv)).stack.head?.map (·.label)
  modifyM fun state => do
    if let some state := state.popNested? then
      return state
    else
      match state.stack with
      | [] =>
        logError m!"Internal Error: closing non-opened directive"
        return state
      | cur :: stack =>
        let payload : InformalData := {
          stx := ref
          deps := cur.deps
          previewBlocks := cur.previewBlocks
        }
        let data ← state.data.register
          cur.label cur.kind payload cur.codeHint cur.parent cur.priority cur.owner cur.tags cur.effort cur.prUrl
        return { state.commitDataForLabel cur.label data with stack }
  let state := informalExt.getState (← getEnv)
  match label? with
  | some label =>
    return (state.data.get? label).map (·.count) |>.getD state.data.size
  | none =>
    return state.data.size

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
    (definedDefs : Array LiterateDef := #[]) (definedTheorems : Array LiterateThm := #[]) : m Unit := do
  modifyDataForLabel label fun data =>
    data.registerCode label code definedDefs definedTheorems

def registerRustCode (label : Label) (code : RustInlineCode) : m Unit := do
  modifyDataForLabel label fun data =>
    data.registerRustCode label code

def registerExternalMarkup (label : Label) (markup : ExternalMarkup) : m Unit := do
  modifyDataForLabel label fun data =>
    data.registerExternalMarkup label markup

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
