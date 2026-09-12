/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintImportedContributions.DocstringBase

/-- Second docstring candidate, belonging to another Lean declaration. -/
@[blueprint "shared_docstring"] theorem docstringAttachmentB : True := trivial
