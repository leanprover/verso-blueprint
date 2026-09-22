/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Lacramioara Astefanoaei
-/

import VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintIssueUrl

open Verso
open Lean
open Verso.Genre.Manual
open Informal
open Verso.VersoBlueprintTests.Blueprint.Support

set_option doc.verso true

-- The caption helper reads the URL path only: query and fragment are dropped,
-- the authority is never a segment, and digits are kept as written.
/-- info: true -/
#guard_msgs in
#eval
  [("https://h/issues/109", some "109"),
   ("https://h/issues/109/", some "109"),
   ("https://h/-/issues/7", some "7"),
   ("https://h/issues/109#discussion", some "109"),
   ("https://h/issues/109?view=full", some "109"),
   ("https://h/issues/109?next=/999", some "109"),
   ("https://h/issues/00109", some "00109"),
   ("https://109", none),
   ("https://h/issues", none),
   ("https://h/T-109", none),
   ("", none)].all fun (url, expected) => issueNumberSegment? url == expected

/-- info: true -/
#guard_msgs in
#eval
  issueLinkText "https://h/issues/109#discussion" == "#109" &&
    issueLinkText "https://h/issues/00109" == "#00109" &&
    issueLinkText "https://h/T-109" == "link"

-- Both URL options share one validator and one set of diagnostics.
/-- error: Label bad_issue has invalid '(issue_url := "not a url")'; expected an http(s) URL -/
#guard_msgs in
#docs (Genre.Manual) invalidIssueUrl "Invalid issue URL" :=
:::::::
:::definition "bad_issue" (issue_url := "not a url")
Rejected metadata.
:::
:::::::

/-- error: Label bad_pr has invalid '(pr_url := "ftp://example.com/pull/1")'; expected an http(s) URL -/
#guard_msgs in
#docs (Genre.Manual) invalidPrUrl "Invalid PR URL" :=
:::::::
:::definition "bad_pr" (pr_url := "ftp://example.com/pull/1")
Rejected metadata.
:::
:::::::

/-- error: Label proof_issue cannot use '(issue_url := ...)' in a proof block -/
#guard_msgs in
#docs (Genre.Manual) proofIssueUrl "Proof issue URL" :=
:::::::
:::lemma_ "proof_issue"
Statement body.
:::
:::proof "proof_issue" (issue_url := "https://example.com/issues/1")
Proof body.
:::
:::::::

/-- error: Label proof_pr cannot use '(pr_url := ...)' in a proof block -/
#guard_msgs in
#docs (Genre.Manual) proofPrUrl "Proof PR URL" :=
:::::::
:::lemma_ "proof_pr"
Statement body.
:::
:::proof "proof_pr" (pr_url := "https://example.com/pull/1")
Proof body.
:::
:::::::

-- A proof block rejects the option's presence, so a blank value still errors there,
-- unlike on a statement block where a blank value counts as absent.
/-- error: Label proof_blank cannot use '(issue_url := ...)' in a proof block -/
#guard_msgs in
#docs (Genre.Manual) proofBlankIssueUrl "Proof blank issue URL" :=
:::::::
:::lemma_ "proof_blank"
Statement body.
:::
:::proof "proof_blank" (issue_url := "   ")
Proof body.
:::
:::::::

-- Split blocks merge issue URLs by exact string equality, like PR URLs.
run_cmd discard <| Environment.contribute `issue_merge {
  kind := some .lemma, issueUrl := some "https://example.com/issues/109" }

#guard_msgs in
run_cmd discard <| Environment.contribute `issue_merge {
  issueUrl := some "https://example.com/issues/109" }

/-- error: Label issue_merge declares conflicting issue URLs: existing 'https://example.com/issues/109', new 'https://example.com/issues/109/' -/
#guard_msgs in
run_cmd discard <| Environment.contribute `issue_merge {
  issueUrl := some "https://example.com/issues/109/" }

end Verso.VersoBlueprintTests.BlueprintIssueUrl
