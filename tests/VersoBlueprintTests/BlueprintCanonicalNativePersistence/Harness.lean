/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Environment

open Lean Informal

namespace CanonicalNativePersistence

-- Expected error messages are captured, then assertions run outside the capture.
-- Test failures cannot be swallowed by the expected-error harness.
def rejected (fragment : String) (action : CoreM (Option Data.Node)) : CoreM Unit := do
  let before := Environment.informalExt.getState (← getEnv)
  let messages ← Core.getMessageLog
  let (result, errors) ← try
    let result ← action
    let after := (← Core.getMessageLog).reportedPlusUnreported.toArray
    let added := after.extract messages.reportedPlusUnreported.size after.size
    let errors ← (added.filter (·.severity == .error)).mapM fun message => message.data.toString
    pure (result, errors)
  finally
    Core.setMessageLog messages
  unless result.isNone && errors.any (·.contains fragment) do
    throwError "Expected explicit rejection containing '{fragment}'"
  unless reprStr before == reprStr (Environment.informalExt.getState (← getEnv)) do
    throwError "Rejected native registration changed a Blueprint store"


end CanonicalNativePersistence
