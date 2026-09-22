/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean.CoreM
import Lean.EnvExtension
import VersoManual
import VersoBlueprint.Data
import VersoBlueprint.NodeAssembly

namespace Informal.Environment

open Lean
open Informal.Data
open Informal.Contributions

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

private def pushUnique [BEq α] (values : Array α) (value : α) : Array α :=
  if values.contains value then values else values.push value

/-- All pending legacy inputs and their provenance for one Blueprint label. -/
structure PendingNode where
  legacy : Array NodeContribution := #[]
  /-- The local subset is exported; imported legacy inputs remain evidence only. -/
  localLegacy : Array NodeContribution := #[]
  /-- First contributor, unless an authored contribution establishes an origin. -/
  origin : Name := .anonymous
  contributors : Array Name := #[]
  authoredOrigin? : Option Name := none
  authoredOriginConflict : Bool := false
deriving Inhabited, Repr

private def PendingNode.append (pending : PendingNode) (incomingOrigin contributor : Name)
    (incoming : Array NodeContribution) (isLocal authored : Bool) : PendingNode :=
  let origin := if pending.contributors.isEmpty then incomingOrigin else pending.origin
  let authoredOriginConflict := pending.authoredOriginConflict ||
    (authored && pending.authoredOrigin?.any (· != incomingOrigin))
  { pending with
    legacy := pending.legacy ++ incoming
    localLegacy := if isLocal then pending.localLegacy ++ incoming else pending.localLegacy
    origin
    contributors := pushUnique pending.contributors contributor
    authoredOrigin? := if authored then pending.authoredOrigin? <|> some incomingOrigin else pending.authoredOrigin?
    authoredOriginConflict }

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
  /-- Pending legacy payloads and all label-local provenance, including rejected imports. -/
  pendingNodes : NameMap PendingNode := {}
  /-- Complete identified selected-fact evidence, including imported records. -/
  factRecords : List Record := []
  /-- Current-module selected facts, exported without rewriting producer identity. -/
  localFactRecords : List Record := []
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
    (facts : List Record := []) (authored : Bool := false)
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

private def addNodeLeanDeclLabels
    (leanNameLabels : NameMap (Array Label)) (label : Name) (node : Node) :
    NameMap (Array Label) :=
  node.leanDecls.foldl (init := leanNameLabels) fun acc decl => addLeanDeclLabel acc decl label

private def claimsAuthoredNode (contribution : NodeContribution) : Bool :=
  contribution.kind.isSome || contribution.statementBody.any (·.hasBody) || contribution.proofBody.any (·.hasBody)

/-- Commit all node stores together only after the shared reducer accepts the registration. -/
private def State.addNode (state : State) (label origin contributor : Name)
    (incoming : Array NodeContribution) (facts : List Record) : Except (Array String) State := do
  let authored := incoming.any claimsAuthoredNode
  let pending := (state.pendingNodes.getD label {}).append origin contributor incoming true authored
  if pending.authoredOriginConflict then
    throw #[s!"Label {label} was independently introduced by authored contributions"]
  let records := facts.foldl (fun records record => collector.insert record records) state.factRecords
  let assembled ← NodeAssembly.assemble label pending.legacy records
  let node := assembled.node
  let nodeOrigin := pending.authoredOrigin?.getD pending.origin
  let registered : RegisteredNode := {
    toNode := node
    origin := nodeOrigin
    modules := pending.contributors }
  return { state with
    data := state.data.insert label registered
    nextCount := max state.nextCount (node.count + 1)
    leanNameLabels := addNodeLeanDeclLabels state.leanNameLabels label node
    pendingNodes := state.pendingNodes.insert label pending
    factRecords := records
    localFactRecords := facts.foldl (fun records record => collector.insert record records) state.localFactRecords
    }

/-- Resolve every imported label against the complete decoded evidence set. -/
private def State.reassembleImported (state : State) : State := Id.run do
  let mut data : NameMap RegisteredNode := {}
  let mut leanNameLabels : NameMap (Array Label) := {}
  let mut nextCount := 1
  let mut conflicts := state.importedConflicts
  for (label, pending) in state.pendingNodes.toArray do
    if pending.authoredOriginConflict then
      let origins := pending.contributors
      conflicts := pushImportedConflict conflicts .node label
        #[s!"Label {label} was independently introduced by authored contributions"] origins
    else match NodeAssembly.assemble label pending.legacy state.factRecords with
    | .ok assembled =>
      let node := assembled.node
      let origin := pending.authoredOrigin?.getD pending.origin
      let modules := pending.contributors
      data := data.insert label { toNode := node, origin, modules }
      nextCount := max nextCount (node.count + 1)
      leanNameLabels := addNodeLeanDeclLabels leanNameLabels label node
    | .error reasons =>
      conflicts := pushImportedConflict conflicts .node label reasons
        pending.contributors
  return { state with data, leanNameLabels, nextCount, importedConflicts := sortImportedConflicts conflicts }

/-- Decode imports as raw evidence; resolution and node diagnostics happen once below. -/
private def State.collectImportedEntry (state : State) : Entry → State
  | .node label origin contributor contributions facts authored =>
    let pending := (state.pendingNodes.getD label {}).append origin contributor contributions false authored
    let records := facts.foldl (fun records record => collector.insert record records) state.factRecords
    { state with
      pendingNodes := state.pendingNodes.insert label pending
      factRecords := records
      }
  | .blueprintAttributeLabel moduleName label =>
    { state with
      blueprintAttributeLabelsByModule :=
        addBlueprintAttributeLabel state.blueprintAttributeLabelsByModule moduleName label }
  | .group label header =>
    if state.groups.contains label then
      { state with importedConflicts := pushImportedConflict state.importedConflicts .group label }
    else
      { state with groups := state.groups.insert label header }
  | .author label info =>
    if state.authors.contains label then
      { state with importedConflicts := pushImportedConflict state.importedConflicts .author label }
    else
      { state with authors := state.authors.insert label info }

initialize informalExt : PersistentEnvExtension Entry Empty State ←
  registerPersistentEnvExtension {
    mkInitial := pure {}
    addEntryFn _ impossible := nomatch impossible
    addImportedFn entries := do
      let state := entries.foldl (init := ({} : State)) fun state entries =>
        entries.foldl (init := state) fun state entry => state.collectImportedEntry entry
      pure state.reassembleImported
    -- Export only local contributions, retaining the original label's module.
    exportEntriesFnEx env := fun state =>
      let compact (payload : InformalBody) :=
        if payload.previewBlocks.isEmpty then payload else { payload with elabStx := #[] }
      let nodeEntries := state.pendingNodes.toArray.filterMap fun (name, pending) =>
        if pending.localLegacy.isEmpty then none else some <| (name, pending)
      let nodeEntries := nodeEntries.map fun (name, pending) =>
        let contributions := pending.localLegacy
        let contributions := contributions.map fun contribution =>
          { contribution with
            statementBody := contribution.statementBody.map compact
            proofBody := contribution.proofBody.map compact }
        match state.data.get? name with
        | some node =>
          let facts := state.localFactRecords.filter (fun record => record.label == name)
          Entry.node name (pending.authoredOrigin?.getD node.origin) env.mainModule
            contributions facts (contributions.any claimsAuthoredNode)
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
  modify fun state => {
    state with
    blueprintAttributeLabelsByModule :=
      addBlueprintAttributeLabel state.blueprintAttributeLabelsByModule moduleName label.eraseMacroScopes
    localBlueprintAttributeLabelsByModule :=
      addBlueprintAttributeLabel state.localBlueprintAttributeLabelsByModule moduleName label.eraseMacroScopes }

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

/-- Commit one checked registration after its admission inputs have been validated. -/
private def commitContribution (label : Label) (contribution : NodeContribution) (facts : List Record) :
    m (Option Node) := do
  let mainModule ← getMainModule
  let state := informalExt.getState (← getEnv)
  let origin := (state.pendingNodes.getD label {}).authoredOrigin?.getD mainModule
  match state.addNode label origin mainModule #[contribution] facts with
  | .ok state =>
    modifyEnv (informalExt.setState · state)
    return (state.data.get? label).map (·.toNode)
  | .error reasons =>
    for reason in reasons do logError reason
    return none

/-- Register a legacy-only payload under an explicit label. -/
def contribute (label : Label) (contribution : NodeContribution) : m (Option Node) := do
  reportImportedConflicts
  if contribution.hasSelectedFields then
    logError m!"Blueprint legacy payload cannot include external references or priority; supply them only in a contribution record"
    return none
  commitContribution label contribution []

/--
Register a producer-identified selected record with a legacy-only payload.
The record is the sole owner of the selected label, external references, and priority.
-/
def contributeRecord (fact : Record) (contribution : NodeContribution) :
    m (Option Node) := do
  reportImportedConflicts
  if contribution.hasSelectedFields then
    logError m!"Blueprint legacy payload cannot include external references or priority; supply them only in a contribution record"
    return none
  commitContribution fact.label contribution [fact]

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
  leanCode := current.codeHint.toArray.filter fun code =>
    match code with | .external _ => false | .literate _ => true
  parent := current.parent
  owner := current.owner
  tags := current.tags
  effort := current.effort
  prUrl := current.prUrl
}

private def CodeRef.externalReferences : CodeRef → Array ExternalRef
  | .external references => references
  | .literate _ => #[]

private def InProgress.selectedFact? (current : InProgress) (ref : Syntax) : CoreM (Option Record) := do
  let references := current.codeHint.map CodeRef.externalReferences |>.getD #[]
  if references.isEmpty && current.priority.isNone then
    return none
  let some position := ref.getPos?
    | throwError "Blueprint selected contributions require a stable source position"
  let source ← Data.SourceLocation.ofSyntax? ref
  return some {
    id := {
      moduleName := ← getMainModule
      producer := `blueprint.directive
      subject := current.label
      site := position.byteIdx
      slot := 0 }
    label := current.label
    references
    priority := current.priority
    source }

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
          let contribution := current.toContribution state.nextCount ref blocks
          let fact? ← liftM <| current.selectedFact? ref
          let node? ← match fact? with
            | some fact => contributeRecord fact contribution
            | none => contribute frame.label contribution
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
