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
  return { node with
    kind, kindIsExplicit
    count := if node.count == 0 then incoming.count else node.count
    statement, proof, rustCode, externalMarkup, parent, owner, effort, prUrl
    literateCodes
    tags := incoming.tags.foldl (fun tags tag => if tags.contains tag then tags else tags.push tag) node.tags }

/-- Private legacy reducer for body, kind, markup, dependency, and literate payloads. -/
private def applyLegacy (label : Label) (node : Node)
    (contributions : Array NodeContribution) : Except (Array String) Node :=
  let (node, errors) := (contributions.foldlM (mergeContribution label) node).run #[]
  if errors.isEmpty then .ok node else .error errors

end Informal.NodeAssembly

namespace Informal.Data

/--
Apply body, kind, markup, dependency, and literate payloads to a node. This
public legacy API rejects priority and external-reference fields because their
admission requires an identified selected contribution record; producers should
use `Environment.contributeRecord` for those fields. Its implementation lives
in `NodeAssembly` so the environment can combine it with the selected-fact
resolver without a Data ↔ Contributions cycle.
-/
def Node.applyContributions (label : Label) (node : Node)
    (contributions : Array NodeContribution) : Except (Array String) Node :=
  if contributions.any NodeContribution.hasSelectedFields then
    .error #["Blueprint external references and priority require an identified contribution record"]
  else
    Informal.NodeAssembly.applyLegacy label node contributions

end Informal.Data

namespace Informal.NodeAssembly

open Lean Informal.Data Informal.Contributions

/-- Capability projection for consumers that need every accepted attribute association. -/
def supportsHaveBlueprintAttributeAttachments (supports : List Record) : Bool :=
  supports.any fun record => record.references.any fun ref => ref.origin == .blueprintAttr

private def recordMessage (record : Record) : String :=
  let refs := String.intercalate ", " (record.references.toList.map fun ref => ref.canonical.toString)
  s!"{record.id.moduleName}.{record.id.producer}:{record.id.subject}@{record.id.site}/{record.id.slot} label={record.label} refs=[{refs}] priority={record.priority}"

private def externalOriginMessage : ExternalOrigin → String
  | .directiveLean => "directive"
  | .blueprintAttr => "attribute"

private def provedStatusMessage : ProvedStatus → String
  | .proved => "proved"
  | .missing => "missing"
  | .axiomLike => "axiom-like"
  | .containsSorry locations => s!"contains-sorry({locations.size})"

private def externalSourceMessage (ref : ExternalRef) : String :=
  let provenance := match ref.provenance with
    | .inWorkspace moduleName sourcePath => s!"workspace:{moduleName}:{sourcePath}"
    | .outWorkspace moduleName sourcePath? =>
      s!"external:{moduleName}:{sourcePath?.getD "-"}"
    | .unknown => "unknown"
  s!"{provenance}; href={ref.sourceHref?.getD "-"}"

private def registrationSourceMessage : Option SourceLocation → String
  | none => "-"
  | some source =>
    s!"{source.path}:{source.range.start.line}:{source.range.start.character}-{source.range.end.line}:{source.range.end.character}"

private def renderStateMessage : ExternalDeclRender → String
  | .ok _ => "ok"
  | .error error => s!"error({error.message})"

private def referenceFieldMessage (references : Array ExternalRef)
    (field : ExternalRef → String) : String :=
  String.intercalate ", " (references.toList.map field)

private def collisionDifferenceMessage (first record : Record) : String := Id.run do
  let mut differences := #[]
  if first.label != record.label then
    differences := differences.push s!"label ({first.label} → {record.label})"
  if first.priority != record.priority then
    differences := differences.push s!"priority ({first.priority} → {record.priority})"
  if first.source != record.source then
    differences := differences.push
      s!"registration source ({registrationSourceMessage first.source} → {registrationSourceMessage record.source})"
  if first.references.map (·.origin) != record.references.map (·.origin) then
    let origins := referenceFieldMessage first.references (externalOriginMessage ·.origin)
    let recordOrigins := referenceFieldMessage record.references (externalOriginMessage ·.origin)
    differences := differences.push s!"origin ({origins} → {recordOrigins})"
  if first.references.map (·.present) != record.references.map (·.present) then
    let presence := referenceFieldMessage first.references (fun ref => toString ref.present)
    let recordPresence := referenceFieldMessage record.references (fun ref => toString ref.present)
    differences := differences.push s!"presence ({presence} → {recordPresence})"
  if first.references.map (fun ref => (ref.provenance, ref.sourceHref?)) !=
      record.references.map (fun ref => (ref.provenance, ref.sourceHref?)) then
    let sources := referenceFieldMessage first.references externalSourceMessage
    let recordSources := referenceFieldMessage record.references externalSourceMessage
    differences := differences.push s!"source metadata ({sources} → {recordSources})"
  if first.references.map (·.provedStatus) != record.references.map (·.provedStatus) then
    let statuses := referenceFieldMessage first.references (provedStatusMessage ·.provedStatus)
    let recordStatuses := referenceFieldMessage record.references (provedStatusMessage ·.provedStatus)
    differences := differences.push s!"status ({statuses} → {recordStatuses})"
  if first.references.map (·.render) != record.references.map (·.render) then
    differences := differences.push s!"render differs ({referenceFieldMessage first.references (renderStateMessage ·.render)} → {referenceFieldMessage record.references (renderStateMessage ·.render)})"
  if first.references != record.references && differences.isEmpty then
    differences := differences.push "reference snapshot"
  return s!"differs from first support in {String.intercalate "; " differences.toList}"

private def diagnosticMessages (label : Label) (diagnostics : Diagnostics) : Array String :=
  let idKey := fun id : ContributionId =>
    s!"{id.moduleName.toString}/{id.producer.toString}/{id.subject.toString}/{id.site}/{id.slot}"
  let collisions := diagnostics.collisions.toArray.qsort fun a b => idKey a.1 < idKey b.1
  let priorities := diagnostics.priorityConflict.toArray.qsort fun a b => a.1 < b.1
  let supportKey := fun record : Record =>
    s!"{idKey record.id}/{record.label.toString}/" ++
      String.intercalate "," (record.references.toList.map fun ref => ref.canonical.toString) ++
      s!"/{record.priority}"
  let keyedSupports := fun (supports : List Record) => supports.toArray.map fun record =>
    (supportKey record, reprStr record, record)
  let supportOrder := fun (a b : String × String × Record) =>
    a.1 < b.1 || (a.1 = b.1 && a.2.1 < b.2.1)
  let collisionMessages := collisions.flatMap fun (id, supports) =>
    #[s!"Label {label} has conflicting contribution identity {id.moduleName}.{id.producer}:{id.subject} at {id.site}/{id.slot}"] ++
      match (keyedSupports supports |>.qsort supportOrder).toList with
      | [] => #[]
      | first :: rest => #[recordMessage first.2.2] ++
        rest.toArray.map fun record =>
          s!"{recordMessage record.2.2}; {collisionDifferenceMessage first.2.2 record.2.2}"
  let priorityMessages := priorities.flatMap fun (value, supports) =>
    #[s!"Label {label} declares conflicting priorities including '{value}'"] ++
      ((keyedSupports supports |>.qsort supportOrder).map fun support => recordMessage support.2.2)
  collisionMessages ++ priorityMessages

/--
Assemble one complete node atomically. Selected records are resolved exactly once;
their accepted projection supplies external references and priority, while the
legacy reducer retains body, kind, markup, dependency, and literate policies.
On success, the node exposes the resolved priority and an attribute capability
projected from every accepted support. It does not choose a general snapshot or
claim confluence for unrelated legacy payloads.
-/
structure Assembly where
  node : Node
  view : View

private def project (node : Node) (view : View) : Assembly :=
  let externalRefs := view.supports.foldl (fun refs record => mergeExternalRefs refs record.references) #[]
  let blueprintAttributeAttachments := supportsHaveBlueprintAttributeAttachments view.supports
  let kind := if node.kindIsExplicit then node.kind else inferredNodeKind externalRefs node.literateCodes
  { node := { node with
    externalRefs := externalRefs
    blueprintAttributeAttachments := blueprintAttributeAttachments
    priority := view.priority
    kind := kind }, view }

def assemble (label : Label) (legacy : Array NodeContribution) (records : List Record) :
    Except (Array String) Assembly :=
  match Node.applyContributions label {} legacy with
  | .error errors => .error errors
  | .ok node => match resolve label records with
    | .error result => .error (diagnosticMessages label result)
    | .ok view => .ok (project node view)

end Informal.NodeAssembly
