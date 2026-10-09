/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint

open Lean Verso Genre Manual Informal

namespace Verso.VersoBlueprintTests.BlueprintProofLeanRefs.Provider

theorem firstProof : True := True.intro
theorem secondProof : True := True.intro
theorem admittedProof : True := by sorry

#docs (Manual) importedAssociations "Imported proof associations" :=
:::::::
:::lemma_ "proof.imported.associations"
An informal statement with its Lean association on the proof.
:::
:::proof "proof.imported.associations" (lean := "firstProof")
The compiled proof association contributes to the node.
:::
:::lemma_ "proof.imported.repeated"
A compiled statement whose proof is admitted.
:::
:::proof "proof.imported.repeated" (lean := "admittedProof")
The observed hole must survive repeated proof attachments.
:::
:::::::

/-- info: true -/
#guard_msgs in
#eval show CoreM Bool from do
  let some node ← Environment.getNode? (Name.mkSimple "proof.imported.associations")
    | return false
  return node.leanDecls == #[``firstProof] &&
    (← Environment.labelsForLeanDecl ``firstProof) == #[Name.mkSimple "proof.imported.associations"]

end Verso.VersoBlueprintTests.BlueprintProofLeanRefs.Provider
