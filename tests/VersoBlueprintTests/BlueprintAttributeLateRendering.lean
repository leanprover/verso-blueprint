/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintAttribute.LatePlacement
import VersoBlueprintTests.Blueprint.Support

open Lean Verso Informal
open Verso.Genre.Manual
open Verso.VersoBlueprintTests.Blueprint.Support
open Verso.VersoBlueprintTests.BlueprintAttribute.LatePlacement

namespace Verso.VersoBlueprintTests.BlueprintAttributeLateRendering

@[blueprint "attr.exported.theorem"
  (uses := ["attr.exported.definition"])
  (proofUses := ["attr.exported.undocumented"])]
theorem lateAttributeAttachment : True := trivial

run_cmd discard <| Informal.Environment.contribute (Name.mkSimple "attr.exported.theorem") {
  tags := #["late-attribute"]
  effort := some "small"
}

private def manualImpls : ExtensionImpls := extension_impls%

#eval show IO Unit from do
  let label := Name.mkSimple "attr.exported.theorem"
  let expectedStatement : Array Data.UseRef := #[{ label := Name.mkSimple "attr.exported.definition" }]
  let expectedProof : Array Data.UseRef := #[{ label := Name.mkSimple "attr.exported.undocumented" }]
  for doc in #[placedDoc, includedDoc] do
    let (html, state) ← renderManualDocHtmlStringAndState manualImpls doc
    let some data := TraversalIndex.Nodes.renderedData? state label
      | throw <| IO.userError "Missing attribute occurrence"
    unless data.statementUses == expectedStatement && data.proofUses == expectedProof &&
        data.tags.contains "late-attribute" && data.effort == some "small" do
      throw <| IO.userError "Attribute placement lost late contributions"
    unless data.foldCodeBlock && data.numberingMode == .global && data.globalCount == some 1 do
      throw <| IO.userError "Rendering lost attribute occurrence options"
    unless hasSubstr html "Exported theorem used to verify" &&
        hasSubstr html "lateAttributeAttachment" do
      throw <| IO.userError "Attribute body or late Lean attachment missing from HTML"
    let files ← buildManualPreviewDataFiles manualImpls doc
    let some entry := files.manifest.findEntry? (PreviewCache.statementKey label)
      | throw <| IO.userError "Missing attribute preview"
    unless entry.statementUses == expectedStatement && entry.proofUses == expectedProof &&
        entry.tags.contains "late-attribute" && entry.leanCodePreviewKeys.size == 2 do
      throw <| IO.userError "Attribute preview lost late dependencies, metadata, or code"
    let some graphNode := files.manifest.graphs.findSome? fun graph =>
        graph.nodes.find? (·.label == label)
      | throw <| IO.userError "Missing attribute graph node"
    unless graphNode.statementUses == entry.statementUses && graphNode.proofUses == entry.proofUses do
      throw <| IO.userError "Attribute graph and preview disagree"

  let (html, state) ← renderManualDocHtmlStringAndState manualImpls includedDoc
    (model := frozen.model)
  let some original := TraversalIndex.Nodes.renderedData? state label
    | throw <| IO.userError "Missing frozen attribute occurrence"
  unless original.statementUses.isEmpty && original.proofUses.isEmpty &&
      original.tags.isEmpty && !hasSubstr html "lateAttributeAttachment" do
    throw <| IO.userError "Later contributions leaked into a captured attribute document"

end Verso.VersoBlueprintTests.BlueprintAttributeLateRendering
