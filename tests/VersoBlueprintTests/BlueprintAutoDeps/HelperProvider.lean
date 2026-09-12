/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintAutoDeps.Reexport

namespace Verso.VersoBlueprintTests.BlueprintAutoDeps.HelperProvider

open Provider

-- This module contributes helpers; the associated sources live two imports away.
def typeAlias : Prop := untaggedTypeAlias
theorem proofHop : typeAlias := untaggedProofHelper
def diamondLeft : Nat := defSource
def diamondRight : Nat := defSource
def diamond : Nat := diamondLeft + diamondRight
opaque opaqueHelper : Nat := defSource
def sharedAlias : Prop := sharedSource

@[blueprint "auto.frontier.boundary"]
def boundary : Nat := defSource
def behindBoundary : Nat := boundary

inductive HiddenBox where
  | mk : typeSource → HiddenBox

mutual
  def left : Nat → Nat
    | 0 => defSource
    | n + 1 => right n
  def right : Nat → Nat
    | 0 => defSource
    | n + 1 => left n
end

-- A persisted inferred node is later consumed through module inclusion.
@[blueprint "auto.frontier.persisted" (autoDeps := true)]
theorem persisted : typeAlias := proofHop

end Verso.VersoBlueprintTests.BlueprintAutoDeps.HelperProvider

-- Deliberately remains active at EOF: this setting must not leak through imports.
set_option verso.blueprint.autoDeps.expandUntagged false
