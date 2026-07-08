/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.ExternalRefSnapshot
import VersoBlueprint.Informal.ExternalCode

namespace Verso.VersoBlueprintTests.ExternalDeclRender

open Lean

def sameModuleRenderDef : Nat := 0

abbrev sameModuleRenderAbbrev : Nat := sameModuleRenderDef

unsafe def sameModuleRenderUnsafeDef : Nat := sameModuleRenderDef + 1

unsafe abbrev sameModuleRenderUnsafeAbbrev : Nat := sameModuleRenderUnsafeDef

theorem sameModuleRenderThm : True := by
  trivial

/--
A package-shaped structure whose constructor is intentionally much less useful
than its field list in compact external declaration panels.
-/
structure sameModuleRenderPackage where
  /-- The first value in the package. -/
  x : Nat
  /-- The second value in the package. -/
  y : Nat
  /-- The ordering witness carried by the package. -/
  hxy : x <= y
  /-- A deliberately dependent equality field. -/
  hsum : x + y = y + x

/--
Given a counterexample-shaped input `x + y = y + x`, produce a package.
-/
theorem sameModuleRenderPackageExists (x y : Nat) (hxy : x <= y) :
    Nonempty sameModuleRenderPackage := by
  exact Nonempty.intro { x := x, y := y, hxy := hxy, hsum := Nat.add_comm x y }

/-- info: true -/
#guard_msgs in
#eval
  show Lean.CoreM Bool from do
    let natAdd? ← (Informal.renderDeclHtmlNodeDirect? `Nat.add).run'
    let prod? ← (Informal.renderDeclHtmlNodeDirect? `Prod).run'
    let sameDef? ← (Informal.renderDeclHtmlNodeDirect? `Verso.VersoBlueprintTests.ExternalDeclRender.sameModuleRenderDef).run'
    let sameAbbrev? ← (Informal.renderDeclHtmlNodeDirect? `Verso.VersoBlueprintTests.ExternalDeclRender.sameModuleRenderAbbrev).run'
    let sameUnsafeDef? ← (Informal.renderDeclHtmlNodeDirect? `Verso.VersoBlueprintTests.ExternalDeclRender.sameModuleRenderUnsafeDef).run'
    let sameUnsafeAbbrev? ← (Informal.renderDeclHtmlNodeDirect? `Verso.VersoBlueprintTests.ExternalDeclRender.sameModuleRenderUnsafeAbbrev).run'
    let sameThm? ← (Informal.renderDeclHtmlNodeDirect? `Verso.VersoBlueprintTests.ExternalDeclRender.sameModuleRenderThm).run'
    let samePackage? ← (Informal.renderDeclHtmlNodeDirect? `Verso.VersoBlueprintTests.ExternalDeclRender.sameModuleRenderPackage).run'
    let samePackageExists? ← (Informal.renderDeclHtmlNodeDirect? `Verso.VersoBlueprintTests.ExternalDeclRender.sameModuleRenderPackageExists).run'
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
      match natAdd?, sameDef?, sameAbbrev?, sameUnsafeDef?, sameUnsafeAbbrev?, sameThm? with
      | some natAdd, some sameDef, some sameAbbrev, some sameUnsafeDef, some sameUnsafeAbbrev, some sameThm =>
        let badWide := "<pre class=\"bp_external_decl_signature signature hl lean block\"><span class=\"keyword token\">def</span> <div class=\"wide-only\">"
        let badAbbrev := "<pre class=\"bp_external_decl_signature signature hl lean block\"><span class=\"keyword token\">abbrev</span> <div class=\"wide-only\">"
        let badUnsafeDef := "<pre class=\"bp_external_decl_signature signature hl lean block\"><span class=\"keyword token\">unsafe def</span> <div class=\"wide-only\">"
        let badUnsafeAbbrev := "<pre class=\"bp_external_decl_signature signature hl lean block\"><span class=\"keyword token\">unsafe abbrev</span> <div class=\"wide-only\">"
        let badTheorem := "<pre class=\"bp_external_decl_signature signature hl lean block\"><span class=\"keyword token\">theorem</span> <div class=\"wide-only\">"
        !natAdd.asString.contains badWide &&
        !sameDef.asString.contains badWide &&
        !sameAbbrev.asString.contains badAbbrev &&
        !sameUnsafeDef.asString.contains badUnsafeDef &&
        !sameUnsafeAbbrev.asString.contains badUnsafeAbbrev &&
        !sameThm.asString.contains badTheorem
      | _, _, _, _, _, _ => false
    let abbrevUsesAbbrevRendering :=
      match sameAbbrev? with
      | some sameAbbrev =>
        let out := sameAbbrev.asString
        out.contains "sameModuleRenderAbbrev" &&
          out.contains "class=\"declaration decl def abbrev\"" &&
          out.contains "data-kind=\"abbrev\"" &&
          out.contains "<span class=\"bp_external_decl_kind\">abbrev</span>" &&
          out.contains "<span class=\"keyword token\">abbrev</span>" &&
          !out.contains "data-kind=\"def\""
      | none => false
    let unsafeDefUsesUniformDefinitionRendering :=
      match sameUnsafeDef? with
      | some sameUnsafeDef =>
        let out := sameUnsafeDef.asString
        out.contains "sameModuleRenderUnsafeDef" &&
          out.contains "class=\"declaration decl def\"" &&
          out.contains "data-kind=\"def\"" &&
          out.contains "<span class=\"bp_external_decl_kind\">def</span>" &&
          out.contains "<span class=\"bp_external_decl_header_meta\">(unsafe)</span>" &&
          out.contains "<span class=\"keyword token\">unsafe def</span>"
      | none => false
    let unsafeAbbrevUsesUniformAbbrevRendering :=
      match sameUnsafeAbbrev? with
      | some sameUnsafeAbbrev =>
        let out := sameUnsafeAbbrev.asString
        out.contains "sameModuleRenderUnsafeAbbrev" &&
          out.contains "class=\"declaration decl def abbrev\"" &&
          out.contains "data-kind=\"abbrev\"" &&
          out.contains "<span class=\"bp_external_decl_kind\">abbrev</span>" &&
          out.contains "<span class=\"bp_external_decl_header_meta\">(unsafe)</span>" &&
          out.contains "<span class=\"keyword token\">unsafe abbrev</span>" &&
          !out.contains "data-kind=\"unsafe abbrev\""
      | none => false
    let structureUsesFieldFirstRendering :=
      match samePackage? with
      | some samePackage =>
        let out := samePackage.asString
        out.contains "class=\"declaration decl structure\"" &&
          out.contains "data-kind=\"structure\"" &&
          out.contains "<span class=\"bp_external_decl_kind\">structure</span>" &&
          out.contains "<span class=\"bp_external_decl_header_meta\">(4 fields)</span>" &&
          out.contains "sameModuleRenderPackage.x" &&
          out.contains "The first value in the package." &&
          !out.contains "sameModuleRenderPackage.mk" &&
          !out.contains "Constructor"
      | none => false
    let theoremDocstringAvailableForRuntimeMarkdown :=
      match samePackageExists? with
      | some samePackageExists =>
        let out := samePackageExists.asString
        out.contains "<pre class=\"docstring\">Given a counterexample-shaped input `x + y = y + x`" &&
          out.contains "produce a package." &&
          !out.contains "<span class=\"bp_external_decl_header_meta\">(docstring)</span>"
      | none => false
    pure
      (natAddHasPayload &&
        natAddHasLocalHover &&
        externalWrapperHtmlOk &&
        abbrevUsesAbbrevRendering &&
        unsafeDefUsesUniformDefinitionRendering &&
        unsafeAbbrevUsesUniformAbbrevRendering &&
        structureUsesFieldFirstRendering &&
        theoremDocstringAvailableForRuntimeMarkdown &&
        prod?.isSome &&
        sameDef?.isSome &&
        sameAbbrev?.isSome &&
        sameUnsafeDef?.isSome &&
        sameUnsafeAbbrev?.isSome &&
        sameThm?.isSome &&
        samePackage?.isSome &&
        samePackageExists?.isSome &&
        missing?.isNone)

private def htmlTestContext :
    Verso.Doc.Html.HtmlT.Context Verso.Genre.Manual Id := {
  options := {
    headerLevel := 1
    logError := fun _ => pure ()
  }
  traverseContext := { logError := fun _ => pure () }
  traverseState := Verso.Genre.Manual.TraverseState.initialize {}
  definitionIds := {}
  linkTargets := {}
  codeOptions := {}
}

/-- info: true -/
#guard_msgs in
#eval
  show Lean.CoreM Bool from do
    let env ← getEnv
    let some cinfo := env.find? `Nat.add
      | return false
    match ← (Informal.renderDeclHtmlDirectFromInfoE `Nat.add cinfo).run' with
    | .ok rendered =>
      pure <|
        rendered.hoverPayloads.size > 0 &&
        rendered.hoverPayloads.any (fun payload => payload.html.contains "class=\"docstring\"") &&
        rendered.html.contains "data-bp-external-hover-local=\"" &&
        rendered.html.contains "data-bp-external-hover-inline-local=\"" &&
        !rendered.html.contains "class=\"hover-info\"" &&
        rendered.selfContained.contains "class=\"hover-info\"" &&
        !rendered.selfContained.contains "data-bp-external-hover-local=" &&
        !rendered.selfContained.contains "data-bp-external-hover-inline-local="
    | .error _ => pure false

/-- info: true -/
#guard_msgs in
#eval
  show Lean.CoreM Bool from do
    let opts ← Lean.getOptions
    let ref ← Informal.externalRefSnapshotAtCurrentDir opts (Informal.Data.ExternalRef.ofName `Nat.add)
    let some payloadCount :=
      (match ref.render with
      | .ok rendered =>
        if rendered.hoverPayloads.any (fun payload => payload.html.contains "class=\"docstring\"") then
          some rendered.hoverPayloads.size
        else
          none
      | .error _ => none)
      | return false
    let previewHtml := Informal.ExternalCode.renderPreviewHtml #[ref, ref] |>.asString
    let (cacheHtml, cacheHoverState) :=
      Informal.ExternalCode.renderPreviewHtmlWithCacheHovers #[ref, ref] {}
    let cacheHtml := cacheHtml.asString
    let renderPage :=
      Informal.ExternalCode.renderPartsWithPageHovers
        { caption := "Code for theorem", number? := some "1" }
        "Lean declarations"
        .empty
        #[ref, ref]
        (fun _ => none)
    let (parts, hoverState) := (renderPage htmlTestContext).run {}
    let pageHtml := parts.externalCodePanel.asString
    pure <|
      payloadCount > 0 &&
      hoverState.dedup.contentId.size == payloadCount &&
      cacheHoverState.dedup.contentId.size == payloadCount &&
      pageHtml.contains "data-verso-hover=\"" &&
      cacheHtml.contains "data-verso-hover=\"" &&
      !pageHtml.contains "data-bp-external-hover-local=\"" &&
      !pageHtml.contains "data-bp-external-hover-inline-local=\"" &&
      !pageHtml.contains "class=\"hover-info\"" &&
      !cacheHtml.contains "data-bp-external-hover-local=\"" &&
      !cacheHtml.contains "data-bp-external-hover-inline-local=\"" &&
      !cacheHtml.contains "class=\"hover-info\"" &&
      previewHtml.contains "class=\"hover-info\"" &&
      !previewHtml.contains "data-bp-external-hover-local=\"" &&
      !previewHtml.contains "data-bp-external-hover-inline-local=\""

/-- info: true -/
#guard_msgs in
#eval
  show Lean.CoreM Bool from do
    let opts ← Lean.getOptions
    let sameDef ← Informal.externalRefSnapshotAtCurrentDir opts
      (Informal.Data.ExternalRef.ofName `Verso.VersoBlueprintTests.ExternalDeclRender.sameModuleRenderDef)
    let sameAbbrev ← Informal.externalRefSnapshotAtCurrentDir opts
      (Informal.Data.ExternalRef.ofName `Verso.VersoBlueprintTests.ExternalDeclRender.sameModuleRenderAbbrev)
    let sameUnsafeDef ← Informal.externalRefSnapshotAtCurrentDir opts
      (Informal.Data.ExternalRef.ofName `Verso.VersoBlueprintTests.ExternalDeclRender.sameModuleRenderUnsafeDef)
    let sameUnsafeAbbrev ← Informal.externalRefSnapshotAtCurrentDir opts
      (Informal.Data.ExternalRef.ofName `Verso.VersoBlueprintTests.ExternalDeclRender.sameModuleRenderUnsafeAbbrev)
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
      sameUnsafeDef.present &&
      sameUnsafeDef.kind == .definition &&
      sameUnsafeDef.render.isOk &&
      sameUnsafeAbbrev.present &&
      sameUnsafeAbbrev.kind == .definition &&
      sameUnsafeAbbrev.render.isOk &&
      importedDef.present &&
      importedDef.render.isOk &&
      importedThm.present &&
      importedThm.render.isOk &&
      !missing.present &&
      (match missing.render with
      | .error _ => true
      | .ok _ => false)

end Verso.VersoBlueprintTests.ExternalDeclRender
