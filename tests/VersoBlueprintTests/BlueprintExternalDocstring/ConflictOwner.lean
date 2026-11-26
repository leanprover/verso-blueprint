/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint

namespace ExternalDocstringFixture

set_option verso.blueprint.project "externalDocstringFixture"

/-- A statement whose default body belongs to its introducing attribute. -/
@[blueprint "external.docstring.attribute"]
theorem tagged : True := True.intro

end ExternalDocstringFixture
