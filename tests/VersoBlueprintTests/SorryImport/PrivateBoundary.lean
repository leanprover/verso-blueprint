/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint
import VersoBlueprintTests.SorryImport.PrivateProvider

open Lean Informal.Data

namespace Verso.VersoBlueprintTests.SorryImport.PrivateBoundary

-- Reuse Lake's actual cache-in-place artifacts and explicitly select visibility;
-- the surrounding legacy module must not accidentally grant import-all coverage.
private unsafe def withPrivateProvider (importAll : Bool) (action : CoreM Bool) : CoreM Bool := do
  liftM enableInitializersExecution
  let output ← liftM <| IO.Process.output {
    cmd := "./scripts/lean-low-priority"
    args := #["lake", "-q", "query", "-J", "+VersoBlueprintTests.SorryImport.PrivateBoundary:setup"]
  }
  unless output.exitCode == 0 do throwError "Private provider setup failed: {output.stderr}"
  let setup : ModuleSetup ← ofExcept <| Json.parse output.stdout >>= fromJson?
  let env ← liftM <| importModules
    #[{ module := `VersoBlueprintTests.SorryImport.PrivateProvider, importAll }]
    {} (loadExts := true) (level := .exported) (arts := setup.importArts)
  withEnv env action

/-- info: true -/
#guard_msgs in
#eval withPrivateProvider false do
  let status ← analyzeDeclaration `PrivateSorryBoundary.exposedHoleConsumer
  return !status.isProved && (status.hasKnownSorry || status.hasUnverifiedCoverage)

/-- info: true -/
#guard_msgs in
#eval withPrivateProvider true do
  let hole ← analyzeDeclaration `PrivateSorryBoundary.exposedHoleConsumer
  let complete ← analyzeDeclaration `PrivateSorryBoundary.exposedCompleteConsumer
  return !hole.isProved && hole.hasKnownSorry && complete.isProved

private def hasLeadingSignatureKeyword (html variantClass keyword : String) : Bool :=
  match html.splitOn s!"<div class=\"{variantClass}\">" with
  | [_, rest] =>
    let variantBody := (rest.splitOn "</div>").headD ""
    match variantBody.splitOn "<pre class=\"bp_external_decl_signature signature hl lean block\">" with
    | [_, afterPre] =>
      afterPre.trimAsciiStart.startsWith s!"<span class=\"keyword token\">{keyword}</span>"
    | _ => false
  | _ => false

private def hasRenderedDeclKind (html kind : String) : Bool :=
  html.contains s!"class=\"declaration decl {kind}\"" &&
  html.contains s!"data-kind=\"{kind}\"" &&
  html.contains s!"<span class=\"bp_external_decl_kind\">{kind}</span>" &&
  hasLeadingSignatureKeyword html "wide-only" kind &&
  hasLeadingSignatureKeyword html "narrow-only" kind &&
  (kind == "axiom" ||
    (!html.contains "data-kind=\"axiom\"" &&
      !html.contains "<span class=\"bp_external_decl_kind\">axiom</span>"))

/-- info: true -/
#guard_msgs in
#eval withPrivateProvider false do
  -- In exported module imports, body-hidden theorems, definitions, and opaques
  -- appear as `.axiomInfo`; both `registerExternalRef` and rendered HTML must
  -- recover their original declaration kind while keeping genuine axioms and
  -- unrecovered axiom views conservative.
  let env ← getEnv
  let isAxiom (name : Name) := match env.find? name with
    | some (.axiomInfo _) => true
    | _ => false
  let register (name : Name) (authoredKind : NodeKind) :=
    Informal.registerExternalRef {} (System.FilePath.mk ".") {
      written := name, canonical := name, kind := authoredKind
    }
  let htmlOf (ref : ExternalRef) : String := match ref.render with
    | .ok rendered => rendered.html
    | .error _ => ""
  let thmRef ← register `PrivateSorryBoundary.completeBridge .definition
  let defRef ← register `PrivateSorryBoundary.hiddenDef .theorem
  let opaqueRef ← register `PrivateSorryBoundary.hiddenOpaque .definition
  let opaqueAsThmRef ← register `PrivateSorryBoundary.hiddenOpaque .theorem
  let axRef ← register `PrivateSorryBoundary.genuineAxiom .theorem
  let axAsDefRef ← register `PrivateSorryBoundary.genuineAxiom .definition
  let thmHtml := htmlOf thmRef
  let defHtml := htmlOf defRef
  let opaqueHtml := htmlOf opaqueRef
  let axHtml := htmlOf axRef
  let some thmInfo := env.find? `PrivateSorryBoundary.completeBridge | return false
  let some defInfo := env.find? `PrivateSorryBoundary.hiddenDef | return false
  let some opaqueInfo := env.find? `PrivateSorryBoundary.hiddenOpaque | return false
  let some axInfo := env.find? `PrivateSorryBoundary.genuineAxiom | return false
  let unknownAxiomInfo : ConstantInfo := .axiomInfo {
    name := `PrivateSorryBoundary.syntheticUnknownAxiom
    levelParams := []
    type := .sort .zero
    isUnsafe := false
  }
  return isAxiom `PrivateSorryBoundary.completeBridge &&
    isAxiom `PrivateSorryBoundary.hiddenDef &&
    isAxiom `PrivateSorryBoundary.hiddenOpaque &&
    isAxiom `PrivateSorryBoundary.genuineAxiom &&
    ConstantInfo.originalKind env thmInfo == some .thm &&
    ConstantInfo.originalKind env defInfo == some .defn &&
    ConstantInfo.originalKind env opaqueInfo == some .opaque &&
    ConstantInfo.originalKind env axInfo == some .axiom &&
    ConstantInfo.originalKind env unknownAxiomInfo == none &&
    (match ConstantInfo.blueprintBodyAccess env opaqueInfo with | .unavailable => true | _ => false) &&
    (match ConstantInfo.blueprintBodyAccess env axInfo with | .absent => true | _ => false) &&
    (match ConstantInfo.blueprintBodyAccess env unknownAxiomInfo with | .unavailable => true | _ => false) &&
    ConstantInfo.externalBlueprintNodeKind? env unknownAxiomInfo .theorem == some .theorem &&
    ConstantKind.exportedAxiomPresentation? .thm ==
      some { kindClass := "theorem", kindMarker := "theorem", keywordText := "theorem" } &&
    ConstantKind.exportedAxiomPresentation? .defn ==
      some { kindClass := "def", kindMarker := "def", keywordText := "def" } &&
    ConstantKind.exportedAxiomPresentation? .opaque ==
      some { kindClass := "opaque", kindMarker := "opaque", keywordText := "opaque" } &&
    ConstantKind.exportedAxiomPresentation? .axiom ==
      some { kindClass := "axiom", kindMarker := "axiom", keywordText := "axiom" } &&
    ConstantKind.exportedAxiomPresentation? .induct == none &&
    thmRef.present && thmRef.kind == .theorem &&
    hasRenderedDeclKind thmHtml "theorem" &&
    defRef.present && defRef.kind == .definition &&
    hasRenderedDeclKind defHtml "def" &&
    opaqueRef.present && opaqueRef.kind == .definition &&
    opaqueAsThmRef.present && opaqueAsThmRef.kind == .theorem &&
    hasRenderedDeclKind opaqueHtml "opaque" &&
    axRef.present && axRef.kind == .theorem &&
    axAsDefRef.present && axAsDefRef.kind == .definition &&
    hasRenderedDeclKind axHtml "axiom"

/-- info: true -/
#guard_msgs in
#eval withPrivateProvider true do
  -- Under import-all, `hiddenOpaque` is visible directly as `.opaqueInfo` and
  -- must keep the same stored kind and rendered `opaque` presentation as the
  -- exported `.axiomInfo` view.
  let env ← getEnv
  let some opaqueInfo := env.find? `PrivateSorryBoundary.hiddenOpaque | return false
  let isOpaque := match opaqueInfo with | .opaqueInfo _ => true | _ => false
  let register (authoredKind : NodeKind) :=
    Informal.registerExternalRef {} (System.FilePath.mk ".") {
      written := `PrivateSorryBoundary.hiddenOpaque
      canonical := `PrivateSorryBoundary.hiddenOpaque
      kind := authoredKind
    }
  let opaqueRef ← register .definition
  let opaqueAsThmRef ← register .theorem
  let opaqueHtml := match opaqueRef.render with
    | .ok rendered => rendered.html
    | .error _ => ""
  return isOpaque &&
    ConstantInfo.originalKind env opaqueInfo == some .opaque &&
    (match ConstantInfo.blueprintBodyAccess env opaqueInfo with | .available _ => true | _ => false) &&
    opaqueRef.present && opaqueRef.kind == .definition &&
    opaqueAsThmRef.present && opaqueAsThmRef.kind == .theorem &&
    hasRenderedDeclKind opaqueHtml "opaque"

end Verso.VersoBlueprintTests.SorryImport.PrivateBoundary
