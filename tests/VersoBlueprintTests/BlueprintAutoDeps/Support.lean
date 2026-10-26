/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint

open Lean
open Informal

namespace Verso.VersoBlueprintTests.BlueprintAutoDeps.Support

def label (s : String) : Name :=
  Name.mkSimple s

def state : CoreM Environment.State := do
  pure <| Environment.informalExt.getState (← getEnv)

def node? (labelText : String) : CoreM (Option Data.Node) := do
  pure <| (← state).data.get? (label labelText)

def statementUses (labelText : String) : CoreM (Array Data.UseRef) := do
  let some node ← node? labelText
    | return #[]
  pure <| node.usesOn `statement

def proofUses (labelText : String) : CoreM (Array Data.UseRef) := do
  let some node ← node? labelText
    | return #[]
  pure <| node.usesOn `proof

def useRefSummary (useRefs : Array Data.UseRef) :
    Array (Name × Data.UseOrigin × Data.UseIntent) :=
  useRefs.map fun useRef => (useRef.label, useRef.origin, useRef.intent)

def useRef
    (labelText : String) (origin : Data.UseOrigin := .manual)
    (intent : Data.UseIntent := .regular) : Name × Data.UseOrigin × Data.UseIntent :=
  (label labelText, origin, intent)

def dataUseRef
    (labelText : String) (origin : Data.UseOrigin := .manual)
    (intent : Data.UseIntent := .regular) : Data.UseRef :=
  { label := label labelText, origin, intent }

def labels (items : Array String) : Array Name :=
  items.map label

structure ExpectedUses where
  labelText : String
  statement : Array (Name × Data.UseOrigin × Data.UseIntent) := #[]
  proof : Array (Name × Data.UseOrigin × Data.UseIntent) := #[]

def summaryString
    (summary : Array (Name × Data.UseOrigin × Data.UseIntent)) : String :=
  let itemString : Name × Data.UseOrigin × Data.UseIntent → String
    | (label, origin, intent) => s!"({label}, {origin}, {intent})"
  "#[" ++ String.intercalate ", " (summary.toList.map itemString) ++ "]"

def expectedUsesFailure? (expected : ExpectedUses) : CoreM (Option String) := do
  let actualStatement := useRefSummary (← statementUses expected.labelText)
  let actualProof := useRefSummary (← proofUses expected.labelText)
  if actualStatement == expected.statement && actualProof == expected.proof then
    return none
  else
    return some <|
      s!"{expected.labelText}: statement expected {summaryString expected.statement}, " ++
      s!"got {summaryString actualStatement}; proof expected {summaryString expected.proof}, " ++
      s!"got {summaryString actualProof}"

def expectedUsesFailures (expectedUses : Array ExpectedUses) : CoreM (Array String) := do
  let mut failures := #[]
  for expected in expectedUses do
    if let some failure ← expectedUsesFailure? expected then
      failures := failures.push failure
  pure failures

end Verso.VersoBlueprintTests.BlueprintAutoDeps.Support
