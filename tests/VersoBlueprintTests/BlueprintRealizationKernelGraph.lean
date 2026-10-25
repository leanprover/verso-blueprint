/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Translations

/-! Pure graph/cache regressions. ALL observations are explicitly MOCK checks;
these controls neither invoke a compiler/provider nor certify production data. -/

open Lean Informal.Realizations Informal.Validation Informal.Translations

namespace VersoBlueprintTests.BlueprintRealizationKernelGraph

private def ensure (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def obtain [Repr ε] : Except ε α → IO α
  | .ok value => pure value
  | .error error => throw <| IO.userError (reprStr error)

private def contribution (id : Name) (value : α) : Contribution α :=
  { origin := { id, moduleName := `MOCK_GRAPH, source := "synthetic" }, value }

private def context : Context := ⟨`lean, `mockGraph⟩
private def key : RealizationKey := ⟨`graph, `implementation⟩
private def document : DocumentKey := ⟨context, "MOCK.lean"⟩
private def requirement (n : Nat) : RequirementKey := ⟨.facet key (.num `facet n), `check⟩

private def input (edges : Array (Array Nat)) : Input := {
  nodes := #[contribution `node { label := key.node, title := "MOCK graph" }]
  documents := #[contribution `document { key := document, text := "MOCK source" }]
  realizations := #[contribution `realization {
    key, context
    facets := edges.mapIdx fun n _ => {
      name := .num `facet n, documents := #[document], required := #[requirement n] } }]
  requirements := edges.mapIdx fun n prerequisites => contribution (.num `requirement n) {
    key := requirement n, expected := .check `MOCK_CHECK
    prerequisites := prerequisites.map requirement } }

private def checked (edges : Array (Array Nat)) (passed : Nat → Bool := fun _ => true) : IO Input := do
  let input := input edges
  let r ← obtain (admit input)
  let evidence ← edges.mapIdxM fun n _ => do
    let some binding := r.bindingFor (requirement n) | throw <| IO.userError "Missing binding"
    pure <| contribution (.num `evidence n) ({
      id := .num `mockEvidence n, requirement := requirement n, binding
      observation := .check { validator := `MOCK_CHECK, outcome := if passed n then .passed else .failed } } : Evidence)
  return { input with evidence }

#eval show IO Unit from do
  -- Sixty-four shared diamonds have exponentially many paths but only 64 keys.
  let edges := (Array.range 64).map fun n =>
    (if n > 0 then #[n - 1] else #[]) ++ (if n > 1 then #[n - 2] else #[])
  let input ← checked edges
  let r ← obtain (admit input)
  for n in [:64] do
    ensure ((r.resultForRequirement (requirement n)).complete) "Every DAG requirement must complete"
  let repeated ← obtain (admit { input with
    nodes := input.nodes.reverse, requirements := input.requirements.reverse
    evidence := input.evidence.reverse, realizations := input.realizations.reverse })
  for n in [:64] do
    ensure (r.resultForRequirement (requirement n) == repeated.resultForRequirement (requirement n) &&
      r.bindingFor (requirement n) == repeated.bindingFor (requirement n))
      "Indexes/SCC evaluation must preserve replay order independence and binding content"
  let changed ← checked edges (· != 0)
  let changed ← obtain (admit changed)
  let result := changed.resultForRequirement (requirement 63)
  ensure (result.status == .blocked && result.localComplete &&
    (changed.localResult (requirement 0)).status == .pending)
    "A fresh evidence snapshot must invalidate closure while retaining local success"
  ensure ((r.resultForRequirement (requirement 63)).complete) "Readmission must not mutate the old admitted snapshot"

#eval show IO Unit from do
  -- The cycle has an unfinished external prerequisite; both cycle members must
  -- retain that actual cause, independent of DFS/query/inventory order.
  let input ← checked #[#[1], #[0, 2], #[], #[0, 1]] (· != 2)
  let r ← obtain (admit input)
  for n in #[0, 1, 3] do
    let result := r.resultForRequirement (requirement n)
    ensure (result.status == .blocked && result.localComplete &&
      result.diagnostics.any (·.code == "requirement-cycle") &&
      result.diagnostics.any (·.subject == (toJson (Name.num `mockEvidence 2)).compress))
      "Cycle closure must preserve local evidence and the external unfinished cause"
  ensure ((r.localResult (requirement 2)).status == .pending) "Cycle cannot overwrite external local status"
  let self ← checked #[#[0], #[]]
  let self ← obtain (admit self)
  ensure ((self.resultForRequirement (requirement 0)).status == .blocked &&
    (self.resultForRequirement (requirement 1)).complete)
    "Self cycles block themselves while unrelated requirements stay complete"

private inductive CollidingJson where
  | left
  | right
  deriving BEq, Repr

private instance : ToJson CollidingJson where
  toJson _ := toJson "same display JSON"

#eval show IO Unit from do
  let a := canonical #[CollidingJson.left, .right, .left]
  let b := canonical #[CollidingJson.right, .left, .right]
  ensure (a.size == 2 && a == b)
    "Canonicalization must retain distinct values and deterministically break display-JSON ties"

-- The reviewed explicit-requirement policy: displayed declarations and required
-- validation subjects are distinct. A facet can require a mathematical check on
-- A while displaying B; this cannot certify declaration B or the whole group.
#eval show IO Unit from do
  let a : ObjectKey := ⟨context, "MOCK.a"⟩
  let b : ObjectKey := ⟨context, "MOCK.b"⟩
  let qa : RequirementKey := ⟨.declaration key a, `proof⟩
  let qb : RequirementKey := ⟨.declaration key b, `proof⟩
  let raw : Input := {
    nodes := #[contribution `node { label := key.node, title := "Explicit requirements" }]
    documents := #[contribution `document { key := document, text := "MOCK source" }]
    objects := #[contribution `objectA { key := a, resolution := .resolved, document := some document },
      contribution `objectB { key := b, resolution := .resolved, document := some document }]
    realizations := #[contribution `realization {
      key, context
      facets := #[{ name := `proof, declarations := #[b], required := #[qa] }]
      declarations := #[{ object := a, required := #[qa] }, { object := b, required := #[qb] }] }]
    requirements := #[contribution `requirementA {
      key := qa, expected := .check NativeLean.bodyValidator, coverage := .dependencyClosure },
      contribution `requirementB { key := qb, expected := .check NativeLean.bodyValidator, coverage := .dependencyClosure }] }
  let r ← obtain (admit raw)
  let some binding := r.bindingFor qa | throw <| IO.userError "Missing exact A binding"
  let r ← obtain (admit { raw with evidence := #[contribution `evidenceA {
    id := `MOCK_CHECK_A_ONLY, requirement := qa, binding
    observation := .check {
      validator := NativeLean.bodyValidator, declaration := some a, outcome := .passed, coverage := .dependencyClosure } }] })
  ensure ((r.resultFor (.facet key `proof)).complete &&
    !(r.resultFor (.declaration key b)).complete && !(r.resultFor (.realization key)).complete &&
    r.requiredFor (.facet key `proof) == #[qa])
    "Facet success establishes its explicit A requirement, not displayed B or whole-realization validity"

end VersoBlueprintTests.BlueprintRealizationKernelGraph
