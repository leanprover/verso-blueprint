/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.Blueprint.Support
import VersoBlueprintTests.BlueprintPreviewSource.Provider
import VersoBlueprint.GraphApi

open Lean
open Informal
open Verso.VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintPreviewSource

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let label := Name.mkSimple "preview.imported"
    let some selection := Informal.PreviewSource.environmentSelection? (← getEnv) label
      | return false
    pure <|
      selection.facet == .statement &&
      selection.key == PreviewCache.statementKey label &&
      !selection.preview.blocks.isEmpty &&
      selection.preview.stxs.isEmpty

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let label := Name.mkSimple "preview.proof_fallback"
    let some selection := Informal.PreviewSource.environmentSelection? (← getEnv) label
      | return false
    pure <|
      selection.facet == .proof &&
      selection.key == PreviewCache.proofKey label &&
      !selection.preview.blocks.isEmpty &&
      selection.preview.stxs.isEmpty

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (_out, st) ← renderManualDocHtmlStringAndState extension_impls%
      Verso.VersoBlueprintTests.BlueprintPreviewSource.Provider.proofFallbackPreviewSourceDoc
    let label := Name.mkSimple "preview.proof_fallback"
    let entry? := Informal.PreviewSource.traversalEntry? st label
    let lookupKey? := Informal.PreviewSource.traversalLookupKey? st label
    let selection? := Informal.PreviewSource.traversalSelection? st label
    pure <|
      match entry?, lookupKey?, selection? with
      | some entry, some lookupKey, some selection =>
        entry.facet == .proof &&
        selection.facet == .proof &&
        selection.key == lookupKey &&
        selection.preview.blocks.size == entry.blocks.size &&
        !entry.blocks.isEmpty &&
        lookupKey == PreviewCache.proofKey label
      | _, _, _ => false

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (_out, st) ← renderManualDocHtmlStringAndState extension_impls%
      Verso.VersoBlueprintTests.BlueprintPreviewSource.Provider.proofFallbackPreviewSourceDoc
    let label := Name.mkSimple "preview.proof_fallback"
    let proofKey := PreviewCache.proofKey label
    let decoded := Informal.PreviewSource.traversalStoredEntries st
    let entries := decoded.filterMap fun
      | .ok entry => some entry
      | .error _ => none
    pure <|
      decoded.all (fun
        | .ok _ => true
        | .error _ => false) &&
      entries.any (fun stored =>
        stored.key == proofKey &&
        stored.entry.label == label &&
        stored.entry.facet == .proof &&
        !stored.entry.blocks.isEmpty)

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (_out, st) ← renderManualDocHtmlStringAndState extension_impls%
      Verso.VersoBlueprintTests.BlueprintPreviewSource.Provider.proofFallbackPreviewSourceDoc
    let label := Name.mkSimple "preview.proof_fallback"
    let statementKey := PreviewCache.statementKey label
    let proofKey := PreviewCache.proofKey label
    let semantic : Informal.Graph.GraphData := {
      nodes := #[{
        label
        title := "Proof fallback"
        displayLabel := "Proof fallback"
        previewKey := PreviewKey.ofString? statementKey
        visual := { fillcolor := "#ffffff" }
      }]
    }
    let finalized := Informal.GraphApi.finalData st semantic
    let variants := finalized.renderVariants {}
    pure <|
      match finalized.nodes[0]? with
      | some node =>
        node.previewKey == PreviewKey.ofString? proofKey &&
        variants.any (fun variant =>
          variant.previewKeyByNodeId.any (fun (_, key) => key == proofKey))
      | none => false

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (_out, st) ← renderManualDocHtmlStringAndState extension_impls%
      Verso.VersoBlueprintTests.BlueprintPreviewSource.Provider.proofFallbackPreviewSourceDoc
    let label := Name.mkSimple "preview.missing"
    let statementKey := PreviewCache.statementKey label
    let semantic : Informal.Graph.GraphData := {
      nodes := #[{
        label
        title := "Missing preview"
        displayLabel := "Missing preview"
        previewKey := PreviewKey.ofString? statementKey
        visual := { fillcolor := "#ffffff" }
      }]
    }
    let finalized := Informal.GraphApi.finalData st semantic
    let variants := finalized.renderVariants {}
    pure <|
      finalized.nodes.isEmpty &&
      finalized.edges.isEmpty &&
      finalized.groups.isEmpty &&
      variants.all (fun variant =>
        variant.previewKeyByNodeId.all (fun (_, key) =>
          !key.isEmpty && key != statementKey))

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (_out, st) ← renderManualDocHtmlStringAndState extension_impls%
      Verso.VersoBlueprintTests.BlueprintPreviewSource.Provider.proofFallbackPreviewSourceDoc
    let label := Name.mkSimple "preview.unknown"
    let semantic : Informal.Graph.GraphData := {
      nodes := #[{
        label
        title := "Unknown preview"
        displayLabel := "Unknown preview"
        previewKey := PreviewKey.ofString? (PreviewCache.statementKey label)
        warnings := { unknownRef := true }
        visual := { fillcolor := "#ffffff" }
      }]
    }
    let finalized := Informal.GraphApi.finalData st semantic
    let variants := finalized.renderVariants {}
    pure <|
      match finalized.nodes[0]? with
      | some node =>
        node.label == label &&
        node.warnings.unknownRef &&
        node.previewKey.isNone &&
        variants.all (fun variant => variant.previewKeyByNodeId.isEmpty)
      | none => false

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (_out, st) ← renderManualDocHtmlStringAndState extension_impls%
      Verso.VersoBlueprintTests.BlueprintPreviewSource.Provider.externalMarkupPreviewSourceDoc
    let label := Name.mkSimple "preview.external_bodyless"
    let externalKey := Informal.PreviewSource.externalMarkupKey label
    let semantic : Informal.Graph.GraphData := {
      nodes := #[{
        label
        title := "External bodyless"
        displayLabel := "External bodyless"
        visual := { fillcolor := "#ffffff" }
      }]
    }
    let finalized := Informal.GraphApi.finalData st semantic
    let variants := finalized.renderVariants {}
    pure <|
      match finalized.nodes[0]? with
      | some node =>
        node.previewKey == PreviewKey.ofString? externalKey &&
          variants.any (fun variant =>
            variant.previewKeyByNodeId.any (fun (_, key) => key == externalKey))
      | none => false

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (_out, st) ← renderManualDocHtmlStringAndState extension_impls%
      Verso.VersoBlueprintTests.BlueprintPreviewSource.Provider.externalMarkupGraphPreviewSourceDoc
    let label := Name.mkSimple "preview.external_graph_bodyless"
    let externalKey := Informal.PreviewSource.externalMarkupKey label
    let files ← Informal.PreviewManifest.buildPreviewDataFiles extension_impls% (fun _ => pure ()) st
      ({ mode := .none } : Informal.ExternalMarkupRender.Config)
    let some entry := files.manifest.previews.find? (fun entry => entry.key == externalKey)
      | return false
    let some graph := files.manifest.graphs[0]?
      | return false
    let some node := graph.nodes.find? (fun node => node.label == label)
      | return false
    pure <|
      entry.targetKind == .externalMarkup &&
        (files.htmlCache.findHtml? externalKey).isNone &&
        node.previewKey.isNone &&
        graph.variants.all (fun variant =>
          variant.previewKeyByNodeId.all (fun (_, key) => key != externalKey))

end Verso.VersoBlueprintTests.BlueprintPreviewSource
