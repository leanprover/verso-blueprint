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
  unless reprStr before == reprStr after do
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
    issueUrl := some "https://example.com/issues/1"
    proofBody := some { stx := .missing, previewBlocks := #[.para #[.text "Rejected proof"]] }
    leanCode := #[.external #[{ canonical := `rejectedDecl, written := `rejectedDecl, present := true }]]
  }
  let after := Environment.informalExt.getState (← getEnv)
  unless reprStr before == reprStr after do
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

-- Standalone producers must agree with the accepted registry, even during recovery.
run_cmd do
  discard <| Environment.contribute `atomic_standalone {
    proofUses := #[{ label := `atomic_dependency, origin := .automatic, intent := .technical }] }
  discard <| Environment.contribute `atomic_standalone_markup {
    externalMarkup := ({} : Data.ExternalMarkupSet).insert {
      language := .markdown, slot := Data.defaultExternalMarkupSlot, raw := "Accepted markup" } }
  discard <| Environment.contribute `atomic_standalone_rust {
    rustCode := some { raw := "pub fn accepted() {}" } }

-- Attribute registration must not publish a module-catalog entry when its
-- contribution is rejected. The shared checker also covers declaration indexes.
/-- error: Label atomic_standalone declares conflicting proof dependency intents for 'atomic_dependency' (automatic): existing 'technical', new 'regular' -/
#guard_msgs in
#check_blueprint_atomic
@[blueprint "atomic_standalone" (autoDeps := true)]
theorem rejectedAttributeWitness : True := atomicDependency

/-- error: Label atomic_standalone declares conflicting proof dependency intents for 'atomic_dependency' (automatic): existing 'technical', new 'regular' -/
#guard_msgs in
#check_blueprint_atomic
#docs (Manual) rejectedStandaloneCode "Rejected standalone code" :=
:::::::
```lean "atomic_standalone" (autoDeps := true)
theorem rejectedStandaloneWitness : True := atomicDependency
```
:::::::

/-- error: Label atomic_standalone_markup already has associated markdown external markup in slot 'default' -/
#guard_msgs in
#check_blueprint_atomic
#docs (Manual) rejectedStandaloneMarkup "Rejected standalone markup" :=
:::::::
```md "atomic_standalone_markup"
Rejected markup.
```
:::::::

/-- error: Label atomic_standalone_rust already has associated Rust code -/
#guard_msgs in
#check_blueprint_atomic
#docs (Manual) rejectedStandaloneRust "Rejected standalone Rust" :=
:::::::
```rust "atomic_standalone_rust"
pub fn rejected() {}
```
:::::::

private partial def hasSemanticCode (block : Verso.Doc.Block Manual) : Bool :=
  match block with
  | .other container contents =>
      #[``Informal.Block.informalCode, ``Informal.Block.externalMarkup,
        ``Informal.Block.informalRustCode].contains container.name || contents.any hasSemanticCode
  | .concat contents => contents.any hasSemanticCode
  | _ => false

#eval show IO Unit from do
  for doc in #[rejectedStandaloneCode, rejectedStandaloneMarkup, rejectedStandaloneRust] do
    if doc.toPart.content.any hasSemanticCode then
      throw <| IO.userError "Rejected registration emitted a semantic code occurrence"

@[code_block]
def positionlessCode : Verso.Doc.Elab.CodeBlockExpanderOf Informal.CodeConfig :=
  fun cfg contents => MonadRef.withRef Syntax.missing (Informal.lean cfg contents)

/-- error: Blueprint code blocks require a source position -/
#guard_msgs in
#check_blueprint_atomic
#docs (Manual) rejectedPositionlessCode "Missing source identity" :=
:::::::
```positionlessCode "atomic_positionless"
theorem positionlessWitness : True := trivial
```
:::::::

-- Attribute/docstring producers must preserve every declaration until the
-- shared reducer validates it, including conflicts within a single docstring.
set_option doc.verso true

/-- error: Label attr_manual_forward declares conflicting statement dependency intents for 'dep' (manual): existing 'technical', new 'regular' -/
#guard_msgs in
#check_blueprint_atomic
/-- {uses "dep" (intent := "technical")}[] and {uses "dep"}[]. -/
@[blueprint "attr_manual_forward"]
def attrManualForward : Nat := 0

/-- error: Label attr_manual_reverse declares conflicting statement dependency intents for 'dep' (manual): existing 'regular', new 'technical' -/
#guard_msgs in
#check_blueprint_atomic
/-- {uses "dep"}[] and {uses "dep" (intent := "technical")}[]. -/
@[blueprint "attr_manual_reverse"]
def attrManualReverse : Nat := 0

-- Attribute list entries are manual/regular, not metadata-free duplicates.
/-- error: Label attr_config_conflict declares conflicting statement dependency intents for 'dep' (manual): existing 'technical', new 'regular' -/
#guard_msgs in
#check_blueprint_atomic
/-- {uses "dep" (intent := "technical")}[]. -/
@[blueprint "attr_config_conflict" (uses := ["dep"])]
def attrConfigConflict : Nat := 0

/-- error: Label attr_auto_forward declares conflicting statement dependency intents for 'dep' (automatic): existing 'regular', new 'technical' -/
#guard_msgs in
#check_blueprint_atomic
/--
{uses "dep" (origin := "automatic")}[],
{uses "dep" (intent := "auxiliary")}[],
{uses "dep" (origin := "automatic") (intent := "technical")}[].
-/
@[blueprint "attr_auto_forward"]
def attrAutoForward : Nat := 0

/-- error: Label attr_auto_reverse declares conflicting statement dependency intents for 'dep' (automatic): existing 'technical', new 'regular' -/
#guard_msgs in
#check_blueprint_atomic
/--
{uses "dep" (origin := "automatic") (intent := "technical")}[],
{uses "dep" (intent := "auxiliary")}[],
{uses "dep" (origin := "automatic")}[].
-/
@[blueprint "attr_auto_reverse"]
def attrAutoReverse : Nat := 0

@[blueprint "atomic_type"] def AtomicType := Nat

/-- error: Label attr_inference_conflict declares conflicting statement dependency intents for 'atomic_type' (automatic): existing 'regular', new 'technical' -/
#guard_msgs in
#check_blueprint_atomic
/-- {uses "atomic_type" (origin := "automatic") (intent := "technical")}[]. -/
@[blueprint "attr_inference_conflict" (autoDeps := true) (uses := ["atomic_type"])]
def attrInferenceConflict : AtomicType := (0 : Nat)

-- Equal declarations deduplicate, but manual precedence only projects the
-- effective edge; it must retain the automatic declaration for later validation.
/-- {uses "atomic_type"}[] and again {uses "atomic_type"}[]. -/
@[blueprint "attr_authorities" (autoDeps := true) (uses := ["atomic_type"])]
def attrAuthorities : AtomicType := (0 : Nat)

#docs (Manual) manualAuthorities "Manual authorities" :=
:::::::
:::definition "manual_authorities" (lean := "attrAuthorities") (autoDeps := true) (uses := "atomic_type")
Manual external-code authoring retains the same authority evidence.
:::
:::::::

run_cmd do
  for label in #[`attr_authorities, `manual_authorities] do
    let some node ← Environment.getNode? label | throwError "Missing node"
    let some statement := node.statement | throwError "Missing statement"
    unless statement.useDeclarations == #[
        { label := `atomic_type, origin := .automatic }, { label := `atomic_type }] &&
        statement.deps == #[{ label := `atomic_type }] do
      throwError "Normalization erased authority evidence or retained equal duplicates"

/-- error: Label attr_authorities declares conflicting statement dependency intents for 'atomic_type' (automatic): existing 'regular', new 'technical' -/
#guard_msgs in
#check_blueprint_atomic
run_cmd discard <| Environment.contribute `attr_authorities {
  statementUses := #[{ label := `atomic_type, origin := .automatic, intent := .technical }] }

/-- error: Label manual_authorities declares conflicting statement dependency intents for 'atomic_type' (automatic): existing 'regular', new 'technical' -/
#guard_msgs in
#check_blueprint_atomic
run_cmd discard <| Environment.contribute `manual_authorities {
  statementUses := #[{ label := `atomic_type, origin := .automatic, intent := .technical }] }
