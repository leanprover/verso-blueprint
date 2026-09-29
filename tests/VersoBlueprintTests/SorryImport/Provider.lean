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
