/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.Statement
import VersoBlueprintTests.BlueprintImportedContributions.Proof

open Verso.Genre

-- Regression for https://github.com/leanprover/verso-blueprint/issues/444.
#doc (Manual) "Document" =>

{include 0 VersoBlueprintTests.BlueprintImportedContributions.Statement}
{include 0 VersoBlueprintTests.BlueprintImportedContributions.Proof}

{blueprint_summary}

# Dependency graph

{blueprint_graph}
