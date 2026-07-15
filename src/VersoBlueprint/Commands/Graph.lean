/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso
import VersoManual
import VersoBlueprint.Commands.Common
import VersoBlueprint.Environment
import VersoBlueprint.Graph
import VersoBlueprint.GraphApi
import VersoBlueprint.Lib.HoverRender
import VersoBlueprint.Lib.HtmlId
import VersoBlueprint.Lib.ExtensionDecode
import VersoBlueprint.PreviewCache
import VersoBlueprint.Lib.PreviewSource
import VersoBlueprint.Resolve
import VersoBlueprint.TeX
import VersoBlueprint.TraversalIndex

namespace Informal.Commands

open Lean Elab Command
open Informal Data Environment
open Informal.Graph

register_option verso.blueprint.graph.defaultDirection : String := {
  defValue := "TB"
  descr := "Default direction for `blueprint_graph` when `(direction := ...)` is omitted (LR, RL, TB, BT)"
}

register_option verso.blueprint.graph.defaultPack : Bool := {
  defValue := false
  descr := "Default Graphviz component packing for `blueprint_graph` when `(pack := ...)` is omitted"
}

register_option verso.blueprint.graph.defaultPreviewMode : String := {
  defValue := "pinned"
  descr := "Default preview behavior for `blueprint_graph` when `(preview := ...)` is omitted (`pinned` or `hover`)"
}

register_option verso.blueprint.graph.defaultPreviewPlacement : String := {
  defValue := "docked"
  descr := "Default preview panel placement for `blueprint_graph` when `(previewPlacement := ...)` is omitted (`docked` or `anchored`)"
}

structure GraphBlockData where
  semanticGraphData : Informal.Graph.GraphData := {}
  options : GraphOptions := {}
  previewMode : Informal.HoverRender.PreviewMode := .pinned
  previewPlacement : Informal.HoverRender.PreviewPlacement := .docked
deriving Inhabited, FromJson, ToJson, Quote

def parseGraphPreviewMode? (s : String) : Option Informal.HoverRender.PreviewMode :=
  match s.trimAscii.toString.toLower with
  | "hover" => some .hover
  | "pinned" => some .pinned
  | _ => none

def parseGraphPreviewPlacement? (s : String) : Option Informal.HoverRender.PreviewPlacement :=
  match s.trimAscii.toString.toLower with
  | "docked" => some .docked
  | "anchored" => some .anchored
  | _ => none

-- Keep this module rebuilt when the embedded graph assets change.
-- This module owns the embedded graph CSS/JS boundary, so adjacent edits here
-- should land whenever graph runtime assets are intentionally refreshed.
def graphCss := include_str "graph.css"

def fallbackGraphControlId (id : Verso.Multi.InternalId) (suffix : String) : String :=
  s!"{Informal.HtmlId.prefixed "bp-graph" (toString id)}{suffix}"

def graphAssetBundle : BlueprintAssetBundle :=
  previewPanelAssetBundle (cssExtras := [graphCss])

open Verso Doc Elab Genre Manual in
block_extension Block.graph (graphData : GraphBlockData) where
  -- for TOC
  -- localContentItem _ _ _ := none
  data := toJson graphData
  usePackages := Informal.TeX.standardMathUsePackages
  traverse id data _contents := do
      match ← Informal.ExtensionDecode.decode? (α := GraphBlockData) data
          (fun _ => "Malformed data in Block.graph.traverse") with
      | some graphData =>
        modify fun state =>
          Informal.GraphApi.saveData state id graphData.semanticGraphData graphData.options
      | Option.none =>
        pure ()
      return none
  toTeX :=
    open Verso.Output.TeX in
    some <| fun _goI _goB _id _data _blocks =>
      pure <| .text "The dependency graph is available in the HTML output."
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun _goI _goB id data _blocks => do
      let graphData : GraphBlockData ←
        match ← Informal.ExtensionDecode.decode? (α := GraphBlockData) data
            (fun err => s!"Malformed data in Block.graph.toHtml ({err})") with
        | some graphData => pure graphData
        | Option.none => pure { semanticGraphData := {}, options := {} }
      let s ← HtmlT.state
      let publicGraphData :=
        Informal.GraphApi.finalDataForBlockWithOptions
          s id graphData.semanticGraphData graphData.options
      let publicGraphDataJson : String := Lean.Json.compress (toJson publicGraphData)
      let graphVariants := publicGraphData.variants
      let hasGroupVariant := graphVariants.any (fun variant => variant.key == groupVariantKey)
      let graphVariantOptions : Array Output.Html :=
        graphVariants.map fun variant => {{
          <option value={{variant.key}}>{{variant.label}}</option>
        }}
      let includeMathlibLegend :=
        publicGraphData.nodes.any (fun node => node.visual.color == Informal.Graph.statementBorderMathlibColor)
      let renderLegend (kind : String) (groups : Array Informal.Graph.LegendGroup)
          (note? : Option String := none) (hidden : Bool := false) : Output.Html :=
        let legendGroupHtml : Array Output.Html :=
          groups.map fun group =>
            let summaryHtml : Output.Html :=
              match group.summary? with
              | some summary => {{
                  <p class="bp_graph_legend_group_summary">
                    {{.text false summary}}
                  </p>
                }}
              | Option.none => .empty
            let itemHtml : Array Output.Html :=
              group.items.map fun item =>
                match item.swatch? with
                | some swatch => {{
                    <span class="bp_graph_legend_item">
                      <span class="bp_graph_legend_swatch" "style"={{swatch.inlineStyle}}></span>
                      {{.text false item.label}}
                    </span>
                  }}
                | Option.none => {{
                    <span class="bp_graph_legend_item">
                      {{.text false item.label}}
                    </span>
                  }}
            {{
              <section class="bp_graph_legend_group">
                <div class="bp_graph_legend_group_header">
                  <span class="bp_graph_legend_group_title">{{.text false group.title}}</span>
                  {{summaryHtml}}
                </div>
                <div class="bp_graph_legend_items">
                  {{itemHtml}}
                </div>
              </section>
            }}
        let noteHtml : Output.Html :=
          match note? with
          | some note => {{
              <p class="bp_graph_legend_note">
                {{.text false note}}
              </p>
            }}
          | Option.none => .empty
        if hidden then
          {{
            <div class="bp_graph_legend" "data-bp-legend-kind"={{kind}} hidden>
              {{noteHtml}}
              {{legendGroupHtml}}
            </div>
          }}
        else
          {{
            <div class="bp_graph_legend" "data-bp-legend-kind"={{kind}}>
              {{noteHtml}}
              {{legendGroupHtml}}
            </div>
          }}
      let fullLegendHtml :=
        renderLegend "full" (Informal.Graph.graphLegendGroups includeMathlibLegend)
          (note? := some Informal.Graph.graphLegendFullViewNote)
      let groupLegendHtml : Output.Html :=
        if hasGroupVariant then
          renderLegend "group" Informal.Graph.groupGraphLegendGroups
            (note? := some Informal.Graph.graphLegendGroupViewNote) (hidden := true)
        else
          .empty
      let graphHtmlAttrs := s.htmlId id
      let graphControlId (suffix : String) : String :=
        match graphHtmlAttrs.findSome? fun
            | ("id", value) => some s!"{value}{suffix}"
            | _ => Option.none with
        | some value => value
        | Option.none => fallbackGraphControlId id suffix
      let graphViewSelectId : String := graphControlId "--view"
      let graphDirectionSelectId : String := graphControlId "--direction"
      let graphPackInputId : String := graphControlId "--pack"
      let graphPreviewModeSelectId : String := graphControlId "--preview-mode"
      let graphPreviewPlacementSelectId : String := graphControlId "--preview-placement"
      let graphLegendPanelId : String := graphControlId "--legend"
      let graphOptionsPanelId : String := graphControlId "--options"
      let graphDirectionOptions : Array Output.Html :=
        allGraphDirections.map fun direction =>
          if direction == graphData.options.direction then
            {{ <option value={{direction.rankdir}} selected>{{direction.rankdir}}</option> }}
          else
            {{ <option value={{direction.rankdir}}>{{direction.rankdir}}</option> }}
      let graphPackChecked : Array (String × String) :=
        if graphData.options.pack then #[("checked", "checked")] else #[]
      let graphPackDefault : String := if graphData.options.pack then "true" else "false"
      let previewModeDefault : String := graphData.previewMode.dataValue
      let graphPreviewModeOptions : Array Output.Html := #[
        if graphData.previewMode == .pinned then
          {{ <option value="pinned" selected>"Click to pin"</option> }}
        else
          {{ <option value="pinned">"Click to pin"</option> }},
        if graphData.previewMode == .hover then
          {{ <option value="hover" selected>"Hover"</option> }}
        else
          {{ <option value="hover">"Hover"</option> }}
      ]
      let previewPlacementDefault : String := graphData.previewPlacement.dataValue
      let graphPreviewPlacementOptions : Array Output.Html := #[
        if graphData.previewPlacement == .docked then
          {{ <option value="docked" selected>"Docked"</option> }}
        else
          {{ <option value="docked">"Docked"</option> }},
        if graphData.previewPlacement == .anchored then
          {{ <option value="anchored" selected>"Near node"</option> }}
        else
          {{ <option value="anchored">"Near node"</option> }}
      ]
      let previewPanel :=
        Informal.HoverRender.graphPreviewPanel
          graphData.previewMode
          graphData.previewPlacement
      let groupHoverPanel := Informal.HoverRender.graphGroupPreviewPanel
      return {{
        <div class="bp_graph_fullwidth">
          <div class="bp_graph_controls">
            <div class="bp_graph_controls_primary">
              <button
                type="button"
                class="bp_graph_controls_button bp_graph_legend_button"
                aria-haspopup="dialog"
                aria-expanded="false"
                aria-controls={{graphLegendPanelId}}
              >
                "Legend"
              </button>
              <label class="bp_graph_controls_label" for={{graphViewSelectId}}>"View"</label>
              <select id={{graphViewSelectId}} class="bp_graph_controls_select bp_graph_view_select">
                {{graphVariantOptions}}
              </select>
            </div>
            <div class="bp_graph_controls_actions">
              <button
                type="button"
                class="bp_graph_controls_button bp_graph_options_button"
                aria-haspopup="dialog"
                aria-expanded="false"
                aria-controls={{graphOptionsPanelId}}
              >
                "Graph options"
              </button>
            </div>
          </div>
          <div id={{graphLegendPanelId}} class="bp_graph_legend_popover" hidden>
            <div class="bp_graph_legend_popover_header">
              <span class="bp_graph_legend_popover_title">"Legend"</span>
              <button type="button" class="bp_graph_legend_popover_close" aria-label="Close legend">"Close"</button>
            </div>
            <div class="bp_graph_legend_popover_body">
              {{fullLegendHtml}}
              {{groupLegendHtml}}
            </div>
          </div>
          <div id={{graphOptionsPanelId}} class="bp_graph_options_popover" hidden>
            <div class="bp_graph_options_popover_header">
              <span class="bp_graph_options_popover_title">"Graph options"</span>
              <button type="button" class="bp_graph_options_popover_close" aria-label="Close graph options">"Close"</button>
            </div>
            <div class="bp_graph_options_popover_body">
              <label class="bp_graph_controls_label" for={{graphDirectionSelectId}}>"Direction"</label>
              <select
                id={{graphDirectionSelectId}}
                class="bp_graph_controls_select bp_graph_direction_select"
                data-bp-graph-default-direction={{graphData.options.direction.rankdir}}
              >
                {{graphDirectionOptions}}
              </select>
              <label class="bp_graph_option_toggle" for={{graphPackInputId}}>
                <input
                  id={{graphPackInputId}}
                  type="checkbox"
                  class="bp_graph_pack_input"
                  data-bp-graph-default-pack={{graphPackDefault}}
                  {{graphPackChecked}}/>
                <span>"Pack disconnected components"</span>
              </label>
              <label class="bp_graph_controls_label" for={{graphPreviewModeSelectId}}>"Preview"</label>
              <select
                id={{graphPreviewModeSelectId}}
                class="bp_graph_controls_select bp_graph_preview_mode_select"
                data-bp-graph-default-preview-mode={{previewModeDefault}}
              >
                {{graphPreviewModeOptions}}
              </select>
              <label class="bp_graph_controls_label" for={{graphPreviewPlacementSelectId}}>"Position"</label>
              <select
                id={{graphPreviewPlacementSelectId}}
                class="bp_graph_controls_select bp_graph_preview_placement_select"
                data-bp-graph-default-preview-placement={{previewPlacementDefault}}
              >
                {{graphPreviewPlacementOptions}}
              </select>
            </div>
          </div>
          <div
            class="bp_graph_canvas"
            "data-bp-graph-direction"={{graphData.options.direction.rankdir}}
            "data-bp-graph-pack"={{graphPackDefault}}
          >
            <script type="application/json" class="bp-graph-data">
              {{.text false s!"{publicGraphDataJson}"}}
            </script>
          </div>
          {{previewPanel}}
          {{groupHoverPanel}}
        </div>
      }}
  extraCss := graphAssetBundle.css
  extraJs := graphAssetBundle.js

def buildAll : CoreM Informal.Graph.GraphData := do
  reportImportedConflicts
  let env ← getEnv
  let state := informalExt.getState env
  let roots : Array Name := state.data.toArray.map (·.1)
  let groupTitles := state.groups.toArray
  let semanticGraphData := Informal.Graph.buildData state roots (groupTitles := groupTitles)
  return semanticGraphData

open Verso.ArgParse

instance : FromArgVal GraphDirection Verso.Doc.Elab.PartElabM where
  fromArgVal := {
    description := doc!"graph direction (`LR`, `RL`, `TB`, or `BT`)"
    signature := CanMatch.Ident ∪ CanMatch.String
    get := fun
      | .name id =>
        match GraphDirection.parse? id.getId.toString with
        | some d => pure d
        | none => throwErrorAt id "Expected one of `LR`, `RL`, `TB`, `BT`"
      | .str s =>
        match GraphDirection.parse? s.getString with
        | some d => pure d
        | none => throwErrorAt s "Expected one of \"lr\", \"rl\", \"tb\", \"bt\""
      | other =>
        throwError "Expected a direction identifier or string, got {toMessageData other}"
  }

instance : FromArgVal Informal.HoverRender.PreviewMode Verso.Doc.Elab.PartElabM where
  fromArgVal := {
    description := doc!"graph preview mode (`pinned` or `hover`)"
    signature := CanMatch.Ident ∪ CanMatch.String
    get := fun
      | .name id =>
        match parseGraphPreviewMode? id.getId.toString with
        | some mode => pure mode
        | none => throwErrorAt id "Expected `pinned` or `hover`"
      | .str s =>
        match parseGraphPreviewMode? s.getString with
        | some mode => pure mode
        | none => throwErrorAt s "Expected \"pinned\" or \"hover\""
      | other =>
        throwError "Expected a preview mode identifier or string, got {toMessageData other}"
  }

instance : FromArgVal Informal.HoverRender.PreviewPlacement Verso.Doc.Elab.PartElabM where
  fromArgVal := {
    description := doc!"graph preview placement (`docked` or `anchored`)"
    signature := CanMatch.Ident ∪ CanMatch.String
    get := fun
      | .name id =>
        match parseGraphPreviewPlacement? id.getId.toString with
        | some placement => pure placement
        | none => throwErrorAt id "Expected `docked` or `anchored`"
      | .str s =>
        match parseGraphPreviewPlacement? s.getString with
        | some placement => pure placement
        | none => throwErrorAt s "Expected \"docked\" or \"anchored\""
      | other =>
        throwError "Expected a preview placement identifier or string, got {toMessageData other}"
  }

structure BlueprintGraphConfig where
  direction : Option GraphDirection := none
  pack : Option Bool := none
  preview : Option Informal.HoverRender.PreviewMode := none
  previewPlacement : Option Informal.HoverRender.PreviewPlacement := none

instance : FromArgs BlueprintGraphConfig Verso.Doc.Elab.PartElabM where
  fromArgs :=
    BlueprintGraphConfig.mk <$>
      .named' `direction true <*>
      .named' `pack true <*>
      .named' `preview true <*>
      .named' `previewPlacement true

def parseGraphDirection (cfg : BlueprintGraphConfig) : Verso.Doc.Elab.PartElabM GraphDirection := do
  match cfg.direction with
  | none =>
    let configured :=
      (← getOptions).get
        verso.blueprint.graph.defaultDirection.name
        verso.blueprint.graph.defaultDirection.defValue
    match GraphDirection.parse? configured with
    | some direction => pure direction
    | none =>
      logWarning m!"Invalid value '{configured}' for option 'verso.blueprint.graph.defaultDirection'; expected LR, RL, TB, or BT. Falling back to TB."
      pure .TB
  | some direction => pure direction

def parseGraphOptions (cfg : BlueprintGraphConfig) : Verso.Doc.Elab.PartElabM GraphOptions := do
  let direction ← parseGraphDirection cfg
  let pack :=
    cfg.pack.getD <|
      (← getOptions).get
        verso.blueprint.graph.defaultPack.name
        verso.blueprint.graph.defaultPack.defValue
  pure { direction, pack }

def parseGraphPreviewMode
    (cfg : BlueprintGraphConfig) : Verso.Doc.Elab.PartElabM Informal.HoverRender.PreviewMode := do
  match cfg.preview with
  | none =>
    let configured :=
      (← getOptions).get
        verso.blueprint.graph.defaultPreviewMode.name
        verso.blueprint.graph.defaultPreviewMode.defValue
    match parseGraphPreviewMode? configured with
    | some mode => pure mode
    | none =>
      logWarning m!"Invalid value '{configured}' for option 'verso.blueprint.graph.defaultPreviewMode'; expected pinned or hover. Falling back to pinned."
      pure .pinned
  | some mode => pure mode

def parseGraphPreviewPlacement
    (cfg : BlueprintGraphConfig) : Verso.Doc.Elab.PartElabM Informal.HoverRender.PreviewPlacement := do
  match cfg.previewPlacement with
  | none =>
    let configured :=
      (← getOptions).get
        verso.blueprint.graph.defaultPreviewPlacement.name
        verso.blueprint.graph.defaultPreviewPlacement.defValue
    match parseGraphPreviewPlacement? configured with
    | some placement => pure placement
    | none =>
      logWarning m!"Invalid value '{configured}' for option 'verso.blueprint.graph.defaultPreviewPlacement'; expected docked or anchored. Falling back to docked."
      pure .docked
  | some placement => pure placement

open Verso Doc Elab Syntax in
def mkGraphPart (stx : Syntax) (endPos : String.Pos.Raw) (options : GraphOptions := {})
    (previewMode : Informal.HoverRender.PreviewMode := .pinned)
    (previewPlacement : Informal.HoverRender.PreviewPlacement := .docked) :
    PartElabM FinishedPart := do
  let titlePreview := "Dependency Graph"
  let titleInlines ← `(inline | "Dependency Graph")
  let expandedTitle ← #[titleInlines].mapM (elabInline ·)
  let metadata : Option (TSyntax `term) := some (← `(term| { number := false }))
  let semanticGraphData ← buildAll
  if verso.blueprint.debug.commands.get (← Lean.getOptions) then
    logInfo m!"Adding {semanticGraphData.nodes.size} graph nodes"
  let graphData : GraphBlockData := { semanticGraphData, options, previewMode, previewPlacement }
  let block ← ``(Verso.Doc.Block.other (Informal.Commands.Block.graph $(quote graphData)) #[])
  let subParts := #[]
  pure <| FinishedPart.mk stx stx expandedTitle titlePreview metadata #[block] subParts endPos

open Verso Doc Elab Syntax PartElabM in
@[part_command Lean.Doc.Syntax.command]
public meta def depGraph : PartCommand
  | stx@`(block|command{blueprint_graph $args*}) => do
    let cfg ← Verso.ArgParse.parseThe BlueprintGraphConfig (← parseArgs args)
    let options ← parseGraphOptions cfg
    let previewMode ← parseGraphPreviewMode cfg
    let previewPlacement ← parseGraphPreviewPlacement cfg
    let endPos := stx.getTailPos?.get!
    closePartsUntil 1 endPos
    addPart (← mkGraphPart stx endPos options previewMode previewPlacement)
  | _ => (Lean.Elab.throwUnsupportedSyntax : PartElabM Unit)

end Informal.Commands
