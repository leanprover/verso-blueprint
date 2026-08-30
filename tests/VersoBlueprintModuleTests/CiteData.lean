/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Cite.Data
meta import VersoBlueprint.Cite.Data

namespace VersoBlueprintModuleTests.CiteData

/-- info: true -/
#guard_msgs in
#eval
  let usage : Informal.Cite.CitationUsageData := {
    uses := [{
      href := "chapter.html#citation"
      kind := some .theorem
      index := some " 4.2 "
    }]
  }
  Informal.Cite.normalizeLabel " Module.Citation " == "Module.Citation" &&
    Informal.Cite.citationAnchorId "Module.Citation" == "module-citation" &&
    Informal.Cite.CitePartKind.parse? "thm" == some .theorem &&
    Informal.Cite.locatorText (some .theorem) (some " 4.2 ") == some "Theorem 4.2" &&
    (Lean.fromJson? (Lean.toJson usage) : Except String Informal.Cite.CitationUsageData).isOk

end VersoBlueprintModuleTests.CiteData
