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
Elaboration-time builder for the single currently open directive.

This stays separate from `Data.Node`: it collects authored metadata and uses
before the final checked contribution is assembled.
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
  proofUses : Array UseRef := #[]
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

/-- A checked node and the module provenance of its accepted contributions. -/
structure RegisteredNode extends Node where
  origin : Name
  modules : Array Name := #[]
deriving Inhabited, Repr

instance : Coe RegisteredNode Node := ⟨RegisteredNode.toNode⟩

/-- Unique module catalog in attribute-application order, with indexed membership. -/
structure AttributeLabelCatalog where
  labels : Array Label := #[]
  members : NameSet := {}
deriving Inhabited, Repr

def AttributeLabelCatalog.insert (catalog : AttributeLabelCatalog) (label : Label) :
    AttributeLabelCatalog :=
  if catalog.members.contains label then catalog
  else { labels := catalog.labels.push label, members := catalog.members.insert label }

/--
Persisted semantic state collected during elaboration.

Rendered traversal stores project from this state and add site-local facts such
as numbering, hrefs, preview ids, and HTML-cache keys. Keep those traversal
facts out of this environment extension unless they become stable semantic
data.
-/
structure State where
  data : NameMap RegisteredNode := {}
  /-- Next elaboration number, advanced only by accepted registrations and import replay. -/
  nextCount : Nat := 1
  /-- Only registrations made in this module, in registration order per label. -/
  localContributions : NameMap (Array NodeContribution) := {}
  /-- Labels with attribute applications in each module, in application order. -/
  blueprintAttributeLabelsByModule : NameMap AttributeLabelCatalog := {}
  /-- Current-module subset exported through the persistent extension. -/
  localBlueprintAttributeLabelsByModule : NameMap AttributeLabelCatalog := {}
  groups : NameMap String := {}
  localGroups : NameMap String := {}
  authors : NameMap AuthorInfo := {}
  localAuthors : NameMap AuthorInfo := {}
  leanNameLabels : NameMap (Array Label) := {}
  importedConflicts : Array ImportedConflict := #[]
  importedConflictsReported : Bool := false
  /-- At most one directive can be open; nested declarations are rejected. -/
  activeDirective : Option InProgress := none
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
  | blueprintAttributeLabel (moduleName : Name) (label : Label)
  | group (label : Name) (header : String)
  | author (label : Name) (info : AuthorInfo)
deriving Inhabited, Repr

private def addBlueprintAttributeLabel
    (modules : NameMap AttributeLabelCatalog) (moduleName : Name) (label : Label) :
    NameMap AttributeLabelCatalog :=
  modules.insert moduleName <|
    (modules.getD moduleName {}).insert label

private def addLeanDeclLabel
    (leanNameLabels : NameMap (Array Label)) (decl label : Name) : NameMap (Array Label) :=
  let decl := decl.eraseMacroScopes
  let labels := leanNameLabels.getD decl #[]
  leanNameLabels.insert decl (Label.pushUnique labels label)

private def addContributionLeanDeclLabels
    (leanNameLabels : NameMap (Array Label)) (label : Name) (contributions : Array NodeContribution) :
    NameMap (Array Label) :=
  contributions.foldl (init := leanNameLabels) fun acc contribution =>
    contribution.leanCode.foldl (init := acc) fun acc code =>
      code.leanDecls.foldl (init := acc) fun acc decl => addLeanDeclLabel acc decl label

/-- Commit all node stores together only after the shared reducer accepts the registration. -/
private def State.addNode (state : State) (label origin contributor : Name)
    (contributions : Array NodeContribution) (isLocal : Bool) : Except (Array String) State := do
  let previous := state.data.get? label
  if let some previous := previous then
    if previous.origin != origin then
      throw #[s!"Label {label} was independently introduced in '{previous.origin}' and '{origin}'"]
  let node ← (previous.map RegisteredNode.toNode |>.getD {}).applyContributions label contributions
  let registered : RegisteredNode := {
    toNode := node
    origin
    modules := pushUnique (previous.map (·.modules) |>.getD #[]) contributor }
  return { state with
    data := state.data.insert label registered
    nextCount := max state.nextCount (node.count + 1)
    leanNameLabels := addContributionLeanDeclLabels state.leanNameLabels label contributions
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
          reasons (pushUnique ((state.data.get? label).map (·.modules) |>.getD #[]) contributor) }
  | .blueprintAttributeLabel moduleName label =>
    { state with
      blueprintAttributeLabelsByModule :=
        addBlueprintAttributeLabel state.blueprintAttributeLabelsByModule moduleName label
      localBlueprintAttributeLabelsByModule := if isLocal then
        addBlueprintAttributeLabel state.localBlueprintAttributeLabelsByModule moduleName label
        else state.localBlueprintAttributeLabelsByModule }
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
        match state.data.get? name with
        | some node => Entry.node name node.origin env.mainModule contributions
        | none => panic! s!"Blueprint invariant violated: local contributions for {name} have no origin"
      let attributeLabelEntries :=
        state.localBlueprintAttributeLabelsByModule.toArray.flatMap fun (moduleName, labels) =>
          labels.labels.map (Entry.blueprintAttributeLabel moduleName)
      let groupEntries := state.localGroups.toArray.map fun (label, header) =>
        Entry.group label header
      let authorEntries := state.localAuthors.toArray.map fun (label, info) =>
        Entry.author label info
      OLeanEntries.uniform
        (nodeEntries ++ attributeLabelEntries ++ groupEntries ++ authorEntries)
  }

section EnvOps

variable [Monad m] [MonadEnv m] [MonadLog m] [AddMessageContext m] [MonadOptions m]

def modify (f : State -> State) : m Unit :=
  modifyEnv (informalExt.modifyState · f)

def modifyM (f : State -> m State) : m Unit := do
  let st := informalExt.getState (← getEnv)
  let st ← f st
  modifyEnv (informalExt.setState · st)

/-- Record a successful attribute registration in module application order. -/
def registerBlueprintAttributeLabel (label : Label) : m Unit := do
  let moduleName := (← getEnv).mainModule
  modifyEnv fun env =>
    informalExt.addEntry env <|
      .blueprintAttributeLabel moduleName label.eraseMacroScopes

/-- Labels contributed by attributes applied in this exact module, in application order. -/
def blueprintAttributeLabelsForModule (moduleName : Name) : m (Array Label) := do
  return ((informalExt.getState (← getEnv)).blueprintAttributeLabelsByModule.getD moduleName {}).labels

def importedConflicts : m (Array ImportedConflict) := do
  return (informalExt.getState (← getEnv)).importedConflicts

def reportImportedConflicts : m Unit := do
  modifyM fun state => do
    if state.importedConflictsReported || state.importedConflicts.isEmpty then
      return state
    for conflict in state.importedConflicts do
      logError conflict.message
    return { state with importedConflictsReported := true }

/-- Apply one complete registration, returning its accepted node or diagnosed failure. -/
def contribute (label : Label) (contribution : NodeContribution) : m (Option Node) := do
  reportImportedConflicts
  let mainModule ← getMainModule
  let state := informalExt.getState (← getEnv)
  let origin := (state.data.get? label).map (·.origin) |>.getD mainModule
  match state.addNode label origin mainModule #[contribution] true with
  | .ok state =>
    modifyEnv (informalExt.setState · state)
    return (state.data.get? label).map (·.toNode)
  | .error reasons =>
    for reason in reasons do logError reason
    return none

def checkLabelAndNesting (label : Label) (kind : Data.InProgressKind) : m Bool := do
  let { data, activeDirective, .. } := informalExt.getState (← getEnv)
  match (kind, data.get? label, activeDirective.isNone) with
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

private def InProgress.toContribution (current : InProgress) (count : Nat) (ref : Syntax)
    (blocks : Array (Verso.Doc.Block Verso.Genre.Manual)) : NodeContribution := {
  kind := match current.kind with | .statement kind => some kind | .proof => none
  count := match current.kind with | .statement _ => count | .proof => 0
  statementBody := match current.kind with
    | .statement _ => some { stx := ref, previewBlocks := blocks }
    | .proof => none
  proofBody := match current.kind with
    | .statement _ => none
    | .proof => some { stx := ref, previewBlocks := blocks }
  statementUses := match current.kind with | .statement _ => current.deps | .proof => #[]
  proofUses := match current.kind with
    | .statement _ => current.proofUses
    | .proof => current.deps ++ current.proofUses
  leanCode := current.codeHint.toArray
  parent := current.parent
  priority := current.priority
  owner := current.owner
  tags := current.tags
  effort := current.effort
  prUrl := current.prUrl
}

private def hasErrorsSince [MonadLiftT CoreM m] (messageCount : Nat) : m Bool := do
  let messages := (← liftM Core.getMessageLog).reportedPlusUnreported
  return (messages.toArray.extract messageCount messages.size).any (·.severity == .error)

/--
Elaborate and register one directive as a scoped Blueprint-state transaction.
Body registrations are visible during elaboration, but rejection, logged errors,
or exceptions restore all Blueprint stores. Other Lean environment changes and
messages are retained. Every exit restores the enclosing directive scope.
-/
def withDirective [MonadExceptOf Exception m] [MonadLiftT CoreM m]
    (prepare : m InProgress) (ref : Syntax)
    (body : m (α × Array (Verso.Doc.Block Verso.Genre.Manual))) : m (Option (α × Nat)) := do
  reportImportedConflicts
  let before := informalExt.getState (← getEnv)
  let messageCount := (← liftM Core.getMessageLog).reportedPlusUnreported.size
  let result ← try
    let frame ← prepare
    if (← hasErrorsSince messageCount) || !(← checkLabelAndNesting frame.label frame.kind) then
      pure none
    else
      modify fun state => { state with activeDirective := some frame }
      let (value, blocks) ← body
      if ← hasErrorsSince messageCount then
        pure none
      else
        let state := informalExt.getState (← getEnv)
        match state.activeDirective with
        | none =>
          logError "Internal error: Blueprint directive scope was closed during elaboration"
          pure none
        | some current =>
          let node? ← contribute frame.label (current.toContribution state.nextCount ref blocks)
          pure <| node?.map fun node => (value, node.count)
  catch exception =>
    modify fun _ => before
    throw exception
  match result with
  | some _ => modify fun state => { state with activeDirective := before.activeDirective }
  | none => modify fun _ => before
  return result

def addUse (stx : Syntax) (useRef : UseRef) : m Unit := do
  match (informalExt.getState (← getEnv)).activeDirective with
  | none => logErrorAt stx m!"uses declaration outside an informal environment"
  | some current =>
    modify fun state =>
      { state with activeDirective := some { current with deps := current.deps.push useRef } }

def addDep (stx : Syntax) (dep : Name) : m Unit :=
  addUse stx { label := dep }

def getNode? (label : Label) : m (Option Node) := do
  return ((informalExt.getState (← getEnv)).data.get? label).map (·.toNode)

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
