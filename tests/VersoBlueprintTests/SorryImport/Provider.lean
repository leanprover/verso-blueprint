/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module
public import Lean

public theorem sorryImportAdmitted : True := by
  sorry

public theorem sorryImportComplete : True := True.intro

public axiom sorryImportAxiom : True

public def sorryImportNumber : Nat := by sorry
public def sorryImportCompleteDef : Nat := 7
public def sorryImportComposedDef : Nat := sorryImportNumber + 1

@[expose] public def sorryImportExposed : Nat := sorryImportNumber + 2
@[expose] public def sorryImportExposedComplete : Nat := 8

public theorem sorryImportStandardAxioms {α : Sort u} (h : Nonempty α) : Nonempty α :=
  ⟨Classical.choice h⟩

-- The statement retains the admitted constant, but reduces to True. The proof
-- contains only True.intro: its cached *combined* footprint cannot locate a
-- proof-side gap after an ordinary import.
public def sorryImportSpec : Prop := let _n := sorryImportNumber; True

public theorem sorryImportTypeOnly : sorryImportSpec := True.intro

public theorem sorryImportHypothesis (_h : sorryImportSpec) : True := True.intro

public theorem sorryImportBoth : sorryImportSpec := by sorry

public theorem sorryImportComposed : True := sorryImportAdmitted

public theorem sorryImportCapturedComplete : True := True.intro

public opaque sorryImportOpaqueComplete : Nat := 1
public opaque sorryImportOpaqueAdmitted : Nat := by sorry

public def sorryImportGap : Type := by sorry
public structure SorryImportRecord where
  payload : sorryImportGap

public structure SorryImportCompleteRecord where
  payload : Nat

public theorem sorryImportRecordHypothesis (_h : SorryImportRecord) : True := True.intro

public structure SorryImportNestedRecord where
  payload : SorryImportRecord

public structure SorryImportNestedCompleteRecord where
  payload : SorryImportCompleteRecord

public theorem sorryImportNestedHypothesis (_h : SorryImportNestedRecord) : True := True.intro
public theorem sorryImportNestedCompleteHypothesis (_h : SorryImportNestedCompleteRecord) : True :=
  True.intro
