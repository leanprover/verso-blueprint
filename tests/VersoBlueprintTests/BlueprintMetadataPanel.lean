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

:::definition "def:meta.panel" (owner := "alice") (tags := "analysis, critical") (effort := "small") (priority := "high") (pr_url := "https://github.com/example/repo/pull/7")
Metadata panel body.
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
      hasSubstr out "https://github.com/example/repo/pull/7"
    )

-- Page rendering and manifest metadata share the complete owner/triage record.
#eval show IO Unit from do
  let files ← buildManualPreviewDataFiles manualImpls metadataPanelDoc
  let some entry := files.manifest.previews.find? (·.authoredLabel == "def:meta.panel")
    | throw <| IO.userError "Missing metadata preview"
  unless entry.ownerUrl == some "https://example.com/alice" &&
      entry.ownerImageUrl == some "https://example.com/alice.png" &&
      entry.prUrl == some "https://github.com/example/repo/pull/7" do
    throw <| IO.userError "The manifest lost metadata available to page rendering"

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
      "https://example.com/pull/1"] do
    unless hasSubstr html expected do
      throw <| IO.userError s!"Manifest-backed shell lost {expected}"
  unless hasSubstr (render { entry with ownerDisplayName := none }) "owner-id" do
    throw <| IO.userError "Manifest-backed shell lost the owner-ID fallback"
  let prOnly := { entry with toBlockMetadata := {
    label := entry.label, prUrl := some "https://example.com/pull/only" } }
  unless hasSubstr (render prOnly) "https://example.com/pull/only" do
    throw <| IO.userError "A PR-only manifest entry lost its metadata panel"

end Verso.VersoBlueprintTests.BlueprintMetadataPanel
