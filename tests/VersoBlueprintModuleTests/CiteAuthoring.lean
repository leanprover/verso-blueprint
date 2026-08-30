/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Cite
meta import VersoBlueprint.Cite

namespace VersoBlueprintModuleTests.CiteAuthoring

open Verso Genre Manual

@[bib "module.citation"]
def moduleCitation : Verso.Genre.Manual.Bibliography.Citable := .arXiv
  { title := .text "Module citation"
  , authors := #[.text "A. Author"]
  , year := 2026
  , id := "module.citation"
  }

#docs (Manual) citeAuthoringContractDoc "Module Citation Authoring" :=
:::::::
Textual {Informal.citet "module.citation" (kind := theorem) (index := "4.2")}[] and
parenthetical {Informal.citep "module.citation"}[] citations.
:::::::

end VersoBlueprintModuleTests.CiteAuthoring
