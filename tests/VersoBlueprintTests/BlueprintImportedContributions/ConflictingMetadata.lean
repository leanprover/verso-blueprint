/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.Metadata
import VersoBlueprintTests.BlueprintImportedContributions.Proof

/--
error: Conflicting imported blueprint contributions for label 'key_theorem'
Label key_theorem declares conflicting priorities including 'high'
Proof.«test.synthetic»:key_theorem@1/0 label=key_theorem refs=[] priority=(some high)
Label key_theorem declares conflicting priorities including 'low'
Metadata.«test.synthetic»:key_theorem@1/0 label=key_theorem refs=[] priority=(some low)
Contributing modules: VersoBlueprintTests.BlueprintImportedContributions.Metadata, VersoBlueprintTests.BlueprintImportedContributions.Proof, VersoBlueprintTests.BlueprintImportedContributions.Statement
-/
#guard_msgs in
#eval show Lean.CoreM Unit from Informal.Environment.reportImportedConflicts
