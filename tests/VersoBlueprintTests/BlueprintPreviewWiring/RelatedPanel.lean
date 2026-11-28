/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Informal.Block.RelatedPanel
import VersoBlueprint.PreviewManifest.RelatedPanel
import VersoBlueprintTests.BlueprintPreviewWiring.Shared

namespace Verso.VersoBlueprintTests.BlueprintPreviewWiring.RelatedPanel

open Verso.VersoBlueprintTests.Blueprint.Support
open Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared

private def samplePanelEntry : Informal.RelatedPanel.PanelEntry := {
  previewId := "preview"
  previewKeys := (Informal.PreviewKey.ofString? "preview-key").toArray
  previewTitle := "Target"
  label := Lean.Name.mkSimple "target"
}

private def sampleMissingPreviewPanelEntry : Informal.RelatedPanel.PanelEntry := {
  previewId := "missing-preview"
  previewTitle := "Missing Preview"
  label := Lean.Name.mkSimple "missing.preview"
}

private def sampleOwner : Informal.RelatedPanel.PanelOwner := {
  title := "Source"
  label := Lean.Name.mkSimple "source"
}

private def cachedStatement
    (label : Lean.Name) (count : Nat) (statementUses : Array Informal.Data.UseRef := #[])
    (parent : Option Informal.Data.Parent := none) :
    Informal.BlockData :=
  {
    kind := .definition
    label
    count
    statementUses
    parent
  }

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let decoded := Lean.fromJson? (α := Informal.PreviewKey) (Lean.Json.str "  externalMarkup:Chapter2  ")
    let emptyRejected := Lean.fromJson? (α := Informal.PreviewKey) (Lean.Json.str "")
    let whitespaceRejected := Lean.fromJson? (α := Informal.PreviewKey) (Lean.Json.str "   ")
    match decoded, emptyRejected, whitespaceRejected with
    | .ok key, .error emptyMessage, .error whitespaceMessage =>
        toString key == "externalMarkup:Chapter2" &&
          Lean.toJson key == Lean.Json.str "externalMarkup:Chapter2" &&
          emptyMessage.contains "expected non-empty preview key" &&
          whitespaceMessage.contains "expected non-empty preview key"
    | _, _, _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let entry : Informal.PreviewManifest.RelatedEntry := {
      label := Lean.Name.mkSimple "target"
      title := "Target"
      previewKey := Informal.PreviewKey.ofString? "informal:target:statement"
      dependencies := #[{ facet := .statement }, { facet := .proof }]
    }
    entry.badgeCodes == #["s", "p"]

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let target := Lean.Name.mkSimple "cache.target"
    let source := Lean.Name.mkSimple "cache.source"
    let empty := Lean.Name.mkSimple "cache.empty"
    let group := Lean.Name.mkSimple "cache.group"
    let targetData := cachedStatement target 0 #[{ label := target }]
    let sourceData := cachedStatement source 1
      #[{ label := target, origin := .automatic, intent := .auxiliary }] (some group)
    let emptyData := cachedStatement empty 2
    let state : Verso.Genre.Manual.TraverseState := .initialize {}
    let state := #[targetData, sourceData, emptyData].foldl (init := state) fun state data =>
      let (id, state) := (Verso.Genre.Manual.freshId :
        StateM Verso.Genre.Manual.TraverseState Verso.Multi.InternalId).run state
      let state := Informal.TraversalIndex.Nodes.saveNode state (Informal.RenderNode.ofBlockData data)
      Informal.TraversalIndex.Nodes.saveId state data.label id
    let state := Informal.PreviewManifest.PreparedPreviewState.prepare state |>.state
    let targetEntries := Informal.TraversalIndex.RelatedPanelUsedByCache.data? state target
    let sourceEntries := Informal.TraversalIndex.RelatedPanelUsedByCache.data? state source
    let emptyEntries := Informal.TraversalIndex.RelatedPanelUsedByCache.data? state empty
    let groupMembers := Informal.TraversalIndex.RelatedPanelGroupMembersCache.data? state group
    let sourceWithoutRelations := cachedStatement source 1
    let cacheOnlyState :=
      Informal.TraversalIndex.Nodes.saveNode state (Informal.RenderNode.ofBlockData sourceWithoutRelations)
    let targetPreview := Informal.PreviewCache.Entry.ofBlocks target .statement #[]
    match Informal.RenderingResolution.facet cacheOnlyState
        (Informal.PreviewCache.statementKey target) targetPreview with
    | .error _ => false
    | .ok resolved =>
      let targetManifestEntry := Informal.PreviewManifest.blockEntryOfFacet cacheOnlyState resolved
      let groupedTargetEntry := { targetManifestEntry with parent := some group }
      let cachedGroup? :=
        Informal.PreviewManifest.groupRelationForEntry? cacheOnlyState groupedTargetEntry
      match targetEntries with
      | some #[entry] =>
          let rawEntry := Lean.toJson entry |>.compress
          match entry.dependencies with
          | #[{ facet := .statement, origin := .automatic, intent := .auxiliary }] =>
              entry.sourceLabel == source &&
                !hasSubstr rawEntry "\"count\"" &&
                !hasSubstr rawEntry "\"statementUses\"" &&
                sourceEntries.map Array.isEmpty == some true &&
                emptyEntries.map Array.isEmpty == some true &&
                groupMembers == some #[source] &&
                targetManifestEntry.usedBy.map (·.label) == #[source] &&
                targetManifestEntry.usedBy.map (fun entry => entry.dependencies.map (·.facet)) == #[#[.statement]] &&
                cachedGroup?.map (fun relation => relation.entries.map (·.label)) == some #[source]
          | _ => false
      | _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let statementEntry : Informal.PreviewManifest.RelatedEntry := {
      label := Lean.Name.mkSimple "manifest.statement"
      title := "Manifest statement"
      dependencies := #[{ facet := .statement }]
    }
    let proofEntry : Informal.PreviewManifest.RelatedEntry := {
      label := Lean.Name.mkSimple "manifest.proof"
      title := "Manifest proof"
      dependencies := #[{ facet := .proof }]
    }
    let panelEntries := Informal.PreviewManifest.relatedPanelEntries
      #[statementEntry, proofEntry]
      statementEntry.label
      "manifest-relation"
    let render cfg := Informal.RelatedPanel.renderPanel cfg sampleOwner panelEntries |>.asString
    let usedBy := render (Informal.RelatedPanel.usedByPanelConfig none)
    -- A uses panel covers one facet, so its rows drop the statement/proof badge.
    let uses := render (Informal.RelatedPanel.statementUsesPanelConfig (Lean.Name.mkSimple "manifest.source"))
    match panelEntries[0]?, panelEntries[1]? with
    | some statementPanelEntry, some proofPanelEntry =>
        statementPanelEntry.badgeCodes == #["s"] &&
          proofPanelEntry.badgeCodes == #["p"] &&
          hasSubstr usedBy "[\"s\"]" &&
          hasSubstr usedBy "[\"p\"]" &&
          !hasSubstr uses "[\"s\"]" &&
          !hasSubstr uses "[\"p\"]"
    | _, _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let punctuatedLabel : Informal.PreviewManifest.RelatedEntry := {
      label := Lean.Name.mkSimple "Chapter2:Introduction"
      title := "Introduction"
    }
    let unlabeledWithPreview : Informal.PreviewManifest.RelatedEntry := {
      label := Lean.Name.mkSimple ""
      title := ""
      previewKey := Informal.PreviewKey.ofString? "externalMarkup:Chapter2"
    }
    let unlabeledWithoutPreview : Informal.PreviewManifest.RelatedEntry := {
      label := Lean.Name.mkSimple ""
      title := ""
    }
    punctuatedLabel.displayLabel == "Chapter2:Introduction" &&
      unlabeledWithPreview.displayLabel == "externalMarkup:Chapter2" &&
      unlabeledWithoutPreview.displayLabel == "unlabeled relation"

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let baseFields := [
      ("label", Lean.toJson (Lean.Name.mkSimple "target")),
      ("title", Lean.Json.str "Target"),
      ("dependencies", Lean.toJson (#[] : Array Informal.Relation.Dependency))
    ]
    let decode (previewKey? : Option Lean.Json) :=
      let fields :=
        match previewKey? with
        | none => baseFields
        | some previewKey => baseFields ++ [("previewKey", previewKey)]
      Lean.fromJson? (α := Informal.PreviewManifest.RelatedEntry) (Lean.Json.mkObj fields)
    let missingOk :=
      match decode none with
      | .ok entry => entry.previewKey.isNone
      | .error _ => false
    let nullOk :=
      match decode (some Lean.Json.null) with
      | .ok entry => entry.previewKey.isNone
      | .error _ => false
    let stringOk :=
      match decode (some (Lean.Json.str "externalMarkup:Chapter2")) with
      | .ok entry => entry.previewKey == Informal.PreviewKey.ofString? "externalMarkup:Chapter2"
      | .error _ => false
    let emptyRejected :=
      match decode (some (Lean.Json.str "")) with
      | .ok _ => false
      | .error message => message.contains "expected non-empty preview key"
    missingOk && nullOk && stringOk && emptyRejected

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let source := Lean.Name.mkSimple "source"
    let statementCfg := Informal.RelatedPanel.statementUsesPanelConfig source
    let proofCfg := Informal.RelatedPanel.proofUsesPanelConfig source
    statementCfg.eyebrow 2 == "Statement uses · 2" &&
      statementCfg.chipTitle 1 == "Statement dependencies used by source" &&
      proofCfg.eyebrow 2 == "Proof uses · 2" &&
      proofCfg.chipTitle 1 == "Proof dependencies used by source" &&
      (Informal.RelatedPanel.usedByPanelConfig none).eyebrow 1 == "Used by · 1" &&
      (Informal.RelatedPanel.groupPanelConfig source "Group" true).eyebrow 1 == "Group · 1 block" &&
      (Informal.RelatedPanel.groupPanelConfig source "Group" true).note?.isNone &&
      (Informal.RelatedPanel.groupPanelConfig source "Group" false).note?.isSome

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let cfg := Informal.RelatedPanel.statementUsesPanelConfig (Lean.Name.mkSimple "source")
    let singleOut :=
      (Informal.RelatedPanel.renderPanel cfg sampleOwner #[sampleMissingPreviewPanelEntry]).asString
    let panelOut := (Informal.RelatedPanel.renderPanel cfg sampleOwner
      #[sampleMissingPreviewPanelEntry, samplePanelEntry]).asString
    let currentOnly := (Informal.RelatedPanel.renderPanel cfg sampleOwner
      #[{ samplePanelEntry with current := true }]).asString
    -- One row opens the same popup as many: there is no separate inline preview path.
    !hasSubstr singleOut "bp_inline_preview_ref" &&
      hasSubstr singleOut "data-bp-relation-eyebrow=\"Statement uses · 1\"" &&
      hasSubstr singleOut "data-bp-relation-title=\"Source\"" &&
      hasSubstr singleOut "data-bp-preview-mode=\"pinned\"" &&
      -- A panel listing only its own block has nothing to show.
      hasSubstr currentOnly "bp_relation_chip_empty" &&
      !hasSubstr currentOnly "bp-relation-entries" &&
      hasSubstr singleOut "class=\"bp-relation-entries\"" &&
      hasSubstr singleOut "Missing Preview" &&
      !hasSubstr singleOut "data-bp-preview-key=" &&
      hasSubstr panelOut "class=\"bp-relation-entries\"" &&
      hasSubstr panelOut "Missing Preview" &&
      hasSubstr panelOut "preview-key" &&
      !hasSubstr panelOut "data-bp-relation-preview-id=\"missing-preview\"" &&
      !hasSubstr panelOut "data-bp-relation-preview-key=\"preview-key\""

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let cfg := Informal.RelatedPanel.statementUsesPanelConfig (Lean.Name.mkSimple "source")
    let unsafeEntry : Informal.RelatedPanel.PanelEntry := {
      previewId := "unsafe-preview"
      previewTitle := "</script><script>unsafeRelationPayload()"
      label := Lean.Name.mkSimple "unsafe.payload"
    }
    let out := Informal.RelatedPanel.renderPanel cfg sampleOwner #[unsafeEntry, samplePanelEntry] |>.asString
    hasSubstr out "\\u003c/script>\\u003cscript>unsafeRelationPayload()" &&
      !hasSubstr out "</script><script>unsafeRelationPayload()"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls usedByPreviewDoc
    let relationJs? := findRelationPanelJs? st
    pure (
      hasSubstr out "used by 2" &&
      !hasSubstr out "class=\"bp_extra_slot bp_extra_slot_group\"" &&
      hasSubstr out "class=\"bp_extra_slot bp_extra_slot_uses\"" &&
      hasSubstr out "class=\"bp_extra_slot bp_extra_slot_used_by\"" &&
      hasSubstr out "class=\"bp_relation_wrap\"" &&
      hasSubstr out "data-bp-relation-eyebrow=\"Used by · 2\"" &&
      hasSubstr out "class=\"bp-relation-entries\"" &&
      -- The runtime builds the popup; pages carry only the chip and its rows.
      !hasSubstr out "bp_relation_panel" &&
      !hasSubstr out "class=\"bp_relation_item bp_relation_item_active\"" &&
      !hasSubstr out "data-bp-relation-preview-id" &&
      !hasSubstr out "data-bp-relation-preview-key=" &&
      hasSubstr out "\"s\"" &&
      hasSubstr out "\"p\"" &&
      hasSubstr out "\"oa\"" &&
      hasSubstr out "\"it\"" &&
      hasSubstr out "\"ia\"" &&
      !hasSubstr out "bp_uses_chip" &&
      !hasSubstr out "bp_uses_origin_badge" &&
      !hasSubstr out "bp_uses_intent_badge" &&
      hasExtraCss st ".bp_preview_panel.bp_relation_panel_placed" &&
      hasExtraCss st ".bp_relation_preview_label" &&
      hasExtraCss st ".bp_relation_badge_origin::before" &&
      hasExtraCss st ".bp_relation_badge_intent_technical" &&
      appearsBefore out "class=\"bp_extra_slot bp_extra_slot_uses\"" "class=\"bp_extra_slot bp_extra_slot_used_by\"" &&
      appearsBefore out "class=\"bp_extra_slot bp_extra_slot_used_by\"" "class=\"bp_extra_slot bp_extra_slot_code\"" &&
      relationJs?.isNone &&
      !hasExtraJs st "window.VersoBlueprint.onRenderReady"
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls usedBySinglePreviewDoc
    pure (
      hasSubstr out "uses 1" &&
      hasSubstr out "uses 0" &&
      hasSubstr out "used by 1" &&
      hasSubstr out "used by 0" &&
      hasSubstr out "bp_code_link_status_absent" &&
      hasSubstr out "bp_code_link_empty" &&
      hasSubstr out "No associated Lean declarations" &&
      hasSubstr out ">○</span>" &&
      hasSubstr out ">L∃∀N</span>" &&
      hasSubstr out "class=\"bp_relation_chip bp_relation_chip_empty\"" &&
      hasSubstr out "data-bp-relation-eyebrow=\"Used by · 1\"" &&
      hasSubstr out "data-bp-relation-eyebrow=\"Statement uses · 1\"" &&
      !hasSubstr out "data-bp-preview-id=\"bp-used-by-" &&
      !hasSubstr out "data-bp-preview-footer-html="
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls usesPreviewDoc
    let relationJs? := findRelationPanelJs? st
    pure (
      hasSubstr out "uses 2" &&
      hasSubstr out "class=\"bp_extra_slot bp_extra_slot_uses\"" &&
      hasSubstr out "class=\"bp_relation_chip\"" &&
      hasSubstr out "data-bp-relation-eyebrow=\"Statement uses · 2\"" &&
      hasSubstr out "data-bp-relation-eyebrow=\"Proof uses · 2\"" &&
      hasSubstr out "class=\"bp-relation-entries\"" &&
      !hasSubstr out "data-bp-relation-preview-id=\"bp-uses-" &&
      hasSubstr out "def:uses.hidden" &&
      hasSubstr out "def:uses.inline" &&
      hasSubstr out "def:uses.proof" &&
      hasSubstr out "def:uses.proof.extra" &&
      hasSubstr out "\"oa\"" &&
      hasSubstr out "\"it\"" &&
      hasSubstr out "\"ia\"" &&
      !hasSubstr out "bp_uses_chip" &&
      !hasSubstr out "bp_uses_origin_badge" &&
      !hasSubstr out "bp_uses_intent_badge" &&
      appearsBefore out "class=\"bp_extra_slot bp_extra_slot_uses\"" "class=\"bp_extra_slot bp_extra_slot_used_by\"" &&
      appearsBefore out "class=\"bp_extra_slot bp_extra_slot_used_by\"" "class=\"bp_extra_slot bp_extra_slot_code\"" &&
      relationJs?.isNone
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls groupPreviewDoc
    let relationJs? := findRelationPanelJs? st
    pure (
      hasSubstr out "class=\"bp_extra_slot bp_extra_slot_group\"" &&
      hasSubstr out "class=\"bp_extra_slot bp_extra_slot_uses\"" &&
      hasSubstr out "class=\"bp_extra_slot bp_extra_slot_used_by\"" &&
      appearsBefore out "class=\"bp_extra_slot bp_extra_slot_group\"" "class=\"bp_extra_slot bp_extra_slot_uses\"" &&
      appearsBefore out "class=\"bp_extra_slot bp_extra_slot_uses\"" "class=\"bp_extra_slot bp_extra_slot_used_by\"" &&
      appearsBefore out "class=\"bp_extra_slot bp_extra_slot_used_by\"" "class=\"bp_extra_slot bp_extra_slot_code\"" &&
      hasSubstr out "data-bp-relation-eyebrow=\"Group · " &&
      hasSubstr out "data-bp-relation-title=\"Preview group title.\"" &&
      hasSubstr out "class=\"bp-relation-entries\"" &&
      !hasSubstr out "class=\"bp_relation_item bp_relation_item_active\"" &&
      hasSubstr out "Preview group title." &&
      hasSubstr out "used by 1" &&
      relationJs?.isNone
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls missingGroupPreviewDoc
    pure (
      hasSubstr out "bp_relation_chip_warn" &&
      hasSubstr out "data-bp-relation-note=" &&
      hasSubstr out "grp:missing"
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls singleDeclaredGroupDoc
    pure (
      !hasSubstr out "class=\"bp_extra_slot bp_extra_slot_group\"" &&
      !hasSubstr out "bp_relation_chip_warn" &&
      !hasSubstr out "data-bp-relation-preview-id=\"bp-group-"
    )

end Verso.VersoBlueprintTests.BlueprintPreviewWiring.RelatedPanel
