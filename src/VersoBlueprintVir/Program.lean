/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
module

meta import Vir.Attributes
import VersoBlueprintVir.ExternalMarkup
import VersoBlueprint.Lib.HtmlId
public import VersoBlueprintRuntime.ManifestResolver
public import Vir.Js

/-- Production selection policy; source bodies and callbacks stay in the browser. -/
@[vir_export]
public def VersoBlueprint.ExternalMarkup.selectMarkup (input : String) : String :=
  VersoBlueprint.ExternalMarkup.selectJson input

/-- Reuse the native DOM-id encoding; counters and DOM construction stay in JS. -/
@[vir_export]
public def VersoBlueprint.HtmlId.encode (key : String) : String :=
  Informal.HtmlId.key key

/-- Prepare once; the public opaque carrier owns the immutable Lean index. -/
@[vir_export]
public def VersoBlueprint.Manifest.prepare (source : String) :
    IO (Lean.Vir.JSL VersoBlueprint.Runtime.ManifestResolver.PreparedManifest) := do
  let prepared ← IO.ofExcept <|
    VersoBlueprint.Runtime.ManifestResolver.prepareManifestJson source
  Lean.Vir.RuntimeM.run (Lean.Vir.LeanRef.toJSL prepared)

/-- Resolve a request batch without rebuilding the manifest index. -/
@[vir_export]
public def VersoBlueprint.Manifest.lookup
    (prepared : Lean.Vir.JSL VersoBlueprint.Runtime.ManifestResolver.PreparedManifest)
    (requests : String) : Lean.Vir.RuntimeM String := do
  return VersoBlueprint.Runtime.ManifestResolver.resolvePreparedJson
    (← Lean.Vir.LeanRef.fromJSL prepared) requests
