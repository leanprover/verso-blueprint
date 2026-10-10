/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
module

public import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
import Lean.Data.Json.Printer

public section

namespace VersoBlueprint.ExternalMarkup

/-- A matching descriptor, not the markup body or its source metadata.
The browser applies its string normalization before crossing the boundary. -/
structure Markup where
  language : String
  slot : String
  hasContent : Bool
  deriving BEq, Lean.ToJson, Lean.FromJson

/-- A browser preference with callback availability represented as data.
Disabled entries preserve positions when the original preference is invalid. -/
structure Preference where
  language : String
  slot : String
  canRender : Bool
  enabled : Bool := true
  deriving BEq, Lean.ToJson, Lean.FromJson

structure Input where
  markups : Array Markup
  preferences : Array Preference
  deriving Lean.ToJson, Lean.FromJson

/-- Indices refer to the original browser arrays; no body or callback is copied. -/
structure Selection where
  ok : Bool
  reason : String
  markupIndex : Option Nat
  preferenceIndex : Option Nat
  deriving BEq, Lean.ToJson, Lean.FromJson

private def isMatch (markup : Markup) (preference : Preference) : Bool :=
  markup.hasContent &&
    (preference.language.isEmpty || markup.language == preference.language) &&
    (preference.slot.isEmpty || markup.slot == preference.slot)

/-- Select in preference order, using the first matching attachment.
Native preferences are handled by the caller's native-preview path. A later
renderable match wins over an earlier match whose renderer is unavailable. -/
def select (input : Input) : Selection := Id.run do
  let mut missingRenderer : Option Selection := none
  let mut missingPreference : Option Nat := none
  for (preference, index) in input.preferences.zipIdx do
    if !preference.enabled || preference.language == "native" || preference.language == "verso" then
      continue
    let markupIndex := input.markups.findIdx? (isMatch · preference)
    match markupIndex with
    | none =>
      if missingPreference.isNone then missingPreference := some index
    | some markupIndex =>
      if preference.canRender then
        return {
          ok := true, reason := "", markupIndex := some markupIndex
          preferenceIndex := some index }
      if missingRenderer.isNone then
        missingRenderer := some {
          ok := false, reason := "external-markup-renderer-missing"
          markupIndex := some markupIndex, preferenceIndex := some index }
  return missingRenderer.getD {
    ok := false, reason := "external-markup-missing", markupIndex := none,
    preferenceIndex := missingPreference }

/-- Ordinary JSON boundary for VIR's supported String → String call surface.
This does not serialize markup bodies, callbacks, DOM nodes or runtime objects. -/
def selectJson (encoded : String) : String :=
  match Lean.Json.parse encoded >>= Lean.fromJson? (α := Input) with
  | .ok input => (Lean.toJson (select input)).compress
  | .error message => (Lean.Json.mkObj [("error", Lean.toJson message)]).compress

end VersoBlueprint.ExternalMarkup
