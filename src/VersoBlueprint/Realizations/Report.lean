/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Translations

/-! Output-only inspection of supplied registry contracts. This is not
project readiness, omitted Blueprint dependency closure, provider authentication
or a source/tool freshness check. All assessment delegates to existing rules. -/

namespace Informal.Realizations.Report

open Lean Validation Translations

private def assessed [ToJson α] (value : α) (result : Result) : Json :=
  Json.mkObj [("value", toJson value), ("result", toJson result)]

private def realization (registry : Registry) (value : Realization) : Json :=
  Json.mkObj [
    ("value", toJson value),
    ("result", toJson (registry.resultFor (.realization value.key))),
    ("facets", toJson (value.facets.map fun facet => Json.mkObj [
      ("value", toJson facet), ("subject", toJson (Subject.facet value.key facet.name)),
      ("result", toJson (registry.resultFor (.facet value.key facet.name)))])),
    ("declarations", toJson (value.declarations.map fun declaration => Json.mkObj [
      ("value", toJson declaration), ("subject", toJson (Subject.declaration value.key declaration.object)),
      ("result", toJson (registry.resultFor (.declaration value.key declaration.object)))]))]

private def requirement (registry : Registry) (value : Requirement) : Json :=
  Json.mkObj [
    ("value", toJson value),
    ("localResult", toJson (registry.localResult value.key)),
    ("result", toJson (registry.resultForRequirement value.key))]

private def evidence (registry : Registry) (value : Evidence) : Json := Id.run do
  -- Structural admission guarantees the referenced requirement. Keep this
  -- lookup total and never infer suitability from any other evidence's result.
  let suitability := do
    let contract ← registry.requirement? value.requirement
    let binding ← registry.bindingFor value.requirement
    let mismatch := value.mismatch? contract binding
    pure <| Json.mkObj [
      ("matchesCurrentRequirement", toJson mismatch.isNone),
      ("mismatch", toJson mismatch)]
  return Json.mkObj [
    ("id", toJson value.id), ("requirement", toJson value.requirement),
    ("observation", toJson value.observation), ("suitability", toJson suitability)]

private def selectedReport (registry : Registry) (node : Option Name) : Json := Id.run do
  let models := registry.realizations.filter fun value => node.all (· == value.key.node)
  let translations := registry.translations.filter fun value => node.all fun node =>
    (value.source ++ value.target).any (·.realization.node == node)
  let selected (subject : Subject) : Bool := match subject with
    | .realization key | .facet key _ | .declaration key _ => node.all (· == key.node)
    | .translation key => translations.any (·.key == key)
    | .claim key => translations.any (·.key == key.translation)
  let requirements := registry.requirements.filter (selected ·.key.subject)
  let objects := registry.objects.filter fun value => node.isNone || models.any fun model =>
    model.declarations.any (·.object == value.key)
  let documents := models.flatMap (·.facets.flatMap (·.documents)) ++ objects.filterMap (·.document) ++
    requirements.flatMap fun value => match value.expected with | .proof goal _ => goal.documents | _ => #[]
  return Json.mkObj [
    ("nodes", toJson (registry.nodes.filter fun value => node.all (· == value.label))),
    ("documents", toJson (registry.documents.filter (fun value => node.isNone || documents.contains value.key) |>.map (·.key))),
    ("objects", toJson objects),
    ("realizations", toJson (models.map (realization registry))),
    ("translations", toJson (translations.map fun value =>
      assessed value (registry.resultFor (.translation value.key)))),
    ("claims", toJson (registry.claims.filter (fun value => selected (.claim value.key)) |>.map fun value =>
      assessed value (registry.resultFor (.claim value.key)))),
    ("requirements", toJson (requirements.map (requirement registry))),
    ("evidence", toJson (registry.evidence.filter (selected ·.requirement.subject) |>.map (evidence registry))),
    ("unfinished", toJson (registry.unfinished.filter (fun value => selected (.translation value.key)) |>.map (·.key))),
    ("actionable", toJson (registry.actionable.filter (fun value => selected (.translation value.key)) |>.map (·.key)))]

/-- Inspect supplied admitted contracts through the existing evaluator/query
methods. Provider observations and exact-current-binding suitability are distinct;
neither authenticates the provider or implies aggregate readiness. Source bytes,
bindings and raw contributions are not exported. There is no report import path. -/
def ofRegistry (registry : Registry) : Json := selectedReport registry none

/-- The same safe assessment projection restricted to a concept and its incident
correspondences. This filters output; it never admits or evaluates a partial model. -/
def ofNode (registry : Registry) (node : Name) : Json := selectedReport registry (some node)

end Informal.Realizations.Report
