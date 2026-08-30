/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

meta import VersoBlueprint.ExternalRefSnapshot

namespace VersoBlueprintModuleTests.ExternalRefSnapshot

open Lean

/-- info: true -/
#guard_msgs in
#eval
  show Lean.CoreM Bool from do
    let snapshot ← Informal.externalRefSnapshotAtCurrentDir {}
      (Informal.Data.ExternalRef.ofName `No.Such.Declaration)
    pure <|
      !snapshot.present &&
        snapshot.provedStatus.isMissing &&
        match snapshot.render with
        | .error (.moduleUnavailable decl) => decl == `No.Such.Declaration
        | _ => false

end VersoBlueprintModuleTests.ExternalRefSnapshot
