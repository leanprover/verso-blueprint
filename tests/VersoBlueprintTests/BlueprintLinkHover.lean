/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.Blueprint.Support
import VersoManual.Bibliography

namespace Verso.VersoBlueprintTests.BlueprintLinkHover

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

#docs (Genre.Manual) hoverCiteOnlyDoc "Hover Cite Only Doc" :=
:::::::
Cite once {Informal.citet hover.cite (kind := lemma) (index := 3)}[] and cite twice
{Informal.citet hover.cite (kind := lemma) (index := 3)}[].

{blueprint_bibliography}
:::::::

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
      hasSubstr out "data-bp-preview-fallback-label=\"«lem:hover.link»\"" &&
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
      countSubstr out
          "data-bp-preview-fallback-label=\"«lem:hover.base»\"" >= 2 &&
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
      hasExtraJs st "bindInlinePreview" &&
      hasExtraCss st ".bp_inline_preview_panel"
    )

end Verso.VersoBlueprintTests.BlueprintLinkHover
