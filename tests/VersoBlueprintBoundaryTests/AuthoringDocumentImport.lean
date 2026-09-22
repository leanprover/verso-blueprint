/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprintBoundaryTests.AuthoringRoot

namespace VersoBlueprintBoundaryTests.AuthoringDocumentImport

/-- Documented Lean declarations remain public across a module import. -/
example : Nat := AuthoringRoot.contractInlineDeclaration

end VersoBlueprintBoundaryTests.AuthoringDocumentImport
