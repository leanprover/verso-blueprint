/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Environment
import VersoBlueprint.Informal.Block.Model
import VersoBlueprint.ProvedStatus

namespace Informal.Graph

open Lean
open Informal Data Environment

/-!
See `doc/DESIGN_RATIONALE.md` for the human-readable graph
status/completion and warning/color mapping rationale.
-/

/-- Upstream-compatible statement-track status (node border). -/
inductive StatementStatus where
  | blocked
  | ready
  | formalized
  | mathlib
deriving Inhabited, Repr, DecidableEq, ToJson, FromJson

/-- Upstream-compatible background status (proof-track for theorem-like nodes). -/
inductive ProofStatus where
  | none
  | ready
  | incomplete
  | formalized
  | formalizedWithAncestors
deriving Inhabited, Repr, DecidableEq, ToJson, FromJson

structure WarningFlags where
  unknownRef : Bool := false
  leanOnlyNoStatement : Bool := false
  missingExternalDecl : Bool := false
deriving Inhabited, Repr, ToJson, FromJson

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

def statementDeps (node : Data.Node) : Array Name :=
  ((node.statement.map (·.deps)).getD #[]).map (fun d => (d : Name))

def proofDeps (node : Data.Node) : Array Name :=
  ((node.proof.map (·.deps)).getD #[]).map (fun d => (d : Name))

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

def codeHealthOfCodeRef (kind : Data.NodeKind) (external : ExternalCodeStatus)
    (codeRef? : Option Data.CodeRef) : CodeHealth :=
  match codeRef? with
  | none => {}
  | some (.external decls) => codeHealthOfExternalDecls kind external decls
  | some (.literate code) =>
    let statuses :=
      (code.definedDefs.map (·.provedStatus)) ++ (code.definedTheorems.map (·.provedStatus))
    codeHealthOfInlineDecls kind statuses

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
  codeHealthOfCodeRef node.kind external node.code

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
  match node.code with
  | some (.external decls) => decls
  | _ => #[]

def nodeHasAssociatedCode (node : Data.Node) : Bool :=
  node.code.isSome

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

def escapeDotString (s : String) : String :=
  let s := s.replace "\\" "\\\\"
  let s := s.replace "\"" "\\\""
  let s := s.replace "\n" "\\n"
  s.replace "\r" ""

def dotIndent (n : Nat) : String := String.ofList (List.replicate n ' ')

private def graphSvgIdPiece (c : Char) : String :=
  if c.isAlphanum || c == '-' || c == '_' then
    String.singleton c
  else
    s!"x{c.toNat}x"

def graphNodeSvgId (label : Name) : String :=
  let escaped :=
    (toString label).toList.foldl (init := "") fun acc c =>
      acc ++ graphSvgIdPiece c
  s!"bp-node-{escaped}"

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

end Informal.Graph
