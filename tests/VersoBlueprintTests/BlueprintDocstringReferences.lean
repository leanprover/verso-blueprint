/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintAttribute.DocstringProvider
import VersoBlueprintTests.Blueprint.Support

open Lean Informal
open Verso Verso.Genre.Manual
open Verso.VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintDocstringReferences

private def manualImpls : ExtensionImpls := extension_impls%

-- These facts are checked after importing the compiled provider, before placement.
/-- info: true -/
#guard_msgs in
#eval show CoreM Bool from do
  let state := Informal.Environment.informalExt.getState (← getEnv)
  let some node := state.data.get? (Name.mkSimple "attr.doc.source") | return false
  let some statement := node.statement | return false
  let some proof := node.proof | return false
  let some late := state.data.get? (Name.mkSimple "attr.doc.late") | return false
  pure <|
    statement.deps == #[
      { label := Name.mkSimple "attr.doc.target", intent := .technical },
      { label := Name.mkSimple "attr.doc.automatic", origin := .automatic, intent := .auxiliary }
    ] &&
    proof.deps == #[{ label := Name.mkSimple "attr.doc.proof" }] &&
    late.statement.any (fun body => body.hasBody && body.dependencyLabels ==
      #[Name.mkSimple "attr.doc.target", Name.mkSimple "attr.doc.automatic"]) &&
    !state.localContributions.contains (Name.mkSimple "attr.doc.source") && state.stack.isEmpty

#docs (Genre.Manual) includedDoc "Docstring references" :=
:::::::
{includeBlueprintModule VersoBlueprintTests.BlueprintAttribute.DocstringProvider}
:::::::

#docs (Genre.Manual) placedDoc "Individual docstring placement" :=
:::::::
{blueprint_node "attr.doc.target"}

{blueprint_node "attr.doc.source"}

{blueprint_node "attr.doc.link"}

{blueprint_node "attr.doc.automatic"}

{blueprint_node "attr.doc.excluded"}

{blueprint_node "attr.doc.proof"}
:::::::

-- Both placement surfaces resolve forward references through ordinary traversal.
/-- info: true -/
#guard_msgs in
#eval show IO Bool from do
  for doc in #[includedDoc, placedDoc] do
    let (html, state) ← renderManualDocHtmlStringAndState manualImpls doc
    let some source := Informal.TraversalIndex.Nodes.data? state (Name.mkSimple "attr.doc.source")
      | return false
    let some target := Informal.TraversalIndex.Nodes.data? state (Name.mkSimple "attr.doc.target")
      | return false
    let some href := Informal.TraversalIndex.Nodes.href? state (Name.mkSimple "attr.doc.target")
      | return false
    unless source.statementUses.map (·.label) ==
        #[Name.mkSimple "attr.doc.target", Name.mkSimple "attr.doc.automatic"] &&
        source.proofUses.map (·.label) == #[Name.mkSimple "attr.doc.proof"] &&
        hasSubstr html s!"href=\"{href}\"" &&
        hasSubstr html s!"{target.displayTitle state}</a>" &&
        hasSubstr html "<strong>the comparison</strong>" &&
        hasSubstr html "bp_math inline" &&
        !hasSubstr html "[??]" do
      return false
  return true

-- Editor Markdown and declaration panels retain readable fallback text, including
-- empty references, without requiring a Blueprint site or creating graph edges.
/-- info: true -/
#guard_msgs in
#eval show MetaM Bool from do
  let decl := ``BlueprintAttribute.DocstringProvider.source
  let some (.inr doc) ← findInternalDocString? (← getEnv) decl | return false
  let some markdown ← findSimpleDocString? (← getEnv) decl | return false
  let html := Informal.Docstring.versoDocstringToHtml doc |>.asString
  pure <| hasSubstr markdown "attr.doc.target" && hasSubstr markdown "the comparison" &&
    hasSubstr html "<code>attr.doc.target</code>" &&
    hasSubstr html "<strong>the comparison</strong>" && hasSubstr html "bp_math inline"

-- Generated preview data must retain the edges and rendered reference bodies,
-- so downstream manifest consumers see the same semantics as the Manual page.
/-- info: true -/
#guard_msgs in
#eval show IO Bool from do
  let files ← buildManualPreviewDataFiles manualImpls includedDoc
  let key := Informal.PreviewCache.statementKey (Name.mkSimple "attr.doc.source")
  let some entry := files.manifest.previews.find? (·.key == key) | return false
  let some html := files.htmlCache.findHtml? key | return false
  pure <| entry.statementUses == #[
      { label := Name.mkSimple "attr.doc.target", intent := .technical },
      { label := Name.mkSimple "attr.doc.automatic", origin := .automatic, intent := .auxiliary }
    ] && entry.proofUses == #[{ label := Name.mkSimple "attr.doc.proof" }] &&
    hasSubstr html "<strong>the comparison</strong>" &&
    hasSubstr html "data-bp-preview-key="

/--
error: uses reference to bad has invalid '(intent := "mistyped")'; expected one of "regular", "auxiliary", "technical"
-/
#guard_msgs in
set_option doc.verso true in
/-- {uses "bad" (intent := "mistyped")}[] -/
def invalidDocstringIntent : Nat := 0

/-- error: Unexpected named argument `intent` -/
#guard_msgs in
set_option doc.verso true in
/-- {bpref "attr.doc.target" (intent := "technical")}[] -/
def rejectedLinkMetadata : Nat := 0

end Verso.VersoBlueprintTests.BlueprintDocstringReferences
