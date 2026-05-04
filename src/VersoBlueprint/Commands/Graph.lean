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
import VersoBlueprint.Lib.HoverRender
import VersoBlueprint.PreviewCache
import VersoBlueprint.Lib.PreviewSource
import VersoBlueprint.Resolve
import VersoBlueprint.TraversalIndex

namespace Informal.Commands

open Lean Elab Command
open Informal Data Environment

abbrev GraphNode := Informal.Graph.GraphNode Name
abbrev Graph := Informal.Graph.Graph Name

inductive GraphDirection where
  | LR
  | RL
  | TB
  | BT
deriving Inhabited, Repr, BEq, FromJson, ToJson, Quote

def GraphDirection.rankdir : GraphDirection → String
  | .LR => "LR"
  | .RL => "RL"
  | .TB => "TB"
  | .BT => "BT"

def GraphDirection.parse? (s : String) : Option GraphDirection :=
  match s.toLower with
  | "lr" | "left-right" | "horizontal" => some .LR
  | "rl" | "right-left" => some .RL
  | "tb" | "top-bottom" | "vertical" => some .TB
  | "bt" | "bottom-top" => some .BT
  | _ => none

register_option verso.blueprint.graph.defaultDirection : String := {
  defValue := "TB"
  descr := "Default direction for `blueprint_graph` when `(direction := ...)` is omitted (LR, RL, TB, BT)"
}

register_option verso.blueprint.graph.defaultPack : Bool := {
  defValue := false
  descr := "Default Graphviz component packing for `blueprint_graph` when `(pack := ...)` is omitted"
}

structure GraphOptions where
  direction : GraphDirection := .TB
  /--
  Ask Graphviz to compact disconnected graph components before d3-graphviz fits
  the SVG into the canvas.
  -/
  pack : Bool := false
deriving Inhabited, BEq, FromJson, ToJson, Quote

structure GraphBlockData where
  graph : Graph
  options : GraphOptions := {}
  groupTitles : Array (Name × String) := #[]
deriving Inhabited, FromJson, ToJson, Quote

def graphPackAttr (pack : Bool) : String :=
  if pack then "true" else "false"

/-- Common DOT header for rendered Blueprint graphs.

`pack=true` keeps disconnected graph components compact before d3-graphviz fits
the SVG into the canvas. Without it, sparse multi-component graphs can be
placed far from the top of the viewport after variant or direction switches.
-/
def graphDotHeader (options : GraphOptions := {}) : String :=
  "strict digraph \"\" {\n" ++
  s!"    rankdir={options.direction.rankdir};\n" ++
  "    bgcolor=\"white\";\n" ++
  s!"    pack={graphPackAttr options.pack};\n" ++
  "    splines=true;\n" ++
  "    nodesep=0.35;\n" ++
  "    ranksep=0.45;\n" ++
  "    node [shape=box, style=\"rounded,filled\", fontname=\"Helvetica\", fontsize=10, margin=\"0.08,0.04\", color=\"#6b7280\", penwidth=1.8];\n" ++
  "    edge [color=\"#6b7280\", arrowhead=vee, arrowsize=0.6, penwidth=1];\n" ++
  "    graph [fontname=\"Helvetica\"];\n" ++
  "  "

def graphToDot (g : Graph) (options : GraphOptions := {})
    (resolveHref : Name → Option String := fun _ => none)
    (resolveGroupTitle : Name → Option String := fun _ => none) : String :=
  Informal.Graph.Graph.toDot g (graphDotHeader options)
    (groupLabel? := some resolveGroupTitle)
    (refAttrs? := some fun ref =>
    (resolveHref ref).map (fun href => s!"URL=\"{href}\", target=\"_self\""))

structure GraphRenderVariant where
  key : String
  label : String
  dot : String
  options : GraphOptions := {}
  selectOnNodeId : Array (String × String) := #[]
  hoverOnNodeId : Array (String × String) := #[]
  previewKeyByNodeId : Array (String × String) := #[]
deriving Inhabited, ToJson

def allGraphDirections : Array GraphDirection := #[.TB, .LR, .RL, .BT]

-- Keep this module rebuilt when the embedded graph assets change.
-- This module owns the embedded graph CSS/JS boundary, so adjacent edits here
-- should land whenever graph runtime assets are intentionally refreshed.
def graphCss := include_str "graph.css"

def fallbackGraphControlId (id : Verso.Multi.InternalId) (suffix : String) : String :=
  let raw := toString id
  let sanitized := raw.foldl (init := "") fun acc c =>
    acc.push <| if c.isAlphanum then c else '-'
  s!"bp-graph-{sanitized}{suffix}"

def groupVariantKey : String := "group"
def parentVariantKey (parent : Name) : String := s!"parent:{parent}"

def graphParentChildren (graph : Graph) : Lean.NameMap (Array Name) :=
  graph.foldl (init := ({} : Lean.NameMap (Array Name))) fun acc node =>
    match node.parent? with
    | none => acc
    | some parent =>
      let children := acc.getD parent #[]
      acc.insert parent (children.push node.label)

def graphNodeParents (graph : Graph) : Lean.NameMap Name :=
  graph.foldl (init := ({} : Lean.NameMap Name)) fun acc node =>
    match node.parent? with
    | none => acc
    | some parent => acc.insert node.label parent

def graphParentTitle (groupTitles : Lean.NameMap String) (parent : Name) : String :=
  let title := (groupTitles.getD parent parent.toString).trimAscii.toString
  if title.isEmpty then parent.toString else title

partial def wrapGraphLabelWords (words : List String) (lineWidth maxLines : Nat)
    (current : String) (lines : Array String) : Array String :=
  match words with
  | [] =>
    if current.isEmpty then lines else lines.push current
  | word :: rest =>
    if lines.size + 1 == maxLines then
      let finalLine :=
        if current.isEmpty then
          String.intercalate " " (word :: rest)
        else
          String.intercalate " " (current :: word :: rest)
      lines.push finalLine
    else
      let candidate := if current.isEmpty then word else current ++ " " ++ word
      if !current.isEmpty && candidate.length > lineWidth then
        wrapGraphLabelWords words lineWidth maxLines "" (lines.push current)
      else
        wrapGraphLabelWords rest lineWidth maxLines candidate lines

def wrapGraphLabel (title : String) (lineWidth : Nat := 26) (maxLines : Nat := 3) : String :=
  let words :=
    (title.splitOn " ").foldr (init := ([] : List String)) fun word acc =>
      let word := word.trimAscii.toString
      if word.isEmpty then acc else word :: acc
  match words with
  | [] => title.trimAscii.toString
  | _ =>
    let lines := wrapGraphLabelWords words lineWidth maxLines "" #[]
    String.intercalate "\n" lines.toList

def graphParentDisplayLabel (groupTitles : Lean.NameMap String) (parent : Name) : String :=
  wrapGraphLabel (graphParentTitle groupTitles parent)

def hexNibble? (c : Char) : Option Nat :=
  match c with
  | '0' => some 0
  | '1' => some 1
  | '2' => some 2
  | '3' => some 3
  | '4' => some 4
  | '5' => some 5
  | '6' => some 6
  | '7' => some 7
  | '8' => some 8
  | '9' => some 9
  | 'a' | 'A' => some 10
  | 'b' | 'B' => some 11
  | 'c' | 'C' => some 12
  | 'd' | 'D' => some 13
  | 'e' | 'E' => some 14
  | 'f' | 'F' => some 15
  | _ => none

def parseHexByte? (c1 c2 : Char) : Option Nat := do
  let hi ← hexNibble? c1
  let lo ← hexNibble? c2
  return hi * 16 + lo

def parseHexColor? (s : String) : Option (Nat × Nat × Nat) := do
  let chars :=
    match s.trimAscii.toString.toList with
    | '#' :: rest => rest
    | xs => xs
  match chars with
  | r1 :: r2 :: g1 :: g2 :: b1 :: b2 :: [] =>
    return (← parseHexByte? r1 r2, ← parseHexByte? g1 g2, ← parseHexByte? b1 b2)
  | _ => none

def hexChar (n : Nat) : Char :=
  if n < 10 then
    Char.ofNat ('0'.toNat + n)
  else
    Char.ofNat ('a'.toNat + (n - 10))

def byteToHex (n : Nat) : String :=
  let n := n % 256
  let hi := n / 16
  let lo := n % 16
  String.ofList [hexChar hi, hexChar lo]

def rgbToHex (r g b : Nat) : String :=
  "#" ++ byteToHex r ++ byteToHex g ++ byteToHex b

def primaryColorToken (s : String) : String :=
  match s.splitOn ":" with
  | token :: _ => token.trimAscii.toString
  | [] => s.trimAscii.toString

def averageHexColor (colors : Array (Nat × Nat × Nat)) (fallback : String) : String :=
  if colors.isEmpty then
    fallback
  else
    let (sumR, sumG, sumB) := colors.foldl (init := (0, 0, 0)) fun (r, g, b) (r', g', b') =>
      (r + r', g + g', b + b')
    let n := colors.size
    rgbToHex (sumR / n) (sumG / n) (sumB / n)

def mixedNodeColor (nodes : Array GraphNode) (colorOf : GraphNode → String) (fallback : String) : String :=
  let colors := nodes.foldl (init := (#[] : Array (Nat × Nat × Nat))) fun acc node =>
    match parseHexColor? (primaryColorToken (colorOf node)) with
    | some rgb => acc.push rgb
    | Option.none => acc
  averageHexColor colors fallback

def fontColorForFill (fillColor : String) : String :=
  match parseHexColor? fillColor with
  | some (r, g, b) =>
    -- Relative luminance approximation, keeps labels readable on dark mixes.
    if (299 * r + 587 * g + 114 * b) < 140000 then "#f8fafc" else "#0f172a"
  | Option.none => "#0f172a"

def nodeHasAncestorParent (parentMap : Lean.NameMap Name) (label ancestor : Name) : Bool :=
  Id.run <| do
    let mut current := label
    let mut seen : Lean.NameSet := {}
    let mut fuel := parentMap.toArray.size + 1
    while fuel > 0 do
      fuel := fuel - 1
      match parentMap.get? current with
      | none => return false
      | some parent =>
        if parent == ancestor then
          return true
        if seen.contains parent then
          return false
        seen := seen.insert parent
        current := parent
    return false

def subgraphForParent (graph : Graph) (parent : Name) : Graph :=
  let parentMap := graphNodeParents graph
  graph.filter fun node =>
    node.label == parent || nodeHasAncestorParent parentMap node.label parent

def mkParentOverviewGraph (graph : Graph) (parents : Array Name)
    (groupTitles : Lean.NameMap String) : Graph :=
  let parentChildren := graphParentChildren graph
  let nodeByLabel : Lean.NameMap GraphNode :=
    graph.foldl (init := ({} : Lean.NameMap GraphNode)) fun acc node =>
      acc.insert node.label node
  let parentSet : Lean.NameSet :=
    parents.foldl (init := ({} : Lean.NameSet)) fun acc parent => acc.insert parent
  let parentMap := graphNodeParents graph
  let addParentDep (acc : Lean.NameMap (Array Name)) (target source : Name) : Lean.NameMap (Array Name) :=
    let deps := acc.getD target #[]
    if deps.contains source then
      acc
    else
      acc.insert target (deps.push source)
  let collectParentDeps (depsOf : GraphNode → Array Name) :=
    graph.foldl (init := ({} : Lean.NameMap (Array Name))) fun acc node =>
      match node.parent? with
      | none => acc
      | some target =>
        if !parentSet.contains target then
          acc
        else
          (depsOf node).foldl (init := acc) fun acc dep =>
            match parentMap.get? dep with
            | some source =>
              if parentSet.contains source && source != target then
                addParentDep acc target source
              else
                acc
            | none => acc
  let parentStatementDeps := collectParentDeps (·.deps)
  let parentProofDeps := collectParentDeps (·.proofDeps)
  parents.map fun parent =>
    let childNodes :=
      (parentChildren.getD parent #[]).foldl (init := (#[] : Array GraphNode)) fun acc child =>
        match nodeByLabel.get? child with
        | some node => acc.push node
        | Option.none => acc
    let mixedFillColor := mixedNodeColor childNodes (·.fillcolor) "#e2e8f0"
    let mixedBorderColor := mixedNodeColor childNodes (·.color) "#475569"
    let title := graphParentTitle groupTitles parent
    {
      label := parent
      displayLabel? := some (graphParentDisplayLabel groupTitles parent)
      deps := parentStatementDeps.getD parent #[]
      proofDeps := parentProofDeps.getD parent #[]
      shape := "tab"
      style := "filled"
      fillcolor := mixedFillColor
      color := mixedBorderColor
      penwidth := "2.4"
      fontcolor := fontColorForFill mixedFillColor
      tooltip? := some s!"Group View: {title} ({childNodes.size} nodes)"
      ref? := none
    }

def mkGraphVariants (graphData : GraphBlockData) (resolveHref : Name → Option String)
    (groupTitles : Lean.NameMap String) : Array GraphRenderVariant :=
  let previewKeyByNodeId (graph : Graph) : Array (String × String) :=
    graph.map fun node =>
      (Informal.Graph.graphNodeSvgId node.label, PreviewCache.key node.label .statement)
  let resolveGroupTitle : Name → Option String := fun group =>
    groupTitles.get? group
  let parentChildren := graphParentChildren graphData.graph
  let parents :=
    parentChildren.toArray
      |>.filter (fun (_, children) => children.size > 1)
      |>.map (·.1)
      |>.qsort (fun a b => graphParentTitle groupTitles a < graphParentTitle groupTitles b)
  if parents.isEmpty then
    #[{
      key := "full"
      label := "Full Graph"
      dot := graphToDot graphData.graph graphData.options resolveHref resolveGroupTitle
      options := graphData.options
      selectOnNodeId := #[]
      hoverOnNodeId := #[]
      previewKeyByNodeId := previewKeyByNodeId graphData.graph
    }]
  else
    let parentVariantRefs := parents.map (fun parent => (Informal.Graph.graphNodeSvgId parent, parentVariantKey parent))
    let groupVariant : GraphRenderVariant := {
      key := groupVariantKey
      label := "Group View"
      dot := graphToDot (mkParentOverviewGraph graphData.graph parents groupTitles)
        graphData.options (fun _ => none) (fun _ => none)
      options := graphData.options
      selectOnNodeId := parentVariantRefs
      hoverOnNodeId := parentVariantRefs
      previewKeyByNodeId := #[]
    }
    let fullVariant : GraphRenderVariant := {
      key := "full"
      label := "Full Graph"
      dot := graphToDot graphData.graph graphData.options resolveHref resolveGroupTitle
      options := graphData.options
      selectOnNodeId := #[]
      hoverOnNodeId := #[]
      previewKeyByNodeId := previewKeyByNodeId graphData.graph
    }
    let parentVariants := parents.map fun parent =>
      let parentSubgraph := subgraphForParent graphData.graph parent
      let title := graphParentTitle groupTitles parent
      {
        key := parentVariantKey parent
        label := title
        dot := graphToDot parentSubgraph
          graphData.options resolveHref resolveGroupTitle
        options := graphData.options
        selectOnNodeId := #[]
        hoverOnNodeId := #[]
        previewKeyByNodeId := previewKeyByNodeId parentSubgraph
      }
    #[fullVariant, groupVariant] ++ parentVariants

-- Keep this binding in Lean so asset updates flow through the command module rebuild.
-- Updated when the runtime asset changes; current runtime leaves block placement to CSS
-- and relies on graphviz auto-fit plus flow-aware canvas sizing for initial placement
-- plus user-controlled resize persistence and cheap height resets.
def loadD3Dot := include_str "graph.js"

-- block_extension Block.dependency_graph (label : String) where
open Verso Doc Elab Genre Manual in
block_extension Block.graph (graphData : GraphBlockData) where
  -- for TOC
  -- localContentItem _ _ _ := none
  data := toJson graphData
  traverse _id _data _contents := do
      return none
  toTeX := none
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun _goI _goB id data _blocks => do
      let graphData : GraphBlockData ←
        match fromJson? (α := GraphBlockData) data with
        | .ok gd => pure gd
        | .error err =>
          HtmlT.logError s!"Malformed data in Block.graph.toHtml ({err})"
          pure { graph := #[], options := {}, groupTitles := #[] }
      let s ← HtmlT.state
      let resolveHref : Name → Option String := fun ref =>
        Informal.TraversalIndex.Nodes.href? s ref
      let groupTitles : Lean.NameMap String :=
        graphData.groupTitles.foldl (init := ({} : Lean.NameMap String)) fun acc (group, title) =>
          acc.insert group title
      let resolveGroupTitle : Name → Option String := fun group =>
        groupTitles.get? group
      let graphVariants := mkGraphVariants graphData resolveHref groupTitles
      let hasGroupVariant := graphVariants.any (fun variant => variant.key == groupVariantKey)
      let graphVariantJson : String := Lean.Json.compress (toJson graphVariants)
      let graphVariantOptions : Array Output.Html :=
        graphVariants.map fun variant => {{
          <option value={{variant.key}}>{{variant.label}}</option>
        }}
      let includeMathlibLegend := graphData.graph.any (fun node => node.color == Informal.Graph.statementBorderMathlibColor)
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
      let graphViewSelectId : String :=
        let attrs := s.htmlId id
        match attrs.findSome? fun
            | ("id", value) => some s!"{value}--view"
            | _ => Option.none with
        | some value => value
        | Option.none => fallbackGraphControlId id "--view"
      let graphDirectionSelectId : String :=
        let attrs := s.htmlId id
        match attrs.findSome? fun
            | ("id", value) => some s!"{value}--direction"
            | _ => Option.none with
        | some value => value
        | Option.none => fallbackGraphControlId id "--direction"
      let graphPackInputId : String :=
        let attrs := s.htmlId id
        match attrs.findSome? fun
            | ("id", value) => some s!"{value}--pack"
            | _ => Option.none with
        | some value => value
        | Option.none => fallbackGraphControlId id "--pack"
      let graphLegendPanelId : String :=
        let attrs := s.htmlId id
        match attrs.findSome? fun
            | ("id", value) => some s!"{value}--legend"
            | _ => Option.none with
        | some value => value
        | Option.none => fallbackGraphControlId id "--legend"
      let graphOptionsPanelId : String :=
        let attrs := s.htmlId id
        match attrs.findSome? fun
            | ("id", value) => some s!"{value}--options"
            | _ => Option.none with
        | some value => value
        | Option.none => fallbackGraphControlId id "--options"
      let graphDirectionOptions : Array Output.Html :=
        allGraphDirections.map fun direction =>
          if direction == graphData.options.direction then
            {{ <option value={{direction.rankdir}} selected>{{direction.rankdir}}</option> }}
          else
            {{ <option value={{direction.rankdir}}>{{direction.rankdir}}</option> }}
      let graphPackChecked : Array (String × String) :=
        if graphData.options.pack then #[("checked", "checked")] else #[]
      let graphPackDefault : String := graphPackAttr graphData.options.pack
      let fallbackDot : String :=
        match graphVariants[0]? with
        | some variant => variant.dot
        | Option.none => graphToDot graphData.graph graphData.options resolveHref resolveGroupTitle
      let previewUi := Informal.HoverRender.graphPreviewUi
      let groupHoverUi := Informal.HoverRender.graphGroupPreviewUi
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
            </div>
          </div>
          <div
            class="bp_graph_canvas"
            "data-bp-graph-direction"={{graphData.options.direction.rankdir}}
            "data-bp-graph-pack"={{graphPackDefault}}
          >
            <script type="application/json" class="bp-graph-variants">
              {{.text false s!"{graphVariantJson}"}}
            </script>
            <script type="text/plain" class="dot-source">
              {{.text false s!"{fallbackDot}"}}
            </script>
          </div>
          {{previewUi.store}}
          {{previewUi.panel}}
          {{groupHoverUi.panel}}
        </div>
      }}
  extraCss := withPreviewPanelCssAssets [graphCss]
  extraJs := withPreviewRuntimeJsAssets [] [loadD3Dot]

def buildAll : CoreM (Graph × Array (Name × String)) := do
  reportImportedConflicts
  let env ← getEnv
  let state := informalExt.getState env
  let roots : Array Name := state.data.toArray.map (·.1)
  let graph := Informal.Graph.build state roots (resolveRef? := some)
  return (graph, state.groups.toArray)

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

structure BlueprintGraphConfig where
  direction : Option GraphDirection := none
  pack : Option Bool := none

instance : FromArgs BlueprintGraphConfig Verso.Doc.Elab.PartElabM where
  fromArgs :=
    BlueprintGraphConfig.mk <$>
      .named' `direction true <*>
      .named' `pack true

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

open Verso Doc Elab Syntax in
def mkGraphPart (stx : Syntax) (endPos : String.Pos.Raw) (options : GraphOptions := {}) :
    PartElabM FinishedPart := do
  let titlePreview := "Dependency Graph"
  let titleInlines ← `(inline | "Dependency Graph")
  let expandedTitle ← #[titleInlines].mapM (elabInline ·)
  let metadata : Option (TSyntax `term) := some (← `(term| { number := false }))
  let (graph, groupTitles) ← buildAll
  if verso.blueprint.debug.commands.get (← Lean.getOptions) then
    logInfo m!"Adding {graph.size} nodes"
  let graphData : GraphBlockData := { graph, options, groupTitles }
  let block ← ``(Verso.Doc.Block.other (Informal.Commands.Block.graph $(quote graphData)) #[])
  let subParts := #[]
  pure <| FinishedPart.mk stx expandedTitle titlePreview metadata #[block] subParts endPos

open Verso Doc Elab Syntax PartElabM in
@[part_command Lean.Doc.Syntax.command]
public meta def depGraph : PartCommand
  | stx@`(block|command{blueprint_graph $args*}) => do
    let cfg ← Verso.ArgParse.parseThe BlueprintGraphConfig (← parseArgs args)
    let options ← parseGraphOptions cfg
    let endPos := stx.getTailPos?.get!
    closePartsUntil 1 endPos
    addPart (← mkGraphPart stx endPos options)
  | _ => (Lean.Elab.throwUnsupportedSyntax : PartElabM Unit)

end Informal.Commands
