/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint

open Verso.Genre
open Informal

namespace ImportedContributions

def statementDependency : Prop := True

theorem proofDependency : statementDependency := trivial

end ImportedContributions

#doc (Manual) "Statement chapter" =>

:::group "split_group"
Split statement and proof
:::

:::author "split_author" (name := "Split Author")
:::

:::definition "statement_dep" (lean := "ImportedContributions.statementDependency")
A statement dependency.
:::

:::lemma_ "proof_dep" (lean := "ImportedContributions.proofDependency")
A proof dependency.
:::

:::theorem "key_theorem" (uses := "statement_dep") (parent := "split_group") (owner := "split_author") (tags := "statement")
A statement declared in this module.
:::
