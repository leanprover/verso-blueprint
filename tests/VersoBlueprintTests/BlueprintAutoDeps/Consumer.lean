/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintAutoDeps.Reexport
import VersoBlueprintTests.BlueprintAutoDeps.Support

open Lean
open Informal
open Verso.VersoBlueprintTests.BlueprintAutoDeps.Support

namespace Verso.VersoBlueprintTests.BlueprintAutoDeps.Consumer

@[blueprint "auto.imported.target" (autoDeps := true)]
theorem importedTarget :
    Verso.VersoBlueprintTests.BlueprintAutoDeps.Provider.typeSource := by
  trivial

@[blueprint "auto.imported.manual_decl"
  (uses := [Verso.VersoBlueprintTests.BlueprintAutoDeps.Provider.manualExtra])]
theorem importedManualDeclTarget : True := by
  trivial

private def expectedUsesMatrix : Array ExpectedUses :=
  #[
    -- Automatic inference by dependency axis.
    {
      labelText := "auto.type.target",
      statement := #[useRef "auto.type.source" .automatic]
    },
    {
      labelText := "auto.proof.target",
      proof := #[useRef "auto.proof.source" .automatic]
    },
    {
      labelText := "auto.def.target",
      proof := #[useRef "auto.def.source" .automatic]
    },
    {
      labelText := "auto.imported.target",
      statement := #[useRef "auto.type.source" .automatic]
    },
    -- Manual dependencies and imported declarations.
    {
      labelText := "auto.imported.manual_decl",
      statement := #[useRef "auto.manual.extra"]
    },
    -- Helpers have no nodes themselves, but expose the first associated declarations.
    {
      labelText := "auto.untagged.target"
    },
    {
      labelText := "auto.untagged.type_target",
      statement := #[useRef "auto.type.source" .automatic]
    },
    {
      labelText := "auto.untagged.proof_target",
      proof := #[useRef "auto.proof.source" .automatic]
    },
    {
      labelText := "auto.duplicate_axis.target",
      statement := #[useRef "auto.def.source" .automatic]
    },
    -- Manual entries, exclusions, duplicate-axis suppression, and manual precedence.
    {
      labelText := "auto.manual.target",
      statement := #[useRef "auto.manual.extra"]
    },
    {
      labelText := "auto.manual.same_axis",
      statement := #[useRef "auto.type.source"]
    },
    {
      labelText := "auto.add_exclude.same_axis"
    },
    {
      labelText := "auto.overlap.target",
      statement := #[useRef "auto.type.source" .automatic],
      proof := #[useRef "auto.type.source"]
    },
    {
      labelText := "auto.decl.manual_no_auto",
      statement := #[useRef "auto.type.source"]
    },
    -- String labels and proof-only manual entries.
    {
      labelText := "auto.string.target",
      statement := #[useRef "auto.synthetic.label"]
    },
    {
      labelText := "auto.string.proof_only",
      proof := #[useRef "auto.synthetic.proof"]
    },
    {
      labelText := "auto.manual.proof_only",
      proof := #[useRef "auto.proof.source"]
    },
    -- Self edges are always suppressed.
    {
      labelText := "auto.self.string_target"
    },
    {
      labelText := "auto.self.decl_target"
    }
  ]

/-- info: true -/
#guard_msgs in
#eval
  let auto := dataUseRef "auto.merge.target" .automatic
  let manual := dataUseRef "auto.merge.target"
  let other := dataUseRef "auto.merge.other" .automatic
  Data.UseRef.mergeByLabel #[auto] #[manual] == #[manual] &&
  Data.UseRef.mergeByLabel #[manual] #[auto] == #[manual] &&
  Data.UseRef.mergeByLabel #[auto] #[other] == #[auto, other]

/-- info: #[] -/
#guard_msgs in
#eval
  show CoreM (Array String) from do
    expectedUsesFailures expectedUsesMatrix

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let sharedLabels ←
      Environment.labelsForLeanDecl
        `Verso.VersoBlueprintTests.BlueprintAutoDeps.Provider.sharedSource
    let sharedUses ← statementUses "auto.shared.target"
    let expectedLabels := labels #[
      "auto.shared.source.primary",
      "auto.shared.source.secondary"
    ]
    pure <|
      sharedLabels.size == expectedLabels.size &&
      expectedLabels.all (fun label => sharedLabels.contains label) &&
      sharedUses.size == expectedLabels.size &&
      expectedLabels.all (fun label =>
        sharedUses.any fun useRef =>
          useRef.label == label && useRef.origin == .automatic)

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let providerLabels ←
      Environment.labelsForLeanDecl
        `Verso.VersoBlueprintTests.BlueprintAutoDeps.Provider.typeSource
    let env ← getEnv
    let some reexportIdx := env.getModuleIdx? `VersoBlueprintTests.BlueprintAutoDeps.Reexport
      | return false
    let reexportEntries := Environment.informalExt.getModuleEntries env reexportIdx
    pure <|
      providerLabels == labels #["auto.type.source"] &&
      reexportEntries.isEmpty

end Verso.VersoBlueprintTests.BlueprintAutoDeps.Consumer
