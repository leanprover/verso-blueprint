/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.Statement

open Lean Informal

run_cmd discard <| Environment.contribute `key_theorem { priority := some "high" }

-- A rejected new label must not reserve its requested number or export/index
-- any of its otherwise valid data.
/-- error: Label rejected_new_node declares conflicting proof dependency intents for 'dep' (manual): existing 'regular', new 'technical' -/
#guard_msgs in
#eval show CoreM Unit from do
  let before := Environment.informalExt.getState (← getEnv)
  discard <| Environment.contribute `rejected_new_node {
    count := before.nextCount + 100
    proofUses := #[{ label := `dep }, { label := `dep, intent := .technical }]
    leanCode := #[.external #[{ canonical := `rejectedNewDecl, written := `rejectedNewDecl, present := true }]]
  }
  let after := Environment.informalExt.getState (← getEnv)
  unless reprStr before.data == reprStr after.data &&
      before.nextCount == after.nextCount &&
      reprStr before.localContributions == reprStr after.localContributions &&
      before.leanNameLabels.toArray == after.leanNameLabels.toArray do
    throwError "Rejected new label changed one of the node stores"

-- A rejected contribution must not leak its otherwise valid proof, tags, code,
-- exports, or declaration-index changes.
/-- error: Label key_theorem declares conflicting priorities: existing 'high', new 'low' -/
#guard_msgs in
#eval show CoreM Unit from do
  let before := Environment.informalExt.getState (← getEnv)
  discard <| Environment.contribute `key_theorem {
    count := before.nextCount + 100
    priority := some "low"
    tags := #["rejected"]
    proofBody := some { stx := .missing, previewBlocks := #[.para #[.text "Rejected proof"]] }
    leanCode := #[.external #[{ canonical := `rejectedDecl, written := `rejectedDecl, present := true }]]
  }
  let after := Environment.informalExt.getState (← getEnv)
  unless reprStr before.data == reprStr after.data &&
      before.nextCount == after.nextCount &&
      reprStr before.localContributions == reprStr after.localContributions &&
      before.leanNameLabels.toArray == after.leanNameLabels.toArray do
    throwError "Rejected contribution changed one of the node stores"

-- Repeating equal single-valued metadata is idempotent and does not warn.
#guard_msgs in
run_cmd discard <| Environment.contribute `key_theorem { priority := some "high" }


open Verso.Genre Lean.Elab.Command

-- Exercise real directive elaboration, including changes made while elaborating
-- the body. The complete Blueprint state must survive a rejected directive.
elab "#check_blueprint_atomic " command:command : command => do
  let before := Environment.informalExt.getState (← getEnv)
  try
    elabCommand command
  finally
    let after := Environment.informalExt.getState (← getEnv)
    unless reprStr before == reprStr after do
      throwError "Rejected directive changed Blueprint state"

@[blueprint "atomic_dependency"] theorem atomicDependency : True := trivial
theorem atomicWitness : True := atomicDependency

#docs (Manual) atomicPlaceholder "Atomic placeholder" :=
:::::::
:::theorem "atomic_directive" (priority := "high")
:::
:::::::

/-- error: Label atomic_directive declares conflicting priorities: existing 'high', new 'low' -/
#guard_msgs in
#check_blueprint_atomic
#docs (Manual) rejectedWithDependencies "Rejected contributions" :=
:::::::
:::theorem "atomic_directive" (priority := "low") (lean := "atomicWitness") (autoDeps := true)
Rejected statement and inferred dependencies.

```rust "atomic_side_effect"
pub fn rejected_attachment() {}
```
:::
:::::::

/-- error: Unexpected argument (unexpected := true) -/
#guard_msgs in
#check_blueprint_atomic
#docs (Manual) malformedAtomicDirective "Malformed role" :=
:::::::
:::theorem "atomic_malformed"
{bpref "atomic_directive" (unexpected := true)}[]
:::
:::::::

/-- error: Cannot declare nested definitions -/
#guard_msgs in
#check_blueprint_atomic
#docs (Manual) nestedAtomicDirective "Nested declaration" :=
:::::::
::::theorem "atomic_outer"
Outer statement.

:::theorem "atomic_inner"
Inner statement.
:::
::::
:::::::

-- This reports an error without throwing out of the body elaborator.
/-- error: Label atomic_duplicate_rust already has associated Rust code -/
#guard_msgs in
#check_blueprint_atomic
#docs (Manual) loggedAtomicFailure "Logged body failure" :=
:::::::
:::theorem "atomic_logged"
```rust "atomic_duplicate_rust"
pub fn first() {}
```

```rust "atomic_duplicate_rust"
pub fn second() {}
```
:::
:::::::

-- Errors during argument resolution are part of the same transaction.
/-- error: Label atomic_bad_config has invalid '(effort := "huge")'; expected one of "small", "medium", "large" -/
#guard_msgs in
#check_blueprint_atomic
#docs (Manual) invalidAtomicConfig "Invalid metadata" :=
:::::::
:::theorem "atomic_bad_config" (effort := "huge")
Rejected metadata must not create a partially accepted statement.
:::
:::::::

-- Both exceptions and logged errors must leave a valid following directive usable.
#guard_msgs in
#docs (Manual) afterAtomicFailures "Recovery" :=
:::::::
:::theorem "atomic_recovered"
A valid statement after rejected declarations.
:::
:::::::

run_cmd do
  let state := Environment.informalExt.getState (← getEnv)
  unless state.activeDirective.isNone &&
      (state.data.get? `atomic_recovered).any (·.hasStatementBody) do
    throwError "Directive scope did not recover after failure"
