/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Environment

/-! Raw authoring uses the existing Environment extension. Only a query after
normal declaration/import elaboration materializes and admits the complete batch.
No validation observation, binding or derived Registry is persisted. -/

namespace Informal.Realizations.Authoring

open Lean

private def orThrow (result : Except (Array Diagnostic) Unit) : CoreM Unit := do
  if let .error issues := result then throwError "{repr issues}"

/-- Configure this exact module, without enrolling its importers. -/
def configureProject (project : Name) : CoreM Unit := do
  orThrow (← Environment.configureAuthoringProject project)

/-- Retain a whole source envelope, not an admitted semantic model. -/
def stage (id : Name) (batch : Environment.AuthoredBatch) : CoreM Unit := do
  orThrow (← Environment.stageAuthored id batch)

/-- Name a separately authored proposition definition in this specification module. -/
def expectNative (id node expectedProposition : Name) : CoreM Unit := do
  orThrow (← Environment.stageNativeExpectation id node expectedProposition)

end Informal.Realizations.Authoring
