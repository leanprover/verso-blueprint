/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module
public import VersoBlueprintVirTests.NativeSession.UpstreamJson.Codec
public import VersoBlueprintVirTests.NativeSession.UpstreamJson.Generated
import all VersoBlueprintVirTests.NativeSession.UpstreamJson.Generated

public section

namespace Lean.Vir.JsonValue

private partial def readChecked (value : Js.Any) : RuntimeM Json := do
  match ← Internal.inspect value with
  | .null => return .null
  | .bool value => return .bool value
  | .integer value => return toJson value
  | .string value => return .str value
  | .array children => return .arr (← children.mapM readChecked)
  | .object fields =>
    let fields ← fields.mapM fun (key, value) => do return (key, ← readChecked value)
    return Json.mkObj fields.toList

/-- Copy ordinary JS data into Lean.Json after checking the entire graph.
Accessors are rejected. Proxies and concurrent mutation are outside this data
contract; this is not an adversarial-JavaScript sandbox. No Promise is awaited. -/
def fromJs (value : Js.Any) : RuntimeM (Except String Json) := do
  match ← Internal.check value with
  | .error error => return .error error
  | .ok () => return .ok (← readChecked value)

private partial def writeJson (value : Json) : ExceptT String RuntimeM Js.Any := do
  let node ← match value with
    | .null => pure Internal.View.null
    | .bool value => pure (.bool value)
    | .num value =>
      match integer? value with
      | .ok value => pure (.integer value)
      | .error error => throw error
    | .str value => pure (.string value)
    | .arr children => return ← liftM (Internal.build (.array (← children.mapM writeJson)))
    | .obj fields =>
      let fields ← fields.toArray.mapM fun (key, value) => do return (key, ← writeJson value)
      pure (.object fields)
  liftM (Internal.build node)

/-- Copy checked Lean.Json into ordinary JavaScript values, without stringify/parse. -/
def toJs (value : Json) : RuntimeM (Except String Js.Any) := do
  match validate value with
  | .error error => return .error error
  | .ok () => writeJson value |>.run

/-- Explicitly choose the existing ToJson instance and copy its checked wire value. -/
def encodeJs [ToJson α] (value : α) : RuntimeM (Except String Js.Any) :=
  toJs (toJson value)

/-- Copy checked ordinary data and apply the author's FromJson decoder. -/
def decodeJs [FromJson α] (value : Js.Any) : RuntimeM (Except String α) := do
  match ← fromJs value with
  | .error error => return .error error
  | .ok json => return decode json

end Lean.Vir.JsonValue
