/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintSummaryLinks.Shared

namespace Verso.VersoBlueprintTests.BlueprintSummaryLinks.Triage

open Verso.VersoBlueprintTests.Blueprint.Support
open Verso.VersoBlueprintTests.BlueprintSummaryLinks.Shared

open Lean Elab Command Term

run_cmd liftTermElabM do
  let model := summaryTriageDocBlueprint.model
  let node (label : Lean.Name) := model.graph.nodes.find? (·.label == label)
  let some foundation := node (Lean.Name.mkSimple "def:triage.01") | throwError "Missing native foundation node"
  let some foundationAssessment := foundation.assessment | throwError "Missing foundation assessment"
  unless foundationAssessment.hasNativeDeclarations && !foundationAssessment.requiredComplete &&
      !foundationAssessment.nativeProofComplete && foundationAssessment.statementDependenciesComplete &&
      foundationAssessment.proofDependenciesComplete && foundation.actionableStage?.isSome do
    throwError "Native debt on triage.01 should be actionable after its selected prerequisites pass"
  let some main := node (Lean.Name.mkSimple "thm:triage.main") | throwError "Missing dependent theorem node"
  let some mainAssessment := main.assessment | throwError "Missing theorem assessment"
  unless mainAssessment.hasNativeDeclarations && !mainAssessment.nativeProofComplete &&
      !mainAssessment.proofDependenciesComplete && main.actionableStage?.isNone do
    throwError "Theorem proof debt should remain non-actionable while selected prerequisites are incomplete"
  let some proseOnly := node (Lean.Name.mkSimple "def:triage.02") | throwError "Missing prose-only node"
  let some proseAssessment := proseOnly.assessment | throwError "Missing prose-only assessment"
  unless !proseAssessment.hasNativeDeclarations && proseOnly.actionableStage?.isNone do
    throwError "A prose-only node should remain unassessed and non-actionable"
  let summary := model.summary
  unless summary.actionablePriorities.any (·.label == (Lean.Name.mkSimple "def:triage.01")) &&
      !summary.actionablePriorities.any (·.label == (Lean.Name.mkSimple "thm:triage.main")) &&
      !summary.actionablePriorities.any (·.label == (Lean.Name.mkSimple "def:triage.02")) do
    throwError "Actionable priority summaries must follow captured native prerequisites"
  unless summary.quickWins.any (·.label == (Lean.Name.mkSimple "def:triage.leaf")) do
    throwError "An actionable native leaf remains a quick win without downstream dependents"

/-- info: #[] -/
#guard_msgs in
#eval
  show IO (Array String) from do
    let out ← renderManualDocHtmlString manualImpls summaryTriageDoc (model := summaryTriageDocBlueprint.model)
    let checks : Array (String × Bool) := #[
      ("overview", hasSubstr out ">Overview</summary>"),
      ("dependency insights", hasSubstr out "Dependency insights"),
      ("ready card", hasSummaryCardValue out "Ready now" (toString summaryTriageDocBlueprint.model.summary.coverageSplit.readyToFormalize)),
      ("priority card", hasSummaryCardValue out "Actionable priorities" "1"),
      ("statement-use card", hasSummaryCardValue out "Statement-used entries" "12"),
      ("proof-use card", hasSummaryCardValue out "Proof-used entries" "2"),
      ("priority rows", hasSubstr out "Actionable priorities (1)"),
      ("statement uses", hasSubstr out "Most used in statements (12)"),
      ("capped statement uses", hasSubstr out "Show all 2 more statement-used entries"),
      ("proof uses", hasSubstr out "Most used in proofs (2)"),
      ("proof-use count", hasSubstr out "proof uses: 1"),
      ("group health", hasSubstr out "Group health (1)"),
      ("parent groups", hasSubstr out "By parent groups (1)"),
      ("metadata", hasSubstr out "Metadata"),
      ("quick-win rows", hasSubstr out "Quick wins (1)"),
      ("owner rollups", hasSubstr out "Owner rollups (2)"),
      ("tag rollups", hasSubstr out "Tag rollups ("),
      ("linked PRs", hasSubstr out "Linked PRs (2)"),
      ("metadata audit", hasSubstr out "Metadata audit"),
      ("missing owner card", hasSummaryCardValue out "Missing owner" "14"),
      ("missing owner rows", hasSubstr out "Missing owner (14)"),
      ("missing effort card", hasSummaryCardValue out "Missing effort" "14"),
      ("missing effort rows", hasSubstr out "Missing effort (14)"),
      ("untagged card", hasSummaryCardValue out "Untagged" "14"),
      ("untagged rows", hasSubstr out "Untagged (14)"),
      ("author Alice", hasSubstr out "Alice Example"),
      ("author Bob", hasSubstr out "Bob Example"),
      ("PR link", hasSubstr out "https://example.com/pr/12"),
      ("issue link 12", hasSubstr out "href=\"https://example.com/issues/12\">Issue</a>"),
      -- Issue links render beside PR links; an issue without a PR does not count as a linked PR.
      ("PR before issue", appearsBefore out "https://example.com/pr/12\">PR</a>" "https://example.com/issues/12\">Issue</a>"),
      ("issue link 13", hasSubstr out "href=\"https://example.com/issues/13\">Issue</a>"),
      ("quick-win tag", hasSubstr out "quick-win"),
      ("leaf quick-win tag", hasSubstr out "leaf-quick-win"),
      ("leaf entry", hasSubstr out "def:triage.leaf"),
      ("leaf downstream count", hasSubstr out "downstream unlocks: 0"),
      ("quick-wins badge", hasSummaryMetricBadge out "quick wins" "1"),
      ("structure section", hasSubstr out "Structure and coverage"),
      ("heaviest prerequisites", hasSubstr out "Heaviest prerequisites ("),
      ("no prerequisites", hasSubstr out "No prerequisites ("),
      ("no dependents", hasSubstr out "No dependents ("),
      ("debt hotspot section", hasSubstr out "Proof debt hotspots (1)"),
      ("group next item", hasSubstr out "Next:"),
      ("total badge", hasSummaryMetricBadge out "total" "15"),
      ("closed badge", hasSummaryMetricBadge out "closed" "0"),
      ("local-only badge", hasSummaryMetricBadge out "local-only" "0"),
      ("ready badge", hasSummaryMetricBadge out "ready" "2"),
      ("blocked badge", hasSummaryMetricBadge out "blocked" "1"),
      ("incomplete Lean badge", hasSummaryMetricBadge out "incomplete Lean" "3"),
      ("unlock score badge", hasSummaryMetricBadge out "unlock score" "14"),
      ("high priority", hasSummaryMetricBadge out "priority" "high"),
      ("low priority", hasSummaryMetricBadge out "priority" "low"),
      ("no axiom index", !hasSubstr out "Axiom-like Index (0)"),
      ("debt hotspot row", hasSubstr out "Proof debt hotspots (1)"),
      ("entry order", appearsBefore out "def:triage.12" "def:triage.01"),
      ("first triage definition", hasSubstr out "def:triage.01"),
      ("one downstream unlock", hasSubstr out "downstream unlocks: 1")]
    pure <| checks.filterMap fun (name, ok) => if ok then none else some name

end Verso.VersoBlueprintTests.BlueprintSummaryLinks.Triage
