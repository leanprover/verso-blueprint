/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintSummaryLinks.Shared

namespace Verso.VersoBlueprintTests.BlueprintSummaryLinks.Triage

open Verso.VersoBlueprintTests.Blueprint.Support
open Verso.VersoBlueprintTests.BlueprintSummaryLinks.Shared

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls summaryTriageDoc
    pure (
      hasSubstr out ">Overview</summary>" &&
      hasSubstr out "Dependency insights" &&
      hasSummaryCardValue out "Ready now" "16" &&
      hasSummaryCardValue out "Actionable priorities" "12" &&
      hasSummaryCardValue out "Statement-used entries" "12" &&
      hasSummaryCardValue out "Proof-used entries" "2" &&
      hasSubstr out "Actionable priorities (12)" &&
      hasSubstr out "Show all 2 more priorities" &&
      hasSubstr out "Most used in statements (12)" &&
      hasSubstr out "Show all 2 more statement-used entries" &&
      hasSubstr out "Most used in proofs (2)" &&
      hasSubstr out "proof uses: 1" &&
      hasSubstr out "Group health (1)" &&
      hasSubstr out "By parent groups (1)" &&
      hasSubstr out "Metadata" &&
      hasSubstr out "Quick wins (2)" &&
      hasSubstr out "Owner rollups (2)" &&
      hasSubstr out "Tag rollups (" &&
      hasSubstr out "Linked PRs (2)" &&
      hasSubstr out "Metadata audit" &&
      hasSummaryCardValue out "Missing owner" "14" &&
      hasSubstr out "Missing owner (14)" &&
      hasSummaryCardValue out "Missing effort" "14" &&
      hasSubstr out "Missing effort (14)" &&
      hasSummaryCardValue out "Untagged" "14" &&
      hasSubstr out "Untagged (14)" &&
      hasSubstr out "Alice Example" &&
      hasSubstr out "Bob Example" &&
      hasSubstr out "https://example.com/pr/12" &&
      hasSubstr out "quick-win" &&
      hasSubstr out "leaf-quick-win" &&
      hasSubstr out "def:triage.leaf" &&
      hasSubstr out "downstream unlocks: 0" &&
      hasSummaryMetricBadge out "quick wins" "2" &&
      hasSubstr out "Structure and coverage" &&
      hasSubstr out "Heaviest prerequisites (" &&
      hasSubstr out "No prerequisites (" &&
      hasSubstr out "No dependents (" &&
      !hasSubstr out "Proof debt hotspots (0)" &&
      hasSubstr out "Next:" &&
      hasSummaryMetricBadge out "total" "15" &&
      hasSummaryMetricBadge out "closed" "0" &&
      hasSummaryMetricBadge out "local-only" "0" &&
      hasSummaryMetricBadge out "ready" "14" &&
      hasSummaryMetricBadge out "blocked" "1" &&
      hasSummaryMetricBadge out "incomplete Lean" "0" &&
      hasSummaryMetricBadge out "unlock score" "14" &&
      hasSummaryMetricBadge out "priority" "high" &&
      hasSummaryMetricBadge out "priority" "low" &&
      !hasSubstr out "Axiom-like Index (0)" &&
      !hasSubstr out "Proof debt hotspots (0)" &&
      appearsBefore out "def:triage.12" "def:triage.01" &&
      hasSubstr out "def:triage.01" &&
      hasSubstr out "downstream unlocks: 1"
    )

end Verso.VersoBlueprintTests.BlueprintSummaryLinks.Triage
