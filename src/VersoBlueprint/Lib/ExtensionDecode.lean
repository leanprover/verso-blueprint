/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Lean.Data.Json.FromToJson.Basic
public import Verso.BuildLog

public section

namespace Informal.ExtensionDecode

open Lean

def decode? {m : Type → Type} {α : Type} [Monad m] [Verso.MonadBuildLog m] [FromJson α]
    (data : Json) (errorMessage : String → String) : m (Option α) := do
  match fromJson? (α := α) data with
  | .ok decoded =>
      pure (some decoded)
  | .error err =>
      Verso.reportError (errorMessage err)
      pure none

end Informal.ExtensionDecode
