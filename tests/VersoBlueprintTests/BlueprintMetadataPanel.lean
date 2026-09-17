/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintMetadataPanel

open Verso
open Lean
open Verso.Genre.Manual
open Informal
open Verso.VersoBlueprintTests.Blueprint.Support

set_option doc.verso true

private def manualImpls : ExtensionImpls := extension_impls%

#docs (Genre.Manual) metadataPanelDoc "Blueprint Metadata Panel" :=
:::::::
:::author "alice" (name := "Alice Example") (url := "https://example.com/alice") (image_url := "https://example.com/alice.png")
:::

:::definition "def:meta.panel" (owner := "alice") (tags := "analysis, critical") (effort := "small") (priority := "high") (pr_url := "https://github.com/example/repo/pull/7") (issue_url := "https://github.com/example/repo/issues/109")
Metadata panel body.
:::

:::theorem "thm:meta.pair" (issue_url := "https://example.com/repo/-/issues/7#note_1")
Statement with a proof facet.
:::

:::proof "thm:meta.pair"
Proof body.
:::

:::definition "def:meta.zero" (issue_url := "https://example.com/issues/00109")
Leading zeros stay in the caption.
:::

:::definition "def:meta.tracker" (issue_url := "  https://tracker.example.com/T-109  ")
No numeric segment.
:::

:::definition "def:meta.blank" (issue_url := "   ")
A blank issue URL counts as absent.
:::

:::definition "def:meta.query" (issue_url := "https://example.com/issues/5?next=/999&x=1")
Query text is escaped in the rendered link.
:::
:::::::

/-- Captured in this fixture's environment before unrelated fixtures are imported. -/
def metadataPanelDocBlueprint : Informal.BlueprintDocument := .capture metadataPanelDoc.toPart

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls metadataPanelDoc
    pure (
      hasSubstr out "class=\"bp_metadata_panel\"" &&
      hasSubstr out "Alice Example" &&
      hasSubstr out "https://example.com/alice" &&
      hasSubstr out "class=\"bp_metadata_avatar\"" &&
      hasSubstr out "https://example.com/alice.png" &&
      hasSubstr out "analysis" &&
      hasSubstr out "critical" &&
      hasSubstr out "Effort" &&
      hasSubstr out "small" &&
      hasSubstr out "Priority" &&
      hasSubstr out "high" &&
      hasSubstr out "https://github.com/example/repo/pull/7" &&
      hasSubstr out "Issue" &&
      hasSubstr out "href=\"https://github.com/example/repo/issues/109\">#109</a>" &&
      appearsBefore out "https://github.com/example/repo/pull/7" "https://github.com/example/repo/issues/109" &&
      hasSubstr out "href=\"https://example.com/repo/-/issues/7#note_1\">#7</a>" &&
      hasSubstr out "href=\"https://example.com/issues/00109\">#00109</a>" &&
      hasSubstr out "href=\"https://tracker.example.com/T-109\">link</a>" &&
      hasSubstr out "href=\"https://example.com/issues/5?next=/999&amp;x=1\">#5</a>"
    )

-- Page rendering and manifest metadata share the complete owner/triage record.
#eval show IO Unit from do
  let files ← buildManualPreviewDataFiles manualImpls metadataPanelDoc
  let some entry := files.manifest.previews.find? (·.authoredLabel == "def:meta.panel")
    | throw <| IO.userError "Missing metadata preview"
  unless entry.ownerUrl == some "https://example.com/alice" &&
      entry.ownerImageUrl == some "https://example.com/alice.png" &&
      entry.prUrl == some "https://github.com/example/repo/pull/7" &&
      entry.issueUrl == some "https://github.com/example/repo/issues/109" &&
      entry.issueNumber == some 109 do
    throw <| IO.userError "The manifest lost metadata available to page rendering"
  -- Both facets of a statement/proof pair carry the URL and the derived number.
  let pair := files.manifest.previews.filter (·.authoredLabel == "thm:meta.pair")
  unless pair.any (·.facet == .statement) && pair.any (·.facet == .proof) &&
      pair.all (fun entry =>
        entry.issueUrl == some "https://example.com/repo/-/issues/7#note_1" &&
        entry.issueNumber == some 7) do
    throw <| IO.userError "A facet of the statement/proof pair lost its issue metadata"
  let lookup (label : String) : IO PreviewManifest.Entry := do
    let some entry := files.manifest.previews.find? (·.authoredLabel == label)
      | throw <| IO.userError s!"Missing preview for {label}"
    pure entry
  let zero ← lookup "def:meta.zero"
  unless zero.issueUrl == some "https://example.com/issues/00109" && zero.issueNumber == some 109 do
    throw <| IO.userError "Leading zeros were normalized in the stored URL or dropped from the number"
  let tracker ← lookup "def:meta.tracker"
  unless tracker.issueUrl == some "https://tracker.example.com/T-109" && tracker.issueNumber == none do
    throw <| IO.userError "A non-numeric tracker URL was not stored trimmed with no derived number"
  let blank ← lookup "def:meta.blank"
  unless blank.issueUrl == none && blank.issueNumber == none do
    throw <| IO.userError "A blank issue URL was stored instead of treated as absent"
  let query ← lookup "def:meta.query"
  unless query.issueUrl == some "https://example.com/issues/5?next=/999&x=1" && query.issueNumber == some 5 do
    throw <| IO.userError "The issue number was read from the query instead of the path"

-- Every inherited field survives the reconstruction, including metadata-only shells.
#eval show IO Unit from do
  let metadata : BlockMetadata := {
    label := `projection, parent := some `parent
    statementUses := #[{ label := `statementDep }]
    proofUses := #[{ label := `proofDep, intent := .technical }]
    owner := some (Name.mkSimple "owner-id"), ownerDisplayName := some "Owner Name"
    ownerUrl := some "https://example.com/owner"
    ownerImageUrl := some "https://example.com/avatar.png"
    prUrl := some "https://example.com/pull/1"
    issueUrl := some "https://example.com/issues/42"
    tags := #["first", "second"], effort := some "small", priority := some "high" }
  let entry : PreviewManifest.Entry := {
    toBlockMetadata := metadata
    key := "projection--statement", targetKind := .block, facet := .statement, title := "Projection" }
  unless entry.blockData.toBlockMetadata == metadata do
    throw <| IO.userError "Manifest-to-block conversion dropped inherited metadata"
  let render (entry : PreviewManifest.Entry) :=
    (PreviewManifest.BlockRender.renderWithRenderedContent {} entry { body := .empty }).asString
  let html := render entry
  for expected in #["Owner Name", "https://example.com/owner", "https://example.com/avatar.png",
      "https://example.com/pull/1", "https://example.com/issues/42\">#42</a>"] do
    unless hasSubstr html expected do
      throw <| IO.userError s!"Manifest-backed shell lost {expected}"
  unless hasSubstr (render { entry with ownerDisplayName := none }) "owner-id" do
    throw <| IO.userError "Manifest-backed shell lost the owner-ID fallback"
  let prOnly := { entry with toBlockMetadata := {
    label := entry.label, prUrl := some "https://example.com/pull/only" } }
  unless hasSubstr (render prOnly) "https://example.com/pull/only" do
    throw <| IO.userError "A PR-only manifest entry lost its metadata panel"
  let issueOnly := { entry with toBlockMetadata := {
    label := entry.label, issueUrl := some "https://example.com/issues/only" } }
  let issueOnlyHtml := render issueOnly
  unless hasSubstr issueOnlyHtml "class=\"bp_metadata_panel\"" &&
      hasSubstr issueOnlyHtml "https://example.com/issues/only\">link</a>" do
    throw <| IO.userError "An issue-only manifest entry lost its metadata panel"

end Verso.VersoBlueprintTests.BlueprintMetadataPanel
