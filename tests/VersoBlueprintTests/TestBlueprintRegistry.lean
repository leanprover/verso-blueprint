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
import VersoBlueprintTests.TestBlueprintRegistryMeta

namespace Verso.VersoBlueprintTests.TestBlueprintRegistry

open Verso
open Verso.Genre.Manual
open Lean
open Verso.VersoBlueprintTests.TestBlueprintRegistryMeta

def manualImpls : ExtensionImpls := extension_impls%

private def curatedTestBlueprintDoc? (slug : String) : Option (Doc.VersoDoc Genre.Manual) :=
  match slug with
  | "hover-link" => some Verso.VersoBlueprintTests.BlueprintLinkHover.hoverLinkDoc
  | "hover-uses-dedup" => some Verso.VersoBlueprintTests.BlueprintLinkHover.hoverUsesDedupDoc
  | "hover-cite-only" => some Verso.VersoBlueprintTests.BlueprintLinkHover.hoverCiteOnlyDoc
  | "widget-preview" => some Verso.VersoBlueprintTests.BlueprintTexMacros.widgetPreviewDoc
  | "rust-inline-preview" => some Verso.VersoBlueprintTests.BlueprintRustCode.rustCatalogDoc
  | "external-markup-source" => some Verso.VersoBlueprintTests.BlueprintExternalMarkup.externalMarkupShowcaseDoc
  | "metadata-panel" => some Verso.VersoBlueprintTests.BlueprintMetadataPanel.metadataPanelDoc
  | "direct-imported-duplicates" => some Verso.VersoBlueprintTests.BlueprintImportedDuplicates.Direct.directImportedDuplicateDoc
  | "transitive-imported-duplicates" => some Verso.VersoBlueprintTests.BlueprintImportedDuplicates.Transitive.transitiveImportedDuplicateDoc
  | "imported-preview-source" => some Verso.VersoBlueprintTests.BlueprintPreviewSource.Provider.importedPreviewSourceDoc
  | "lean-auto-deps" => some Verso.VersoBlueprintTests.BlueprintAutoDeps.Preview.autoDepsPreviewDoc
  | "blueprint-grafts" => some Verso.VersoBlueprintTests.BlueprintGraft.manualSideBySideGraftDoc
  | "state-showcase" => some Verso.VersoBlueprintTests.BlueprintPreviewWiring.StateShowcase.stateShowcaseDoc
  | "external-summary-links" => some Verso.VersoBlueprintTests.BlueprintSummaryLinks.Shared.externalSummaryLinksDoc
  | "summary-blockers" => some Verso.VersoBlueprintTests.BlueprintSummaryLinks.Shared.summaryBlockersDoc
  | "summary-triage" => some Verso.VersoBlueprintTests.BlueprintSummaryLinks.Shared.summaryTriageDoc
  | "preview-wiring" => some Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.previewWiringDoc
  | "used-by-preview" => some Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.usedByPreviewDoc
  | "used-by-single-preview" => some Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.usedBySinglePreviewDoc
  | "lean-status-chip" => some Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.leanStatusChipDoc
  | "lean-code-link-preview" => some Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.leanCodeLinkPreviewDoc
  | "group-preview" => some Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.groupPreviewDoc
  | "missing-group-preview" => some Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.missingGroupPreviewDoc
  | "single-declared-group" => some Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.singleDeclaredGroupDoc
  | _ => none

def curatedTestBlueprintDocSlugs : Array String :=
  curatedTestBlueprintMetas.map (·.slug)

def findCuratedTestBlueprintDoc? (slug : String) : Option (Doc.VersoDoc Genre.Manual) :=
  curatedTestBlueprintDoc? slug

end Verso.VersoBlueprintTests.TestBlueprintRegistry
