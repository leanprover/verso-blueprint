/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintInformal.Shared

open Lean
open Verso Genre Manual
open Informal
open Verso.VersoBlueprintTests.BlueprintInformal.Shared

namespace Verso.VersoBlueprintTests.BlueprintInformal.LeanRefs

inductive AttachedInductive where
  /-- Constructor used to exercise inductive external references. -/
  | mk

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

/--
error: Label «proof.external.forbidden» cannot use '(lean := ...)' in a proof block
-/
#guard_msgs in
#docs (Manual) proofLeanForbidden "Proof Lean Forbidden" :=
:::::::
:::lemma_ "proof.external.forbidden"
Statement body.
:::
:::proof "proof.external.forbidden" (lean := "Nat.add")
Proof body.
:::
:::::::

/--
error: Label «conflict.ext.inline» has both '(lean := ...)' and an associated Lean code block; preferring inline code
-/
#guard_msgs in
#docs (Manual) conflictExternalThenInline "Conflict External Then Inline" :=
:::::::
:::definition "conflict.ext.inline" (lean := "Nat.add")
Simple body.
:::

```lean "conflict.ext.inline"
def conflictExternalThenInlineValue : Nat := Nat.succ 0
```
:::::::

/--
error: Label «conflict.inline.ext» has both an associated Lean code block and '(lean := ...)'; preferring inline code
-/
#guard_msgs in
#docs (Manual) conflictInlineThenExternal "Conflict Inline Then External" :=
:::::::
```lean "conflict.inline.ext"
def conflictInlineThenExternalValue : Nat := Nat.succ 1
```

:::definition "conflict.inline.ext" (lean := "Nat.add")
Simple body.
:::
:::::::

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
      match node.code with
      | some (.external #[ref]) =>
        ref.present &&
        ref.kind == .definition &&
        ref.canonical == `Verso.VersoBlueprintTests.BlueprintInformal.LeanRefs.AttachedInductive &&
        ref.render.isOk
      | _ => false

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
    pure node.code.isNone

set_option verso.blueprint.trimTeXLabelPrefix false

end Verso.VersoBlueprintTests.BlueprintInformal.LeanRefs
