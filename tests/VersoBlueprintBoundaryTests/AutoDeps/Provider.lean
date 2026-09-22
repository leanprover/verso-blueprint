/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
module

import VersoBlueprint
meta import VersoBlueprint

namespace VersoBlueprintBoundaryTests.AutoDeps

@[blueprint "module.auto.source"]
public def source : Nat := 1

@[expose, blueprint "module.auto.proposition"]
public def proposition : Prop := True

@[blueprint "module.auto.proof"]
public theorem proofSource : True := True.intro

public def hiddenHelper : Nat := source
@[expose] public def exposedHelper : Nat := source
public theorem proofHelper : True := proofSource

-- The attribute sees the just-compiled body, before the module hides it.
@[blueprint "module.auto.persisted" (autoDeps := true)]
public def persisted : Nat := hiddenHelper

@[blueprint "module.auto.private" (autoDeps := true)]
private def privateNode : Nat := source

@[blueprint "module.auto.persisted_proof" (autoDeps := true)]
public theorem persistedProof : True := proofHelper

end VersoBlueprintBoundaryTests.AutoDeps
