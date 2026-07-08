/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Environment
import VersoBlueprint.Informal.Block.Model
import VersoBlueprint.Lib.HtmlId
import VersoBlueprint.Lib.PreviewKey
import VersoBlueprint.PreviewCache
import VersoBlueprint.ProvedStatus

namespace Informal.Graph

open Lean
open Informal Data Environment

/-!
See `doc/DESIGN_RATIONALE.md` for the human-readable graph
status/completion and warning/color mapping rationale.
-/

/-- Upstream-aligned statement-track status (node border). -/
inductive StatementStatus where
  | blocked
  | ready
  | formalized
  | mathlib
deriving Inhabited, Repr, DecidableEq, ToJson, FromJson, Quote

/-- Upstream-aligned background status (proof-track for theorem-like nodes). -/
inductive ProofStatus where
  | none
  | ready
  | incomplete
  | formalized
  | formalizedWithAncestors
deriving Inhabited, Repr, DecidableEq, ToJson, FromJson, Quote

structure WarningFlags where
  unknownRef : Bool := false
  leanOnlyNoStatement : Bool := false
  missingExternalDecl : Bool := false
deriving Inhabited, Repr, DecidableEq, ToJson, FromJson, Quote

structure GraphNode (Ref : Type) where
  label : Name
  displayLabel? : Option String := none
  deps : Array Name
  proofDeps : Array Name := #[]
  parent? : Option Name := none
  shape : String := "box"
  style : String := "filled"
  fillcolor : String
  color : String := "#6b7280"
  penwidth : String := "1.8"
  fontcolor : String := "#111827"
  peripheries : Nat := 1
  gradientangle? : Option String := none
  tooltip? : Option String := none
  ref? : Option Ref := none
deriving Inhabited, Repr, ToJson, FromJson

instance [Quote Ref] : Quote (GraphNode Ref) where
  quote n := Syntax.mkCApp ``GraphNode.mk
    #[
      quote n.label, quote n.displayLabel?, quote n.deps, quote n.proofDeps, quote n.parent?, quote n.shape,
      quote n.style, quote n.fillcolor, quote n.color, quote n.penwidth, quote n.fontcolor, quote n.peripheries,
      quote n.gradientangle?, quote n.tooltip?, quote n.ref?
    ]

abbrev Graph (Ref : Type) := Array (GraphNode Ref)

def GraphNode.displayLabel (node : GraphNode Ref) : String :=
  node.displayLabel?.getD (toString node.label)

/-- Graphviz rank direction used by rendered Blueprint graph layouts. -/
inductive GraphDirection where
  | LR
  | RL
  | TB
  | BT
deriving Inhabited, Repr, BEq, FromJson, ToJson, Quote

/-- DOT `rankdir` token corresponding to a graph direction. -/
def GraphDirection.rankdir : GraphDirection → String
  | .LR => "LR"
  | .RL => "RL"
  | .TB => "TB"
  | .BT => "BT"

/-- Parse user-facing direction aliases accepted by `blueprint_graph`. -/
def GraphDirection.parse? (s : String) : Option GraphDirection :=
  match s.toLower with
  | "lr" | "left-right" | "horizontal" => some .LR
  | "rl" | "right-left" => some .RL
  | "tb" | "top-bottom" | "vertical" => some .TB
  | "bt" | "bottom-top" => some .BT
  | _ => none

/--
Options that affect Graphviz layout for rendered Blueprint graphs.

These options are stored in graph block payloads and serialized with render
variants, so keep changes compatible with existing generated sites.
-/
structure GraphOptions where
  /-- Graphviz rank direction. -/
  direction : GraphDirection := .TB
  /--
  Ask Graphviz to compact disconnected graph components before d3-graphviz fits
  the SVG into the canvas.
  -/
  pack : Bool := false
deriving Inhabited, Repr, BEq, FromJson, ToJson, Quote

private def graphPackAttr (pack : Bool) : String :=
  if pack then "true" else "false"

/--
DOT rendering style knobs shared by page graphs and compact widget graphs.

This is a rendering implementation detail, not part of the public graph-data
schema. It lets all DOT emitters share one header template while preserving
surface-specific sizing.
-/
structure GraphDotStyle where
  /-- Node font size used in the DOT header. -/
  nodeFontSize : String := "10"
  /-- Node margin used in the DOT header. -/
  nodeMargin : String := "0.08,0.04"
  /-- Default node stroke width used in the DOT header. -/
  nodePenwidth : String := "1.8"
  /-- Default edge arrow size used in the DOT header. -/
  edgeArrowsize : String := "0.6"
  /-- Default edge stroke width used in the DOT header. -/
  edgePenwidth : String := "1"
  /-- Whether to emit the Graphviz `pack` attribute. -/
  includePack : Bool := true
deriving Inhabited, BEq

/-- Smaller DOT styling for embedded graph panels. -/
def GraphDotStyle.compact : GraphDotStyle := {
  nodeFontSize := "9"
  nodeMargin := "0.05,0.03"
  nodePenwidth := "1.4"
  edgeArrowsize := "0.5"
  edgePenwidth := "0.9"
  includePack := false
}

/--
One rendered graph view.

The bundled renderer uses variants for the full graph, the synthetic group
overview, and per-group subgraphs. The `selectOnNodeId` and `hoverOnNodeId`
arrays describe variant transitions keyed by SVG node id, and
`previewKeyByNodeId` maps SVG nodes to manifest/cache-backed preview keys.
-/
structure GraphRenderVariant where
  /-- Stable key used by the graph view selector and variant links. -/
  key : String
  /-- Human-readable view label. -/
  label : String
  /-- DOT source for this view. -/
  dot : String
  /-- Initial layout options used to build the DOT source. -/
  options : GraphOptions := {}
  /-- Node ids that switch to another variant when selected. -/
  selectOnNodeId : Array (String × String) := #[]
  /-- Node ids that preview another variant on hover. -/
  hoverOnNodeId : Array (String × String) := #[]
  /-- Node ids that open manifest/cache-backed previews; nodes without such previews are omitted. -/
  previewKeyByNodeId : Array (String × String) := #[]
deriving Inhabited, Repr, ToJson, FromJson, Quote

/-- Direction order used by the bundled graph controls. -/
def allGraphDirections : Array GraphDirection := #[.TB, .LR, .RL, .BT]

/--
Stable visual metadata for a graph node.

This mirrors the render-facing DOT attributes without exposing the generic
`GraphNode Ref` type in cached/public JSON schemas.
-/
structure NodeVisual where
  shape : String := "box"
  style : String := "filled"
  fillcolor : String
  color : String := "#6b7280"
  penwidth : String := "1.8"
  fontcolor : String := "#111827"
  peripheries : Nat := 1
  gradientangle? : Option String := none
  tooltip? : Option String := none
deriving Inhabited, Repr, DecidableEq, ToJson, FromJson, Quote

def NodeVisual.ofGraphNode (node : GraphNode Ref) : NodeVisual := {
  shape := node.shape
  style := node.style
  fillcolor := node.fillcolor
  color := node.color
  penwidth := node.penwidth
  fontcolor := node.fontcolor
  peripheries := node.peripheries
  gradientangle? := node.gradientangle?
  tooltip? := node.tooltip?
}

/-- Axis represented by a dependency edge in the public graph API. -/
inductive EdgeAxis where
  | statement
  | proof
deriving Inhabited, Repr, DecidableEq, ToJson, FromJson, Quote

/-- Public dependency edge data. Edges point from dependency source to dependent target. -/
structure EdgeData where
  source : Name
  target : Name
  axes : Array EdgeAxis := #[]
deriving Inhabited, Repr, DecidableEq, ToJson, FromJson, Quote

/-- Public group/parent metadata for graph consumers. -/
structure GroupData where
  label : Name
  title : String
  declared : Bool := false
  children : Array Name := #[]
deriving Inhabited, Repr, DecidableEq, ToJson, FromJson, Quote

/--
Stable per-node graph data for Lean, manifest, and browser consumers.

Use `statementStatus`, `proofStatus`, and `warnings` for semantics. `visual`
is provided only for renderers that want to reuse Blueprint's current graph
styling without reverse-engineering colors into statuses.
-/
structure NodeData where
  label : Name
  title : String
  displayLabel : String
  kind : Option Data.NodeKind := none
  parent : Option Name := none
  href : Option String := none
  /-- Selected manifest/cache-backed preview key for this node, if available. -/
  previewKey : Option PreviewKey := none
  statementUses : Array Data.UseRef := #[]
  proofUses : Array Data.UseRef := #[]
  statementStatus : StatementStatus := .blocked
  proofStatus : ProofStatus := .none
  warnings : WarningFlags := {}
  visual : NodeVisual
deriving Inhabited, Repr, ToJson, FromJson, Quote

/--
Stable graph data shared by Lean, generated manifests, and browser runtime code.

`schemaVersion` is bumped only for incompatible public-shape changes.
-/
structure GraphData where
  schemaVersion : Nat := 2
  key : String := "graph"
  nodes : Array NodeData := #[]
  edges : Array EdgeData := #[]
  groups : Array GroupData := #[]
  /--
  Precomputed DOT render variants for the bundled browser graph renderer.

  Manifest clients should use these variants instead of re-deriving DOT from
  graph topology in JavaScript. The semantic fields above remain the stable
  data contract for dashboards and audits.
  -/
  variants : Array GraphRenderVariant := #[]
deriving Inhabited, Repr, ToJson, FromJson, Quote

/-- Traversal-time graph cache payload, before href/title finalization. -/
structure CachedGraphData where
  data : GraphData := {}
  options : GraphOptions := {}
deriving Inhabited, Repr, ToJson, FromJson, Quote

def NodeData.toGraphNode (node : NodeData) : GraphNode String := {
  label := node.label
  displayLabel? := some node.displayLabel
  deps := node.statementUses.map (fun useRef => (useRef.label : Name))
  proofDeps := node.proofUses.map (fun useRef => (useRef.label : Name))
  parent? := node.parent
  shape := node.visual.shape
  style := node.visual.style
  fillcolor := node.visual.fillcolor
  color := node.visual.color
  penwidth := node.visual.penwidth
  fontcolor := node.visual.fontcolor
  peripheries := node.visual.peripheries
  gradientangle? := node.visual.gradientangle?
  tooltip? := node.visual.tooltip?
  ref? := node.href
}

def GraphData.toGraph (data : GraphData) : Graph String :=
  data.nodes.map NodeData.toGraphNode

def GraphData.groupTitleMap (data : GraphData) : Lean.NameMap String :=
  data.groups.foldl (init := ({} : Lean.NameMap String)) fun acc group =>
    acc.insert group.label group.title

structure LegendSwatch where
  background : String := "#ffffff"
  borderColor : String := "#6b7280"
  borderWidth : Nat := 1
  borderStyle : String := "solid"
  borderRadius : String := "0.2rem"
deriving Inhabited, Repr, ToJson, FromJson

structure LegendItem where
  label : String
  swatch? : Option LegendSwatch := none
deriving Inhabited, Repr, ToJson, FromJson

structure LegendGroup where
  key : String
  title : String
  summary? : Option String := none
  items : Array LegendItem
deriving Inhabited, Repr, ToJson, FromJson

def LegendSwatch.inlineStyle (swatch : LegendSwatch) : String :=
  String.intercalate "; " [
    s!"background: {swatch.background}",
    s!"border-color: {swatch.borderColor}",
    s!"border-width: {swatch.borderWidth}px",
    s!"border-style: {swatch.borderStyle}",
    s!"border-radius: {swatch.borderRadius}"
  ]

def statementBorderBlockedColor : String := "#f59e0b"
def statementBorderReadyColor : String := "#2563eb"
def statementBorderFormalizedColor : String := "#16a34a"
def statementBorderMathlibColor : String := "#14532d"

def proofBackgroundNeutralColor : String := "#f8fafc"
def proofBackgroundReadyColor : String := "#dbeafe"
def proofBackgroundIncompleteColor : String := "#fef3c7"
def proofBackgroundFormalizedColor : String := "#dcfce7"
def proofBackgroundFormalizedAncColor : String := "#166534"

def definitionBackgroundColor : String := "#ffffff"

def unresolvedFillColor : String := "#fee2e2"
def unresolvedBorderColor : String := "#b91c1c"
def unresolvedFontColor : String := "#7f1d1d"

def statementStatusBlockedText : String := "blocked"
def statementStatusReadyText : String := "ready to formalize"
def statementStatusFormalizedText : String := "formalized"
def statementStatusMathlibText : String := "in Mathlib"

def proofStatusNoneText : String := "not ready"
def proofStatusReadyText : String := "ready to formalize"
def proofStatusIncompleteText : String := "Lean code incomplete"
def proofStatusFormalizedText : String := "locally formalized"
def proofStatusFormalizedAncestorsText : String := "locally formalized + dependencies complete"

def warningLeanOnlyText : String := "Lean code present but informal statement is missing"
def warningMissingExternalText : String := "Associated Lean declaration is missing from the current environment"
def warningHiddenInGroupViewText : String := "Warning markers are not shown individually in Group View"
def edgeMixedText : String := "Thicker solid/dashed: statement + proof deps"
def groupEdgeMixedText : String := "Thicker solid: statement + proof deps"
def graphLegendFullViewNote : String :=
  "Shape shows declaration kind, border shows statement status, fill shows proof status, and edge style separates statement from proof dependencies."

private def legendItem (label : String) (swatch? : Option LegendSwatch := none) : LegendItem :=
  { label, swatch? }

def graphLegendGroups (includeMathlib : Bool := false) : Array LegendGroup :=
  let statementItems :=
    #[
      legendItem "Blocked" (some { borderColor := statementBorderBlockedColor }),
      legendItem "Ready to formalize" (some { borderColor := statementBorderReadyColor }),
      legendItem "Formalized" (some { borderColor := statementBorderFormalizedColor })
    ]
  let statementItems :=
    if includeMathlib then
      statementItems.push (legendItem "In Mathlib" (some { borderColor := statementBorderMathlibColor }))
    else
      statementItems
  #[
    {
      key := "shape"
      title := "Shapes"
      summary? := some "Node outline shows whether the item is definition-like or theorem-like."
      items := #[
        legendItem "Definition" (some { borderRadius := "0.2rem" }),
        legendItem "Theorem / lemma / corollary" (some { borderRadius := "999px" })
      ]
    },
    {
      key := "statement"
      title := "Statement Border"
      summary? := some "Border color tracks whether the statement is blocked, ready, or already formalized."
      items := statementItems
    },
    {
      key := "proof"
      title := "Proof Status"
      summary? := some "Fill color tracks proof readiness independently from statement progress."
      items := #[
        legendItem proofStatusNoneText (some { background := proofBackgroundNeutralColor }),
        legendItem proofStatusReadyText (some { background := proofBackgroundReadyColor }),
        legendItem proofStatusIncompleteText (some { background := proofBackgroundIncompleteColor }),
        legendItem proofStatusFormalizedText (some { background := proofBackgroundFormalizedColor }),
        legendItem proofStatusFormalizedAncestorsText
          (some { background := proofBackgroundFormalizedAncColor, borderColor := statementBorderMathlibColor })
      ]
    },
    {
      key := "warning"
      title := "Warning Markers"
      summary? := some "Border treatments flag missing references, missing declarations, or Lean-only nodes without an informal statement."
      items := #[
        legendItem "Unknown reference"
          (some { background := unresolvedFillColor, borderColor := unresolvedBorderColor }),
        legendItem "Lean code, informal statement missing"
          (some {
            background := definitionBackgroundColor
            borderStyle := "dashed"
          }),
        legendItem "Missing external Lean declaration"
          (some {
            background := definitionBackgroundColor
            borderStyle := "dotted"
          })
      ]
    },
    {
      key := "edge"
      title := "Edges"
      summary? := some "Line style distinguishes statement dependencies from proof-only dependencies."
      items := #[
        legendItem "Solid: statement deps from theorem-like sources",
        legendItem "Dashed: statement deps from box-shaped sources",
        legendItem "Dotted: proof-only deps",
        legendItem edgeMixedText
      ]
    }
  ]

def graphLegendGroupViewNote : String :=
  "Group View uses tab-shaped aggregate group nodes; labels use group titles, colors are averaged over child nodes, and individual warning markers are hidden."

def groupGraphLegendGroups : Array LegendGroup :=
  #[
    {
      key := "group-view"
      title := "Group View"
      summary? := some "Group nodes summarize children instead of showing each declaration separately."
      items := #[
        legendItem "Tab nodes summarize grouped children",
        legendItem "Border/fill colors average child node status colors",
        legendItem warningHiddenInGroupViewText
      ]
    },
    {
      key := "group-edge"
      title := "Edges"
      summary? := some "Grouped edges compress many child edges into one aggregate connection."
      items := #[
        legendItem "Solid: at least one statement dep",
        legendItem "Dotted: proof-only deps",
        legendItem groupEdgeMixedText
      ]
    }
  ]

def statementUses (node : Data.Node) : Array Data.UseRef :=
  (node.statement.map (·.deps)).getD #[]

def proofUses (node : Data.Node) : Array Data.UseRef :=
  (node.proof.map (·.deps)).getD #[]

def statementDeps (node : Data.Node) : Array Name :=
  (statementUses node).map (fun useRef => (useRef.label : Name))

def proofDeps (node : Data.Node) : Array Name :=
  (proofUses node).map (fun useRef => (useRef.label : Name))

def allDeps (node : Data.Node) : Array Name :=
  statementDeps node ++ proofDeps node

structure ExternalCodeStatus where
  isMissing : Name → Bool := fun _ => false
  provedStatus : Name → Data.ProvedStatus := fun _ => .proved

structure CodeHealth where
  hasAssociatedCode : Bool := false
  totalDecls : Nat := 0
  presentDecls : Nat := 0
  missingDecls : Nat := 0
  statementAxisCount : Nat := 0
  proofAxisCount : Nat := 0
  statementBlockCount : Nat := 0
  proofBlockCount : Nat := 0
  anyGapCount : Nat := 0
  hasAxiomLike : Bool := false
deriving Inhabited, Repr

private def statusGapIncrements (status : Data.ProvedStatus) : Nat × Nat × Nat :=
  match status.hasTypeGap, status.hasProofGap with
  | false, false => (0, 0, 0)
  | true, false => (1, 0, 1)
  | false, true => (0, 1, 1)
  | true, true => (1, 1, 1)

private def CodeHealth.bump (health : CodeHealth) (kind : Data.NodeKind) (status : Data.ProvedStatus) : CodeHealth :=
  let (statementAxisInc, proofAxisInc, anyInc) := statusGapIncrements status
  let statementBlockInc := if status.blocksStatementCompletion kind then 1 else 0
  let proofBlockInc := if status.blocksProofCompletion then 1 else 0
  {
    health with
      statementAxisCount := health.statementAxisCount + statementAxisInc
      proofAxisCount := health.proofAxisCount + proofAxisInc
      statementBlockCount := health.statementBlockCount + statementBlockInc
      proofBlockCount := health.proofBlockCount + proofBlockInc
      anyGapCount := health.anyGapCount + anyInc
      hasAxiomLike := health.hasAxiomLike || status.isAxiomLike
  }

private def CodeHealth.merge (left right : CodeHealth) : CodeHealth :=
  {
    hasAssociatedCode := left.hasAssociatedCode || right.hasAssociatedCode
    totalDecls := left.totalDecls + right.totalDecls
    presentDecls := left.presentDecls + right.presentDecls
    missingDecls := left.missingDecls + right.missingDecls
    statementAxisCount := left.statementAxisCount + right.statementAxisCount
    proofAxisCount := left.proofAxisCount + right.proofAxisCount
    statementBlockCount := left.statementBlockCount + right.statementBlockCount
    proofBlockCount := left.proofBlockCount + right.proofBlockCount
    anyGapCount := left.anyGapCount + right.anyGapCount
    hasAxiomLike := left.hasAxiomLike || right.hasAxiomLike
  }

private def codeHealthOfInlineDecls (kind : Data.NodeKind) (statuses : Array Data.ProvedStatus) : CodeHealth :=
  statuses.foldl
      (init := { hasAssociatedCode := true, totalDecls := statuses.size, presentDecls := statuses.size })
      fun health status => health.bump kind status

def codeHealthOfExternalDecls (kind : Data.NodeKind) (external : ExternalCodeStatus) (decls : Array Data.ExternalRef) : CodeHealth :=
  decls.foldl
      (init := { hasAssociatedCode := true, totalDecls := decls.size })
      fun health decl =>
    let missing := !decl.present || external.isMissing decl.canonical
    if missing then
      { health with missingDecls := health.missingDecls + 1 }
    else
      let status := Data.ProvedStatus.mergeConservative decl.provedStatus (external.provedStatus decl.canonical)
      let health := health.bump kind status
      { health with presentDecls := health.presentDecls + 1 }

private def codeHealthOfOneCodeRef (kind : Data.NodeKind) (external : ExternalCodeStatus)
    (codeRef : Data.CodeRef) : CodeHealth :=
  match codeRef with
  | .external decls => codeHealthOfExternalDecls kind external decls
  | .literate code =>
    let statuses :=
      (code.definedDefs.map (·.provedStatus)) ++ (code.definedTheorems.map (·.provedStatus))
    codeHealthOfInlineDecls kind statuses

def codeHealthOfLeanCode (kind : Data.NodeKind) (external : ExternalCodeStatus)
    (leanCode : Array Data.CodeRef) : CodeHealth :=
  leanCode.foldl (init := {}) fun health codeRef =>
    health.merge (codeHealthOfOneCodeRef kind external codeRef)

def codeHealthOfBlockSource (kind : Data.NodeKind) (external : ExternalCodeStatus)
    (source? : Option Informal.BlockCodeData) : CodeHealth :=
  match source? with
  | none => {}
  | some (.external decls) => codeHealthOfExternalDecls kind external decls
  | some (.inline codeData) =>
    let statuses :=
      (codeData.definedDefs.map (·.provedStatus)) ++ (codeData.definedTheorems.map (·.provedStatus))
    codeHealthOfInlineDecls kind statuses

def nodeCodeHealth (external : ExternalCodeStatus) (node : Data.Node) : CodeHealth :=
  codeHealthOfLeanCode node.kind external node.leanCode

def CodeHealth.hasMissingExternalDecls (health : CodeHealth) : Bool :=
  health.missingDecls > 0

def CodeHealth.hasStatementGaps (health : CodeHealth) : Bool :=
  health.statementBlockCount > 0

def CodeHealth.hasProofGaps (health : CodeHealth) : Bool :=
  health.proofBlockCount > 0

def CodeHealth.hasAnyGaps (health : CodeHealth) : Bool :=
  health.anyGapCount > 0

def CodeHealth.localStatementFormalized (health : CodeHealth) : Bool :=
  health.hasAssociatedCode && !health.hasMissingExternalDecls && !health.hasStatementGaps

def CodeHealth.localProofFormalized (health : CodeHealth) : Bool :=
  health.hasAssociatedCode && !health.hasMissingExternalDecls && !health.hasAnyGaps

def CodeHealth.incompleteAssociatedCode (health : CodeHealth) : Bool :=
  health.hasAssociatedCode && !health.hasMissingExternalDecls && health.hasAnyGaps

def CodeHealth.localFormalized (health : CodeHealth) (kind : Data.NodeKind) : Bool :=
  if kind.isTheoremLike then
    health.localProofFormalized
  else if kind == Data.NodeKind.definition then
    health.localStatementFormalized
  else
    false

def nodeExternalDecls (node : Data.Node) : Array Data.ExternalRef :=
  node.externalRefs

def nodeHasAssociatedCode (node : Data.Node) : Bool :=
  node.hasAssociatedCode

def externalDeclMissing (external : ExternalCodeStatus) (decl : Data.ExternalRef) : Bool :=
  !decl.present || external.isMissing decl.canonical

def externalDeclProvedStatus (external : ExternalCodeStatus) (decl : Data.ExternalRef) : Data.ProvedStatus :=
  Data.ProvedStatus.mergeConservative decl.provedStatus (external.provedStatus decl.canonical)

def nodeHasMissingExternalDecls (external : ExternalCodeStatus) (node : Data.Node) : Bool :=
  (nodeCodeHealth external node).hasMissingExternalDecls

def nodeHasStatementSorries (external : ExternalCodeStatus) (node : Data.Node) : Bool :=
  (nodeCodeHealth external node).hasStatementGaps

def nodeHasProofSorries (external : ExternalCodeStatus) (node : Data.Node) : Bool :=
  (nodeCodeHealth external node).hasProofGaps

def nodeHasSorries (external : ExternalCodeStatus) (node : Data.Node) : Bool :=
  (nodeCodeHealth external node).hasAnyGaps

def nodeLocalStatementFormalized (external : ExternalCodeStatus) (node : Data.Node) : Bool :=
  (nodeCodeHealth external node).localStatementFormalized

def nodeLocalProofFormalized (external : ExternalCodeStatus) (node : Data.Node) : Bool :=
  (nodeCodeHealth external node).localProofFormalized

def nodeLocalFormalized (external : ExternalCodeStatus) (node : Data.Node) : Bool :=
  (nodeCodeHealth external node).localFormalized node.kind

def eraseDups (xs : Array Name) : Array Name :=
  xs.foldl (init := #[]) fun acc x => if acc.contains x then acc else acc.push x

/-- Placeholder branch for future `(lean := "...")` Mathlib integration. -/
def nodeInMathlib (_state : Environment.State) (_label : Name) (_node : Data.Node) : Bool :=
  false

inductive DepTraversal where
  | statement
  | proof
  | both
deriving Inhabited, Repr

def depsForTraversal (mode : DepTraversal) (node : Data.Node) : Array Name :=
  match mode with
  | .statement => statementDeps node
  | .proof => proofDeps node
  | .both => allDeps node

partial def depsClosureComplete (external : ExternalCodeStatus) (state : Environment.State) (mode : DepTraversal)
    (roots : Array Name) (visited : NameSet := {}) : Bool :=
  roots.all fun dep =>
    if visited.contains dep then
      true
    else
      match state.data.get? dep with
      | none => false
      | some node =>
        if !nodeLocalFormalized external node then
          false
        else
          let visited := visited.insert dep
          depsClosureComplete external state mode (depsForTraversal mode node) visited

def nodeAncestorsFormalized (external : ExternalCodeStatus) (state : Environment.State) (node : Data.Node) : Bool :=
  depsClosureComplete external state .both (allDeps node)

def statementStatus (external : ExternalCodeStatus) (state : Environment.State) (label : Name)
    (node : Data.Node) : StatementStatus :=
  if nodeInMathlib state label node then
    .mathlib
  else if nodeLocalStatementFormalized external node then
    .formalized
  else if depsClosureComplete external state .statement (statementDeps node) then
    .ready
  else
    .blocked

def proofStatus (external : ExternalCodeStatus) (state : Environment.State) (_label : Name)
    (node : Data.Node) : ProofStatus :=
  let health := nodeCodeHealth external node
  if !node.kind.isTheoremLike then
    if health.localStatementFormalized then
      if nodeAncestorsFormalized external state node then .formalizedWithAncestors else .formalized
    else if health.incompleteAssociatedCode then
      .incomplete
    else if depsClosureComplete external state .statement (statementDeps node) then
      .ready
    else
      .none
  else if health.localProofFormalized then
    if nodeAncestorsFormalized external state node then .formalizedWithAncestors else .formalized
  else if health.incompleteAssociatedCode then
    .incomplete
  else
    let stmtDepsDone := depsClosureComplete external state .statement (statementDeps node)
    let proofDepsDone := depsClosureComplete external state .proof (proofDeps node)
    if stmtDepsDone && proofDepsDone then .ready else .none

def nodeWarnings (external : ExternalCodeStatus) (_state : Environment.State) (_label : Name)
    (node : Data.Node) : WarningFlags :=
  let health := nodeCodeHealth external node
  {
    unknownRef := false
    leanOnlyNoStatement := health.hasAssociatedCode && node.statement.isNone
    missingExternalDecl := health.hasAssociatedCode && health.hasMissingExternalDecls
  }

def statementStatusBorderColor : StatementStatus → String
  | .blocked => statementBorderBlockedColor
  | .ready => statementBorderReadyColor
  | .formalized => statementBorderFormalizedColor
  | .mathlib => statementBorderMathlibColor

def proofStatusFillColor (kind : Data.NodeKind) : ProofStatus → String
  | .none =>
    if kind.isTheoremLike then proofBackgroundNeutralColor else definitionBackgroundColor
  | .ready => proofBackgroundReadyColor
  | .incomplete => proofBackgroundIncompleteColor
  | .formalized => proofBackgroundFormalizedColor
  | .formalizedWithAncestors => proofBackgroundFormalizedAncColor

def proofStatusFontColor : ProofStatus → String
  | .formalizedWithAncestors => "#ffffff"
  | _ => "#111827"

def kindShape (kind : Data.NodeKind) : String :=
  if kind.isTheoremLike then "ellipse" else "box"

def StatementStatus.toText : StatementStatus → String
  | .blocked => statementStatusBlockedText
  | .ready => statementStatusReadyText
  | .formalized => statementStatusFormalizedText
  | .mathlib => statementStatusMathlibText

def ProofStatus.toText : ProofStatus → String
  | .none => proofStatusNoneText
  | .ready => proofStatusReadyText
  | .incomplete => proofStatusIncompleteText
  | .formalized => proofStatusFormalizedText
  | .formalizedWithAncestors => proofStatusFormalizedAncestorsText

def warningTooltipParts (warnings : WarningFlags) : List String :=
  (if warnings.leanOnlyNoStatement then [warningLeanOnlyText] else []) ++
  (if warnings.missingExternalDecl then [warningMissingExternalText] else [])

private def styleTokensForWarnings (warnings : WarningFlags) : Array String :=
  let tokens : Array String := #["filled"]
  let tokens :=
    if warnings.leanOnlyNoStatement then tokens.push "dashed" else tokens
  let tokens :=
    if warnings.missingExternalDecl then tokens.push "dotted" else tokens
  tokens

def mkStyledNode (kind : Data.NodeKind) (label : Name) (deps proofDeps : Array Name)
    (parent? : Option Name)
    (statement : StatementStatus) (proof : ProofStatus) (warnings : WarningFlags)
    (ref? : Option Ref) : GraphNode Ref :=
  if warnings.unknownRef then
    {
      label
      deps
      proofDeps
      parent?
      shape := "box"
      style := "filled"
      fillcolor := unresolvedFillColor
      color := unresolvedBorderColor
      penwidth := "2.2"
      fontcolor := unresolvedFontColor
      peripheries := 1
      gradientangle? := none
      tooltip? := some s!"Unknown reference: {label}"
      ref?
    }
  else
    let shape := kindShape kind
    let baseFill := proofStatusFillColor kind proof
    let styleTokens := styleTokensForWarnings warnings
    let style := String.intercalate "," styleTokens.toList
    let tooltipParts :=
      [s!"Statement: {statement.toText}", s!"Proof: {proof.toText}"] ++ warningTooltipParts warnings
    let tooltip? :=
      if tooltipParts.isEmpty then none else some (String.intercalate " | " tooltipParts)
    {
      label
      deps
      proofDeps
      parent?
      shape
      style
      fillcolor := baseFill
      color := statementStatusBorderColor statement
      penwidth := "2.2"
      fontcolor := proofStatusFontColor proof
      peripheries := 1
      gradientangle? := none
      tooltip?
      ref?
    }

def expandLabels (state : Environment.State) (roots : Array Name) : Array Name :=
  Id.run <| do
    let mut queue : Array Name := eraseDups roots
    let mut enqueued : NameSet := queue.foldl (init := {}) fun acc label => acc.insert label
    let mut seen : NameSet := {}
    let mut idx : Nat := 0
    while idx < queue.size do
      let label := queue[idx]!
      idx := idx + 1
      if seen.contains label then
        continue
      seen := seen.insert label
      match state.data.get? label with
      | none => pure ()
      | some node =>
        for dep in allDeps node do
          if !enqueued.contains dep then
            queue := queue.push dep
            enqueued := enqueued.insert dep
    return queue

def mkNode (external : ExternalCodeStatus) (state : Environment.State)
    (resolveRef? : Name → Option Ref) (label : Name) : GraphNode Ref :=
  match state.data.get? label with
  | some node =>
    let deps := statementDeps node
    let nodeProofDeps := proofDeps node
    let statement := statementStatus external state label node
    let proof := proofStatus external state label node
    let warnings := nodeWarnings external state label node
    let ref? := resolveRef? label
    mkStyledNode node.kind label deps nodeProofDeps node.parent statement proof warnings ref?
  | none =>
    let unresolvedWarnings : WarningFlags := { unknownRef := true }
    mkStyledNode Data.NodeKind.definition label #[] #[] none .blocked .none unresolvedWarnings none

def build (state : Environment.State) (roots : Array Name) (resolveRef? : Name → Option Ref := fun _ => none) :
    Graph Ref :=
  let labels := expandLabels state roots
  let external : ExternalCodeStatus := {}
  labels.map (mkNode external state resolveRef?)

def buildWithExternal (state : Environment.State) (roots : Array Name)
    (external : ExternalCodeStatus) (resolveRef? : Name → Option Ref := fun _ => none) : Graph Ref :=
  let labels := expandLabels state roots
  labels.map (mkNode external state resolveRef?)

private def edgeAxes (isStatement isProof : Bool) : Array EdgeAxis :=
  let axes := #[]
  let axes := if isStatement then axes.push .statement else axes
  if isProof then axes.push .proof else axes

def edgesForNode (node : GraphNode Ref) : Array EdgeData :=
  let stmtDeps := eraseDups node.deps
  let proofDeps := eraseDups node.proofDeps
  let deps := proofDeps.foldl (init := stmtDeps) fun deps dep =>
    if deps.contains dep then deps else deps.push dep
  deps.map fun dep => {
    source := dep
    target := node.label
    axes := edgeAxes (stmtDeps.contains dep) (proofDeps.contains dep)
  }

def edgesForGraph (graph : Graph Ref) : Array EdgeData :=
  let known : NameSet := graph.foldl (init := {}) fun acc node => acc.insert node.label
  graph.foldl (init := #[]) fun edges node =>
    edges ++ (edgesForNode node).filter (fun edge => known.contains edge.source)

def graphParentChildren (graph : Graph Ref) : Lean.NameMap (Array Name) :=
  graph.foldl (init := ({} : Lean.NameMap (Array Name))) fun acc node =>
    match node.parent? with
    | none => acc
    | some parent =>
      let children := acc.getD parent #[]
      acc.insert parent (children.push node.label)

def graphNodeParents (graph : Graph Ref) : Lean.NameMap Name :=
  graph.foldl (init := ({} : Lean.NameMap Name)) fun acc node =>
    match node.parent? with
    | none => acc
    | some parent => acc.insert node.label parent

private def groupTitleMap (groupTitles : Array (Name × String)) : Lean.NameMap String :=
  groupTitles.foldl (init := ({} : Lean.NameMap String)) fun acc (group, title) =>
    acc.insert group title

def groupTitle (groupTitles : Lean.NameMap String) (parent : Name) : String :=
  let title := (groupTitles.getD parent parent.toString).trimAscii.toString
  if title.isEmpty then parent.toString else title

def groupDataForGraph (graph : Graph Ref) (groupTitles : Array (Name × String) := #[]) :
    Array GroupData :=
  let titleMap := groupTitleMap groupTitles
  graphParentChildren graph |>.toArray
    |>.map (fun (parent, children) => {
      label := parent
      title := groupTitle titleMap parent
      declared := titleMap.contains parent
      children
    })
    |>.qsort (fun a b => a.title < b.title)

private def nodeTitle (resolveTitle? : Name → Option String) (label : Name) : String :=
  match resolveTitle? label with
  | some title =>
    let title := title.trimAscii.toString
    if title.isEmpty then label.toString else title
  | none => label.toString

def nodeDataWithExternal
    (external : ExternalCodeStatus)
    (state : Environment.State)
    (resolveHref? : Name → Option String)
    (resolveTitle? : Name → Option String)
    (graphNode : GraphNode String) : NodeData :=
  let label := graphNode.label
  match state.data.get? label with
  | some node =>
    let statement := statementStatus external state label node
    let proof := proofStatus external state label node
    let warnings := nodeWarnings external state label node
    {
      label
      title := nodeTitle resolveTitle? label
      displayLabel := graphNode.displayLabel
      kind := some node.kind
      parent := node.parent
      href := resolveHref? label
      previewKey := PreviewKey.ofString? (PreviewCache.statementKey label)
      statementUses := statementUses node
      proofUses := proofUses node
      statementStatus := statement
      proofStatus := proof
      warnings
      visual := NodeVisual.ofGraphNode graphNode
    }
  | none =>
    {
      label
      title := nodeTitle resolveTitle? label
      displayLabel := graphNode.displayLabel
      kind := none
      parent := none
      href := resolveHref? label
      previewKey := PreviewKey.ofString? (PreviewCache.statementKey label)
      statementUses := #[]
      proofUses := #[]
      statementStatus := .blocked
      proofStatus := .none
      warnings := { unknownRef := true }
      visual := NodeVisual.ofGraphNode graphNode
    }

def buildDataWithExternal
    (state : Environment.State)
    (roots : Array Name)
    (external : ExternalCodeStatus)
    (resolveHref? : Name → Option String := fun _ => none)
    (resolveTitle? : Name → Option String := fun _ => none)
    (groupTitles : Array (Name × String) := #[]) : GraphData :=
  let graph := buildWithExternal state roots external resolveHref?
  {
    nodes := graph.map (nodeDataWithExternal external state resolveHref? resolveTitle?)
    edges := edgesForGraph graph
    groups := groupDataForGraph graph groupTitles
  }

def buildData
    (state : Environment.State)
    (roots : Array Name)
    (resolveHref? : Name → Option String := fun _ => none)
    (resolveTitle? : Name → Option String := fun _ => none)
    (groupTitles : Array (Name × String) := #[]) : GraphData :=
  buildDataWithExternal state roots {} resolveHref? resolveTitle? groupTitles

def escapeDotString (s : String) : String :=
  let s := s.replace "\\" "\\\\"
  let s := s.replace "\"" "\\\""
  let s := s.replace "\n" "\\n"
  s.replace "\r" ""

def dotIndent (n : Nat) : String := String.ofList (List.replicate n ' ')

def graphNodeSvgId (label : Name) : String :=
  Informal.HtmlId.prefixed "bp-node" (toString label)

partial def emitGroupClusterLines (nodeDefs : NameMap String) (groupMembers : NameMap (Array Name))
    (groupChildren : NameMap (Array Name)) (groupIds : NameMap Nat)
    (groupLabel? : Name → Option String) (group : Name) (level fuel : Nat)
    (visited : NameSet) : Array String × NameSet :=
  if fuel == 0 || visited.contains group then
    (#[], visited)
  else
    let visited := visited.insert group
    let pad := dotIndent level
    let pad2 := dotIndent (level + 2)
    let clusterName := s!"cluster_{groupIds.getD group 0}"
    let groupLabel :=
      match groupLabel? group with
      | some label =>
        let label := label.trimAscii.toString
        if label.isEmpty then toString group else label
      | none => toString group
    let openLine := pad ++ s!"subgraph \"{escapeDotString clusterName}\" " ++ "{"
    let clusterMeta : Array String := #[
      s!"{pad2}label=\"{escapeDotString groupLabel}\";",
      s!"{pad2}style=\"rounded,dashed\";",
      s!"{pad2}color=\"#cbd5e1\";",
      s!"{pad2}penwidth=1.2;"
    ]
    let memberLines := (groupMembers.getD group #[]).foldl (init := (#[] : Array String)) fun acc label =>
      match nodeDefs.get? label with
      | some line => acc.push s!"{pad2}{line}"
      | none => acc
    let (childLines, visited) :=
      (groupChildren.getD group #[]).foldl (init := ((#[] : Array String), visited)) fun (acc, visited) child =>
        let (lines, visited) := emitGroupClusterLines nodeDefs groupMembers groupChildren groupIds groupLabel? child (level + 2) (fuel - 1) visited
        (acc ++ lines, visited)
    let closeLine := pad ++ "}"
    ((#[openLine] ++ clusterMeta ++ memberLines ++ childLines).push closeLine, visited)

def Graph.toDot (g : Graph Ref) (header : String)
    (groupLabel? : Option (Name → Option String) := none)
    (refAttrs? : Option (Ref → Option String) := none) : String :=
  let known : NameSet := g.foldl (init := {}) fun acc node => acc.insert node.label
  let defLike : NameSet := g.foldl (init := {}) fun acc node =>
    if node.shape == "box" then acc.insert node.label else acc
  let nodeByLabel : NameMap (GraphNode Ref) :=
    g.foldl (init := ({} : NameMap (GraphNode Ref))) fun acc node => acc.insert node.label node
  let (nodeDefs, groupMembers, edges) :=
    g.foldl
      (init := (({} : NameMap String), ({} : NameMap (Array Name)), (#[] : Array String)))
      fun (nodeDefs, groupMembers, edges) node =>
        let attrs :=
          let base : Array String := #[
            s!"id=\"{escapeDotString (graphNodeSvgId node.label)}\"",
            s!"label=\"{escapeDotString node.displayLabel}\"",
            s!"shape=\"{escapeDotString node.shape}\"",
            s!"style=\"{escapeDotString node.style}\"",
            s!"fillcolor=\"{escapeDotString node.fillcolor}\"",
            s!"color=\"{escapeDotString node.color}\"",
            s!"penwidth=\"{escapeDotString node.penwidth}\"",
            s!"fontcolor=\"{escapeDotString node.fontcolor}\"",
            s!"peripheries={node.peripheries}"
          ]
          let base :=
            match node.gradientangle? with
            | some gradientangle => base.push s!"gradientangle={gradientangle}"
            | none => base
          let base :=
            match node.tooltip? with
            | some tooltip => base.push s!"tooltip=\"{escapeDotString tooltip}\""
            | none => base
          match node.ref?, refAttrs? with
          | some ref, some mkAttrs =>
            match mkAttrs ref with
            | some extra => (String.intercalate ", " base.toList) ++ ", " ++ extra
            | none => String.intercalate ", " base.toList
          | _, _ => String.intercalate ", " base.toList
        let nodeDefs := nodeDefs.insert node.label s!"\"{node.label}\" [{attrs}];"
        let groupMembers :=
          match node.parent? with
          | none => groupMembers
          | some parent =>
            let members := groupMembers.getD parent #[]
            groupMembers.insert parent (members.push node.label)
        let stmtDeps := eraseDups node.deps
        let proofDeps := eraseDups node.proofDeps
        let stmtDepSet : NameSet :=
          stmtDeps.foldl (init := ({} : NameSet)) fun acc dep => acc.insert dep
        let proofDepSet : NameSet :=
          proofDeps.foldl (init := ({} : NameSet)) fun acc dep => acc.insert dep
        let edges := stmtDeps.foldl (init := edges) fun edges dep =>
          if known.contains dep then
            let mixed := proofDepSet.contains dep
            if defLike.contains dep then
              if mixed then
                edges.push s!"  \"{dep}\" -> \"{node.label}\" [style=dashed, penwidth=1.7];"
              else
                edges.push s!"  \"{dep}\" -> \"{node.label}\" [style=dashed, penwidth=1.2];"
            else if mixed then
              edges.push s!"  \"{dep}\" -> \"{node.label}\" [penwidth=1.7];"
            else
              edges.push s!"  \"{dep}\" -> \"{node.label}\";"
          else
            edges
        let edges := proofDeps.foldl (init := edges) fun edges dep =>
          if known.contains dep && !stmtDepSet.contains dep then
            edges.push s!"  \"{dep}\" -> \"{node.label}\" [style=dotted, penwidth=1.2];"
          else
            edges
        (nodeDefs, groupMembers, edges)
  let groupMembers :=
    groupMembers.foldl (init := ({} : NameMap (Array Name))) fun acc parent members =>
      if members.size > 1 then
        acc.insert parent members
      else
        acc
  let groupedLabels : NameSet :=
    groupMembers.foldl (init := ({} : NameSet)) fun acc _parent members =>
      members.foldl (init := acc) fun acc label => acc.insert label
  let groups : Array Name := groupMembers.toArray.map (·.1)
  let groupSet : NameSet := groups.foldl (init := ({} : NameSet)) fun acc group => acc.insert group
  let groupParent : NameMap Name :=
    groups.foldl (init := ({} : NameMap Name)) fun acc group =>
      match nodeByLabel.get? group with
      | some node =>
        match node.parent? with
        | some parent =>
          if groupSet.contains parent then
            acc.insert group parent
          else
            acc
        | none => acc
      | none => acc
  let groupChildren : NameMap (Array Name) :=
    groupParent.toArray.foldl (init := ({} : NameMap (Array Name))) fun acc (child, parent) =>
      let children := acc.getD parent #[]
      if children.contains child then
        acc
      else
        acc.insert parent (children.push child)
  let (groupIds, _nextId) :=
    groups.foldl (init := (({} : NameMap Nat), 0)) fun (acc, i) group =>
      (acc.insert group i, i + 1)
  let rootGroups :=
    let roots := groups.filter (fun group => !(groupParent.contains group))
    if roots.isEmpty then groups else roots
  let groupLabel? := groupLabel?.getD (fun _ => none)
  let (clusterLines, visitedGroups) :=
    rootGroups.foldl (init := ((#[] : Array String), ({} : NameSet))) fun (acc, visited) group =>
      let (lines, visited) := emitGroupClusterLines nodeDefs groupMembers groupChildren groupIds groupLabel? group 2 (groups.size + 1) visited
      (acc ++ lines, visited)
  let (clusterLines, _visitedGroups) :=
    groups.foldl (init := (clusterLines, visitedGroups)) fun (acc, visited) group =>
      if visited.contains group then
        (acc, visited)
      else
        let (lines, visited) := emitGroupClusterLines nodeDefs groupMembers groupChildren groupIds groupLabel? group 2 (groups.size + 1) visited
        (acc ++ lines, visited)
  let ungroupedNodeLines :=
    g.foldl (init := (#[] : Array String)) fun acc node =>
      if groupedLabels.contains node.label then
        acc
      else
        match nodeDefs.get? node.label with
        | some line => acc.push s!"  {line}"
        | none => acc
  let lines := #[header] ++ ungroupedNodeLines ++ clusterLines ++ edges
  let lines := lines.push "}"
  lines.foldl (init := "") fun acc line =>
    if acc.isEmpty then line else acc ++ "\n" ++ line

/-- Common DOT header for rendered Blueprint graphs.

`pack=true` keeps disconnected graph components compact before d3-graphviz fits
the SVG into the canvas. Without it, sparse multi-component graphs can be
placed far from the top of the viewport after variant or direction switches.
-/
def graphDotHeader (options : GraphOptions := {}) (style : GraphDotStyle := {}) : String :=
  "strict digraph \"\" {\n" ++
  s!"    rankdir={options.direction.rankdir};\n" ++
  "    bgcolor=\"white\";\n" ++
  (if style.includePack then s!"    pack={graphPackAttr options.pack};\n" else "") ++
  "    splines=true;\n" ++
  "    nodesep=0.35;\n" ++
  "    ranksep=0.45;\n" ++
  s!"    node [shape=box, style=\"rounded,filled\", fontname=\"Helvetica\", fontsize={style.nodeFontSize}, margin=\"{style.nodeMargin}\", color=\"#6b7280\", penwidth={style.nodePenwidth}];\n" ++
  s!"    edge [color=\"#6b7280\", arrowhead=vee, arrowsize={style.edgeArrowsize}, penwidth={style.edgePenwidth}];\n" ++
  "    graph [fontname=\"Helvetica\"];\n" ++
  "  "

/--
Render a graph to DOT using the shared Blueprint graph header.

Use `graphToDot` for the usual page-graph case where refs are href strings.
`graphToDotWith` is for renderers such as widgets that need a different ref
type or compact DOT styling.
-/
def graphToDotWith (g : Graph Ref) (options : GraphOptions := {}) (style : GraphDotStyle := {})
    (resolveGroupTitle : Name → Option String := fun _ => none)
    (refAttrs? : Option (Ref → Option String) := none) : String :=
  Graph.toDot g (graphDotHeader options style)
    (groupLabel? := some resolveGroupTitle)
    (refAttrs? := refAttrs?)

/-- Render a page graph with string refs interpreted as same-page hrefs. -/
def graphToDot (g : Graph String) (options : GraphOptions := {})
    (resolveGroupTitle : Name → Option String := fun _ => none) : String :=
  graphToDotWith g options {} resolveGroupTitle
    (some fun href => some s!"URL=\"{href}\", target=\"_self\"")

/-- Render finalized graph data to DOT using its href and group-title fields. -/
def GraphData.toDotWith (data : GraphData) (options : GraphOptions := {})
    (style : GraphDotStyle := {}) : String :=
  graphToDotWith data.toGraph options style (fun group => data.groupTitleMap.get? group)
    (some fun href => some s!"URL=\"{href}\", target=\"_self\"")

/-- Stable key for the synthetic group overview variant. -/
def groupVariantKey : String := "group"
private def parentVariantKey (parent : Name) : String := s!"parent:{parent}"

private partial def wrapGraphLabelWords (words : List String) (lineWidth maxLines : Nat)
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

private def wrapGraphLabel (title : String) (lineWidth : Nat := 26) (maxLines : Nat := 3) : String :=
  let words :=
    (title.splitOn " ").foldr (init := ([] : List String)) fun word acc =>
      let word := word.trimAscii.toString
      if word.isEmpty then acc else word :: acc
  match words with
  | [] => title.trimAscii.toString
  | _ =>
    let lines := wrapGraphLabelWords words lineWidth maxLines "" #[]
    String.intercalate "\n" lines.toList

private def graphParentDisplayLabel (groupTitles : Lean.NameMap String) (parent : Name) : String :=
  wrapGraphLabel (groupTitle groupTitles parent)

private def hexNibble? (c : Char) : Option Nat :=
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

private def parseHexByte? (c1 c2 : Char) : Option Nat := do
  let hi ← hexNibble? c1
  let lo ← hexNibble? c2
  return hi * 16 + lo

private def parseHexColor? (s : String) : Option (Nat × Nat × Nat) := do
  let chars :=
    match s.trimAscii.toString.toList with
    | '#' :: rest => rest
    | xs => xs
  match chars with
  | r1 :: r2 :: g1 :: g2 :: b1 :: b2 :: [] =>
    return (← parseHexByte? r1 r2, ← parseHexByte? g1 g2, ← parseHexByte? b1 b2)
  | _ => none

private def hexChar (n : Nat) : Char :=
  if n < 10 then
    Char.ofNat ('0'.toNat + n)
  else
    Char.ofNat ('a'.toNat + (n - 10))

private def byteToHex (n : Nat) : String :=
  let n := n % 256
  let hi := n / 16
  let lo := n % 16
  String.ofList [hexChar hi, hexChar lo]

private def rgbToHex (r g b : Nat) : String :=
  "#" ++ byteToHex r ++ byteToHex g ++ byteToHex b

private def primaryColorToken (s : String) : String :=
  match s.splitOn ":" with
  | token :: _ => token.trimAscii.toString
  | [] => s.trimAscii.toString

private def averageHexColor (colors : Array (Nat × Nat × Nat)) (fallback : String) : String :=
  if colors.isEmpty then
    fallback
  else
    let (sumR, sumG, sumB) := colors.foldl (init := (0, 0, 0)) fun (r, g, b) (r', g', b') =>
      (r + r', g + g', b + b')
    let n := colors.size
    rgbToHex (sumR / n) (sumG / n) (sumB / n)

private def mixedNodeColor (nodes : Array (GraphNode String)) (colorOf : GraphNode String → String)
    (fallback : String) : String :=
  let colors := nodes.foldl (init := (#[] : Array (Nat × Nat × Nat))) fun acc node =>
    match parseHexColor? (primaryColorToken (colorOf node)) with
    | some rgb => acc.push rgb
    | none => acc
  averageHexColor colors fallback

private def fontColorForFill (fillColor : String) : String :=
  match parseHexColor? fillColor with
  | some (r, g, b) =>
    -- Relative luminance approximation, keeps labels readable on dark mixes.
    if (299 * r + 587 * g + 114 * b) < 140000 then "#f8fafc" else "#0f172a"
  | none => "#0f172a"

private def nodeHasAncestorParent (parentMap : Lean.NameMap Name) (label ancestor : Name) : Bool :=
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

private def subgraphForParent (graph : Graph Ref) (parent : Name) : Graph Ref :=
  let parentMap := graphNodeParents graph
  graph.filter fun node =>
    node.label == parent || nodeHasAncestorParent parentMap node.label parent

/--
Build the synthetic group overview graph used by graph view variants.

Each parent with multiple children becomes one aggregate node whose colors are
derived from its children and whose edges summarize cross-group dependencies.
-/
def mkParentOverviewGraph (graph : Graph String) (parents : Array Name)
    (groupTitles : Lean.NameMap String) : Graph String :=
  let parentChildren := graphParentChildren graph
  let nodeByLabel : Lean.NameMap (GraphNode String) :=
    graph.foldl (init := ({} : Lean.NameMap (GraphNode String))) fun acc node =>
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
  let collectParentDeps (depsOf : GraphNode String → Array Name) :=
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
      (parentChildren.getD parent #[]).foldl (init := (#[] : Array (GraphNode String))) fun acc child =>
        match nodeByLabel.get? child with
        | some node => acc.push node
        | none => acc
    let mixedFillColor := mixedNodeColor childNodes (·.fillcolor) "#e2e8f0"
    let mixedBorderColor := mixedNodeColor childNodes (·.color) "#475569"
    let title := groupTitle groupTitles parent
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

/--
Build the render variants for the bundled graph UI.

Graphs without multi-child groups produce just the full graph variant. Grouped
graphs additionally produce a synthetic group overview and one focused subgraph
per parent group.
-/
def mkGraphVariants (graph : Graph String) (options : GraphOptions)
    (groupTitles : Lean.NameMap String)
    (previewKeyForLabel : Name → Option PreviewKey := fun _ => none) :
    Array GraphRenderVariant :=
  let previewKeyByNodeId (graph : Graph String) : Array (String × String) :=
    graph.filterMap fun node =>
      previewKeyForLabel node.label |>.map fun previewKey =>
        (graphNodeSvgId node.label, toString previewKey)
  let resolveGroupTitle : Name → Option String := fun group =>
    groupTitles.get? group
  let parentChildren := graphParentChildren graph
  let parents :=
    parentChildren.toArray
      |>.filter (fun (_, children) => children.size > 1)
      |>.map (·.1)
      |>.qsort (fun a b => groupTitle groupTitles a < groupTitle groupTitles b)
  if parents.isEmpty then
    #[{
      key := "full"
      label := "Full Graph"
      dot := graphToDot graph options resolveGroupTitle
      options
      selectOnNodeId := #[]
      hoverOnNodeId := #[]
      previewKeyByNodeId := previewKeyByNodeId graph
    }]
  else
    let parentVariantRefs := parents.map (fun parent => (graphNodeSvgId parent, parentVariantKey parent))
    let groupVariant : GraphRenderVariant := {
      key := groupVariantKey
      label := "Group View"
      dot := graphToDot (mkParentOverviewGraph graph parents groupTitles) options (fun _ => none)
      options
      selectOnNodeId := parentVariantRefs
      hoverOnNodeId := parentVariantRefs
      previewKeyByNodeId := #[]
    }
    let fullVariant : GraphRenderVariant := {
      key := "full"
      label := "Full Graph"
      dot := graphToDot graph options resolveGroupTitle
      options
      selectOnNodeId := #[]
      hoverOnNodeId := #[]
      previewKeyByNodeId := previewKeyByNodeId graph
    }
    let parentVariants := parents.map fun parent =>
      let parentSubgraph := subgraphForParent graph parent
      let title := groupTitle groupTitles parent
      {
        key := parentVariantKey parent
        label := title
        dot := graphToDot parentSubgraph options resolveGroupTitle
        options
        selectOnNodeId := #[]
        hoverOnNodeId := #[]
        previewKeyByNodeId := previewKeyByNodeId parentSubgraph
      }
    #[fullVariant, groupVariant] ++ parentVariants

/-- Build the bundled renderer's DOT variants from finalized public graph data. -/
def GraphData.renderVariants (data : GraphData) (options : GraphOptions) : Array GraphRenderVariant :=
  let previewKeyForLabel label :=
    match data.nodes.find? (fun node => node.label == label) with
    | some node => node.previewKey
    | none => none
  mkGraphVariants data.toGraph options data.groupTitleMap previewKeyForLabel

end Informal.Graph
