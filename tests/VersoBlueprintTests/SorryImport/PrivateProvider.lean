/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module
public import Lean

namespace PrivateSorryBoundary

private theorem hiddenHole : True := by sorry
private theorem hiddenComplete : True := True.intro

public theorem holeBridge : True := hiddenHole
public theorem completeBridge : True := hiddenComplete

@[expose] public def exposedHoleConsumer : Bool :=
  let _proof := holeBridge
  true

@[expose] public def exposedCompleteConsumer : Bool :=
  let _proof := completeBridge
  true

end PrivateSorryBoundary
