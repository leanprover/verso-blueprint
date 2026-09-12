/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintAutoDeps.Preview

set_blueprint_helper_expansion .all

open Verso
open Verso.Genre.Manual
open Lean
open Informal
open Verso.VersoBlueprintTests.Blueprint.Support

set_option doc.verso true

def manualImpls : ExtensionImpls := extension_impls%

private def label (s : String) : Name :=
  Name.mkSimple s

@[blueprint "auto.demo.type_source"]
def autoDemoTypeSource : Prop := True

@[blueprint "auto.demo.proof_source"]
theorem autoDemoProofSource : True := by
  trivial

@[blueprint "auto.demo.manual_extra"]
theorem autoDemoManualExtra : True := by
  trivial

def autoDemoTypeAlias : Prop := autoDemoTypeSource
theorem autoDemoProofHelper : True := autoDemoProofSource

@[blueprint "auto.demo.statement_target"
  (autoDeps := true)
  (uses := ["auto.demo.manual_extra"])]
theorem autoDemoStatementTarget : autoDemoTypeAlias := by
  trivial

@[blueprint "auto.demo.proof_target"
  (autoDeps := true)
  (proofUses := [autoDemoManualExtra])]
theorem autoDemoProofTarget : True := by
  exact autoDemoProofHelper

@[blueprint "auto.demo.excluded_target"
  (autoDeps := true)
  (uses := [-"auto.demo.type_source", "auto.demo.manual_extra"])]
theorem autoDemoExcludedTarget : autoDemoTypeSource := by
  trivial

theorem autoDemoExternalTargetDecl : autoDemoTypeAlias := by
  exact autoDemoProofHelper

theorem autoDemoExternalOptOutDecl : autoDemoTypeSource := by
  exact autoDemoProofSource

set_option verso.blueprint.autoDeps true

#docs (Genre.Manual) autoDepsPreviewDoc "Lean Auto Dependencies" :=
:::::::
Inspect `auto.demo.statement_target` for a statement panel with one automatic
edge and one manual edge, `auto.demo.proof_target` for the same split on a
proof panel, and `auto.demo.excluded_target` for an automatic edge removed by
an attribute exclusion. This file also enables
`set_option verso.blueprint.autoDeps true` for the examples that use
`(lean := "...")` and inline Lean code. It explicitly selects
`set_blueprint_helper_expansion .all` to follow unassociated helpers.

:::definition "auto.demo.type_source"
Tagged source declaration used by another declaration's type. Edges to this
node can pass through unassociated type aliases without giving those aliases nodes.
:::

:::theorem "auto.demo.proof_source"
Tagged source theorem used by another declaration's proof. Edges to this node
should appear on proof dependency chips, not statement dependency chips.
:::

:::theorem "auto.demo.manual_extra"
Manual comparison dependency. This edge is written in the attribute options, so
it should stay manual while inferred edges are marked automatic.
:::

:::theorem "auto.demo.statement_target"
The Lean statement uses `autoDemoTypeAlias`, which leads to `autoDemoTypeSource`,
so automatic dependency inference adds `auto.demo.type_source`. The attribute also adds
`auto.demo.manual_extra` manually, making the statement dependency panel show
both origins side by side.
:::

:::theorem "auto.demo.proof_target"
The Lean statement is just `True`, so there is no inferred statement dependency.
The proof below reaches `autoDemoProofSource` through `autoDemoProofHelper`.
:::

:::proof "auto.demo.proof_target"
The Lean proof body reaches `autoDemoProofSource` through a helper, so automatic dependency
inference adds `auto.demo.proof_source` to the proof dependencies. The attribute
also adds `auto.demo.manual_extra` manually for comparison.
:::

:::theorem "auto.demo.excluded_target"
The Lean statement mentions `autoDemoTypeSource`, but the attribute excludes
`auto.demo.type_source`. Only the manually listed `auto.demo.manual_extra`
dependency remains.
:::

:::theorem "auto.demo.external_target" (lean := "autoDemoExternalTargetDecl")
This node points at an existing compiled Lean declaration with `(lean := ...)`.
The file option enables automatic dependencies, so the declaration's type and
proof body provide statement and proof edges through the same helpers.
:::

:::definition "auto.demo.inline_target"
This node has an inline Lean block. The file option also enables automatic
dependencies for the declarations defined in the block.
:::

```lean "auto.demo.inline_target"
theorem autoDemoInlineTargetDecl : autoDemoTypeAlias := by
  exact autoDemoProofHelper
```

:::theorem "auto.demo.external_opt_out" (lean := "autoDemoExternalOptOutDecl") (autoDeps := false)
This node points at a compiled Lean declaration, but locally disables automatic
dependency inference.
:::

:::theorem "auto.demo.viewer"
A prose-first node links to the inferred targets with ordinary manual
dependencies: {uses "auto.demo.statement_target"}[],
{uses "auto.demo.proof_target"}[], {uses "auto.demo.external_target"}[], and
{uses "auto.demo.inline_target"}[].
:::

{blueprint_graph}

{blueprint_summary}
:::::::

/-- Captured in this fixture's environment before unrelated fixtures are imported. -/
def autoDepsPreviewDocBlueprint : Informal.BlueprintDocument := .capture autoDepsPreviewDoc.toPart

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let some node ← Environment.getNode? (label "auto.demo.statement_target")
      | return false
    let some statement := node.statement
      | return false
    pure <|
      statement.hasBody &&
      statement.deps ==
        #[
          { label := label "auto.demo.type_source", origin := .automatic },
          { label := label "auto.demo.manual_extra" }
        ]

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let some node ← Environment.getNode? (label "auto.demo.proof_target")
      | return false
    let some proof := node.proof
      | return false
    pure <|
      proof.hasBody &&
      proof.deps ==
        #[
          { label := label "auto.demo.proof_source", origin := .automatic },
          { label := label "auto.demo.manual_extra" }
        ]

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let some node ← Environment.getNode? (label "auto.demo.excluded_target")
      | return false
    let some statement := node.statement
      | return false
    pure <|
      statement.hasBody &&
      statement.deps == #[{ label := label "auto.demo.manual_extra" }]

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let some node ← Environment.getNode? (label "auto.demo.external_target")
      | return false
    let some statement := node.statement
      | return false
    let some proof := node.proof
      | return false
    pure <|
      statement.deps == #[{ label := label "auto.demo.type_source", origin := .automatic }] &&
      proof.deps == #[{ label := label "auto.demo.proof_source", origin := .automatic }]

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let some node ← Environment.getNode? (label "auto.demo.inline_target")
      | return false
    let some statement := node.statement
      | return false
    let some proof := node.proof
      | return false
    pure <|
      statement.deps == #[{ label := label "auto.demo.type_source", origin := .automatic }] &&
      proof.deps == #[{ label := label "auto.demo.proof_source", origin := .automatic }]

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let some node ← Environment.getNode? (label "auto.demo.external_opt_out")
      | return false
    let statementDeps := node.statement.map (·.deps) |>.getD #[]
    let proofDeps := node.proof.map (·.deps) |>.getD #[]
    pure <| statementDeps.isEmpty && proofDeps.isEmpty

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let labels :=
      #[
        "auto.demo.type_source",
        "auto.demo.proof_source",
        "auto.demo.manual_extra",
        "auto.demo.statement_target",
        "auto.demo.proof_target",
        "auto.demo.excluded_target",
        "auto.demo.external_target",
        "auto.demo.inline_target",
        "auto.demo.external_opt_out",
        "auto.demo.viewer"
      ]
    let counts ← labels.mapM fun labelText => do
      let some node ← Environment.getNode? (label labelText)
        | return 0
      return node.count
    pure <| counts == #[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls autoDepsPreviewDoc
    pure <|
      hasSubstr out "auto.demo.type_source" &&
      hasSubstr out "auto.demo.statement_target" &&
      hasSubstr out "auto.demo.proof_target" &&
      hasSubstr out "auto.demo.excluded_target" &&
      hasSubstr out "auto.demo.external_target" &&
      hasSubstr out "auto.demo.inline_target" &&
      hasSubstr out "auto.demo.external_opt_out" &&
      hasSubstr out "Statement uses 2" &&
      hasSubstr out "Proof uses 2" &&
      hasSubstr out "Origin: automatic"

end Verso.VersoBlueprintTests.BlueprintAutoDeps.Preview
