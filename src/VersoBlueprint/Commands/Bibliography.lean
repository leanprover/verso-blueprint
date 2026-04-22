/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso
import VersoManual
import VersoBlueprint.Cite
import VersoBlueprint.Commands.Common
import VersoBlueprint.PreviewCache
import VersoBlueprint.Resolve
import VersoBlueprint.TraversalIndex

namespace Informal.Commands

open Lean Elab Command
open Verso.Genre.Manual.Bibliography

structure BibliographyEntry where
  label : String
  citation : Citable
deriving FromJson, ToJson

structure BibliographyData where
  entries : List BibliographyEntry := []
deriving FromJson, ToJson

def bibliographyCss := include_str "bibliography.css"

open Verso Doc Elab Genre Manual in
block_extension Block.bibliography (biblio : BibliographyData) where
  data := toJson biblio
  traverse id data _contents := do
    let .ok biblio := fromJson? (α := BibliographyData) data
      | logError "Malformed data in Block.bibliography.traverse"
        return none
    let path ← (·.path) <$> read
    let _ ← Verso.Genre.Manual.externalTag id path s!"--bp-bibliography"
    for entry in biblio.entries do
      modify fun st =>
        Informal.TraversalIndex.Bibliography.saveId st entry.label id
    return none
  toTeX := none
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun goI _goB _id data _blocks => do
      let .ok data := fromJson? (α := BibliographyData) data
        | HtmlT.logError "Malformed data in Block.bibliography.toHtml"
          pure .empty
      let st ← HtmlT.state
      let entries := data.entries.toArray.qsort (fun a b => a.citation.sortKey < b.citation.sortKey)
      let rows ← entries.mapM fun entry => do
        let rendered ← entry.citation.bibHtml goI
        let itemId := s!"bp-bib-{Informal.Cite.citationAnchorId entry.label}"
        let usageHrefs := Informal.TraversalIndex.CitationUsages.hrefs st entry.label
        let usageData : Informal.Cite.CitationUsageData :=
          match Informal.TraversalIndex.CitationUsages.object? st entry.label with
          | some obj =>
            match fromJson? (α := Informal.Cite.CitationUsageData) obj.data with
            | .ok data => data
            | .error _ => {}
          | Option.none => {}
        let usageDetails := usageData.uses.toArray.qsort (fun a b => a.href < b.href)
        let usageRows : Array Output.Html :=
          if usageDetails.isEmpty then
            usageHrefs.foldl (init := #[]) fun out href =>
              out.push {{<li><a href={{href}}>s!"Citation use {out.size + 1}"</a></li>}}
          else
            usageDetails.map fun use =>
              let summaryText := use.summary.text st
              let inlineMeta : Output.Html :=
                let index? :=
                  match use.index.map (·.trimAscii.toString) with
                  | some i =>
                    if i.isEmpty then Option.none else some i
                  | Option.none => Option.none
                let detailText? : Option String :=
                  match use.kind, index? with
                  | some .page, some i => some s!"Cites page {i}"
                  | some k, some i => some s!"Cites {k.text} {i}"
                  | some .page, Option.none => some "Cites a page"
                  | some k, Option.none => some s!"Cites {k.text}"
                  | Option.none, some i => some s!"Cites reference {i}"
                  | Option.none, Option.none => Option.none
                match detailText? with
                | some detail =>
                  {{<span class="bp_bibliography_use_inline_meta">
                    {{.text true s!" - {detail}"}}
                  </span>}}
                | Option.none => .empty
              let lineNode : Output.Html := {{
                <a href={{use.href}} class="bp_bibliography_use_line">
                  {{.text true summaryText}}
                  {{inlineMeta}}
                </a>}}
              let previewLine : Output.Html :=
                match use.summary.theoremCtx with
                | some theoremCtx =>
                  let previewKey :=
                    PreviewCache.key theoremCtx.label (PreviewCache.Facet.ofInProgressKind theoremCtx.kind)
                  let previewId :=
                    s!"bp-bib-use-{Informal.HoverRender.previewKey use.href}"
                  Informal.HoverRender.inlinePreviewRef
                    lineNode previewId summaryText
                    (previewLookupKey? := some previewKey)
                    (previewFallbackLabel? := some s!"{theoremCtx.label}")
                | Option.none => lineNode
              {{<li class="bp_bibliography_use_item">
                {{previewLine}}
              </li>}}
        let usageCount := if usageDetails.isEmpty then usageHrefs.size else usageDetails.size
        pure {{
          <li id={{itemId}}>
            {{rendered}}
            <details class="bp_bibliography_uses">
              <summary>s!"Cited from ({usageCount})"</summary>
              <ul class="bp_bibliography_uses_list">
                {{if usageRows.isEmpty then {{<li class="bp_bibliography_empty">"No citation uses recorded."</li>}} else usageRows}}
              </ul>
            </details>
          </li>
        }}
      pure {{
        <div class="bp_bibliography">
          <details class="bp_bibliography_section" open>
            <summary>s!"Bibliography ({entries.size})"</summary>
            <ul class="bp_bibliography_list">
              {{if rows.isEmpty then {{<li class="bp_bibliography_empty">"No bibliography entries registered."</li>}} else rows}}
            </ul>
          </details>
        </div>
      }}
  extraCss := Informal.Commands.withInlinePreviewCssAssets [bibliographyCss]
  extraJs := Informal.Commands.withInlinePreviewJsAssets [openTargetDetailsJs] []

open Verso Doc Elab Syntax in
def mkBibliographyPart (stx : Syntax) (endPos : String.Pos.Raw) : PartElabM FinishedPart := do
  let titlePreview := "Blueprint Bibliography"
  let titleInlines ← `(inline | "Blueprint Bibliography")
  let expandedTitle ← #[titleInlines].mapM (elabInline ·)
  let metadata : Option (TSyntax `term) := some (← `(term| { number := false }))
  let entries := Informal.Cite.allBibEntries (← getEnv)
  if verso.blueprint.debug.commands.get (← Lean.getOptions) then
    logInfo m!"Blueprint bibliography for {entries.length} entries"
  let refs : Array (TSyntax `term) ← entries.toArray.mapM fun (label, decl) =>
    `(BibliographyEntry.mk $(quote label) $(mkIdent decl))
  let block ← ``(Verso.Doc.Block.other
    (Informal.Commands.Block.bibliography
      (BibliographyData.mk (entries := ([$refs,*] : List BibliographyEntry)))) #[])
  let subParts := #[]
  pure <| FinishedPart.mk stx expandedTitle titlePreview metadata #[block] subParts endPos

open Verso Doc Elab Syntax PartElabM in
@[part_command Lean.Doc.Syntax.command]
public meta def blueprintBibliographyCmd : PartCommand
  | stx@`(block|command{blueprint_bibliography}) => do
    let endPos := stx.getTailPos?.get!
    closePartsUntil 1 endPos
    addPart (← mkBibliographyPart stx endPos)
  | _ => (Lean.Elab.throwUnsupportedSyntax : PartElabM Unit)

end Informal.Commands
