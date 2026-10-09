/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
module

public import Vir.Resources.Assets

/-- Lake prepares the program; VIR supplies the matching runtime and embedding. -/
public def VersoBlueprintVirClientTests.resources : Vir.Resources.ResourceSet :=
  include_vir_assets (modules := #[VersoBlueprintVirClientTests.Program])
