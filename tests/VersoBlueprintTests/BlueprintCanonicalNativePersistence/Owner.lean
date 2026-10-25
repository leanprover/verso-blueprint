/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint

open Informal

namespace CanonicalNativePersistence

/-- An ordinary native theorem; its prose is not a proofread correspondence. -/
@[blueprint "canonical.native"]
theorem original : True := True.intro

end CanonicalNativePersistence
