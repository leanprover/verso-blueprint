/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Source
meta import VersoBlueprint.Source

namespace VersoBlueprintModuleTests.SourceAuthoring

open Verso Genre Manual
open Informal

#docs (Manual) sourceAuthoringContractDoc "Module Source Authoring" :=
:::::::
:::source_document "module-paper"
%%%
title := "Module Paper"
kind := .pdf
pdf := "module-paper.pdf"
pageRoot := "module-pages"
%%%
:::
:::::::

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let document : Informal.Source.Document := {
      id := "module-paper"
      title := "Module Paper"
      kind := .pdf
      pdf := "module-paper.pdf"
      pageRoot := "module-pages"
    }
    document.validationErrors.isEmpty &&
      document.pdf == some "module-paper.pdf" &&
      document.pageRoot == some "module-pages"

end VersoBlueprintModuleTests.SourceAuthoring
