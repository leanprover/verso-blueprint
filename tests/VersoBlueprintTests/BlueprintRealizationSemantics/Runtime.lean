/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
namespace FIRSemanticFixture

-- The integration test changes this one body by bytes, then rebuilds normally.
def runtimeMode : Nat := 0

def RefinedReturnPost : Prop := runtimeMode = runtimeMode

end FIRSemanticFixture
