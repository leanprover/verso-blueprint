/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
module

public import VersoBlueprintRuntime.ManifestResolver
public import VersoBlueprintVir.Program
meta import Vir.Attributes

/-- Conformance entry only; not the production manifest transport. -/
@[vir_export]
public def VersoBlueprintRuntimeClientTests.Program.resolve (source : String) : String :=
  VersoBlueprint.Runtime.ManifestResolver.resolveBatchJson source

/-- Test the production retained-index entry without duplicating its body. -/
@[vir_export]
public def VersoBlueprintRuntimeClientTests.Program.prepare (source : String) :=
  VersoBlueprint.Manifest.prepare source

@[vir_export]
public def VersoBlueprintRuntimeClientTests.Program.lookup
    (prepared : Lean.Vir.JSL VersoBlueprint.Runtime.ManifestResolver.PreparedManifest)
    (requests : String) :=
  VersoBlueprint.Manifest.lookup prepared requests
