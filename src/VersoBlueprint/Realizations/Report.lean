/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Translations

/-! Opt-in, output-only inspection of supplied registry contracts. This is not
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

/-- Inspect the supplied admitted contracts through the existing evaluator/query
methods. Provider observations and exact-current-binding suitability are distinct;
neither authenticates the provider or implies aggregate readiness. Source bytes,
bindings and raw contributions are not exported. There is no report import path. -/
def ofRegistry (registry : Registry) : Json :=
  Json.mkObj [
    ("nodes", toJson registry.nodes),
    ("documents", toJson (registry.documents.map (·.key))),
    ("objects", toJson registry.objects),
    ("realizations", toJson (registry.realizations.map (realization registry))),
    ("translations", toJson (registry.translations.map fun value =>
      assessed value (registry.resultFor (.translation value.key)))),
    ("claims", toJson (registry.claims.map fun value =>
      assessed value (registry.resultFor (.claim value.key)))),
    ("requirements", toJson (registry.requirements.map (requirement registry))),
    ("evidence", toJson (registry.evidence.map (evidence registry))),
    ("unfinished", toJson (registry.unfinished.map (·.key))),
    ("actionable", toJson (registry.actionable.map (·.key)))]

end Informal.Realizations.Report
