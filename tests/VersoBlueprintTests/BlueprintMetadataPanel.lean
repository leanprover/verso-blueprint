/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintMetadataPanel

open Verso
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

end Verso.VersoBlueprintTests.BlueprintMetadataPanel
