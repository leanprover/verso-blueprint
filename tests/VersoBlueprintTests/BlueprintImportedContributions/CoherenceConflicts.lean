/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.CoherenceConflictC
import VersoBlueprintTests.BlueprintImportedContributions.CoherenceConflictB
import VersoBlueprintTests.BlueprintImportedContributions.CoherenceConflictA

open Lean Informal

-- Complete import decoding finds all three priority values and the two labels
-- touched by one identity; neither accepted prefix is published.
/-- info: true -/
#guard_msgs in
#eval show CoreM Bool from do
  let conflicts ← Environment.importedConflicts
  return conflicts.size == 3 &&
    conflicts.any (fun conflict => conflict.label == `coherent_three &&
      conflict.reasons.size == 6) &&
    conflicts.any (fun conflict => conflict.label == `coherent_cross_a &&
      conflict.reasons.size == 3) &&
    conflicts.any (fun conflict => conflict.label == `coherent_cross_b &&
      conflict.reasons.size == 3) &&
    (← Environment.getNode? `coherent_three).isNone &&
    (← Environment.getNode? `coherent_cross_a).isNone &&
    (← Environment.getNode? `coherent_cross_b).isNone

/--
error: Conflicting imported blueprint contributions for label 'coherent_cross_a'
Label coherent_cross_a has conflicting contribution identity CoherenceCross.«test.synthetic»:shared_identity at 9/0
CoherenceCross.«test.synthetic»:shared_identity@9/0 label=coherent_cross_a refs=[] priority=none
CoherenceCross.«test.synthetic»:shared_identity@9/0 label=coherent_cross_b refs=[] priority=none
Contributing modules: VersoBlueprintTests.BlueprintImportedContributions.CoherenceConflictA
---
error: Conflicting imported blueprint contributions for label 'coherent_cross_b'
Label coherent_cross_b has conflicting contribution identity CoherenceCross.«test.synthetic»:shared_identity at 9/0
CoherenceCross.«test.synthetic»:shared_identity@9/0 label=coherent_cross_a refs=[] priority=none
CoherenceCross.«test.synthetic»:shared_identity@9/0 label=coherent_cross_b refs=[] priority=none
Contributing modules: VersoBlueprintTests.BlueprintImportedContributions.CoherenceConflictB
---
error: Conflicting imported blueprint contributions for label 'coherent_three'
Label coherent_three declares conflicting priorities including 'high'
CoherenceConflictA.«test.synthetic»:coherent_three@1/0 label=coherent_three refs=[] priority=(some high)
Label coherent_three declares conflicting priorities including 'low'
CoherenceConflictC.«test.synthetic»:coherent_three@1/0 label=coherent_three refs=[] priority=(some low)
Label coherent_three declares conflicting priorities including 'medium'
CoherenceConflictB.«test.synthetic»:coherent_three@1/0 label=coherent_three refs=[] priority=(some medium)
Contributing modules: VersoBlueprintTests.BlueprintImportedContributions.CoherenceConflictA, VersoBlueprintTests.BlueprintImportedContributions.CoherenceConflictB, VersoBlueprintTests.BlueprintImportedContributions.CoherenceConflictC
-/
#guard_msgs in
#eval show CoreM Unit from Environment.reportImportedConflicts
