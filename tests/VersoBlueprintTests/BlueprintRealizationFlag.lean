/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean

namespace RealizationAdapterFixture

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

end RealizationAdapterFixture
