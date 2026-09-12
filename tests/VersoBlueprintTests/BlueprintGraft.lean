/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Verso.Output.Html
import VersoBlueprint
import Verso.Doc.Concrete
import VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintGraft

open Verso
open Verso.Genre.Manual
open Informal
open Verso.Output
open Verso.Output.Html
open Verso.VersoBlueprintTests.Blueprint.Support

def manualImpls : ExtensionImpls := extension_impls%

def graftManualLeftValue : Nat := 2

#docs (Genre.Manual) manualGraftDoc "Manual Blueprint Graft" :=
:::::::
:::definition "def:graft.manual.source"
Manual graft body.
:::

{blueprint_node "def:graft.manual.source" -header +compact}
:::::::

#docs (Genre.Manual) facetCodeProjectionDoc "Graft Facet Code Projection" :=
:::::::
:::theorem "thm:graft.facet.code"
Statement facet with attached Lean code.
:::

:::proof "thm:graft.facet.code"
Proof facet without its own Lean code.
:::

```lean "thm:graft.facet.code"
theorem graftFacetCodeWitness : True := by
  trivial
```

{blueprint_node "thm:graft.facet.code"}
:::::::

#docs (Genre.Manual) manualSideBySideGraftDoc "Manual Side-by-Side Blueprint Graft" :=
:::::::
:::definition "def:graft.manual.left" (tags := "graft, source") (effort := "small") (lean := "graftManualLeftValue")
Manual left graft body with inline math $`x + y = y + x` and an attached Lean preview.
:::

:::theorem "thm:graft.manual.sum" (uses := "def:graft.manual.left") (priority := "high")
The grafted theorem states $`(a + b) + c = a + (b + c)`.
:::

:::proof "thm:graft.manual.sum"
The proof graft records the same goal and keeps the proof facet selectable.
:::

:::definition "def:graft.manual.right" (uses := "thm:graft.manual.sum")
Manual right graft body references {uses "def:graft.manual.left"}[] and includes display math:
$$`\sum_{i=0}^{n} i = n`.
:::

:::blueprint_side_by_side +boxed
{blueprint_node "def:graft.manual.left" (displayLabel := "Featured definition")}

{blueprint_node "thm:graft.manual.sum" (displayLabel := "Theorem view") -header +compact}

{blueprint_node "thm:graft.manual.sum" (facet := "proof") (displayLabel := "Proof view") -header +compact}

{blueprint_node "def:graft.manual.right" (displayLabel := "Uses view") +compact}
:::
:::::::

/-- Captured in this fixture's environment before unrelated fixtures are imported. -/
def manualSideBySideGraftDocBlueprint : Informal.BlueprintDocument := .capture manualSideBySideGraftDoc.toPart

private def graftNode (label : String) : Informal.Graft.BlueprintNode :=
  ({ label := label } : Informal.Graft.BlueprintNodeConfig).toNode

private def graftManifestRenderConfig : Informal.Graft.ManifestRenderConfig :=
  {
    blockRenderConfig := {
      wrapperClass := "bp_test_graft_node_blueprint"
      codeBodyClass := "bp_test_graft_code_body"
    }
    nodeAttrs := fun node => node.renderedAttrsWithClass "bp_test_graft_node"
    renderMissingNode := fun node title detail =>
      .tag "div" (node.renderedAttrsWithClass "bp_test_graft_notice") <|
        Html.ofString s!"{title}: {detail}"
  }

private def facetRelated
    (label : String) (axis : Informal.PreviewManifest.RelationAxis) :
    Informal.PreviewManifest.RelatedEntry :=
  {
    label := Lean.Name.mkSimple label
    title := label
    axes := #[axis]
  }

private def facetProjectionEntry
    (facet : Informal.PreviewCache.Facet) : Informal.PreviewManifest.Entry :=
  {
    key := Informal.PreviewCache.key (Lean.Name.mkSimple "thm:graft.facet") facet
    targetKind := .block
    label := Lean.Name.mkSimple "thm:graft.facet"
    facet
    kind := some .theorem
    title := "Theorem 7"
    displayCaption := some "Theorem"
    displayLabel := some "7"
    parent := some (Lean.Name.mkSimple "grp:graft.facet")
    uses := #[
      facetRelated "def:graft.statement.dep" .statement,
      facetRelated "def:graft.proof.dep" .proof
    ]
    usedBy := #[facetRelated "def:graft.used.by" .statement]
  }

private def facetProjectionGroup : Informal.PreviewManifest.GroupRelation :=
  {
    label := Lean.Name.mkSimple "grp:graft.facet"
    title := "Graft facet group"
    declared := true
    entries := #[facetRelated "def:graft.group.member" .statement]
  }

/- Manifest-backed graft presentation projects dependency and auxiliary UI by facet. -/
#guard
  let content : Informal.PreviewManifest.BlockRender.RenderedContent := {
    body := Html.ofString "Facet body"
    codeBodies := #[Html.ofString "Facet code body"]
  }
  let render facet :=
    Informal.PreviewManifest.BlockRender.renderWithRenderedContent
      {}
      (facetProjectionEntry facet)
      content
      (some facetProjectionGroup)
      |>.asString
  let statement := render .statement
  let proof := render .proof
  hasSubstr statement "Statement uses 1" &&
    hasSubstr statement "def:graft.statement.dep" &&
    !hasSubstr statement "def:graft.proof.dep" &&
    hasSubstr statement "class=\"bp_extra_slot bp_extra_slot_group\"" &&
    hasSubstr statement "class=\"bp_extra_slot bp_extra_slot_used_by\"" &&
    hasSubstr statement "bp_code_panel_wrapper" &&
    hasSubstr proof "Proof uses 1" &&
    hasSubstr proof "def:graft.proof.dep" &&
    !hasSubstr proof "def:graft.statement.dep" &&
    !hasSubstr proof "class=\"bp_extra_slot bp_extra_slot_group\"" &&
    !hasSubstr proof "class=\"bp_extra_slot bp_extra_slot_used_by\"" &&
    !hasSubstr proof "bp_code_panel_wrapper"

/- Both facets retain shared code metadata; only the statement renders its panel. -/
/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let files ← buildManualPreviewDataFiles manualImpls facetCodeProjectionDoc
    let label := Lean.Name.mkSimple "thm:graft.facet.code"
    let statementKey := Informal.PreviewCache.statementKey label
    let proofKey := Informal.PreviewCache.proofKey label
    let some statementEntry := files.manifest.previews.find? (·.key == statementKey)
      | return false
    let some proofEntry := files.manifest.previews.find? (·.key == proofKey)
      | return false
    let ctx :=
      Informal.Graft.RenderContext.ofPreviewData? (some files.manifest) (some files.htmlCache)
    let statementNode :=
      (({ label := "thm:graft.facet.code" } :
        Informal.Graft.BlueprintNodeConfig).toNode)
    let proofNode :=
      (({ label := "thm:graft.facet.code", facet := some "proof" } :
        Informal.Graft.BlueprintNodeConfig).toNode)
    let statementHtml ←
      Informal.Graft.renderNodeFromManifestCache {} ctx statementNode
    let proofHtml ←
      Informal.Graft.renderNodeFromManifestCache {} ctx proofNode
    pure <|
      !statementEntry.leanCodePreviewKeys.isEmpty &&
      statementEntry.codeData.isSome &&
      proofEntry.leanCodePreviewKeys == statementEntry.leanCodePreviewKeys &&
      Lean.toJson proofEntry.codeData == Lean.toJson statementEntry.codeData &&
      hasSubstr statementHtml.asString "graftFacetCodeWitness" &&
      hasSubstr statementHtml.asString "bp_code_panel_wrapper" &&
      !hasSubstr proofHtml.asString "graftFacetCodeWitness" &&
      !hasSubstr proofHtml.asString "bp_code_panel_wrapper"

private def renderAuditNode
    (manifest : Informal.PreviewManifest.File)
    (htmlCache : Informal.PreviewManifest.HtmlCache.File)
    (label : String) : IO Html := do
  let node :=
    ({ label, compact := true, showHeader := false } :
      Informal.Graft.BlueprintNodeConfig).toNode
  let ctx := Informal.Graft.RenderContext.ofPreviewData? (some manifest) (some htmlCache)
  Informal.Graft.renderNodeFromManifestCache
    {
      blockRenderConfig := {
        wrapperClass := "audit_blueprint_node"
        codeBodyClass := "audit_blueprint_code"
      }
      nodeAttrs := fun node =>
        node.renderedAttrsWithClass "audit_graft_node"
    }
    ctx
    node

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (html, _st) ← renderManualDocHtmlStringAndState manualImpls manualGraftDoc
    pure <|
      hasSubstr html "bp_graft_node" &&
        countSubstr html "Manual graft body." == 2 &&
        countSubstr html "class=\"bp_heading " == 1 &&
        !hasSubstr html "Blueprint node not found"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (html, _st) ← renderManualDocHtmlStringAndState manualImpls manualSideBySideGraftDoc
    pure <|
      hasSubstr html "bp_graft_side_by_side" &&
        hasSubstr html "bp_graft_side_by_side_boxed" &&
        hasSubstr html "bp_graft_manifest_node" &&
        countSubstr html "data-bp-blueprint-node=\"true\"" == 4 &&
        countSubstr html "Manual left graft body with inline math" == 2 &&
        countSubstr html "The grafted theorem states" == 2 &&
        countSubstr html "The proof graft records" == 2 &&
        countSubstr html "Manual right graft body references" == 2 &&
        hasSubstr html "Featured definition" &&
        hasSubstr html "Uses view" &&
        hasSubstr html "graftManualLeftValue" &&
        hasSubstr html "bp_math inline" &&
        hasSubstr html "bp_math display" &&
        hasSubstr html "data-bp-facet=\"proof\"" &&
        hasSubstr html "bp_code_panel_wrapper" &&
        !hasSubstr html "Blueprint node not found"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let files ← buildManualPreviewDataFiles manualImpls manualSideBySideGraftDoc
    let ctx := Informal.Graft.RenderContext.ofPreviewData? (some files.manifest) (some files.htmlCache)
    let node := { graftNode "def:graft.manual.left" with displayLabel? := some "API view" }
    let renderedHtml ← Informal.Graft.renderNodeFromManifestCache
      graftManifestRenderConfig
      ctx
      node
    let rendered := renderedHtml.asString
    pure <|
      hasSubstr rendered "data-bp-rendered=\"static\"" &&
        hasSubstr rendered "bp_graft_manifest_node" &&
        hasSubstr rendered "bp_test_graft_node" &&
        hasSubstr rendered "bp_test_graft_node_blueprint" &&
        hasSubstr rendered "bp_test_graft_code_body" &&
        hasSubstr rendered "API view" &&
        hasSubstr rendered "Manual left graft body with inline math" &&
        hasSubstr rendered "graftManualLeftValue" &&
        hasSubstr rendered "bp_code_panel_wrapper" &&
        !hasSubstr rendered "Blueprint node not found"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let files ← buildManualPreviewDataFiles manualImpls manualSideBySideGraftDoc
    let renderedHtml ← renderAuditNode files.manifest files.htmlCache "def:graft.manual.left"
    let rendered := renderedHtml.asString
    pure <|
      hasSubstr rendered "audit_graft_node" &&
        hasSubstr rendered "audit_blueprint_node" &&
        hasSubstr rendered "data-bp-rendered=\"static\"" &&
        hasSubstr rendered "Manual left graft body with inline math" &&
        !hasSubstr rendered "bp_heading" &&
        !hasSubstr rendered "bp_code_panel_wrapper" &&
        !hasSubstr rendered "Blueprint node not found"

#guard
  let attrs := (graftNode "def:graft.manual.left").renderedAttrsWithClass "audit_graft_node"
  attrs.contains ("class", "bp_graft_manifest_node audit_graft_node") &&
    attrs.contains ("data-bp-rendered", "static") &&
    (attrs.filter (fun attr => attr.1 == "class")).size == 1

#guard
  let attrs := Informal.Graft.setClassAttr
    (graftNode "def:graft.manual.left").renderedAttrs
    "bp_graft_node"
  attrs.contains ("class", "bp_graft_node") &&
    attrs.contains ("data-bp-rendered", "static") &&
    (attrs.filter (fun attr => attr.1 == "class")).size == 1

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let node := graftNode "def:graft.manual.left"
    let ctx := Informal.Graft.RenderContext.ofPreviewData? none none
    let renderedHtml ← Informal.Graft.renderNodeFromManifestCache
      graftManifestRenderConfig
      ctx
      node
    let rendered := renderedHtml.asString
    pure <|
      hasSubstr rendered "Preview manifest unavailable" &&
        hasSubstr rendered "Provide a Blueprint preview manifest" &&
        hasSubstr rendered "bp_test_graft_notice" &&
        hasSubstr rendered "data-bp-rendered=\"static\""

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let files ← buildManualPreviewDataFiles manualImpls manualSideBySideGraftDoc
    let node := graftNode "def:graft.manual.missing"
    let ctx := Informal.Graft.RenderContext.ofPreviewData? (some files.manifest) (some files.htmlCache)
    let renderedHtml ← Informal.Graft.renderNodeFromManifestCache
      graftManifestRenderConfig
      ctx
      node
    let rendered := renderedHtml.asString
    pure <|
      hasSubstr rendered "Blueprint node not found" &&
        hasSubstr rendered "label `def:graft.manual.missing`" &&
        hasSubstr rendered "facet `statement`" &&
        hasSubstr rendered node.key &&
        hasSubstr rendered "bp_test_graft_notice"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let logs ← IO.mkRef #[]
    let logError (msg : String) : IO Unit := logs.modify (·.push msg)
    let files ← buildManualPreviewDataFiles manualImpls manualSideBySideGraftDoc
    let node := graftNode "def:graft.manual.left"
    let ctx := Informal.Graft.RenderContext.ofPreviewData? (some files.manifest) (some {}) logError
    let renderedHtml ← Informal.Graft.renderNodeFromManifestCache
      graftManifestRenderConfig
      ctx
      node
    let rendered := renderedHtml.asString
    let logs ← logs.get
    pure <|
      hasSubstr rendered "Blueprint HTML cache entry not found" &&
        hasSubstr rendered node.key &&
        logs.any (fun msg => hasSubstr msg "Blueprint HTML cache: missing rendered body") &&
        logs.any (fun msg => hasSubstr msg node.key)

-- A required selected facet cannot degrade into a plausible metadata shell when
-- either its cached content or captured semantics are malformed.
#eval show IO Unit from do
  let (blocks, state) ← traverseManualDocBlocksAndState manualImpls manualSideBySideGraftDoc
  let label := LabelNameParsing.parse "def:graft.manual.left"
  let key := PreviewCache.statementKey label
  let .ok (some selected) := RenderingResolution.facetByKey? state key
    | throw <| IO.userError "Missing graft test facet"
  let .ok none := RenderingResolution.facetByKey? state "omitted--proof"
    | throw <| IO.userError "An absent facet borrowed another facet"
  let corruptPreview := TraversalIndex.TraversalPreviews.saveData state key (Lean.Json.str "broken")
  let wrongPreview := { selected.preview with facet := .proof }
  let wrongIdentity := TraversalIndex.TraversalPreviews.saveData state key (Lean.toJson wrongPreview)
  let corruptNode := state.saveDomainObjectData TraversalIndex.Nodes.domainName label.toString
    (Lean.Json.str "broken")
  for (invalid, expected) in #[(corruptPreview, "Malformed Blueprint preview"),
      (wrongIdentity, "Mismatched Blueprint preview identity"),
      (corruptNode, "Malformed rendering node")] do
    let .error error := RenderingResolution.facetByKey? invalid key
      | throw <| IO.userError "Invalid selected facet was accepted"
    unless hasSubstr error expected do
      throw <| IO.userError s!"Selected-facet diagnostic lost its cause: {error}"
    let errors ← IO.mkRef (#[] : Array String)
    let logError := fun message => errors.modify (·.push message)
    let html ← renderManualBlocksHtmlWithState blocks manualImpls invalid (logError := logError)
    unless hasSubstr html.asString "Invalid Blueprint node" &&
        (← errors.get).any (hasSubstr · expected) do
      throw <| IO.userError "Live graft concealed a required facet lookup failure"
    errors.set #[]
    let files ← PreviewManifest.buildPreviewDataFiles manualImpls logError
      (PreviewManifest.PreparedPreviewState.prepare invalid)
    unless (files.manifest.findEntry? key).isNone && !(← errors.get).isEmpty do
      throw <| IO.userError "Export fabricated metadata for an invalid selected facet"
  let missingModel := TraversalIndex.TraversalPreviews.saveData (.initialize {}) key
    (Lean.toJson selected.preview)
  let .error error := RenderingResolution.facetByKey? missingModel key
    | throw <| IO.userError "A selected facet accepted a missing model"
  unless hasSubstr error "initialize traversal" do
    throw <| IO.userError "Missing model was confused with missing content"
  let some codeKey := (RenderingResolution.codePreviewKeys state selected)[0]?
    | throw <| IO.userError "Missing associated code preview"
  let corruptCode := TraversalIndex.LeanCodePreviews.saveData state codeKey (Lean.Json.str "broken")
  let .error malformed := RenderingResolution.codePanelByKey corruptCode codeKey
    | throw <| IO.userError "Malformed code preview was accepted"
  let .error absent := RenderingResolution.codePanelByKey state "absent-code-preview"
    | throw <| IO.userError "Missing required code preview was accepted"
  unless hasSubstr malformed "Malformed Blueprint Lean-code preview" &&
      hasSubstr absent "Missing Blueprint Lean-code preview" do
    throw <| IO.userError "Code-preview diagnostics lost the missing/malformed distinction"

-- Included inline content requires the matching metadata, even when its preview
-- payload is otherwise valid. Exercise both live rendering and export.
#eval show IO Unit from do
  let (blocks, state) ← traverseManualDocBlocksAndState manualImpls facetCodeProjectionDoc
  let label := Lean.Name.mkSimple "thm:graft.facet.code"
  let some block := (TraversalIndex.InlineCode.blocks state label)[0]?
    | throw <| IO.userError "Missing inline code fixture"
  let key := TraversalIndex.LeanCodePreviews.lookupInlineKey block.blockId
  let .ok valid := RenderingResolution.codePanelByKey state key
    | throw <| IO.userError "Valid inline panel was rejected"
  unless valid.facts.literateDeclarations.declarations.any (·.name == ``graftFacetCodeWitness) do
    throw <| IO.userError "Resolved panel lost its declaration facts"
  let .ok domains := (Lean.toJson state.domains).getObj?
    | throw <| IO.userError "Could not serialize fixture domains"
  let .ok missing := Lean.fromJson? (α := TraverseState)
    ((Lean.toJson state).setObjVal! "domains"
      (.obj (domains.erase TraversalIndex.InlineCode.domainName.toString)))
    | throw <| IO.userError "Could not restore state with missing inline metadata"
  let corrupt := state.saveDomainObjectData TraversalIndex.InlineCode.domainName block.blockId.toString
    (Lean.Json.str "broken")
  let wrongBlock := state.saveDomainObjectData TraversalIndex.InlineCode.domainName block.blockId.toString
    (Lean.toJson { block with blockId := `wrongBlock })
  let wrongOwner := state.saveDomainObjectData TraversalIndex.InlineCode.domainName block.blockId.toString
    (Lean.toJson { block with label := `wrongOwner })
  let wrongPreview := TraversalIndex.LeanCodePreviews.saveData state key
    (Lean.toJson { valid.preview with target := `wrongTarget })
  for (invalid, expected) in #[(missing, "Missing Blueprint inline-code metadata"),
      (corrupt, "Malformed Blueprint inline-code metadata"),
      (wrongBlock, "Mismatched Blueprint inline-code identity"),
      (wrongOwner, "Mismatched Blueprint inline-code owner"),
      (wrongPreview, "Mismatched Blueprint Lean-code preview identity")] do
    let .error error := RenderingResolution.codePanelByKey invalid key
      | throw <| IO.userError "Invalid code panel was accepted"
    unless hasSubstr error expected do
      throw <| IO.userError s!"Code-panel diagnostic lost its cause: {error}"
    let errors ← IO.mkRef (#[] : Array String)
    let logError := fun message => errors.modify (·.push message)
    let _ ← renderManualBlocksHtmlWithState blocks manualImpls invalid (logError := logError)
    unless (← errors.get).any (hasSubstr · expected) do
      throw <| IO.userError "Live graft concealed invalid code-panel metadata"
    errors.set #[]
    let files ← PreviewManifest.buildPreviewDataFiles manualImpls logError
      (PreviewManifest.PreparedPreviewState.prepare invalid)
    unless (files.manifest.findEntry? key).isNone &&
        (files.htmlCache.entries.all (·.key != key)) &&
        (← errors.get).any (hasSubstr · expected) do
      throw <| IO.userError "Export emitted an invalid code panel"
  let (_, externalState) ← traverseManualDocBlocksAndState manualImpls manualSideBySideGraftDoc
  let externalKey := TraversalIndex.LeanCodePreviews.lookupKey ``graftManualLeftValue
  let .ok external := RenderingResolution.codePanelByKey externalState externalKey
    | throw <| IO.userError "Valid external panel was rejected"
  let .error _ := RenderingResolution.codePanel externalState "wrong-key" external.preview
    | throw <| IO.userError "External preview accepted the wrong storage key"
  let .error _ := RenderingResolution.codePanel externalState externalKey
    { external.preview with target := `wrongTarget }
    | throw <| IO.userError "External preview accepted inconsistent declaration identity"

end Verso.VersoBlueprintTests.BlueprintGraft
