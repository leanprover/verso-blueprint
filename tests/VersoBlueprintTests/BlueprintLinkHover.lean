/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.Blueprint.Support
import VersoBlueprint.Lib.HtmlId
import VersoManual.Bibliography

namespace Verso.VersoBlueprintTests.BlueprintLinkHover

open Lean
open Verso
open Verso.Genre.Manual
open Informal
open Verso.VersoBlueprintTests.Blueprint.Support

set_option doc.verso true

private def manualImpls : ExtensionImpls := extension_impls%

@[bib "hover.cite"]
def hover.cite : Verso.Genre.Manual.Bibliography.Citable := .arXiv
  { title := inlines!"Hover target citation"
  , authors := #[inlines!"A. Author", inlines!"B. Author"]
  , year := 2026
  , id := "hover.cite"
  }

private def hoverCiteItem : Informal.Cite.CiteItem :=
  { label := "hover.cite", citation := hover.cite }

private def hoverCitePreviewKey : String :=
  Informal.Cite.citationPreviewKey hoverCiteItem
    Informal.Cite.CitationStyle.textual
    (some Informal.Cite.CitePartKind.lemma)
    (some "3")

/-- info: true -/
#guard_msgs in
#eval
  Informal.Cite.citationAnchorId "hover.cite" == "hover-cite" &&
  Informal.Cite.citationAnchorId "Hover.Cite" == "hover-cite" &&
  Informal.HtmlId.key "hover.cite" == "hover-002Ecite"

/-- info: true -/
#guard_msgs in
#eval
  Informal.Cite.CitePartKind.parse? "prop" == some .proposition &&
  Informal.Cite.CitePartKind.proposition.text == "Proposition"

#docs (Genre.Manual) hoverLinkDoc "Hover Link Doc" :=
:::::::
:::lemma_ "lem:hover.link"
Using {uses "lem:hover.link"}[], see {Informal.citet hover.cite (kind := lemma) (index := 3)}[].
:::

{blueprint_bibliography}
:::::::

/-- Captured in this fixture's environment before unrelated fixtures are imported. -/
def hoverLinkDocBlueprint : Informal.BlueprintDocument := .capture hoverLinkDoc.toPart

#docs (Genre.Manual) hoverUsesDedupDoc "Hover Uses Dedup Doc" :=
:::::::
:::lemma_ "lem:hover.base"
Base lemma for repeated references.
:::

:::lemma_ "lem:hover.dedup"
Using {uses "lem:hover.base"}[] and again {uses "lem:hover.base"}[].
:::
:::::::

/-- Captured in this fixture's environment before unrelated fixtures are imported. -/
def hoverUsesDedupDocBlueprint : Informal.BlueprintDocument := .capture hoverUsesDedupDoc.toPart

#docs (Genre.Manual) hoverBprefDoc "Hover Bpref Doc" :=
:::::::
:::lemma_ "lem:hover.bpref.target"
Target lemma for reference-only links.
:::

:::lemma_ "lem:hover.bpref.ref"
Mention {bpref "lem:hover.bpref.target"}[] without declaring a dependency.
:::
:::::::

#docs (Genre.Manual) hoverUseIntentDoc "Hover Use Intent Doc" :=
:::::::
:::lemma_ "lem:hover.intent.hidden"
Hidden metadata dependency target.
:::

:::lemma_ "lem:hover.intent.inline"
Inline dependency target.
:::

:::lemma_ "lem:hover.intent.node" (uses := "lem:hover.intent.hidden") (uses_origin := "automatic") (uses_intent := "technical")
Mention {uses "lem:hover.intent.inline" (intent := "auxiliary")}[] while the
technical edge is declared in block metadata.
:::
:::::::

#docs (Genre.Manual) hoverCiteOnlyDoc "Hover Cite Only Doc" :=
:::::::
Cite once {Informal.citet hover.cite (kind := lemma) (index := 3)}[] and cite twice
{Informal.citet hover.cite (kind := lemma) (index := 3)}[].

{blueprint_bibliography}
:::::::

/-- Captured in this fixture's environment before unrelated fixtures are imported. -/
def hoverCiteOnlyDocBlueprint : Informal.BlueprintDocument := .capture hoverCiteOnlyDoc.toPart

-- Exercise the role expanders with both automatic titles and authored link text.
@[blueprint "hover:unrendered"] theorem hoverUnrendered : True := trivial
@[blueprint "hover:source-only"] theorem hoverSourceOnly : True := trivial

#docs (Genre.Manual) hoverAvailabilityDoc "Reference availability" :=
:::::::
:::theorem "hover:placeholder"
:::

:::theorem "hover:proof"
:::

:::proof "hover:proof"
The proof supplies the only preview body.
:::

:::theorem "hover:markup"
:::

```md "hover:markup" (slot := statement)
The external markup supplies the preview body.
```

```md "hover:source-only" (slot := statement)
Source markup without an informal document occurrence.
```

```rust "hover:unrendered"
pub fn unrendered_attachment() {}
```

:::lemma_ "hover:references"
{bpref "hover:unrendered"}[] {bpref "hover:unrendered"}[custom prose]
{uses "hover:unrendered"}[] {uses "hover:unrendered"}[custom dependency]

{bpref "hover:placeholder"}[] {bpref "hover:placeholder"}[custom prose]
{uses "hover:placeholder"}[] {uses "hover:placeholder"}[custom dependency]

{bpref "hover:proof"}[] {bpref "hover:proof"}[custom prose]
{uses "hover:proof"}[] {uses "hover:proof"}[custom dependency]

{bpref "hover:markup"}[] {bpref "hover:markup"}[custom prose]
{uses "hover:markup"}[] {uses "hover:markup"}[custom dependency]

{bpref "hover:source-only"}[] {bpref "hover:source-only"}[custom prose]
{uses "hover:source-only"}[] {uses "hover:source-only"}[custom dependency]
:::

:::::::

#eval show IO Unit from do
  let errors ← IO.mkRef (#[] : Array String)
  let (blocks, state) ← traverseManualDocBlocksAndState manualImpls hoverAvailabilityDoc
    (fun error => errors.modify (·.push error))
  let fullHtml ← renderManualBlocksHtmlWithState blocks manualImpls state
  unless !hasSubstr fullHtml.asString "Theorem 0" &&
      hasSubstr fullHtml.asString "Rust code for hover:unrendered" do
    throw <| IO.userError "Related or Rust panels invented a document number"
  let some (.concat #[.other _ references]) := blocks.back?
    | throw <| IO.userError "Missing authored reference paragraphs"
  let cases := #[
    ("hover:unrendered", none, false),
    ("hover:placeholder", none, true),
    ("hover:proof", some (PreviewCache.proofKey (Name.mkSimple "hover:proof")), true),
    ("hover:markup", some (PreviewSource.externalMarkupKey (Name.mkSimple "hover:markup")), true),
    ("hover:source-only", some (PreviewSource.externalMarkupKey (Name.mkSimple "hover:source-only")), false)
  ]
  unless references.size == cases.size do
    throw <| IO.userError "Reference fixture paragraphs changed"
  let files ← PreviewManifest.buildPreviewDataFiles manualImpls
    (fun error => errors.modify (·.push error)) (PreviewManifest.PreparedPreviewState.prepare state)
  for (reference, (label, key, linked)) in references.zip cases do
    let html ← renderManualBlocksHtmlWithState #[reference] manualImpls state
    let html := html.asString
    let tex ← renderManualBlocksTeXWithState manualImpls #[reference] state
    unless hasSubstr html "custom prose" && hasSubstr tex "custom prose" &&
        hasSubstr html "custom dependency" && hasSubstr tex "custom dependency" &&
        !hasSubstr html "Theorem 0" && !hasSubstr tex "Theorem 0" &&
        countSubstr html "<a " == (if linked then 4 else 0) do
      throw <| IO.userError s!"Reference text, numbering or links disagreed for {label}"
    match key with
    | some key =>
        unless countSubstr html s!"data-bp-preview-key=\"{key}\"" == 4 &&
            (files.manifest.findEntry? key).isSome && (files.htmlCache.findHtml? key).isSome do
          throw <| IO.userError s!"Reference requested an unavailable preview for {label}"
    | none =>
        unless !hasSubstr html "bp_inline_preview_ref" do
          throw <| IO.userError s!"Reference offered a bodyless hover for {label}"
    if !linked then
      unless countSubstr html s!">{label}</span>" == 2 && countSubstr tex label == 2 do
        throw <| IO.userError "An unrendered reference lost its authored label"
  unless (← errors.get).isEmpty do
    throw <| IO.userError s!"Reference rendering errors: {← errors.get}"

/--
error: Unexpected argument (origin := "automatic")
-/
#guard_msgs in
#docs (Genre.Manual) hoverDirectiveRejectsRoleOriginDoc "Directive Rejects Role Origin" :=
:::::::
:::lemma_ "lem:hover.reject.directive.origin" (origin := "automatic")
This directive option belongs to inline uses only.
:::
:::::::

/--
error: Unexpected argument (intent := "technical")
-/
#guard_msgs in
#docs (Genre.Manual) hoverBprefRejectsIntentDoc "Bpref Rejects Intent" :=
:::::::
:::lemma_ "lem:hover.reject.bpref.target"
Target.
:::

:::lemma_ "lem:hover.reject.bpref.ref"
Mention {bpref "lem:hover.reject.bpref.target" (intent := "technical")}[].
:::
:::::::

/--
error: uses reference to «lem:hover.reject.inline.intent.target» has invalid '(intent := "aux")'; expected one of "regular", "auxiliary", "technical"
-/
#guard_msgs in
#docs (Genre.Manual) hoverUsesRejectsIntentAliasDoc "Uses Rejects Intent Alias" :=
:::::::
Mention {uses "lem:hover.reject.inline.intent.target" (intent := "aux")}[].
:::::::

/-- info: true -/
#guard_msgs in
#eval
  let valid := Informal.UseConfig.parseMetadata (some "automatic") (some "technical")
  let invalid := Informal.UseConfig.parseMetadata (some "auto") (some "tech")
  valid.origin == .automatic &&
  valid.invalidOrigin.isNone &&
  valid.intent == .technical &&
  valid.invalidIntent.isNone &&
  invalid.origin == .manual &&
  invalid.invalidOrigin == some "auto" &&
  invalid.intent == .regular &&
  invalid.invalidIntent == some "tech" &&
  Informal.Data.UseIntent.parse? "aux" == none &&
  Informal.Data.UseIntent.parse? "technical" == some .technical

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls hoverLinkDoc
    pure (
      countSubstr out "class=\"bp_inline_preview_ref\"" >= 3 &&
      !hasSubstr out "class=\"bp_inline_preview_tpl\"" &&
      hasSubstr out "Bibliography: hover.cite" &&
      hasSubstr out "#bp-bib-hover-cite" &&
      hasSubstr out "class=\"bp_bibliography_use_line\"" &&
      hasSubstr out "data-bp-preview-key=\"«lem:hover.link»--statement\"" &&
      !hasSubstr out "data-bp-preview-fallback-label" &&
      hasSubstr out s!"data-bp-preview-key=\"{hoverCitePreviewKey}\""
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls hoverUsesDedupDoc
    pure (
      countSubstr out "class=\"bp_inline_preview_ref\"" >= 2 &&
      countSubstr out
          "data-bp-preview-key=\"«lem:hover.base»--statement\"" >= 2 &&
      !hasSubstr out "data-bp-preview-fallback-label" &&
      !hasSubstr out "class=\"bp_inline_preview_tpl\""
    )

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let state := Informal.Environment.informalExt.getState (← getEnv)
    let hiddenLabel := Name.mkSimple "lem:hover.intent.hidden"
    let inlineLabel := Name.mkSimple "lem:hover.intent.inline"
    match state.data.get? (Name.mkSimple "lem:hover.intent.node") with
    | some node =>
      match node.statement with
      | some statement =>
        let uses := statement.deps
        let hidden? := uses.find? (·.label == hiddenLabel)
        let inline? := uses.find? (·.label == inlineLabel)
        pure <|
          uses.any (·.label == hiddenLabel) &&
          uses.any (·.label == inlineLabel) &&
          match hidden?, inline? with
          | some hidden, some inline =>
            hidden.origin == .automatic &&
            hidden.intent == Informal.Data.UseIntent.technical &&
            inline.origin == .manual &&
            inline.intent == Informal.Data.UseIntent.auxiliary
          | _, _ => false
      | none => pure false
    | none => pure false

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (_out, st) ← renderManualDocHtmlStringAndState manualImpls hoverUseIntentDoc
    let hiddenLabel := Name.mkSimple "lem:hover.intent.hidden"
    let inlineLabel := Name.mkSimple "lem:hover.intent.inline"
    match Informal.TraversalIndex.Nodes.capturedData? st (Name.mkSimple "lem:hover.intent.node") with
    | some block =>
      let hidden? := block.statementUses.find? (·.label == hiddenLabel)
      let inline? := block.statementUses.find? (·.label == inlineLabel)
      pure <|
        block.statementDeps.contains hiddenLabel &&
        block.statementDeps.contains inlineLabel &&
        match hidden?, inline? with
        | some hidden, some inline =>
          hidden.origin == .automatic &&
          hidden.intent == Informal.Data.UseIntent.technical &&
          inline.origin == .manual &&
          inline.intent == Informal.Data.UseIntent.auxiliary
        | _, _ => false
    | none => pure false

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let state := Informal.Environment.informalExt.getState (← getEnv)
    match state.data.get? (Name.mkSimple "lem:hover.bpref.ref") with
    | some node =>
      pure <| node.statement.map (·.deps.isEmpty) |>.getD false
    | none => pure false

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls hoverBprefDoc
    pure (
      countSubstr out "class=\"bp_inline_preview_ref\"" >= 1 &&
      countSubstr out
          "data-bp-preview-key=\"«lem:hover.bpref.target»--statement\"" >= 1 &&
      !hasSubstr out "data-bp-preview-fallback-label" &&
      !hasSubstr out "class=\"bp_inline_preview_tpl\""
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls hoverCiteOnlyDoc
    pure (
      countSubstr out "class=\"bp_inline_preview_ref\"" == 2 &&
      !hasSubstr out "class=\"bp_inline_preview_tpl\"" &&
      countSubstr out s!"data-bp-preview-key=\"{hoverCitePreviewKey}\"" == 2 &&
      !hasExtraJs st "bindInlinePreview" &&
      hasExtraCss st ".bp_inline_preview_panel"
    )

-- References are validated against the completed capture, independently of blocks or graphs.
run_cmd discard <| Environment.contribute `reference_known_omitted {}

#docs (Genre.Manual) referenceOnlyDoc "References before their target" :=
:::::::
{bpref "reference_forward"}[] and {bpref "reference_known_omitted"}[].
:::::::

#docs (Genre.Manual) forwardTargetDoc "Later target" :=
:::::::
:::theorem "reference_forward"
The target is elaborated after the reference.
:::
:::::::

#docs (Genre.Manual) misspelledReferenceDoc "Misspelled reference" :=
:::::::
{bpref "reference_forwad"}[].
:::::::

#eval show IO Unit from do
  let model : RenderModel := blueprint_render_model%
  let errors ← IO.mkRef (#[] : Array String)
  let logError := fun message => errors.modify (·.push message)
  let part := { referenceOnlyDoc.toPart with
    content := referenceOnlyDoc.toPart.content ++ forwardTargetDoc.toPart.content }
  let forward : Doc.VersoDoc Genre.Manual := .mk (fun _ => part) "{}"
  let (blocks, state) ← traverseManualDocBlocksAndState manualImpls forward logError (model := model)
  let html ← renderManualBlocksHtmlWithState blocks manualImpls state
  unless (← errors.get).isEmpty && hasSubstr html.asString "Theorem 1" &&
      hasSubstr html.asString "reference_known_omitted" &&
      (TraversalIndex.Nodes.href? state `reference_known_omitted).isNone do
    throw <| IO.userError "Forward references or known omitted nodes were rejected"
  let .ok omitted := RenderingResolution.canonical state `reference_known_omitted
    | throw <| IO.userError "Captured but omitted nodes must remain resolvable"
  let omittedReference := RenderingResolution.referenceOfData state omitted
  unless omittedReference.title == "reference_known_omitted" &&
      omittedReference.href.isNone && omittedReference.previewKey.isNone do
    throw <| IO.userError "An omitted node acquired a synthetic number, target, or preview"
  -- Qualified labels containing punctuation should have the same readable
  -- fallback in page references and exported previews, without Lean name quoting.
  let qualified := Name.str (Name.mkSimple "odd namespace") "odd label"
  let qualifiedState := TraversalIndex.Nodes.saveNode state { label := qualified }
  let .ok reference := RenderingResolution.reference qualifiedState qualified
    | throw <| IO.userError "Could not resolve reference"
  let entry := PreviewManifest.blockEntryOfTraversalPreview qualifiedState
    (PreviewCache.Entry.ofBlocks qualified .statement #[])
  unless reference.title == "odd namespace.odd label" && entry.title == reference.title do
    throw <| IO.userError "Reference and manifest fallbacks disagree on qualified labels"
  let markup : Data.ExternalMarkupData := {
    label := qualified
    markup := ({} : Data.ExternalMarkupSet).insert {
      language := .markdown, slot := "default", raw := "A source-backed statement." }
  }
  let markupState := TraversalIndex.ExternalMarkup.saveData qualifiedState qualified (toJson markup)
  let .ok statement := RenderingResolution.reference markupState qualified (some .statement)
    | throw <| IO.userError "Could not resolve source-backed statement"
  let .ok proof := RenderingResolution.reference markupState qualified (some .proof)
    | throw <| IO.userError "Could not resolve source-backed node's missing proof"
  let optional := RenderingResolution.referenceOrLabel markupState qualified
  unless statement.previewKey == PreviewKey.ofString? (PreviewSource.externalMarkupKey qualified) &&
      optional.previewKey == statement.previewKey && proof.previewKey.isNone && proof.href.isNone do
    throw <| IO.userError "External markup was lost from a relation or borrowed as a proof preview"
  let _ ← traverseManualDocBlocksAndState manualImpls referenceOnlyDoc logError (model := model)
  unless (← errors.get).isEmpty do
    throw <| IO.userError "A reference-only document rejected captured but unrendered labels"
  let _ ← traverseManualDocBlocksAndState manualImpls misspelledReferenceDoc logError (model := model)
  unless (← errors.get).any (hasSubstr · "Unknown Blueprint label 'reference_forwad'") do
    throw <| IO.userError "A misspelled reference survived without a diagnostic"
  errors.set #[]
  let _ ← Informal.traverseManualBlocks referenceOnlyDoc.toPart.content manualImpls logError
  unless (← errors.get).any (hasSubstr · "initialize traversal with the document's RenderModel") do
    throw <| IO.userError "A reference-only document failed to diagnose its missing model"
  let corrupt := state.saveDomainObjectData TraversalIndex.Nodes.domainName "reference_forward" (.str "corrupt")
  match TraversalIndex.Nodes.required corrupt `reference_forward with
  | .ok _ => throw <| IO.userError "Accepted a malformed rendering node"
  | .error message =>
    unless hasSubstr message "Malformed rendering node 'reference_forward':" do
      throw <| IO.userError "A malformed node was confused with a missing node"

  for (state, expected) in #[(state, "Unknown Blueprint label"),
      (Verso.Genre.Manual.TraverseState.initialize {}, "initialize traversal"),
      (corrupt, "Malformed rendering node")] do
    let label := if expected == "Unknown Blueprint label" then `reference_forwad else `reference_forward
    for result in #[(RenderingResolution.canonical state label).map (fun _ => ()),
        (RenderingResolution.occurrence state { label, count := 0 }).map (fun _ => ()),
        (RenderingResolution.reference state label).map (fun _ => ())] do
      match result with
      | .ok _ => throw <| IO.userError "Resolution accepted an invalid registry entry"
      | .error message =>
        unless hasSubstr message expected do
          throw <| IO.userError "Resolution erased the registry lookup diagnostic"
    -- Even a saved state passed directly to a renderer must not silently turn
    -- an invalid authored reference into plain text, with or without link text.
    for contents in #[#[], #[Doc.Inline.text "invalid authored reference"]] do
      let references : Array (Doc.Block Genre.Manual) := #[.para #[
        .other (Inline.informal { label }) contents]]
      let (references, _) ← Informal.traverseManualBlocks references manualImpls (fun _ => pure ())
      errors.set #[]
      let html ← renderManualBlocksHtmlWithState references manualImpls state (logError := logError)
      unless (← errors.get).any (hasSubstr · expected) &&
          !hasSubstr html.asString "invalid authored reference" do
        throw <| IO.userError "HTML rendering concealed a required reference lookup failure"
      let texError? ← try
        let _ ← renderManualBlocksTeXWithState manualImpls references state
        pure none
      catch error => pure (some error.toString)
      unless texError?.any (hasSubstr · expected) do
        throw <| IO.userError "TeX rendering concealed a required reference lookup failure"

end Verso.VersoBlueprintTests.BlueprintLinkHover
