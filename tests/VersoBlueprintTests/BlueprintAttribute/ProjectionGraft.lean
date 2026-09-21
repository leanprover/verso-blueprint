/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintAttribute.ProjectionDirective
import VersoBlueprintTests.Blueprint.Support

open Lean Verso Informal
open Verso.Genre.Manual
open Verso.VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintAttribute.ProjectionGraft

private def manualImpls : ExtensionImpls := extension_impls%

-- Importing the directive records its selected fact, but this consumer does
-- not include `directiveDocument`; grafting must still materialize the actual
-- attribute association whose original declaration has no docstring.
#docs (Genre.Manual) consumerDocument "Projection graft consumer" :=
:::::::
{blueprint_node "attr.projection.shared"}
:::::::

#eval show CoreM Unit from do
  let some node ← Environment.getNode? (Name.mkSimple "attr.projection.shared")
    | throwError "Missing selected projection node"
  unless node.blueprintAttributeAttachments do
    throwError "Accepted attribute support did not project to the assembled node"

#eval show IO Unit from do
  let html ← renderManualDocHtmlString manualImpls consumerDocument
  unless hasSubstr html "projectionWitness" && hasSubstr html "data-bp-blueprint-node=\"true\"" do
    throw <| IO.userError "Graft did not materialize the imported attribute association"

end Verso.VersoBlueprintTests.BlueprintAttribute.ProjectionGraft
