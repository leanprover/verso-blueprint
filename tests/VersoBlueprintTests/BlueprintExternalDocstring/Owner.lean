/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean

namespace ExternalDocstringFixture

/-- The **upstream statement marker** retains λ and 😀. -/
theorem selected : True := True.intro

/-- A different source marker for the other attached declaration. -/
theorem alternative : True := True.intro

set_option doc.verso true in
/-- The *upstream Verso marker* names {name}`True`. -/
theorem versoSelected : True := True.intro

/--
-/
theorem emptyComment : True := True.intro

@[inherit_doc selected]
theorem inherited : True := True.intro

theorem undocumented : True := True.intro

end ExternalDocstringFixture
