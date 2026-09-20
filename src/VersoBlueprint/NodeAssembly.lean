/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Contributions

/-! The narrow assembly layer combines legacy node payloads with the proved
external-association/priority slice.  It deliberately does not import the
environment extension or rendering consumers. -/

namespace Informal.NodeAssembly

open Lean Informal.Data Informal.Contributions

private abbrev MergeM := StateM (Array String)

private def conflict (message : String) : MergeM Unit := modify (·.push message)

private def mergeMetadata [BEq α] [ToString α] (label : Label) (field : String)
    (current incoming : Option α) : MergeM (Option α) := do
  match current, incoming with
  | none, _ => return incoming
  | _, none => return current
  | some existing, some value =>
    if existing != value then
      conflict s!"Label {label} declares conflicting {field}: existing '{existing}', new '{value}'"
    return current

private def mergeUses (label : Label) (side : String)
    (current incoming : Array UseRef) : MergeM (Array UseRef) := do
  let mut uses := current
  for ref in incoming do
    if let some previous := uses.find? (fun previous =>
        previous.label == ref.label && previous.origin == ref.origin) then
      if previous.intent != ref.intent then
        conflict s!"Label {label} declares conflicting {side} dependency intents for '{ref.label}' ({ref.origin}): existing '{previous.intent}', new '{ref.intent}'"
    else uses := uses.push ref
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
  | none => return if useDeclarations.isEmpty then none else some { stx := .missing, useDeclarations }

private def mergeExternalRefs (current incoming : Array ExternalRef) : Array ExternalRef := Id.run do
  let mut positions : NameMap Nat := {}
  for i in [:current.size] do positions := positions.insert current[i]!.canonical i
  let mut refs := current
  for ref in incoming do
    let ref := { ref with canonical := ref.canonical.eraseMacroScopes }
    match positions.get? ref.canonical with
    | some i => if !refs[i]!.present && ref.present then refs := refs.set! i ref
    | none => positions := positions.insert ref.canonical refs.size; refs := refs.push ref
  return refs

private def inferredNodeKind (external : Array ExternalRef) (literate : Array Code) : NodeKind :=
  if external.any (·.kind.isTheoremLike) || literate.any (! ·.definedTheorems.isEmpty) then .theorem
  else if !external.isEmpty || literate.any (! ·.definedDefs.isEmpty) then .definition else .lemma

private def mergeContribution (label : Label) (node : Node)
    (incoming : NodeContribution) : MergeM Node := do
  let statement ← mergePayload label "statement" node.statement incoming.statementBody incoming.statementUses
  let proof ← mergePayload label "proof" node.proof incoming.proofBody incoming.proofUses
  let mut rustCode := node.rustCode
  if let some code := incoming.rustCode then
    if rustCode.isSome then conflict s!"Label {label} already has associated Rust code" else rustCode := some code
  let mut externalMarkup := node.externalMarkup
  for markup in incoming.externalMarkup.toArray do
    let key := markup.key
    if externalMarkup.contains key then
      conflict s!"Label {label} already has associated {key.language} external markup in slot '{key.slot}'"
    else externalMarkup := externalMarkup.insert markup
  let parent ← mergeMetadata label "parents" node.parent incoming.parent
  let owner ← mergeMetadata label "owners" node.owner incoming.owner
  let effort ← mergeMetadata label "effort values" node.effort incoming.effort
  let prUrl ← mergeMetadata label "PR URLs" node.prUrl incoming.prUrl
  let externalRefs := node.externalRefs
  let mut literateCodes := node.literateCodes
  for code in incoming.leanCode do
    match code with
    | .external _ => pure ()
    | .literate code => literateCodes := literateCodes.push code
  let kindIsExplicit := node.kindIsExplicit || incoming.kind.isSome
  let kind ← match incoming.kind with
    | some kind =>
      if node.kindIsExplicit && node.kind != kind then
        conflict s!"Label {label} declares conflicting statement kinds: existing '{node.kind}', new '{kind}'"
      pure kind
    | none => pure <| if node.kindIsExplicit then node.kind else inferredNodeKind externalRefs literateCodes
  return {
    kind, kindIsExplicit
    count := if node.count == 0 then incoming.count else node.count
    statement, proof, rustCode, externalMarkup, parent, priority := node.priority, owner, effort, prUrl
    externalRefs, literateCodes
    tags := incoming.tags.foldl (fun tags tag => if tags.contains tag then tags else tags.push tag) node.tags }

/-- The legacy reducer is retained for body/kind/markup and non-migrated callers. -/
def applyLegacy (label : Label) (node : Node)
    (contributions : Array NodeContribution) : Except (Array String) Node :=
  let (node, errors) := (contributions.foldlM (mergeContribution label) node).run #[]
  if errors.isEmpty then .ok node else .error errors

end Informal.NodeAssembly

namespace Informal.Data

/--
Pure checked legacy reducer. Its implementation lives in `NodeAssembly` so the
environment can combine it with the selected-fact resolver without a Data ↔
Contributions cycle.
-/
def Node.applyContributions (label : Label) (node : Node)
    (contributions : Array NodeContribution) : Except (Array String) Node :=
  Informal.NodeAssembly.applyLegacy label node contributions

end Informal.Data

namespace Informal.NodeAssembly

open Lean Informal.Data Informal.Contributions

/-- Remove fields whose admission is owned by a selected contribution record. -/
def withoutSelectedFacts (contribution : NodeContribution) : NodeContribution :=
  { contribution with
    priority := none
    leanCode := contribution.leanCode.filter fun code =>
      match code with | .external _ => false | .literate _ => true }

private def recordMessage (record : Record) : String :=
  let refs := String.intercalate ", " (record.references.toList.map fun ref => ref.canonical.toString)
  s!"{record.id.moduleName}.{record.id.producer}:{record.id.subject}@{record.id.site}/{record.id.slot} label={record.label} refs=[{refs}] priority={record.priority}"

private def diagnosticMessages (label : Label) (diagnostics : Diagnostics) : Array String :=
  let idKey := fun id : ContributionId =>
    s!"{id.moduleName.toString}/{id.producer.toString}/{id.subject.toString}/{id.site}/{id.slot}"
  let collisions := diagnostics.collisions.toArray.qsort fun a b => idKey a.1 < idKey b.1
  let priorities := diagnostics.priorityConflict.toArray.qsort fun a b => a.1 < b.1
  let supportKey := fun record : Record =>
    s!"{idKey record.id}/{record.label.toString}/" ++
      String.intercalate "," (record.references.toList.map fun ref => ref.canonical.toString) ++
      s!"/{record.priority}"
  let supportOrder := fun (a b : Record) => decide <| supportKey a < supportKey b
  let collisionMessages := collisions.flatMap fun (id, supports) =>
    #[s!"Label {label} has conflicting contribution identity {id.moduleName}.{id.producer}:{id.subject} at {id.site}/{id.slot}"] ++
      ((supports.toArray.qsort supportOrder).map recordMessage)
  let priorityMessages := priorities.flatMap fun (value, supports) =>
    #[s!"Label {label} declares conflicting priorities including '{value}'"] ++
      ((supports.toArray.qsort supportOrder).map recordMessage)
  collisionMessages ++ priorityMessages

/--
Assemble one complete node atomically. Selected records are resolved exactly once;
their accepted projection supplies external references and priority, while the
legacy reducer retains body, kind, markup, dependency, and literate policies.
-/
structure Assembly where
  node : Node
  view : View

def assemble (label : Label) (legacy : Array NodeContribution) (records : List Record) :
    Except (Array String) Assembly := do
  let node ← Node.applyContributions label {} legacy
  match resolve label records with
  | .error result => throw (diagnosticMessages label result)
  | .ok view =>
    let externalRefs := view.supports.foldl (fun refs record => mergeExternalRefs refs record.references) #[]
    let kind := if node.kindIsExplicit then node.kind else inferredNodeKind externalRefs node.literateCodes
    return { node := { node with externalRefs, priority := view.priority, kind }, view }

end Informal.NodeAssembly
