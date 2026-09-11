/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.Statement

-- A sibling extension that supplies metadata without another proof body.
run_cmd discard <| Informal.Environment.contribute `key_theorem { priority := some "low" }
