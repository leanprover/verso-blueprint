/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
module

public import VersoBlueprintRuntime.ManifestResolver
public import Vir.Js
meta import Vir.Attributes

/-- Conformance entry only; not the production manifest transport. -/
@[vir_export]
public def VersoBlueprintRuntimeClientTests.Program.resolve (source : String) : String :=
  VersoBlueprint.Runtime.ManifestResolver.resolveBatchJson source

/-- Retain one immutable manifest using the public runtime-owned opaque carrier. -/
@[vir_export]
public def VersoBlueprintRuntimeClientTests.Program.prepare (source : String) :
    IO (Lean.Vir.JSL VersoBlueprint.Runtime.ManifestResolver.PreparedManifest) := do
  let prepared ← IO.ofExcept <|
    VersoBlueprint.Runtime.ManifestResolver.prepareManifestJson source
  Lean.Vir.RuntimeM.run (Lean.Vir.LeanRef.toJSL prepared)

/-- Resolve a batch without rebuilding the retained manifest. -/
@[vir_export]
public def VersoBlueprintRuntimeClientTests.Program.lookup
    (prepared : Lean.Vir.JSL VersoBlueprint.Runtime.ManifestResolver.PreparedManifest)
    (requests : String) : Lean.Vir.RuntimeM String := do
  return VersoBlueprint.Runtime.ManifestResolver.resolvePreparedJson
    (← Lean.Vir.LeanRef.fromJSL prepared) requests
