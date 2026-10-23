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

-- Native adaptation of the canonical translation-reuse/Fixture/Flag.lean pilot.
-- This is an ordinary local build, not imported LIRIS artifacts or a claim of
-- validated Rocq correspondence. The package controls below are local tests.
inductive Flag where
  | off
  | on

def toggle : Flag → Flag
  | .off => .on
  | .on => .off

structure FlagPackage where
  operation : Flag → Flag

def togglePackage : FlagPackage := ⟨toggle⟩
def identityPackage : FlagPackage := ⟨id⟩
def Involutive (package : FlagPackage) : Prop :=
  ∀ flag, package.operation (package.operation flag) = flag

/-- Toggling a two-state flag twice returns the original flag. -/
@[blueprint "adapter.flag.involutive"]
theorem flagInvolutive : Involutive togglePackage := by
  intro flag
  cases flag <;> rfl

theorem identityInvolutive : Involutive identityPackage := fun _ => rfl

theorem conditionalInvolutive (h : Involutive togglePackage) : Involutive togglePackage := h

/-- Ordinary escaped names remain supported. -/
@[blueprint "adapter.escaped"]
theorem «with.dot» : True := True.intro

-- A real kernel-checked theorem with a legal internal name that cannot be
-- spelled by Name.toString/String.toName without identity loss. Register it
-- using the existing public attribute implementation, not new admission code.
open Lean Elab Command in
run_cmd do
  let name := Name.str `RealizationAdapterFixture "bad»name"
  liftTermElabM <| addDecl <| .thmDecl {
    name, levelParams := [], type := mkConst ``True, value := mkConst ``True.intro }
  addDocStringCore name "Non-round-tripping internal declaration name."
  let attributeSyntax ← `(attr| blueprint "adapter.nonroundtrip")
  let impl ← ofExcept <| getAttributeImpl (← getEnv) `blueprint
  liftTermElabM <| liftM <| impl.add name attributeSyntax.raw .global

end RealizationAdapterFixture
