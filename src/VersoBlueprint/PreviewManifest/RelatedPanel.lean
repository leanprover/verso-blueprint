/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoBlueprint.Informal.Block.RelatedPanel
public import VersoBlueprint.Lib.HoverRender
public import VersoBlueprint.PreviewManifest

public section

namespace Informal.PreviewManifest

open Lean

def RelatedEntry.displayLabel (entry : RelatedEntry) : String :=
  let label := labelString entry.label |>.trimAscii.toString
  if !label.isEmpty then
    label
  else
    entry.previewKey.map (toString ·) |>.getD "unlabeled relation"

def RelatedEntry.displayTitle (entry : RelatedEntry) : String :=
  let title := entry.title.trimAscii.toString
  if title.isEmpty then entry.displayLabel else title

/-- Shared badge policy over the manifest's facet-bound relation facts. -/
def RelatedEntry.badgeCodes (entry : RelatedEntry) : Array String :=
  Informal.RelatedPanel.dependencyBadgeCodes entry.dependencies

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
    dependencies := entry.dependencies
    active := entry.label == currentLabel
  }

def relatedPanelEntries
    (entries : Array RelatedEntry)
    (currentLabel : Name)
    (idPrefix : String) : Array Informal.RelatedPanel.PanelEntry :=
  entries.map fun entry => entry.panelEntry currentLabel idPrefix

end Informal.PreviewManifest
