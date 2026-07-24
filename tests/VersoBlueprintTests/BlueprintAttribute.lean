/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintAttribute.Reexport
import VersoBlueprintTests.BlueprintAttribute.HybridProvider
import VersoBlueprintTests.Blueprint.Support

open Lean
open Informal

namespace Verso.VersoBlueprintTests.BlueprintAttribute

open Verso
open Verso.Genre.Manual
open Verso.VersoBlueprintTests.Blueprint.Support

private def manualImpls : ExtensionImpls := extension_impls%

#docs (Genre.Manual) placedAttributeDoc "Placed attribute-owned nodes" :=
:::::::
Introductory prose before the imported declaration.

{blueprint_node "attr.exported.theorem"}

Connecting prose between declarations.

{blueprint_node "attr.exported.undocumented"}

Concluding prose after the imported declarations.
:::::::

#docs (Genre.Manual) includedAttributeModuleDoc "Attribute module inclusion" :=
:::::::
{includeBlueprintModule 0 VersoBlueprintTests.BlueprintAttribute.Provider (title := "Imported attribute declarations")}
:::::::

#docs (Genre.Manual) includedAttributeModuleDefaultDoc "Default attribute module inclusion" :=
:::::::
{includeBlueprintModule VersoBlueprintTests.BlueprintAttribute.Provider}
:::::::

#docs (Genre.Manual) includedHybridAttributeModuleDoc "Hybrid attribute module inclusion" :=
:::::::
{includeBlueprintModule VersoBlueprintTests.BlueprintAttribute.HybridProvider}
:::::::

set_option verso.blueprint.numbering "global" in
#docs (Genre.Manual) globallyNumberedAttributeModuleDoc "Globally numbered attribute module" :=
:::::::
{includeBlueprintModule VersoBlueprintTests.BlueprintAttribute.Provider}
:::::::

set_option verso.blueprint.numbering "global" in
#docs (Genre.Manual) repeatedAttributePlacementDoc "Repeated attribute placement" :=
:::::::
{blueprint_node "attr.exported.theorem"}

Intervening prose between two placements of the same declaration.

{blueprint_node "attr.exported.theorem"}
:::::::

set_option verso.blueprint.numbering "local" in
#docs (Genre.Manual) interleavedLocalAttributePlacementDoc "Interleaved local attribute placement" :=
:::::::
:::definition "attr.consumer.before.placement"
A consumer-authored node before an imported attribute placement.
:::

{blueprint_node "attr.exported.theorem"}

:::definition "attr.consumer.after.placement"
A consumer-authored node after an imported attribute placement.
:::
:::::::

set_option verso.blueprint.numbering "local" in
#docs (Genre.Manual) locallyNumberedHybridAttributeModuleDoc "Locally numbered hybrid module" :=
:::::::
:::definition "attr.consumer.before.module"
A consumer-authored node that precedes the imported attribute module.
:::

{includeBlueprintModule VersoBlueprintTests.BlueprintAttribute.HybridProvider}
:::::::

/--
error: Blueprint module include: imported module 'VersoBlueprintTests.BlueprintAttribute.Reexport' has no declarations registered with `@[blueprint]`
-/
#guard_msgs in
#docs (Genre.Manual) rejectedEmptyAttributeModuleDoc "Rejected empty attribute module" :=
:::::::
{includeBlueprintModule VersoBlueprintTests.BlueprintAttribute.Reexport}
:::::::

/--
error: Blueprint module include: module 'NotImported.BlueprintModule' is not available through this Lean module's imports; add `import NotImported.BlueprintModule`
-/
#guard_msgs in
#docs (Genre.Manual) rejectedUnimportedAttributeModuleDoc "Rejected unimported attribute module" :=
:::::::
{includeBlueprintModule NotImported.BlueprintModule}
:::::::

/--
error: Blueprint module include is only available in Manual documents
-/
#guard_msgs in
#docs (VersoSlides.Slides) rejectedSlidesAttributeModuleDoc "Rejected Slides module include" :=
:::::::
{includeBlueprintModule VersoBlueprintTests.BlueprintAttribute.Provider}
:::::::

private def importedState : CoreM Informal.Environment.State := do
  pure <| Informal.Environment.informalExt.getState (← getEnv)

private def importedNode? (label : String) : CoreM (Option Informal.Data.Node) := do
  pure <| (← importedState).data.get? (Name.mkSimple label)

private def importedNodeInLocalData (label : String) : CoreM Bool := do
  pure <| (← importedState).localData.contains (Name.mkSimple label)

private def substringsInOrder (text : String) : List String → Bool
  | [] => true
  | needle :: rest =>
    match text.splitOn needle with
    | _before :: after =>
      if after.isEmpty then
        false
      else
        substringsInOrder (String.intercalate needle after) rest
    | _ => false

private def isBlueprintAttrRef (expectedDecl : Name) (expectedKind : Informal.Data.NodeKind)
    (node : Informal.Data.Node) : Bool :=
  match node.externalRefs with
  | #[ref] =>
    ref.origin == .blueprintAttr &&
      ref.present &&
      ref.written == expectedDecl &&
      ref.canonical == expectedDecl &&
      ref.kind == expectedKind
  | _ => false

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let some theoremNode ← importedNode? "attr.exported.theorem"
      | return false
    let some definitionNode ← importedNode? "attr.exported.definition"
      | return false
    let some inductiveNode ← importedNode? "attr.exported.inductive"
      | return false
    let some undocumentedNode ← importedNode? "attr.exported.undocumented"
      | return false
    pure (
      theoremNode.kind == .theorem &&
      theoremNode.hasAssociatedCode &&
      theoremNode.statement.isSome &&
      definitionNode.kind == .definition &&
      definitionNode.hasAssociatedCode &&
      definitionNode.statement.isSome &&
      inductiveNode.kind == .definition &&
      inductiveNode.hasAssociatedCode &&
      inductiveNode.statement.isSome &&
      undocumentedNode.kind == .definition &&
      undocumentedNode.hasAssociatedCode
    )

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    pure <|
      !(← importedNodeInLocalData "attr.exported.theorem") &&
      !(← importedNodeInLocalData "attr.exported.definition") &&
      !(← importedNodeInLocalData "attr.exported.inductive") &&
      !(← importedNodeInLocalData "attr.exported.undocumented")

/- Imported module catalogs retain direct attribute ownership and source order. -/
/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let providerLabels ← Informal.Environment.blueprintAttributeLabelsForModule
      `VersoBlueprintTests.BlueprintAttribute.Provider
    let reexportLabels ← Informal.Environment.blueprintAttributeLabelsForModule
      `VersoBlueprintTests.BlueprintAttribute.Reexport
    let hybridLabels ← Informal.Environment.blueprintAttributeLabelsForModule
      `VersoBlueprintTests.BlueprintAttribute.HybridProvider
    pure <|
      providerLabels == #[
        Name.mkSimple "attr.exported.theorem",
        Name.mkSimple "attr.exported.definition",
        Name.mkSimple "attr.exported.inductive",
        Name.mkSimple "attr.exported.undocumented"
      ] &&
      hybridLabels == #[
        Name.mkSimple "attr.hybrid.body",
        Name.mkSimple "attr.hybrid.verso_docstring",
        Name.mkSimple "attr.hybrid.shared"
      ] &&
      reexportLabels.isEmpty

/- Hybrid fixtures exercise persisted bodies, structural Verso docstrings, and many-to-one labels. -/
/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let some bodyNode ← importedNode? "attr.hybrid.body"
      | return false
    let some sharedNode ← importedNode? "attr.hybrid.shared"
      | return false
    let versoDoc? ← liftM <| findInternalDocString? (← getEnv)
      `Verso.VersoBlueprintTests.BlueprintAttribute.HybridProvider.hybridVersoDocstring
    let bodyWasPersisted :=
      match bodyNode.statement with
      | some statement => !statement.previewBlocks.isEmpty && statement.elabStx.isEmpty
      | none => false
    pure <|
      bodyWasPersisted &&
      (match versoDoc? with | some (.inr _) => true | _ => false) &&
      sharedNode.leanDecls == #[
        `Verso.VersoBlueprintTests.BlueprintAttribute.HybridProvider.hybridSharedFirst,
        `Verso.VersoBlueprintTests.BlueprintAttribute.HybridProvider.hybridSharedSecond
      ]

/- The no-level form creates a child part and derives its title from the module name. -/
/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    includedAttributeModuleDefaultDoc.toPart.subParts.any fun part =>
      part.titleString == "Provider" && part.content.size == 4

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let some theoremNode ← importedNode? "attr.exported.theorem"
      | return false
    let some definitionNode ← importedNode? "attr.exported.definition"
      | return false
    let some inductiveNode ← importedNode? "attr.exported.inductive"
      | return false
    pure <|
      isBlueprintAttrRef `Verso.VersoBlueprintTests.BlueprintAttribute.Provider.exportedTheorem .theorem theoremNode &&
      isBlueprintAttrRef `Verso.VersoBlueprintTests.BlueprintAttribute.Provider.exportedDefinition .definition definitionNode &&
      isBlueprintAttrRef `Verso.VersoBlueprintTests.BlueprintAttribute.Provider.exportedInductive .definition inductiveNode

/-- Imported statement payloads should keep empty deps and at least one preview source. -/
private def importedStatementExportOk (node : Informal.Data.Node) : Bool :=
  match node.statement with
  | some st => st.deps.isEmpty && (!st.previewBlocks.isEmpty || !st.elabStx.isEmpty)
  | none => false

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let some theoremNode ← importedNode? "attr.exported.theorem"
      | return false
    let some definitionNode ← importedNode? "attr.exported.definition"
      | return false
    let some inductiveNode ← importedNode? "attr.exported.inductive"
      | return false
    let some undocumentedNode ← importedNode? "attr.exported.undocumented"
      | return false
    pure <|
      importedStatementExportOk theoremNode &&
      importedStatementExportOk definitionNode &&
      importedStatementExportOk inductiveNode &&
      undocumentedNode.statement.isNone

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (html, state) ← renderManualDocHtmlStringAndState manualImpls placedAttributeDoc
    let theoremKey := Informal.PreviewCache.statementKey (Name.mkSimple "attr.exported.theorem")
    let undocumentedKey :=
      Informal.PreviewCache.statementKey (Name.mkSimple "attr.exported.undocumented")
    pure <|
      hasSubstr html "Introductory prose before the imported declaration." &&
      hasSubstr html "Connecting prose between declarations." &&
      hasSubstr html "Concluding prose after the imported declarations." &&
      hasSubstr html "Exported theorem used to verify" &&
      hasSubstr html "bp_attribute_node_anchor" &&
      hasSubstr html "exportedTheorem" &&
      hasSubstr html "exportedUndocumentedDefinition" &&
      !hasSubstr html "Blueprint node not found" &&
      !hasSubstr html "Blueprint node has no cached content" &&
      (Informal.PreviewManifest.findTraversalBlockEntry? state theoremKey).isSome &&
      (Informal.PreviewManifest.findTraversalBlockEntry? state undocumentedKey).isSome

/- A regular imported Lean module can become a source-ordered Verso part. -/
/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (html, state) ← renderManualDocHtmlStringAndState manualImpls includedAttributeModuleDoc
    let hasIncludedTitle :=
      includedAttributeModuleDoc.toPart.subParts.any
        (·.titleString == "Imported attribute declarations")
    let labels := #[
      "attr.exported.theorem",
      "attr.exported.definition",
      "attr.exported.inductive",
      "attr.exported.undocumented"
    ]
    let hasAnchor := hasSubstr html "bp_attribute_node_anchor"
    let ordered := substringsInOrder html [
        "exportedTheorem",
        "exportedDefinition",
        "exportedInductive",
        "exportedUndocumentedDefinition"
      ]
    let hasEntries := labels.all fun label =>
        let key := Informal.PreviewCache.statementKey (Name.mkSimple label)
        (Informal.PreviewManifest.findTraversalBlockEntry? state key).isSome
    pure <| hasIncludedTitle && hasAnchor && ordered && hasEntries

/- Generated module nodes honor non-default Blueprint numbering options. -/
/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (_html, state) ←
      renderManualDocHtmlStringAndState manualImpls globallyNumberedAttributeModuleDoc
    let theoremLabel := Name.mkSimple "attr.exported.theorem"
    let definitionLabel := Name.mkSimple "attr.exported.definition"
    let some theoremData := Informal.TraversalIndex.Nodes.data? state theoremLabel
      | return false
    let some definitionData := Informal.TraversalIndex.Nodes.data? state definitionLabel
      | return false
    pure <|
      theoremData.numberingMode == .global &&
      theoremData.globalCount == some 1 &&
      theoremData.count == 1 &&
      theoremData.displayNumber state == "1" &&
      definitionData.numberingMode == .global &&
      definitionData.globalCount == some 2 &&
      definitionData.count == 2 &&
      definitionData.displayNumber state == "2"

/- Repeated placements keep the first number and canonical traversal anchors. -/
/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (html, state) ←
      renderManualDocHtmlStringAndState manualImpls repeatedAttributePlacementDoc
    let label := Name.mkSimple "attr.exported.theorem"
    let previewKey := Informal.PreviewCache.statementKey label
    let some data := Informal.TraversalIndex.Nodes.data? state label
      | return false
    let some nodeObject := Informal.TraversalIndex.Nodes.object? state label
      | return false
    let some previewObject :=
        Informal.TraversalIndex.TraversalPreviews.object? state previewKey
      | return false
    pure <|
      data.numberingMode == .global &&
      data.globalCount == some 1 &&
      data.count == 1 &&
      Informal.nextGlobalBlockNumber state == 2 &&
      nodeObject.ids.toArray.size == 1 &&
      previewObject.ids.toArray.size == 1 &&
      (html.splitOn "class=\"bp_graft_node bp_graft_manifest_node\"").length == 3

/- Generated placements cannot reuse a later authored block's source-local count. -/
/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (_html, state) ←
      renderManualDocHtmlStringAndState manualImpls interleavedLocalAttributePlacementDoc
    let some beforeData :=
        Informal.TraversalIndex.Nodes.data? state (Name.mkSimple "attr.consumer.before.placement")
      | return false
    let some attributeData :=
        Informal.TraversalIndex.Nodes.data? state (Name.mkSimple "attr.exported.theorem")
      | return false
    let some afterData :=
        Informal.TraversalIndex.Nodes.data? state (Name.mkSimple "attr.consumer.after.placement")
      | return false
    pure <|
      beforeData.numberingMode == .local &&
      attributeData.numberingMode == .local &&
      afterData.numberingMode == .local &&
      beforeData.count + 1 == attributeData.count &&
      attributeData.count + 1 == afterData.count &&
      beforeData.globalCount == some 1 &&
      attributeData.globalCount == some 2 &&
      afterData.globalCount == some 3

/- Imported placements receive source-local numbers in consumer traversal order. -/
/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (_html, state) ←
      renderManualDocHtmlStringAndState manualImpls locallyNumberedHybridAttributeModuleDoc
    let some consumerData :=
        Informal.TraversalIndex.Nodes.data? state (Name.mkSimple "attr.consumer.before.module")
      | return false
    let some bodyData :=
        Informal.TraversalIndex.Nodes.data? state (Name.mkSimple "attr.hybrid.body")
      | return false
    let some versoDocstringData :=
        Informal.TraversalIndex.Nodes.data? state (Name.mkSimple "attr.hybrid.verso_docstring")
      | return false
    let some sharedData :=
        Informal.TraversalIndex.Nodes.data? state (Name.mkSimple "attr.hybrid.shared")
      | return false
    pure <|
      consumerData.numberingMode == .local &&
      bodyData.numberingMode == .local &&
      consumerData.count + 1 == bodyData.count &&
      bodyData.count + 1 == versoDocstringData.count &&
      versoDocstringData.count + 1 == sharedData.count &&
      consumerData.globalCount == some 1 &&
      bodyData.globalCount == some 2 &&
      versoDocstringData.globalCount == some 3 &&
      sharedData.globalCount == some 4

/- Persisted Manual bodies, Verso docstrings, and repeated labels share the module path. -/
/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (html, state) ← renderManualDocHtmlStringAndState manualImpls includedHybridAttributeModuleDoc
    let labels := #[
      "attr.hybrid.body",
      "attr.hybrid.verso_docstring",
      "attr.hybrid.shared"
    ]
    let hasEntries := labels.all fun label =>
      let key := Informal.PreviewCache.statementKey (Name.mkSimple label)
      (Informal.PreviewManifest.findTraversalBlockEntry? state key).isSome
    let some bodyData :=
        Informal.TraversalIndex.Nodes.data? state (Name.mkSimple "attr.hybrid.body")
      | return false
    pure <|
      hasSubstr html "<strong>structural emphasis</strong>" &&
      hasSubstr html "First persisted Manual list item." &&
      hasSubstr html "Second persisted Manual list item." &&
      hasSubstr html "<strong>structurally emphasized Verso docstring body</strong>" &&
      hasSubstr html "<code>Nat.succ</code>" &&
      hasSubstr html "First imported docstring list item." &&
      hasSubstr html "Second imported docstring list item." &&
      3 ≤ (html.splitOn "<ul>").length &&
      hasSubstr html "<code class=\"bp_math inline\">1 + 1 = 2</code>" &&
      hasSubstr html "<code class=\"bp_math inline\">2 + 2 = 4</code>" &&
      hasSubstr html "hybridSharedFirst" &&
      hasSubstr html "hybridSharedSecond" &&
      bodyData.statementUses.map (·.label) ==
        #[Name.mkSimple "attr.hybrid.verso_docstring"] &&
      bodyData.proofUses.map (·.label) == #[Name.mkSimple "attr.hybrid.shared"] &&
      hasEntries

/- Attribute-owned, code-only nodes remain available in the manifest/cache pair. -/
/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let files ← buildManualPreviewDataFiles manualImpls placedAttributeDoc
    let key := Informal.PreviewCache.statementKey (Name.mkSimple "attr.exported.undocumented")
    let some entry := files.manifest.previews.find? (·.key == key)
      | return false
    let some body := files.htmlCache.findHtml? key
      | return false
    pure <|
      body.contains "bp_code_only_preview_body" &&
      !entry.leanCodePreviewKeys.isEmpty &&
      entry.kind == some .definition &&
      (files.htmlCache.codeHtmlBodies entry |>.any (·.contains "exportedUndocumentedDefinition"))

end Verso.VersoBlueprintTests.BlueprintAttribute
