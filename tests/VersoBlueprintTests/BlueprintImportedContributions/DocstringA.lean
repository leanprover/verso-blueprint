/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintImportedContributions.DocstringBase

/-- First docstring candidate, belonging to the Lean declaration. -/
@[blueprint "shared_docstring"] theorem docstringAttachmentA : True := trivial

/-- Code documentation must not replace the authored statement. -/
@[blueprint "authored_docstring"] theorem docstringAuthoredAttachment : True := trivial
