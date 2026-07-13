/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Informal.Block.RelatedPanel
import VersoBlueprint.Lib.HoverRender
import VersoBlueprint.PreviewManifest

namespace Informal.PreviewManifest

open Lean
open Verso.Output
open Verso.Output.Html

def RelatedEntry.displayLabel (entry : RelatedEntry) : String :=
  let label := labelString entry.label |>.trimAscii.toString
  if !label.isEmpty then
    label
  else
    entry.previewKey.map (toString ·) |>.getD "unlabeled relation"

def RelatedEntry.displayTitle (entry : RelatedEntry) : String :=
  let title := entry.title.trimAscii.toString
  if title.isEmpty then entry.displayLabel else title

/-- Compact browser-runtime code for one manifest relation axis. -/
def RelationAxis.badgeCode (axis : RelationAxis) : String :=
  match axis with
  | .statement => Informal.RelatedPanel.statementAxisBadgeCode
  | .proof => Informal.RelatedPanel.proofAxisBadgeCode

/-- Compact browser-runtime badge codes for one manifest relation entry. -/
def RelatedEntry.badgeCodes (entry : RelatedEntry) : Array String :=
  entry.axes.map RelationAxis.badgeCode

def RelatedEntry.badgesHtml (entry : RelatedEntry) : Html :=
  Informal.RelatedPanel.renderRelationBadgeCodes entry.badgeCodes

def RelatedEntry.panelEntry
    (entry : RelatedEntry)
    (currentLabel : Name)
    (idPrefix : String) : Informal.RelatedPanel.PanelEntry :=
  {
    previewId := Informal.HoverRender.previewId idPrefix entry.displayLabel
    previewKey := entry.previewKey
    previewTitle := entry.displayTitle
    label := entry.label
    href := entry.href
    badgeCodes := entry.badgeCodes
    active := entry.label == currentLabel
  }

def relatedPanelEntries
    (entries : Array RelatedEntry)
    (currentLabel : Name)
    (idPrefix : String) : Array Informal.RelatedPanel.PanelEntry :=
  entries.map fun entry => entry.panelEntry currentLabel idPrefix

end Informal.PreviewManifest
