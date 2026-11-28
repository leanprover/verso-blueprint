/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean

/-! Compiled declaration ownership. -/

namespace Informal.ExternalModuleSource
open Lean

/-- Read a module-table entry without allocating the projected names array. -/
def moduleNameAt? (env : Environment) (idx : ModuleIdx) : Option Name :=
  env.header.modules[idx.toNat]?.map (·.module)

/-- Resolve the owner of a checked declaration. An invalid imported index
must not turn an imported declaration into a current-module declaration. -/
def moduleNameForDecl? (env : Environment) (name : Name) : Option Name :=
  match env.getModuleIdxFor? name with
  | some idx => moduleNameAt? env idx
  | none => if env.mainModule.isAnonymous then none else some env.mainModule

end Informal.ExternalModuleSource
