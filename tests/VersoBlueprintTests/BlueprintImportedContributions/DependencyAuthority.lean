/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint

open Informal.Data
open Informal.NodeAssembly

-- Validate all permutations and every contiguous registration batching.
#eval show IO Unit from do
  let a : NodeContribution := { proofUses := #[{ label := `dep, origin := .automatic }] }
  let b : NodeContribution := { proofUses := #[{ label := `dep, origin := .automatic, intent := .technical }] }
  let m : NodeContribution := { proofUses := #[{ label := `dep, intent := .auxiliary }] }
  for refs in #[#[a,b,m], #[a,m,b], #[b,a,m], #[b,m,a], #[m,a,b], #[m,b,a]] do
    for batches in #[#[refs], #[refs[:1].toArray, refs[1:].toArray],
        #[refs[:2].toArray, refs[2:].toArray], refs.map (#[·])] do
      let result := batches.foldlM (fun node batch => node.applyContributions `target batch) ({} : Node)
      match result with
      | .error _ => pure ()
      | .ok _ => throw <| IO.userError "A manual override hid conflicting automatic intents"
  for refs in #[#[a,m], #[m,a], #[a,a,m,m]] do
    let .ok node := ({} : Node).applyContributions `target refs
      | throw <| IO.userError "Compatible authority levels were rejected"
    unless node.proof.map (·.deps) == some #[{ label := `dep, intent := .auxiliary }] do
      throw <| IO.userError "Manual metadata lost precedence"
    unless node.proof.map (·.useDeclarations.size) == some 2 do
      throw <| IO.userError "Validation evidence was lost or duplicated"

-- This is also reachable through ordinary author syntax, regardless of role order.
open Verso.Genre Informal

#docs (Manual) authorityStatement "Statement" :=
:::::::
:::theorem "authority_target"
Statement.
:::
:::::::

/-- error: Label authority_target declares conflicting proof dependency intents for 'dep' (automatic): existing 'regular', new 'technical' -/
#guard_msgs in
#docs (Manual) authorityAutomaticFirst "Automatic first" :=
:::::::
:::proof "authority_target"
{uses "dep" (origin := "automatic")}[Automatic regular].
{uses "dep" (origin := "automatic") (intent := "technical")}[Automatic technical].
{uses "dep" (intent := "auxiliary")}[Manual auxiliary].
:::
:::::::

/-- error: Label authority_target declares conflicting proof dependency intents for 'dep' (automatic): existing 'regular', new 'technical' -/
#guard_msgs in
#docs (Manual) authorityManualFirst "Manual first" :=
:::::::
:::proof "authority_target"
{uses "dep" (intent := "auxiliary")}[Manual auxiliary].
{uses "dep" (origin := "automatic")}[Automatic regular].
{uses "dep" (origin := "automatic") (intent := "technical")}[Automatic technical].
:::
:::::::
