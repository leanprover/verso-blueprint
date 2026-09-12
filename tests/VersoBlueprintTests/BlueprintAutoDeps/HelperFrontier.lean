/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintAutoDeps.HelperProvider
import VersoBlueprintTests.BlueprintAutoDeps.Support
import VersoBlueprintTests.Blueprint.Support

open Lean Verso Verso.Genre.Manual Informal
open Verso.VersoBlueprintTests.BlueprintAutoDeps.Support
open Verso.VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintAutoDeps.HelperFrontier

set_blueprint_helper_expansion .all

open HelperProvider

@[blueprint "auto.frontier.attribute" (autoDeps := true)]
theorem attributeTarget : typeAlias := proofHop

@[blueprint "auto.frontier.diamond" (autoDeps := true)]
def diamondTarget : Nat := diamond

@[blueprint "auto.frontier.stopped" (autoDeps := true)]
def stoppedTarget : Nat := behindBoundary

@[blueprint "auto.frontier.excluded_boundary" (autoDeps := true)
  (proofUses := [-"auto.frontier.boundary"])]
def excludedBoundary : Nat := behindBoundary

-- The helper type is reached from the proof, so both resulting edges are proof-side.
@[blueprint "auto.frontier.helper_type" (autoDeps := true)]
theorem helperTypeTarget : True := proofHop

axiom axiomaticHelper : Provider.typeSource
@[blueprint "auto.frontier.axiom_leaf" (autoDeps := true)]
theorem axiomLeafTarget : True := axiomaticHelper

@[blueprint "auto.frontier.opaque" (autoDeps := true)]
def opaqueTarget : Nat := opaqueHelper

@[blueprint "auto.frontier.inductive" (autoDeps := true)]
def boxTarget : HiddenBox → Nat := fun _ => 0

@[blueprint "auto.frontier.recursive" (autoDeps := true)]
def recursiveTarget : Nat := left 4

@[blueprint "auto.frontier.shared" (autoDeps := true)]
theorem sharedTarget : sharedAlias := True.intro

@[blueprint "auto.frontier.manual" (autoDeps := true)
  (uses := ["auto.type.source"]) (proofUses := [-"auto.proof.source"])]
theorem manualTarget : typeAlias := proofHop

@[blueprint "auto.frontier.disabled" (autoDeps := false)]
theorem disabledTarget : typeAlias := proofHop

-- These Lean declarations are independent of Blueprint authoring.
theorem externalTarget : typeAlias := proofHop
def plainSource : Prop := True
def plainAlias : Prop := plainSource

set_option doc.verso true

#docs (Genre.Manual) helpersDoc "Dependencies through helpers" :=
:::::::
{includeBlueprintModule VersoBlueprintTests.BlueprintAutoDeps.HelperProvider}

# Local consumers

{blueprint_node "auto.frontier.attribute"}

:::theorem "auto.frontier.external" (lean := "externalTarget") (autoDeps := true)
An independent Lean declaration reaches imported attribute sources through helpers.
:::

:::definition "auto.frontier.plain_source" (lean := "plainSource")
An independent Lean source acquires its association in Blueprint.
:::

:::theorem "auto.frontier.inline"
Inline Lean reaches the same imported sources.
:::

```lean "auto.frontier.inline" (autoDeps := true)
theorem inlineTarget : typeAlias := proofHop
```

:::definition "auto.frontier.inline_source"
A source associated by inline Lean code.
:::

```lean "auto.frontier.inline_source"
def inlineSource : Prop := True
```
:::::::

def inlineAlias : Prop := inlineSource

-- Mixed authoring in the reverse direction: attributes consume prose/inline sources.
@[blueprint "auto.frontier.from_plain" (autoDeps := true)]
theorem fromPlain : plainAlias := True.intro

@[blueprint "auto.frontier.from_inline" (autoDeps := true)]
theorem fromInline : inlineAlias := True.intro

-- Inference observes current associations; there is no environment-wide frontier cache.
def lateSource : Prop := True
def lateHelper : Prop := lateSource
@[blueprint "auto.frontier.before" (autoDeps := true)]
theorem beforeAssociation : lateHelper := True.intro
attribute [blueprint "auto.frontier.late_source"] lateSource
@[blueprint "auto.frontier.after" (autoDeps := true)]
theorem afterAssociation : lateHelper := True.intro

#eval show CoreM Unit from do
  let common : Array ExpectedUses :=
    (#["auto.frontier.attribute", "auto.frontier.external", "auto.frontier.inline",
        "auto.frontier.persisted"]).map fun labelText =>
      { labelText, statement := #[useRef "auto.type.source" .automatic],
        proof := #[useRef "auto.proof.source" .automatic] }
  let failures ← expectedUsesFailures <| common ++ #[
    { labelText := "auto.frontier.diamond", proof := #[useRef "auto.def.source" .automatic] },
    { labelText := "auto.frontier.stopped", proof := #[useRef "auto.frontier.boundary" .automatic] },
    { labelText := "auto.frontier.excluded_boundary" },
    { labelText := "auto.frontier.helper_type",
      proof := #[useRef "auto.proof.source" .automatic, useRef "auto.type.source" .automatic] },
    { labelText := "auto.frontier.axiom_leaf" },
    { labelText := "auto.frontier.opaque", proof := #[useRef "auto.def.source" .automatic] },
    { labelText := "auto.frontier.inductive", statement := #[useRef "auto.type.source" .automatic] },
    { labelText := "auto.frontier.recursive", proof := #[useRef "auto.def.source" .automatic] },
    { labelText := "auto.frontier.shared",
      statement := #[useRef "auto.shared.source.primary" .automatic,
        useRef "auto.shared.source.secondary" .automatic] },
    { labelText := "auto.frontier.manual", statement := #[useRef "auto.type.source"] },
    { labelText := "auto.frontier.disabled" },
    { labelText := "auto.frontier.from_plain",
      statement := #[useRef "auto.frontier.plain_source" .automatic] },
    { labelText := "auto.frontier.from_inline",
      statement := #[useRef "auto.frontier.inline_source" .automatic] },
    { labelText := "auto.frontier.before" },
    { labelText := "auto.frontier.after",
      statement := #[useRef "auto.frontier.late_source" .automatic] }]
  unless failures.isEmpty do throwError "{failures}"

-- Exercise the collector's public API on a chain longer than Lean's default
-- recursion-depth budget. These are ordinary kernel-checked declarations;
-- inference inspects their expressions without needing compiled runtime code.
#eval show CoreM Unit from do
  let mut previous := ``Provider.defSource
  for i in [:2048] do
    let name := Name.num `blueprintHelperChain i
    addDecl <| .defnDecl {
      name, levelParams := [], type := mkConst ``Nat,
      value := mkConst previous, hints := .abbrev, safety := .safe }
    previous := name
  let deps ← DependencyAnalysis.inferDecl? previous
  unless deps.statement.isEmpty && deps.proof == #[label "auto.def.source"] do
    throwError "Long helper chain lost its frontier"
  -- Missing names are terminal, not fabricated nodes.
  let missing ← DependencyAnalysis.inferDecl? `blueprintMissingHelper
  unless missing.statement.isEmpty && missing.proof.isEmpty do
    throwError "Unknown declaration created a dependency"
  -- A tagged root is analyzed, not returned as its own frontier.
  let root ← DependencyAnalysis.inferDecl? ``HelperProvider.boundary
  unless root.statement.isEmpty && root.proof == #[label "auto.def.source"] do
    throwError "The root's association hid its dependencies"
  -- Exercise a programmatically supplied constructor association. The standard
  -- authoring syntax does not currently accept constructor attachments.
  let some _ ← Environment.contribute (label "auto.frontier.constructor") {
      leanCode := #[.external #[Data.ExternalRef.ofName ``HelperProvider.HiddenBox.mk]] }
    | throwError "Could not register the collector's constructor boundary"
  -- Inductive bodies walk constructor names, respecting their associations.
  let inductiveDeps ← DependencyAnalysis.inferDecl? ``HelperProvider.HiddenBox
  unless inductiveDeps.statement.isEmpty &&
      inductiveDeps.proof == #[label "auto.frontier.constructor"] do
    throwError "Inductive expansion bypassed an associated constructor"

private def impls : Genre.Manual.ExtensionImpls := extension_impls%

-- Check the projection boundary, not merely the elaboration-time environment.
#eval show IO Unit from do
  let files ← buildManualPreviewDataFiles impls helpersDoc
  for text in #["auto.frontier.attribute", "auto.frontier.external", "auto.frontier.inline",
      "auto.frontier.persisted"] do
    let some entry := files.manifest.previews.find? (fun entry =>
        entry.label == Name.mkSimple text && entry.facet == .statement)
      | throw <| IO.userError s!"Missing exported statement: {text}"
    unless entry.statementUses == #[{ label := label "auto.type.source", origin := .automatic }] &&
        entry.proofUses == #[{ label := label "auto.proof.source", origin := .automatic }] do
      throw <| IO.userError s!"Export lost inferred dependency axes: {text}"

end Verso.VersoBlueprintTests.BlueprintAutoDeps.HelperFrontier
