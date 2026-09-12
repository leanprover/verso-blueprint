/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso

namespace Informal.ExtensionDecode

open Lean

/-- Report a required lookup or decoding failure without losing its diagnostic. -/
def report? {m : Type → Type} {α : Type} [Monad m] [Verso.MonadBuildLog m]
    (result : Except String α) : m (Option α) := do
  match result with
  | .ok decoded =>
      pure (some decoded)
  | .error err =>
      Verso.reportError err
      pure none

def decode? {m : Type → Type} {α : Type} [Monad m] [Verso.MonadBuildLog m] [FromJson α]
    (data : Json) (errorMessage : String → String) : m (Option α) :=
  report? <| (fromJson? (α := α) data).mapError errorMessage

end Informal.ExtensionDecode
