/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintBlockFolding

open Verso
open Verso.Genre.Manual
open Informal
open Verso.VersoBlueprintTests.Blueprint.Support

private def manualImpls : ExtensionImpls := extension_impls%

set_option doc.verso true

#docs (Genre.Manual) defaultProofBlockDoc "Default Proof Block" :=
:::::::
:::definition "folding.default.proof"
Default proof statement.
:::

:::proof "folding.default.proof"
Default proof body.
:::
:::::::

#docs (Genre.Manual) proofTargetTitleDoc "Proof Target Title" :=
:::::::
:::lemma_ "display.lemma.proof"
Lemma statement.
:::

:::proof "display.lemma.proof"
Lemma proof body.
:::
:::::::

#docs (Genre.Manual) blockKindDisplayDoc "Block Kind Display" :=
:::::::
:::proposition "display.proposition"
Proposition statement.
:::
:::::::

set_option verso.blueprint.foldProofBlocks true

#docs (Genre.Manual) foldedProofBlockDoc "Folded Proof Block" :=
:::::::
:::definition "folding.folded.proof"
Folded proof statement.
:::

:::proof "folding.folded.proof"
Folded proof body.
:::

{blueprint_node "folding.folded.proof" (facet := "proof")}
:::::::

set_option verso.blueprint.foldProofBlocks false

#docs (Genre.Manual) defaultCodeBlockDoc "Default Code Block" :=
:::::::
```lean "folding.default.lean"
def defaultCodeBlockWitness : Nat := 1
```
:::::::

#docs (Genre.Manual) openCodeBlockDoc "Open Code Blocks" :=
:::::::
```lean "folding.open.lean"
def openCodeBlockWitness : Nat := 1
```

```rust "folding.open.rust"
pub fn open_rust_block() -> i32 {
    1
}
```
:::::::

set_option verso.blueprint.foldCodeBlocks true

#docs (Genre.Manual) foldedCodeBlockDoc "Folded Code Blocks" :=
:::::::
```lean "folding.folded.lean"
def foldedCodeBlockWitness : Nat := 1
```
:::::::

set_option verso.blueprint.foldCodeBlocks false

/-- info: true -/
#guard_msgs in
#eval! do
  let out ← renderManualDocHtmlString manualImpls defaultProofBlockDoc
  pure <|
    hasSubstr out "<div class=\"bp_wrapper bp_kind_proof_wrapper" &&
    !hasSubstr out "<details class=\"bp_wrapper bp_kind_proof_wrapper" &&
    hasSubstr out "Default proof body."

/-- info: true -/
#guard_msgs in
#eval! do
  let out ← renderManualDocHtmlString manualImpls proofTargetTitleDoc
  pure <|
    hasSubstr out "Proof for Lemma" &&
    hasSubstr out "Lemma proof body."

/-- info: true -/
#guard_msgs in
#eval! do
  let out ← renderManualDocHtmlString manualImpls blockKindDisplayDoc
  pure <|
    hasSubstr out "bp_kind_proposition_wrapper" &&
    hasSubstr out "Proposition"

/-- info: true -/
#guard_msgs in
#eval! do
  let out ← renderManualDocHtmlString manualImpls foldedProofBlockDoc
  pure <|
    countSubstr out "<details class=\"bp_wrapper bp_kind_proof_wrapper" == 2 &&
    hasSubstr out "class=\"bp_graft_node_blueprint\"" &&
    hasSubstr out "<summary class=\"bp_heading bp_kind_proof_heading" &&
    hasSubstr out "Folded proof body."

/-- info: true -/
#guard_msgs in
#eval! do
  let out ← renderManualDocHtmlString manualImpls defaultCodeBlockDoc
  pure <|
    hasSubstr out "class=\"bp_code_block bp_code_panel\"" &&
    hasSubstr out "data-bp-proof-fold=\"on\"" &&
    hasSubstr out "open=\"open\""

/-- info: true -/
#guard_msgs in
#eval! do
  let out ← renderManualDocHtmlString manualImpls openCodeBlockDoc
  pure <|
    countSubstr out "class=\"bp_code_block bp_code_panel\"" == 2 &&
    countSubstr out "open=\"open\"" == 2 &&
    hasSubstr out "openCodeBlockWitness" &&
    hasSubstr out "open_rust_block"

/-- info: true -/
#guard_msgs in
#eval! do
  let out ← renderManualDocHtmlString manualImpls foldedCodeBlockDoc
  pure <|
    hasSubstr out "class=\"bp_code_block bp_code_panel\"" &&
    hasSubstr out "foldedCodeBlockWitness" &&
    !hasSubstr out "open=\"open\""

end Verso.VersoBlueprintTests.BlueprintBlockFolding
