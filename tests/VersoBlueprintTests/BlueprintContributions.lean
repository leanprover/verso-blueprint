/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.NodeAssembly.Laws

open Lean Informal.Data Informal.Contributions
namespace VersoBlueprintTests.BlueprintContributions

private def a : Record := {
  id := ⟨`A, `blueprint.attribute, `declA, 10, 0⟩
  label := `shared
  references := #[ExternalRef.ofName `declA .blueprintAttr]
  priority := none
  source := some { path := "A.lean", range := default }
}
private def b : Record := {
  id := ⟨`B, `blueprint.attribute, `declB, 20, 0⟩
  label := `shared
  references := #[ExternalRef.ofName `declB .blueprintAttr]
  priority := none
  source := some { path := "B.lean", range := default }
}
private def c : Record := { b with id := ⟨`C, `blueprint.attribute, `declC, 30, 0⟩ }

private def sameMembers [BEq α] (xs ys : List α) : Bool :=
  xs.all ys.contains && ys.all xs.contains

private def accepts (label : Label) (rs : List Record) (decls : List Name)
    (priority : Option String) (supports : List Record) : Bool :=
  match resolve label rs with
  | .error _ => false
  | .ok v => sameMembers v.declarations decls && v.priority == priority &&
      sameMembers v.supports supports

private def sameBuckets [BEq α] (xs ys : List (α × List Record)) : Bool :=
  xs.length == ys.length && xs.all fun (key, values) =>
    ys.any fun (expectedKey, expectedValues) => key == expectedKey && sameMembers values expectedValues

private def rejects (label : Label) (rs : List Record)
    (collisions : List (ContributionId × List Record))
    (priorities : List (String × List Record)) : Bool :=
  match resolve label rs with
  | .ok _ => false
  | .error d => sameBuckets d.collisions collisions && sameBuckets d.priorityConflict priorities

-- Positive #462: both independent producers survive either import order/replay.
#guard accepts `shared [a, b] [`declA, `declB] none [a, b]
#guard accepts `shared [b, a] [`declA, `declB] none [a, b]
#guard accepts `shared [a, b, a] [`declA, `declB] none [a, b]
#guard (collector.collect [a, b, a]).length == 2
#guard sameMembers (collector.batches [a] [[b], [a, b]]) [a, b]
#guard accepts `empty [] [] none []

-- A universal specialization, not only evaluation of the two concrete orders.
theorem issue462_positive (rs : List Record) (h : List.Perm rs [a, b]) :
    ∃ v, resolve `shared rs = .ok v ∧
      (∀ d, d ∈ v.declarations ↔ d = `declA ∨ d = `declB) ∧
      v.priority = none ∧ EvidenceEq v.supports [a, b] := by
  obtain ⟨v, hv, hd, hp, hs⟩ := independentAssociations a b `shared
    (by decide) rfl rfl rfl rfl rs h
  refine ⟨v, hv, ?_, hp, hs⟩
  intro d
  rw [hd]
  have ea : (`declA : Name).eraseMacroScopes = `declA := rfl
  have eb : (`declB : Name).eraseMacroScopes = `declB := rfl
  simp [Association, a, b, ExternalRef.ofName, ea, eb] <;> simp only [eq_comm]
  constructor
  · intro h
    exact h.imp And.right And.right
  · intro h
    exact h.imp (fun h => ⟨rfl, h⟩) (fun h => ⟨rfl, h⟩)

private def lowA := { a with priority := some "low" }
private def lowB := { b with priority := some "low" }
private def highB := { b with priority := some "high" }
private def mediumC := { c with priority := some "medium" }
#guard rejects `shared [lowA, lowB, b] [(b.id, [lowB, b])] []
-- Different IDs can agree on a scalar; absent claims add no competing value.
#guard accepts `shared [lowA, b] [`declA, `declB] (some "low") [lowA, b]
#guard accepts `shared [lowA, lowB] [`declA, `declB] (some "low") [lowA, lowB]
#guard rejects `shared [lowA, highB, mediumC] []
  [("low", [lowA]), ("high", [highB]), ("medium", [mediumC])]
#guard rejects `shared [mediumC, highB, lowA] []
  [("low", [lowA]), ("high", [highB]), ("medium", [mediumC])]

-- Same ID/different record preserves all variants and all scalar conflicts.
#guard rejects `shared [a, lowA, highB] [(a.id, [a, lowA])]
  [("low", [lowA]), ("high", [highB])]
#guard rejects `shared [highB, lowA, a] [(a.id, [a, lowA])]
  [("low", [lowA]), ("high", [highB])]
#guard (collector.collect [a, lowA, a]).length == 2
private def otherA := { a with label := `other }
#guard rejects `shared [a, otherA] [(a.id, [a, otherA])] []
#guard rejects `other [otherA, a] [(a.id, [a, otherA])] []
#guard accepts `unrelated [otherA, a] [] none []

-- Complete snapshot differences are not collapsed to declaration-name equality.
private def snapshotA := { a with references := #[{
  (ExternalRef.ofName `declA .blueprintAttr) with
  provedStatus := .containsSorry #[{ location := .proof }]
  provenance := .inWorkspace `A "formalization.lean"
  render := .ok { html := "proof with sorry", hoverPayloads := #[⟨7, "type info"⟩] }
}] }
#guard rejects `shared [a, snapshotA] [(a.id, [a, snapshotA])] []
-- Different contribution IDs retain BOTH snapshots as support. Status arbitration
-- is outside this resolver's guarantee; membership is still exactly declA.
private def independentSnapshotA := { snapshotA with id := c.id }
#guard accepts `shared [a, independentSnapshotA] [`declA] none [a, independentSnapshotA]

private def missingB := { b with references := #[{ (ExternalRef.ofName `declB) with present := false }] }
#guard accepts `shared [a, missingB] [`declA] none [a, missingB]
#guard rejects `shared [missingB, b] [(b.id, [missingB, b])] []

-- The assembly capability follows every accepted support, rather than the
-- snapshot retained for the declaration. This reproduces the former reversal.
private def sameDeclDirective : Record := {
  id := ⟨`Directive, `blueprint.directive, `declA, 40, 0⟩
  label := `shared
  references := #[ExternalRef.ofName `declA .directiveLean]
  priority := none
  source := none
}

private def hasAttributeCapability (records : List Record) : Bool :=
  match Informal.NodeAssembly.assemble `shared #[] records with
  | .ok assembled => assembled.node.blueprintAttributeAttachments
  | .error _ => false

#guard hasAttributeCapability [a, sameDeclDirective]
#guard hasAttributeCapability [sameDeclDirective, a]
#guard hasAttributeCapability (collector.batches [] [[a], [sameDeclDirective, a]])

private def highA : Record := { a with priority := some "high" }
#guard match Informal.NodeAssembly.assemble `shared #[] [highA] with
  | .ok assembled => assembled.node.priority == some "high" &&
      assembled.view.priority == some "high"
  | .error _ => false

-- The retained public reducer rejects the selected fields it cannot admit, but
-- continues to accept the legacy body and dependency payloads it owns.
#guard match ({} : Node).applyContributions `shared #[{ priority := some "high" }] with
  | .error _ => true
  | .ok _ => false
#guard match ({} : Node).applyContributions `shared
    #[{ leanCode := #[.external a.references] }] with
  | .error _ => true
  | .ok _ => false
#guard match ({} : Node).applyContributions `shared #[{
    statementBody := some { stx := .missing, elabStx := #[.missing] }
    statementUses := #[{ label := `dependency }]
    leanCode := #[.literate { stx := .missing }]
  }] with
  | .ok node => node.statement.any fun statement => statement.hasBody &&
      statement.deps == #[{ label := `dependency }] && node.literateCodes.size == 1
  | .error _ => false

-- Supported legacy updates must preserve an already assembled capability.
#guard match Informal.NodeAssembly.assemble `shared #[] [a] with
  | .error _ => false
  | .ok assembled => match assembled.node.applyContributions `shared #[{
      statementBody := some { stx := .missing, elabStx := #[.missing] }
      statementUses := #[{ label := `dependency }]
    }] with
    | .error _ => false
    | .ok updated => updated.blueprintAttributeAttachments &&
        updated.statement.any fun statement => statement.hasBody &&
          statement.deps == #[{ label := `dependency }]

end VersoBlueprintTests.BlueprintContributions
