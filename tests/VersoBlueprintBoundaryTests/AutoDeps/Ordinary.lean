/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
module

import VersoBlueprint
meta import VersoBlueprint
import VersoBlueprintBoundaryTests.AutoDeps.Provider

open Lean Informal
namespace VersoBlueprintBoundaryTests.AutoDeps

@[blueprint "module.auto.direct" (autoDeps := true)]
def direct : Nat := source

@[blueprint "module.auto.hidden" (autoDeps := true)]
def hidden : Nat := hiddenHelper

@[blueprint "module.auto.exposed" (autoDeps := true)]
def exposed : Nat := exposedHelper

@[blueprint "module.auto.theorem" (autoDeps := true)]
theorem viaTheorem : True := proofHelper

@[blueprint "module.auto.type" (autoDeps := true)]
theorem viaType : proposition := True.intro

/-- error: invalid attribute '[blueprint]', declaration is in an imported module -/
#guard_msgs in
attribute [blueprint "module.auto.illegal"] source

run_meta do
  for (label, statement, proof) in #[
      ("module.auto.direct", #[], #["module.auto.source"]),
      ("module.auto.hidden", #[], #[]),
      ("module.auto.exposed", #[], #["module.auto.source"]),
      ("module.auto.theorem", #[], #[]),
      ("module.auto.type", #["module.auto.proposition"], #[]),
      ("module.auto.persisted", #[], #["module.auto.source"]),
      ("module.auto.private", #[], #["module.auto.source"]),
      ("module.auto.persisted_proof", #[], #["module.auto.proof"])] do
    let some node ← Environment.getNode? (Name.mkSimple label)
      | throwError "Missing imported attribute node {label}"
    unless node.blueprintAttributeAttachments && node.externalRefs.all (·.provedStatus == .proved) do
      throwError "{label}: lost local declaration status or attribute capability"
    let actualStatement := (node.statement.map (·.deps)).getD #[] |>.map (·.label)
    let actualProof := (node.proof.map (·.deps)).getD #[] |>.map (·.label)
    unless actualStatement == statement.map Name.mkSimple && actualProof == proof.map Name.mkSimple do
      throwError "{label}: statement {actualStatement}, proof {actualProof}"
    for dep in (node.statement.map (·.deps)).getD #[] ++ (node.proof.map (·.deps)).getD #[] do
      unless dep.origin == .automatic do
        throwError "{label}: lost automatic origin"
  let catalog ← Environment.blueprintAttributeLabelsForModule
    `VersoBlueprintBoundaryTests.AutoDeps.Provider
  unless catalog.contains (Name.mkSimple "module.auto.private") do
    throwError "Private attribute node lost its module catalog entry"

#docs (Verso.Genre.Manual) importedAttributes "Imported attributes" :=
:::::::
{includeBlueprintModule VersoBlueprintBoundaryTests.AutoDeps.Provider}

# Local consumers

:::definition "module.auto.external_hidden" (lean := "hiddenHelper") (autoDeps := true)
An imported hidden body cannot be scanned by an external attachment either.
:::

:::definition "module.auto.external_exposed" (lean := "exposedHelper") (autoDeps := true)
An exposed imported definition can be scanned.
:::

:::definition "module.auto.inline"
Inline declarations use the same visibility rules.
:::

```lean "module.auto.inline" (autoDeps := true)
def inlineConsumer : Nat := exposedHelper
```
:::::::

run_meta do
  for (label, expected) in #[
      ("module.auto.external_hidden", #[]),
      ("module.auto.external_exposed", #["module.auto.source"]),
      -- The earlier external attachment is now the first associated frontier.
      ("module.auto.inline", #["module.auto.external_exposed"])] do
    let some node ← Environment.getNode? (Name.mkSimple label)
      | throwError "Missing node {label}"
    let actual := (node.proof.map (·.deps)).getD #[] |>.map (·.label)
    unless actual == expected.map Name.mkSimple do
      throwError "{label}: expected {expected}, got {actual}"

end VersoBlueprintBoundaryTests.AutoDeps
