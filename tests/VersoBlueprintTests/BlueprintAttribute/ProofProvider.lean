/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintAttribute.Provider

open Verso Informal

namespace Verso.VersoBlueprintTests.BlueprintAttribute.ProofProvider

/-- A statement with proof dependencies but no informal proof body. -/
@[blueprint "imported.proof.metadata" (proofUses := ["attr.exported.definition"])]
theorem metadataOnly : True := trivial

-- The proof is contributed by a different module from the tagged declaration.
-- Consumers import this module without including this document as content.
set_option verso.blueprint.foldProofBlocks true in
#docs (Genre.Manual) proofDocument "Provider proof" :=
:::::::
:::proof "attr.exported.theorem"
The *imported informal argument* uses
{uses "attr.exported.definition"}[the auxiliary definition].
:::
:::::::

end Verso.VersoBlueprintTests.BlueprintAttribute.ProofProvider
