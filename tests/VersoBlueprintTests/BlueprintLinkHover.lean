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

#docs (Genre.Manual) hoverUsesDedupDoc "Hover Uses Dedup Doc" :=
:::::::
:::lemma_ "lem:hover.base"
Base lemma for repeated references.
:::

:::lemma_ "lem:hover.dedup"
Using {uses "lem:hover.base"}[] and again {uses "lem:hover.base"}[].
:::
:::::::

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
    match Informal.TraversalIndex.Nodes.data? st (Name.mkSimple "lem:hover.intent.node") with
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

end Verso.VersoBlueprintTests.BlueprintLinkHover
