/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.DirectiveArgParsing
import VersoBlueprint.LabelNameParsing
import VersoBlueprint.LeanNameParsing
import VersoBlueprint.Lib.HtmlId
import VersoBlueprint.Lib.PreviewKey
meta import VersoBlueprint.DirectiveArgParsing
meta import VersoBlueprint.Informal.LabelArg
meta import VersoBlueprint.Informal.UseConfig
meta import VersoBlueprint.Informal.Uses.Config
meta import VersoBlueprint.LabelNameParsing
meta import VersoBlueprint.LeanNameParsing
meta import VersoBlueprint.Lib.HtmlId
meta import VersoBlueprint.Lib.PreviewKey

namespace VersoBlueprintModuleTests.Foundation

open Lean

local macro "previewKeyContract" : term => do
  match Informal.PreviewKey.ofString? " quoted " with
  | some key => return quote key
  | none => unreachable!

/-- info: true -/
#guard_msgs in
#eval
  let directiveArgs :=
    Informal.DirectiveArgParsing.splitCommaSeparatedList " alpha, , beta,gamma "
  let leanNameOk :=
    match Informal.LeanNameParsing.parseE " Example.contract " with
    | .ok name => name == `Example.contract
    | .error _ => false
  let emptyLeanNameRejected :=
    match Informal.LeanNameParsing.parseE " " with
    | .error message => message == "empty name"
    | .ok _ => false
  directiveArgs == #["alpha", "beta", "gamma"] &&
    leanNameOk &&
    emptyLeanNameRejected &&
    Informal.LabelNameParsing.parse "thm:contract" == Name.mkSimple "thm:contract" &&
    Informal.HtmlId.key "alpha.beta" == "alpha-002Ebeta" &&
    Informal.HtmlId.prefixed "bp" "" == "bp" &&
    toString (previewKeyContract : Informal.PreviewKey) == "quoted" &&
    Lean.toJson (previewKeyContract : Informal.PreviewKey) == Lean.Json.str "quoted" &&
    (match Lean.fromJson? (α := Informal.PreviewKey) (Lean.Json.str " normalized ") with
      | .ok key => toString key == "normalized"
      | .error _ => false) &&
    (match Lean.fromJson? (α := Informal.PreviewKey) (Lean.Json.str "  ") with
      | .error _ => true
      | .ok _ => false)

set_option verso.blueprint.trimTeXLabelPrefix true in
/-- info: true -/
#guard_msgs in
#eval true

/-- info: true -/
#guard_msgs in
#eval
  let labelSyntax := mkIdent `authorWrittenLabel
  let parsed := Informal.LabelArg.parse {
    val := "module.authoring.label"
    «syntax» := labelSyntax
  }
  parsed.label == Name.mkSimple "module.authoring.label" &&
    parsed.labelSyntax.getId == `authorWrittenLabel

/-- info: true -/
#guard_msgs in
#eval
  let labels := Informal.UseConfig.parseLabels (some " source.one, source.two ")
  let valid := Informal.UseConfig.parseMetadata (some " automatic ") (some " technical ")
  let invalid := Informal.UseConfig.parseMetadata (some "auto") (some "tech")
  let refs := Informal.UseConfig.refsForLabels labels valid
  labels == #[Name.mkSimple "source.one", Name.mkSimple "source.two"] &&
    valid.origin == .automatic && valid.intent == .technical &&
    valid.invalidOrigin.isNone && valid.invalidIntent.isNone &&
    invalid.origin == .manual && invalid.intent == .regular &&
    invalid.invalidOrigin == some "auto" && invalid.invalidIntent == some "tech" &&
    refs.all fun ref => ref.origin == .automatic && ref.intent == .technical

/-- info: true -/
#guard_msgs in
#eval
  let labelSyntax := mkIdent `usesConfigLabel
  let uses : Informal.UsesConfig := {
    label := Name.mkSimple "uses.config.contract"
    labelSyntax
    origin := .automatic
    intent := .auxiliary
  }
  let bpref : Informal.BprefConfig := {
    label := uses.label
    labelSyntax
  }
  uses.label == bpref.label && uses.origin == .automatic && uses.intent == .auxiliary &&
    uses.labelSyntax.getId == `usesConfigLabel && bpref.labelSyntax.getId == `usesConfigLabel

end VersoBlueprintModuleTests.Foundation
