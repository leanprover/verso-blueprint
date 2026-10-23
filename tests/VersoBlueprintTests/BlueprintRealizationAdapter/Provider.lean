/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint

namespace RealizationAdapterFixture

/-- Every natural number equals itself. Raw Markdown, with **emphasis**. -/
@[blueprint "adapter.reflexivity"]
theorem reflexivity : ∀ n : Nat, n = n := fun _ => rfl

def Reflexivity : Prop := ∀ n : Nat, n = n

/-- This theorem deliberately has an unfinished proof. -/
@[blueprint "adapter.admitted"]
theorem admitted : True := by sorry

axiom assumption : True
theorem conditionalProof : True := assumption
def admittedProposition : Prop := by sorry

theorem polymorphic.{u} : ∀ (α : Type u) (x : α), x = x := fun _ _ => rfl

/-- First declaration in an unsupported grouped node. -/
@[blueprint "adapter.grouped"]
theorem groupedOne : True := True.intro

@[blueprint "adapter.grouped"]
theorem groupedTwo : True := True.intro

@[blueprint "adapter.undocumented"]
theorem undocumented : True := True.intro

/-- An unsupported definition. -/
@[blueprint "adapter.definition"]
def number : Nat := 1

set_option doc.verso true in
/-- A Verso docstring is outside this first Markdown projection. -/
@[blueprint "adapter.verso"]
theorem versoDocstring : True := True.intro

@[inherit_doc reflexivity, blueprint "adapter.inherited"]
theorem inheritedDocstring : ∀ n : Nat, n = n := fun _ => rfl

end RealizationAdapterFixture
