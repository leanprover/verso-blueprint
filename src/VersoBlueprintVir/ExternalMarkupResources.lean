/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
module

public import Vir.Resources.Assets
public import Vir.Resources.Site

/-- Lake-prepared selection program and its exact matching runtime. -/
public def VersoBlueprint.ExternalMarkup.resources : Vir.Resources.ResourceSet :=
  include_vir_assets (modules := #[VersoBlueprintVir.ExternalMarkupProgram])
