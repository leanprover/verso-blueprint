/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedDuplicates.Direct
import VersoBlueprintTests.BlueprintImportedDuplicates.Transitive
import VersoBlueprintTests.BlueprintAutoDeps.Preview
import VersoBlueprintTests.BlueprintExternalMarkup
import VersoBlueprintTests.BlueprintGraft
import VersoBlueprintTests.BlueprintLinkHover
import VersoBlueprintTests.BlueprintMetadataPanel
import VersoBlueprintTests.BlueprintPreviewSource.Provider
import VersoBlueprintTests.BlueprintPreviewWiring.Shared
import VersoBlueprintTests.BlueprintPreviewWiring.StateShowcase
import VersoBlueprintTests.BlueprintRustCode
import VersoBlueprintTests.BlueprintSummaryLinks.Shared
import VersoBlueprintTests.BlueprintTexMacros
import VersoBlueprintTests.BlueprintImportedContributions.LateRender
import VersoBlueprintTests.BlueprintImportedContributions.LiterateRender
import VersoBlueprintTests.TestBlueprintRegistryMeta

namespace Verso.VersoBlueprintTests.TestBlueprintRegistry

open Verso
open Verso.Genre.Manual
open Lean
open Verso.VersoBlueprintTests.TestBlueprintRegistryMeta

def manualImpls : ExtensionImpls := extension_impls%

private def curatedTestBlueprintDoc? (slug : String) : Option Informal.BlueprintDocument :=
  match slug with
  | "hover-link" => some Verso.VersoBlueprintTests.BlueprintLinkHover.hoverLinkDocBlueprint
  | "hover-uses-dedup" => some Verso.VersoBlueprintTests.BlueprintLinkHover.hoverUsesDedupDocBlueprint
  | "hover-cite-only" => some Verso.VersoBlueprintTests.BlueprintLinkHover.hoverCiteOnlyDocBlueprint
  | "widget-preview" => some Verso.VersoBlueprintTests.BlueprintTexMacros.widgetPreviewDocBlueprint
  | "rust-inline-preview" => some Verso.VersoBlueprintTests.BlueprintRustCode.rustCatalogDocBlueprint
  | "external-markup-source" => some Verso.VersoBlueprintTests.BlueprintExternalMarkup.externalMarkupShowcaseDocBlueprint
  | "metadata-panel" => some Verso.VersoBlueprintTests.BlueprintMetadataPanel.metadataPanelDocBlueprint
  | "direct-imported-duplicates" => some Verso.VersoBlueprintTests.BlueprintImportedDuplicates.Direct.directImportedDuplicateDocBlueprint
  | "transitive-imported-duplicates" => some Verso.VersoBlueprintTests.BlueprintImportedDuplicates.Transitive.transitiveImportedDuplicateDocBlueprint
  | "imported-preview-source" => some Verso.VersoBlueprintTests.BlueprintPreviewSource.Provider.importedPreviewSourceDocBlueprint
  | "lean-auto-deps" => some Verso.VersoBlueprintTests.BlueprintAutoDeps.Preview.autoDepsPreviewDocBlueprint
  | "blueprint-grafts" => some Verso.VersoBlueprintTests.BlueprintGraft.manualSideBySideGraftDocBlueprint
  | "state-showcase" => some Verso.VersoBlueprintTests.BlueprintPreviewWiring.StateShowcase.stateShowcaseDocBlueprint
  | "external-summary-links" => some Verso.VersoBlueprintTests.BlueprintSummaryLinks.Shared.externalSummaryLinksDocBlueprint
  | "summary-blockers" => some Verso.VersoBlueprintTests.BlueprintSummaryLinks.Shared.summaryBlockersDocBlueprint
  | "summary-triage" => some Verso.VersoBlueprintTests.BlueprintSummaryLinks.Shared.summaryTriageDocBlueprint
  | "preview-wiring" => some Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.previewWiringDocBlueprint
  | "used-by-preview" => some Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.usedByPreviewDocBlueprint
  | "used-by-single-preview" => some Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.usedBySinglePreviewDocBlueprint
  | "lean-status-chip" => some Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.leanStatusChipDocBlueprint
  | "lean-code-link-preview" => some Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.leanCodeLinkPreviewDocBlueprint
  | "group-preview" => some Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.groupPreviewDocBlueprint
  | "missing-group-preview" => some Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.missingGroupPreviewDocBlueprint
  | "single-declared-group" => some Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.singleDeclaredGroupDocBlueprint
  | "imported-late-attachments" => some _root_.lateBlueprint
  | "imported-literate-attachments" => some _root_.literateBlueprint
  | _ => none

def curatedTestBlueprintDocSlugs : Array String :=
  curatedTestBlueprintMetas.map (·.slug)

def findCuratedTestBlueprintDoc? (slug : String) : Option Informal.BlueprintDocument :=
  curatedTestBlueprintDoc? slug

end Verso.VersoBlueprintTests.TestBlueprintRegistry
