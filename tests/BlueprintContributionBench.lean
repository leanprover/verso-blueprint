/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.NodeAssembly

/-! Optional native benchmark for collision checking and full node assembly.
The deliberately slow reference reproduces the pre-fix executable specification;
it is confined to this comparison tool, never used in production or normal tests.
All modes use full production records. Input construction is outside the timer.
-/

open Lean Informal.Data Informal.Contributions

private def records (count : Nat) : List Record := (List.range count).map fun i => {
  id := ⟨`Benchmark, `synthetic, .num `node i, i, 0⟩
  label := .num `node i
  references := #[ExternalRef.ofName (.num `declaration i)]
  priority := none
  source := none }

private def referenceCollisionIds (label : Label) (rs : List Record) : List ContributionId :=
  letI (id : ContributionId) : Decidable (Collision rs id) := by
    unfold Collision
    infer_instance
  letI (id : ContributionId) : Decidable (RelevantCollision rs label id) := by
    unfold RelevantCollision
    infer_instance
  (rs.map (·.id)).eraseDups.filter fun id => decide (RelevantCollision rs label id)

def main (args : List String) : IO Unit := do
  let [mode, count, labels] := args
    | throw <| IO.userError "usage: blueprint-contribution-bench (reference|indexed|assemble) RECORDS LABELS"
  let some count := count.toNat? | throw <| IO.userError "invalid record count"
  let some labels := labels.toNat? | throw <| IO.userError "invalid label count"
  unless labels > 0 && labels ≤ count do
    throw <| IO.userError "require 0 < LABELS <= RECORDS"
  unless ["reference", "indexed", "assemble"].contains mode do
    throw <| IO.userError "unknown mode"
  let rs := records count
  let start ← IO.monoNanosNow
  let mut checked := 0
  for i in [:labels] do
    let label := Name.num `node i
    if mode == "assemble" then
      match Informal.NodeAssembly.assemble label #[] rs with
      | .error _ => throw <| IO.userError "unexpected assembly rejection"
      | .ok result =>
        unless result.node.leanDecls == #[Name.num `declaration i] do
          throw <| IO.userError "assembly lost the expected declaration"
    else
      let collisions := if mode == "reference" then referenceCollisionIds label rs else collisionIds label rs
      unless collisions.isEmpty do
        throw <| IO.userError "unexpected identity collision"
    checked := checked + 1
  let elapsed := (← IO.monoNanosNow) - start
  IO.println <| Json.compress <| Json.mkObj [
    ("mode", toJson mode), ("records", toJson count), ("labels", toJson labels),
    ("checked", toJson checked), ("elapsedNs", toJson elapsed)]
