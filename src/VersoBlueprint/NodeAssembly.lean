/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Contributions

/-! The narrow assembly layer combines node payloads with the proved
external-association/priority slice.  It deliberately does not import the
environment extension or rendering consumers. -/

namespace Informal.NodeAssembly

open Lean Informal.Data Informal.Contributions

private abbrev MergeM := StateM (Array String)

private def conflict (message : String) : MergeM Unit :=
  modify fun messages => if messages.contains message then messages else messages.push message

private def mergeMetadata [BEq α] [ToString α] (label : Label) (field : String)
    (current incoming : Option α) : MergeM (Option α) := do
  match current, incoming with
  | none, _ => return incoming
  | _, none => return current
  | some existing, some value =>
    if existing != value then
      conflict s!"Label {label} declares conflicting {field}: existing '{existing}', new '{value}'"
    return current

private def inferredNodeKind (external : Array ExternalRef) (literate : Array Code) : NodeKind :=
  if external.any (·.kind.isTheoremLike) || literate.any (! ·.definedTheorems.isEmpty) then .theorem
  else if !external.isEmpty || literate.any (! ·.definedDefs.isEmpty) then .definition else .lemma

private def mergeContribution (label : Label) (node : Node)
    (incoming : SourceData.Registration) : MergeM Node := do
  -- Keep every raw source and use; conflicts are scoped to their actual keys.
  let mut sources := node.sources
  for source in incoming.sources do
    for previous in sources do
      if previous.destination == source.destination then
        let occupied := match previous.payload, source.payload with
          | .prose first, .prose second => first.hasBody && second.hasBody
          | .text _, .text _ => true
          | .prose body, .text _ | .text _, .prose body => body.hasBody
          | .markup first, .markup second => first.key == second.key
          | _, _ => false
        if occupied then
          conflict s!"Label {label}: duplicate-source: realization '{source.destination.realization.name}' already has a {source.destination.facet} source"
    sources := sources.push source
  let mut uses := node.uses
  for use in incoming.uses do
    for previous in uses do
      if previous.realization == use.realization && previous.facet == use.facet &&
          previous.reference.label == use.reference.label && previous.reference.origin == use.reference.origin &&
          previous.reference.intent != use.reference.intent then
        conflict s!"Label {label} declares conflicting {use.facet} dependency intents for '{use.reference.label}' ({use.reference.origin}): existing '{previous.reference.intent}', new '{use.reference.intent}'"
    uses := uses.push use
  let parent ← mergeMetadata label "parents" node.parent incoming.parent
  let owner ← mergeMetadata label "owners" node.owner incoming.owner
  let effort ← mergeMetadata label "effort values" node.effort incoming.effort
  let prUrl ← mergeMetadata label "PR URLs" node.prUrl incoming.prUrl
  let issueUrl ← mergeMetadata label "issue URLs" node.issueUrl incoming.issueUrl
  let kindIsExplicit := node.kindIsExplicit || incoming.kind.isSome
  let kind ← match incoming.kind with
    | some kind =>
      if node.kindIsExplicit && node.kind != kind then
        conflict s!"Label {label} declares conflicting statement kinds: existing '{node.kind}', new '{kind}'"
      pure kind
    | none => pure <| if node.kindIsExplicit then node.kind else
        inferredNodeKind node.externalAssociationSnapshots ({ node with sources }.inlineCodes)
  return { node with
    kind, kindIsExplicit
    count := if node.count == 0 then incoming.count else node.count
    sources, uses, parent, owner, effort, prUrl, issueUrl
    tags := incoming.tags.foldl (fun tags tag => if tags.contains tag then tags else tags.push tag) node.tags }

/-- Raw well-formedness only. Destination membership is checked after complete
realization composition; no fixed language-slot representability gate remains. -/
private def registrationIssues (label : Label) (incoming : SourceData.Registration) : Array String := Id.run do
  let mut errors := incoming.sources.flatMap fun source =>
    (source.rawIssues label).map fun issue => s!"Label {label}: {issue.code}: {issue.message}"
  for use in incoming.uses do
    if use.node != label || use.reference.label.isAnonymous || use.facet.isAnonymous ||
        use.realization.any (·.isAnonymous) ||
        (use.realization.isNone && use.facet != `statement && use.facet != `proof) then
      errors := errors.push s!"Label {label}: invalid-use-destination: Use must preserve its concept, scope and explicit facet"
  return errors

/-- Payload reducer for body, kind, markup, dependency, and literate payloads. -/
private def applyPayloads (label : Label) (node : Node)
    (contributions : Array SourceData.Registration) : Except (Array String) Node :=
  let sourceErrors := contributions.flatMap (registrationIssues label)
  let (node, errors) := (contributions.foldlM (mergeContribution label) node).run sourceErrors
  if errors.isEmpty then .ok node else .error errors

end Informal.NodeAssembly

namespace Informal.Data

/-- Apply body, kind, markup, dependency, and literate payloads to a node.
Selected associations and priority are supplied separately through identified
records. This reducer preserves those fields on an already assembled node. -/
def Node.applyRegistrations (label : Label) (node : Node)
    (contributions : Array SourceData.Registration) : Except (Array String) Node :=
  Informal.NodeAssembly.applyPayloads label node contributions

end Informal.Data

namespace Informal.NodeAssembly

open Lean Informal.Data Informal.Contributions

private def recordMessage (record : Record) : String :=
  let statement := (record.nativeAssociations.filter (·.facets.contains `statement)).map (·.reference)
  let proof := (record.nativeAssociations.filter (·.facets.contains `proof)).map (·.reference)
  let refs := String.intercalate ", " (statement.toList.map fun ref => ref.canonical.toString)
  let proofRefs := if proof.isEmpty then "" else
    s!" proofRefs=[{String.intercalate ", " (proof.toList.map fun ref => ref.canonical.toString)}]"
  s!"{record.id.moduleName}.{record.id.producer}:{record.id.subject}@{record.id.site}/{record.id.slot} label={record.label} refs=[{refs}]{proofRefs} priority={record.priority}"

private def externalOriginMessage : ExternalOrigin → String
  | .directiveLean => "directive"
  | .blueprintAttr => "attribute"

private def provedStatusMessage : ProvedStatus → String
  | .proved => "proved"
  | .missing => "missing"
  | .axiomLike => "axiom-like"
  | .incomplete info =>
    s!"incomplete(known-sorry={info.knownSorry.size}, unverified={info.unverified.size})"

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
  if first.nativeAssociations.map (fun association => (association.realization, association.context, association.facets)) !=
      record.nativeAssociations.map (fun association => (association.realization, association.context, association.facets)) then
    differences := differences.push "native destinations"
  if first.allReferences.map (·.canonical) != record.allReferences.map (·.canonical) then
    differences := differences.push "native associations"
  if first.allReferences.map (·.origin) != record.allReferences.map (·.origin) then
    let origins := referenceFieldMessage first.allReferences (externalOriginMessage ·.origin)
    let recordOrigins := referenceFieldMessage record.allReferences (externalOriginMessage ·.origin)
    differences := differences.push s!"origin ({origins} → {recordOrigins})"
  if first.allReferences.map (·.present) != record.allReferences.map (·.present) then
    let presence := referenceFieldMessage first.allReferences (fun ref => toString ref.present)
    let recordPresence := referenceFieldMessage record.allReferences (fun ref => toString ref.present)
    differences := differences.push s!"presence ({presence} → {recordPresence})"
  if first.allReferences.map (fun ref => (ref.provenance, ref.sourceHref?)) !=
      record.allReferences.map (fun ref => (ref.provenance, ref.sourceHref?)) then
    let sources := referenceFieldMessage first.allReferences externalSourceMessage
    let recordSources := referenceFieldMessage record.allReferences externalSourceMessage
    differences := differences.push s!"source metadata ({sources} → {recordSources})"
  if first.allReferences.map (·.provedStatus) != record.allReferences.map (·.provedStatus) then
    let statuses := referenceFieldMessage first.allReferences (provedStatusMessage ·.provedStatus)
    let recordStatuses := referenceFieldMessage record.allReferences (provedStatusMessage ·.provedStatus)
    differences := differences.push s!"status ({statuses} → {recordStatuses})"
  if first.allReferences.map (·.render) != record.allReferences.map (·.render) then
    differences := differences.push s!"render differs ({referenceFieldMessage first.allReferences (renderStateMessage ·.render)} → {referenceFieldMessage record.allReferences (renderStateMessage ·.render)})"
  if first.allReferences != record.allReferences && differences.isEmpty then
    differences := differences.push "reference snapshot"
  return s!"differs from first support in {String.intercalate "; " differences.toList}"

private def diagnosticMessages (label : Label) (diagnostics : Diagnostics) : Array String :=
  let idKey := fun id : ContributionId =>
    s!"{id.moduleName.toString}/{id.producer.toString}/{id.subject.toString}/{id.site}/{id.slot}"
  let collisions := diagnostics.collisions.toArray.qsort fun a b => idKey a.1 < idKey b.1
  let priorities := diagnostics.priorityConflict.toArray.qsort fun a b => a.1 < b.1
  let supportKey := fun record : Record =>
    s!"{idKey record.id}/{record.label.toString}/" ++
      String.intercalate "," (record.allReferences.toList.map fun ref => ref.canonical.toString) ++
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

/-- Assemble one complete source inventory atomically. The accepted resolver
view supplies all keyed native associations and agreed priority. Source/use
payloads retain their original destinations and scopes; no completion is inferred.
Metadata display defaults are independent of validation. -/
structure Assembly where
  node : Node
  view : View

private def project (node : Node) (view : View) : Assembly :=
  let nativeAssociations := view.supports.toArray.flatMap (·.nativeAssociations)
  let kind := if node.kindIsExplicit then node.kind else
    inferredNodeKind (nativeAssociations.map (·.reference)) node.inlineCodes
  { node := { node with nativeAssociations, priority := view.priority, kind }, view }

/-- Raw keyed destination checks shared by local planning and complete import
reassembly. They do not establish composed membership or native-name stability. -/
def sourceDestinationIssues (label : Label) (payloads : Array SourceData.Registration) (records : List Record) : Array String := Id.run do
  let records := (recordsFor label records).toArray
  let mut issues := records.flatMap fun record =>
    record.nativeAssociations.flatMap fun association =>
      (association.rawIssues label).map fun issue =>
        s!"Label {label}: {issue.code}: {issue.message} ({issue.subject})"
  let mut contexts : Std.HashMap Realizations.RealizationKey Realizations.Context := {}
  for source in payloads.flatMap (·.sources) do
    let key := source.destination.realization
    match contexts[key]? with
    | some context =>
      if context != source.context then
        issues := issues.push s!"Label {label}: source-context-mismatch: Realization '{key.name}' has conflicting source contexts"
    | none => contexts := contexts.insert key source.context
  for record in records do
    for association in record.nativeAssociations do
      match contexts[association.realization]? with
      | some context =>
        if context != association.context then
          let message := s!"Label {label}: source-context-mismatch: Native realization '{association.realization.name}' has conflicting source contexts"
          unless issues.contains message do issues := issues.push message
      | none => contexts := contexts.insert association.realization association.context
  return issues

def assemble (label : Label) (payloads : Array SourceData.Registration) (records : List Record) :
    Except (Array String) Assembly :=
  match Node.applyRegistrations label {} payloads with
  | .error errors => .error errors
  | .ok node => match resolve label records with
    | .error result => .error (diagnosticMessages label result)
    | .ok view =>
      let issues := sourceDestinationIssues label payloads records
      if issues.isEmpty then .ok (project node view) else .error issues

end Informal.NodeAssembly
