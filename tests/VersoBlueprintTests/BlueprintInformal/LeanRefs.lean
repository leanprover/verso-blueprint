/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintInformal.Shared
import VersoBlueprintTests.Blueprint.Support

open Lean
open Verso Genre Manual
open Informal
open Verso.VersoBlueprintTests.Blueprint.Support
open Verso.VersoBlueprintTests.BlueprintInformal.Shared

namespace Verso.VersoBlueprintTests.BlueprintInformal.LeanRefs

private def manualImpls : ExtensionImpls := extension_impls%

private def attachedInductiveName : Name :=
  `Verso.VersoBlueprintTests.BlueprintInformal.LeanRefs.AttachedInductive

inductive AttachedInductive where
  /-- Constructor used to exercise inductive external references. -/
  | mk

private def attachedInductiveCtorAndRecursor? : CoreM (Option (Name × Name)) := do
  let env ← getEnv
  match env.find? attachedInductiveName with
  | some (.inductInfo info) =>
    pure <| info.ctors.head?.map fun ctorName =>
      (ctorName, Lean.mkRecName info.name)
  | _ =>
    pure none

private def externalRefRejectedWithKind (decl : Name) (expectedKind : String) : CoreM Bool := do
  let opts ← getOptions
  try
    let _ ← Informal.externalRefSnapshotAtCurrentDir opts (Informal.Data.ExternalRef.ofName decl)
    pure false
  catch ex =>
    let msg ← liftM <| ex.toMessageData.toString
    pure <|
      msg.contains s!"with kind '{expectedKind}'" &&
      msg.contains "Only definition-like declarations, theorems, and axiom-like placeholders are currently supported."

/-- info: true -/
#guard_msgs in
#eval
  Informal.shouldWritePreviewDataByIds (#[] : Array Nat) 7 &&
  Informal.shouldWritePreviewDataByIds #[1, 7, 9] 7 &&
  !(Informal.shouldWritePreviewDataByIds #[1, 2, 3] 7)

/--
warning: Label «bad.warning»: external Lean name 'No.Such.Decl' could not be resolved in current namespace/open declarations; keeping parsed name
-/
#guard_msgs in
#docs (Manual) malformedLeanRef "Malformed Lean Ref" :=
:::::::
:::definition "bad.warning" (lean := "No.Such.Decl")
Simple body.
:::
:::::::

/--
error: Label «bad.duplicate» has duplicate external Lean reference 'Nat.add' (canonical 'Nat.add'); previously declared as 'Nat.add'
-/
#guard_msgs in
#docs (Manual) duplicateLeanRefs "Duplicate Lean Refs" :=
:::::::
:::definition "bad.duplicate" (lean := "Nat.add, Nat.add")
Simple body.
:::
:::::::

#docs (Manual) conflictExternalThenInline "Conflict External Then Inline" :=
:::::::
:::definition "conflict.ext.inline" (lean := "Nat.add")
Simple body.
:::

```lean "conflict.ext.inline"
def conflictExternalThenInlineValue : Nat := Nat.succ 0
```
:::::::

#docs (Manual) conflictInlineThenExternal "Conflict Inline Then External" :=
:::::::
```lean "conflict.inline.ext"
def conflictInlineThenExternalValue : Nat := Nat.succ 1
```

:::definition "conflict.inline.ext" (lean := "Nat.add")
Simple body.
:::
:::::::

private def hasLabel (labels : Array Informal.Data.Label) (label : String) : Bool :=
  labels.contains (Name.mkSimple label)

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let natAddLabels ← Environment.labelsForLeanDecl `Nat.add
    let extInlineLabels ←
      Environment.labelsForLeanDecl
        `Verso.VersoBlueprintTests.BlueprintInformal.LeanRefs.conflictExternalThenInlineValue
    let inlineExtLabels ←
      Environment.labelsForLeanDecl
        `Verso.VersoBlueprintTests.BlueprintInformal.LeanRefs.conflictInlineThenExternalValue
    let state ← currentState
    let some extInlineNode := state.data.get? (Name.mkSimple "conflict.ext.inline")
      | pure false
    let some inlineExtNode := state.data.get? (Name.mkSimple "conflict.inline.ext")
      | pure false
    pure <|
      hasLabel natAddLabels "conflict.ext.inline" &&
      hasLabel natAddLabels "conflict.inline.ext" &&
      hasLabel extInlineLabels "conflict.ext.inline" &&
      hasLabel inlineExtLabels "conflict.inline.ext" &&
      extInlineNode.externalRefs.any (fun ref => ref.canonical == `Nat.add) &&
      inlineExtNode.externalRefs.any (fun ref => ref.canonical == `Nat.add) &&
      extInlineNode.literateCodes.size == 1 &&
      inlineExtNode.literateCodes.size == 1

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let extInlineOut ← renderManualDocHtmlString manualImpls conflictExternalThenInline
    let inlineExtOut ← renderManualDocHtmlString manualImpls conflictInlineThenExternal
    pure <|
      hasSubstr extInlineOut "bp_external_decl_rendered" &&
      hasSubstr extInlineOut "Nat.add" &&
      hasSubstr extInlineOut "conflictExternalThenInlineValue" &&
      appearsBefore extInlineOut "Simple body." "bp_external_decl_rendered" &&
      appearsBefore extInlineOut "bp_external_decl_rendered" "conflictExternalThenInlineValue" &&
      hasSubstr inlineExtOut "bp_external_decl_rendered" &&
      hasSubstr inlineExtOut "Nat.add" &&
      hasSubstr inlineExtOut "conflictInlineThenExternalValue" &&
      appearsBefore inlineExtOut "conflictInlineThenExternalValue" "Simple body." &&
      appearsBefore inlineExtOut "Simple body." "bp_external_decl_rendered"

#docs (Manual) inductiveLeanRefAccepted "Inductive Lean Ref Accepted" :=
:::::::
:::definition "inductive.external" (lean := "AttachedInductive")
Simple body.
:::
:::::::

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let state ← currentState
    let some node := state.data.get? (Name.mkSimple "inductive.external")
      | pure false
    pure <|
      node.kind == .definition &&
      match node.externalRefs with
      | #[ref] =>
        ref.present &&
        ref.kind == .definition &&
        ref.canonical == `Verso.VersoBlueprintTests.BlueprintInformal.LeanRefs.AttachedInductive &&
        ref.render.isOk
      | _ => false

/-- info: true -/
#guard_msgs in
#eval!
  show CoreM Bool from do
    let some (ctorName, recursorName) ← attachedInductiveCtorAndRecursor?
      | pure false
    let env ← getEnv
    let ctorPresent := (env.find? ctorName).isSome
    let recursorPresent := (env.find? recursorName).isSome
    let ctorRejected ← externalRefRejectedWithKind ctorName "constructor"
    let recursorRejected ← externalRefRejectedWithKind recursorName "recursor"
    pure (ctorPresent && recursorPresent && ctorRejected && recursorRejected)

set_option verso.blueprint.trimTeXLabelPrefix true

/--
warning: Label «trim.external.name»: ignoring malformed names in '(lean := ...)' (thm:Nat.add (invalid Lean name 'thm:Nat.add'))
-/
#guard_msgs in
#docs (Manual) keepLeanExternalName "Keep Lean External Name" :=
:::::::
:::theorem "trim.external.name" (lean := "thm:Nat.add")
Simple body.
:::
:::::::

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let state ← currentState
    let some node := state.data.get? (Name.mkSimple "trim.external.name")
      | pure false
    pure !node.hasAssociatedCode

set_option verso.blueprint.trimTeXLabelPrefix false

end Verso.VersoBlueprintTests.BlueprintInformal.LeanRefs
