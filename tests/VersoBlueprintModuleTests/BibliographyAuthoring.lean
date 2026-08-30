/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Commands.Bibliography
meta import VersoBlueprint.Commands.Bibliography

namespace VersoBlueprintModuleTests.BibliographyAuthoring

open Verso Genre Manual

@[bib "module.bibliography"]
def moduleBibliographyEntry : Verso.Genre.Manual.Bibliography.Citable := .arXiv
  { title := .text "Module bibliography"
  , authors := #[.text "B. Author"]
  , year := 2026
  , id := "module.bibliography"
  }

#docs (Manual) bibliographyAuthoringContractDoc "Module Bibliography Authoring" :=
:::::::
See {Informal.citet "module.bibliography"}[].

{blueprint_bibliography}
:::::::

end VersoBlueprintModuleTests.BibliographyAuthoring
