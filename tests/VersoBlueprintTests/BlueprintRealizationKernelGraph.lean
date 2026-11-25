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

private def context : Context := ⟨`mockGraph, `mockGraph⟩
private def key : RealizationKey := ⟨`graph, `implementation⟩
private def document : DocumentKey := ⟨context, "MOCK.lean"⟩
private def realizationKey (n : Nat) : RealizationKey :=
  { key with name := .num `realization n }
private def requirement (n : Nat) : RequirementKey :=
  ⟨.realization (realizationKey n), `check⟩

private def input (edges : Array (Array Nat)) : Input := {
  nodes := #[contribution `node { label := key.node, title := "MOCK graph" }]
  documents := #[contribution `source { key := document, text := "MOCK selected content" }]
  -- Independently owned mock content keeps these graph controls focused on
  -- prerequisite evaluation without bypassing source availability.
  realizations := edges.mapIdx fun n _ => contribution (.num `realization n) {
    key := realizationKey n, context, role := .num `mockRole n, documents := #[document],
    required := #[requirement n] }
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
  let leafDiagnostics := (changed.localResult (requirement 0)).diagnostics
  let prerequisiteSubjects := canonical ((Array.range 63).map fun n => (toJson (requirement (n + 1))).compress)
  ensure (result.diagnostics == canonical result.diagnostics && result.diagnostics.size == 64 &&
    result.diagnostics.filter (·.code == "check-not-passed") == leafDiagnostics &&
    (result.diagnostics.filter (·.code == "unfinished-prerequisite")).map (·.subject) == prerequisiteSubjects)
    "Shared prerequisite paths must retain every distinct unfinished reason and one copy of its original cause"
  ensure ((r.resultForRequirement (requirement 63)).complete) "Readmission must not mutate the old admitted snapshot"

#eval show IO Unit from do
  -- The cycle has an unfinished external prerequisite; both cycle members must
  -- retain that actual cause, independent of DFS/query/inventory order.
  let input ← checked #[#[1, 2], #[0, 2], #[], #[0, 1]] (· != 2)
  let r ← obtain (admit input)
  let subjects (indices : Array Nat) := canonical (indices.map fun n => (toJson (requirement n)).compress)
  let externalDiagnostics := (r.localResult (requirement 2)).diagnostics
  for n in #[0, 1, 3] do
    let result := r.resultForRequirement (requirement n)
    let diagnosticSubjects (code : String) := (result.diagnostics.filter (·.code == code)).map (·.subject)
    let unfinished := if n == 3 then #[0, 1, 3] else #[n]
    ensure (result.status == .blocked && result.localComplete &&
      result.diagnostics.filter (·.code == "check-not-passed") == externalDiagnostics &&
      diagnosticSubjects "requirement-cycle" == subjects #[0, 1] &&
      diagnosticSubjects "unfinished-prerequisite" == subjects unfinished)
      "Cycle closure must preserve local evidence, each member's marker, and the shared external cause"
  ensure ((r.localResult (requirement 2)).status == .pending) "Cycle cannot overwrite external local status"
  let self ← checked #[#[0], #[]]
  let self ← obtain (admit self)
  ensure ((self.resultForRequirement (requirement 0)).status == .blocked &&
    (self.resultForRequirement (requirement 1)).complete)
    "Self cycles block themselves while unrelated requirements stay complete"

private inductive CollidingJson where
  | left
  | right
  deriving Ord, BEq, Repr

private instance : ToJson CollidingJson where
  toJson _ := toJson "same display JSON"

#eval show IO Unit from do
  let a := canonical #[CollidingJson.left, .right, .left]
  let b := canonical #[CollidingJson.right, .left, .right]
  ensure (a.size == 2 && a == b)
    "Canonicalization must retain distinct values and order by structural identity independently of display JSON"

-- These are valid typed names with identical display JSON AND Repr. Neither
-- display representation may order identities or decide producer compatibility.
#eval show IO Unit from do
  let left := Name.mkSimple "foo.bar»"
  let right := Name.str (Name.mkSimple "foo") "bar»"
  ensure (left != right && toJson left == toJson right && reprStr left == reprStr right)
    "Control must exercise a real display-name collision"
  ensure (canonical #[left, right, left] == canonical #[right, left, right] &&
    (canonical #[left, right]).size == 2)
    "Distinct names must survive canonicalization in permutation-independent order"
  let a : Node := { label := left, title := "same" }
  let b : Node := { label := right, title := "same" }
  let forward : Input := { nodes := #[contribution `left a, contribution `right b] }
  let reverse : Input := { nodes := forward.nodes.reverse }
  let first ← obtain (admit forward)
  let second ← obtain (admit reverse)
  ensure (first.nodes == second.nodes && first.nodes.size == 2)
    "Admitted nodes must preserve structural names and replay order independence"
  let collision : Input := { nodes := #[contribution `same a, contribution `same b] }
  for records in #[collision.nodes, collision.nodes.reverse] do
    match admit { collision with nodes := records } with
    | .ok _ => throw <| IO.userError "Producer collision hidden by name display was accepted"
    | .error issues => ensure (issues.any (·.code == "producer-collision")) "Typed producer collision must remain explicit"
  -- Nested metadata and provenance names must be structural too.
  let metadataA : Node := { label := `nested, title := "same", parent := some left }
  let metadataB : Node := { metadataA with parent := some right }
  ensure (canonical #[metadataA, metadataB] == canonical #[metadataB, metadataA] &&
    (canonical #[metadataA, metadataB]).size == 2) "Nested metadata identity was lost"
  let original := contribution `same a
  let changed := { original with origin := { original.origin with moduleName := right } }
  let original := { original with origin := { original.origin with moduleName := left } }
  match admit { nodes := #[original, changed] } with
  | .ok _ => throw <| IO.userError "Producer origin collision hidden by display was accepted"
  | .error issues => ensure (issues.any (·.code == "producer-collision")) "Producer origin must use typed equality"
  let replay ← obtain (admit { nodes := #[original, original] })
  ensure (replay.nodes.size == 1) "Exact producer replay must remain idempotent"

-- Each declaration selection has one owner and its own exact requirement.
-- A check on A cannot be borrowed by B, even when the declarations share a
-- source document or belong to the same Blueprint node.
#eval show IO Unit from do
  let a : ObjectKey := ⟨context, "MOCK.a"⟩
  let b : ObjectKey := ⟨context, "MOCK.b"⟩
  let statementOwner := key.forRole `statement
  let proofOwner := key.forRole `proof
  let qa : RequirementKey := ⟨.declaration statementOwner a, `proof⟩
  let qb : RequirementKey := ⟨.declaration proofOwner b, `proof⟩
  let raw : Input := {
    nodes := #[contribution `node { label := key.node, title := "Explicit requirements" }]
    documents := #[contribution `document { key := document, text := "MOCK source" }]
    objects := #[contribution `objectA { key := a, resolution := .resolved, document := some document },
      contribution `objectB { key := b, resolution := .resolved, document := some document }]
    realizations := #[
      contribution `statementOwner {
        key := statementOwner, context, role := `statement,
        declarations := #[{ object := a, projection := .statement, required := #[qa] }] },
      contribution `proofOwner {
        key := proofOwner, context, role := `proof,
        declarations := #[{ object := b, projection := .implementation, required := #[qb] }] }]
    requirements := #[contribution `requirementA {
      key := qa, expected := .check `MOCK_CHECK, coverage := .dependencyClosure },
      contribution `requirementB { key := qb, expected := .check `MOCK_CHECK, coverage := .dependencyClosure }] }

  -- Reassigning A's requirement to B is rejected at the ownership boundary,
  -- rather than being hidden by a flattened document inventory.
  let borrowed : Input := { raw with realizations := #[
    contribution `statementOwner {
      key := statementOwner, context, role := `statement,
      declarations := #[{ object := a, projection := .statement, required := #[qa] }] },
    contribution `proofOwner {
      key := proofOwner, context, role := `proof,
      declarations := #[{ object := b, projection := .implementation, required := #[qa, qb] }] }] }
  match admit borrowed with
  | .ok _ => throw <| IO.userError "A's requirement was borrowed by B's realization"
  | .error issues =>
      ensure (issues.any (·.code == "wrong-subject"))
        "Cross-owner requirement borrowing must be diagnosed explicitly"

  let r ← obtain (admit raw)
  let some binding := r.bindingFor qa | throw <| IO.userError "Missing exact A binding"
  let r ← obtain (admit { raw with evidence := #[contribution `evidenceA {
    id := `MOCK_CHECK_A_ONLY, requirement := qa, binding
    observation := .check {
      validator := `MOCK_CHECK, outcome := .passed, coverage := .dependencyClosure } }] })
  ensure ((r.resultFor (.declaration statementOwner a)).complete &&
    !(r.resultFor (.declaration proofOwner b)).complete &&
    r.requiredFor (.realization statementOwner) == #[qa] &&
    r.requiredFor (.realization proofOwner) == #[qb])
    "A's result must remain local to its realization and cannot certify B"

end VersoBlueprintTests.BlueprintRealizationKernelGraph
