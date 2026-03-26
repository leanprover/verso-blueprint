/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint

namespace Verso.VersoBlueprintTests.BlueprintAttribute.Provider

/-- Exported theorem used to verify `@[blueprint]` persistence across imports. -/
@[blueprint "attr.exported.theorem"]
theorem exportedTheorem : True := by
  trivial

/-- Exported definition used to verify `@[blueprint]` persistence across imports. -/
@[blueprint "attr.exported.definition"]
def exportedDefinition : Nat := 7

/-- Exported inductive used to verify `@[blueprint]` accepts definition-like targets. -/
@[blueprint "attr.exported.inductive"]
inductive exportedInductive where
  /-- Constructor used to verify imported inductive blueprint attributes. -/
  | mk

@[blueprint "attr.exported.undocumented"]
def exportedUndocumentedDefinition : Nat := 11

end Verso.VersoBlueprintTests.BlueprintAttribute.Provider
