/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint
import VersoBlueprint.Realizations.NativeSource
import VersoBlueprintTests.BlueprintRealizationFlag

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
/-- An own *Verso* docstring with {name}`Nat` and é 😀. -/
@[blueprint "adapter.verso"]
theorem versoDocstring : True := True.intro

@[inherit_doc reflexivity, blueprint "adapter.inherited"]
theorem inheritedDocstring : ∀ n : Nat, n = n := fun _ => rfl

/-- Own text with conflicting inheritance. -/
@[inherit_doc reflexivity, blueprint "adapter.own.inherited"]
theorem ownInheritedDocstring : True := True.intro

set_option doc.verso true in
/-- Même *texte* 😀 λ with {name}`Nat`. -/ @[blueprint "adapter.unicode"] theorem «état😀» : True := True.intro

set_option doc.verso true in
/-- Même *texte* 😀 λ with {name}`Nat`. -/
theorem neighboringComment : True := True.intro

set_option doc.verso true in
/-- Actual Verso metadata with an intentionally conflicting Markdown entry. -/
@[blueprint "adapter.ambiguous"]
theorem ambiguousFormat : True := True.intro

-- Explicit native-metadata ambiguity injection in its owning module. This
-- supplies no successful proof/review observation and must remain unsupported.
run_cmd Lean.addDocStringCore ``ambiguousFormat "injected competing Markdown"

theorem noOriginalComment : True := True.intro

-- Own native text injected before attribute registration still cannot supply a
-- source comment where the actual declaration has none.
open Lean Elab Command in
run_cmd do
  let name := ``noOriginalComment
  addDocStringCore name "Injected metadata is not an original modifier comment."
  let attr ← `(attr| blueprint "adapter.no.original.comment")
  let impl ← ofExcept <| getAttributeImpl (← getEnv) `blueprint
  liftTermElabM <| liftM <| impl.add name attr.raw .global

-- Native adaptation of the canonical translation-reuse/Fixture/Flag.lean pilot.
-- This is an ordinary local build, not imported LIRIS artifacts or a claim of
-- validated Rocq correspondence. The package controls below are local tests.
set_option doc.verso true in
/--
Toggling a *two-state* flag twice returns the original flag: é 😀.
For {name}`RealizationAdapterFixture.Flag.off`, toggle gives on then off;
for on, it gives off then on.
-/
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

-- Actual native metadata without an original declaration/source range. It must
-- remain unsupported rather than attaching a neighboring comment.
open Lean Elab Command in
run_cmd do
  let name := `RealizationAdapterFixture.syntheticDoc
  liftTermElabM <| addDecl <| .thmDecl {
    name, levelParams := [], type := mkConst ``True, value := mkConst ``True.intro }
  addDocStringCore name "Synthetic documentation without source ranges."
  let attributeSyntax ← `(attr| blueprint "adapter.synthetic")
  let impl ← ofExcept <| getAttributeImpl (← getEnv) `blueprint
  liftTermElabM <| liftM <| impl.add name attributeSyntax.raw .global

end RealizationAdapterFixture

namespace RealizationAdapterFixture

/-- Test-only construction of a source-provider model from an explicit native
identity. This does not project a Blueprint node or test canonical capture. -/
def prepareModel (project label canonical : Lean.Name)
    (reader : System.FilePath → IO String := IO.FS.readFile)
    (metadata : Informal.Data.NodeMetadata := {}) :
    Lean.CoreM (Except Informal.Realizations.Diagnostic Informal.Realizations.NativeSource.PreparedModel) := do
  let request : Informal.Realizations.NativeSource.Request := {
    project, canonical
    moduleName := `VersoBlueprintTests.BlueprintRealizationAdapter.Provider
    sourcePath := "tests/VersoBlueprintTests/BlueprintRealizationAdapter/Provider.lean" }
  match ← Informal.Realizations.NativeSource.prepareDocumented request reader with
  | .error diagnostic => return .error diagnostic
  | .ok source =>
    let origin : Informal.Realizations.Origin := {
      id := label ++ `providerFixture, moduleName := request.moduleName, source := request.sourcePath }
    return source.realize origin { toNodeMetadata := metadata, label, title := label.toString } `lean `docstring


end RealizationAdapterFixture
