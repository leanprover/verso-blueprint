/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.ExternalRefSnapshot

namespace Verso.VersoBlueprintTests.DocGenNameRender

open Lean

def sameModuleRenderDef : Nat := 0

abbrev sameModuleRenderAbbrev : Nat := sameModuleRenderDef

theorem sameModuleRenderThm : True := by
  trivial

/-- info: true -/
#guard_msgs in
#eval
  show Lean.CoreM Bool from do
    let natAdd? ← (Informal.renderDeclHtmlNodeDirect? `Nat.add).run'
    let prod? ← (Informal.renderDeclHtmlNodeDirect? `Prod).run'
    let sameDef? ← (Informal.renderDeclHtmlNodeDirect? `Verso.VersoBlueprintTests.DocGenNameRender.sameModuleRenderDef).run'
    let sameAbbrev? ← (Informal.renderDeclHtmlNodeDirect? `Verso.VersoBlueprintTests.DocGenNameRender.sameModuleRenderAbbrev).run'
    let sameThm? ← (Informal.renderDeclHtmlNodeDirect? `Verso.VersoBlueprintTests.DocGenNameRender.sameModuleRenderThm).run'
    let missing? ← (Informal.renderDeclHtmlNodeDirect? `No.Such.Declaration).run'
    let natAddHasPayload :=
      match natAdd? with
      | some html => html.asString.length > 0
      | none => false
    let natAddHasLocalHover :=
      match natAdd? with
      | some html =>
        let out := html.asString
        out.contains "class=\"hover-info\"" && !out.contains "data-verso-hover="
      | none => false
    let externalWrapperHtmlOk :=
      match natAdd?, sameDef?, sameAbbrev?, sameThm? with
      | some natAdd, some sameDef, some sameAbbrev, some sameThm =>
        let badWide := "<pre class=\"bp_external_decl_signature signature hl lean block\"><span class=\"keyword token\">def</span> <div class=\"wide-only\">"
        let badAbbrev := "<pre class=\"bp_external_decl_signature signature hl lean block\"><span class=\"keyword token\">abbrev</span> <div class=\"wide-only\">"
        let badTheorem := "<pre class=\"bp_external_decl_signature signature hl lean block\"><span class=\"keyword token\">theorem</span> <div class=\"wide-only\">"
        !natAdd.asString.contains badWide &&
        !sameDef.asString.contains badWide &&
        !sameAbbrev.asString.contains badAbbrev &&
        !sameThm.asString.contains badTheorem
      | _, _, _, _ => false
    let abbrevUsesAbbrevRendering :=
      match sameAbbrev? with
      | some sameAbbrev =>
        let out := sameAbbrev.asString
        out.contains "sameModuleRenderAbbrev" &&
          out.contains "class=\"declaration decl def abbrev\"" &&
          out.contains "data-kind=\"abbrev\"" &&
          out.contains "<span class=\"keyword token\">abbrev</span>" &&
          !out.contains "data-kind=\"def\""
      | none => false
    pure
      (natAddHasPayload &&
        natAddHasLocalHover &&
        externalWrapperHtmlOk &&
        abbrevUsesAbbrevRendering &&
        prod?.isSome &&
        sameDef?.isSome &&
        sameAbbrev?.isSome &&
        sameThm?.isSome &&
        missing?.isNone)

/-- info: true -/
#guard_msgs in
#eval
  show Lean.CoreM Bool from do
    let opts ← Lean.getOptions
    let sameDef ← Informal.externalRefSnapshotAtCurrentDir opts
      (Informal.Data.ExternalRef.ofName `Verso.VersoBlueprintTests.DocGenNameRender.sameModuleRenderDef)
    let sameAbbrev ← Informal.externalRefSnapshotAtCurrentDir opts
      (Informal.Data.ExternalRef.ofName `Verso.VersoBlueprintTests.DocGenNameRender.sameModuleRenderAbbrev)
    let importedDef ← Informal.externalRefSnapshotAtCurrentDir opts
      (Informal.Data.ExternalRef.ofName `Nat.add)
    let importedThm ← Informal.externalRefSnapshotAtCurrentDir opts
      ({ (Informal.Data.ExternalRef.ofName `Nat.add_assoc) with kind := .theorem })
    let missing ← Informal.externalRefSnapshotAtCurrentDir opts
      (Informal.Data.ExternalRef.ofName `No.Such.Declaration)
    pure <|
      sameDef.present &&
      sameDef.render.isOk &&
      sameAbbrev.present &&
      sameAbbrev.kind == .definition &&
      sameAbbrev.render.isOk &&
      importedDef.present &&
      importedDef.render.isOk &&
      importedThm.present &&
      importedThm.render.isOk &&
      !missing.present &&
      (match missing.render with
      | .error _ => true
      | .ok _ => false)

end Verso.VersoBlueprintTests.DocGenNameRender
