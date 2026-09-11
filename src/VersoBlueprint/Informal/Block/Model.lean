/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import VersoBlueprint.Data
import VersoBlueprint.Source.Data

namespace Informal

open Lean

/-- Which broad numbering scheme should informal blocks use? -/
inductive NumberingMode where
  | sub
  | global
  | local
deriving Repr, Inhabited, BEq, FromJson, ToJson, Quote

/-- Which numbered ancestors should appear before the local sub-number? -/
inductive SubNumberingPrefix where
  | full
  | first
deriving Repr, Inhabited, BEq, FromJson, ToJson, Quote

/-- Which counter should be appended after the rendered sub-numbering prefix? -/
inductive SubNumberingCounter where
  | prefix
  | document
deriving Repr, Inhabited, BEq, FromJson, ToJson, Quote

def NumberingMode.parse? (raw : String) : Option NumberingMode :=
  match raw.trimAscii.toString.toLower with
  | "sub" | "chapter" | "section" | "subnumber" | "sub-number" => some .sub
  | "global" => some .global
  | "local" => some .local
  | _ => none

def SubNumberingPrefix.parse? (raw : String) : Option SubNumberingPrefix :=
  match raw.trimAscii.toString.toLower with
  | "full" | "path" | "section" | "sections" => some .full
  | "first" | "top" | "chapter" => some .first
  | _ => none

def SubNumberingCounter.parse? (raw : String) : Option SubNumberingCounter :=
  match raw.trimAscii.toString.toLower with
  | "prefix" | "section" | "sections" | "local" => some .prefix
  | "document" | "global" => some .document
  | _ => none

register_option verso.blueprint.numbering : String := {
  defValue := "sub"
  descr := "Numbering mode for blueprint informal blocks: `sub` (default; prefix according to sub-numbering options), `global`, or `local`"
}

register_option verso.blueprint.subNumberingPrefix : String := {
  defValue := "full"
  descr := "Prefix used by `verso.blueprint.numbering = sub`: `full` (default; full numbered part path) or `first` (first numbered ancestor)"
}

register_option verso.blueprint.subNumberingCounter : String := {
  defValue := "prefix"
  descr := "Counter used by `verso.blueprint.numbering = sub`: `prefix` (default; reset for each rendered prefix) or `document` (document-order count)"
}

def numberingMode (opts : Lean.Options) : NumberingMode :=
  match NumberingMode.parse? (verso.blueprint.numbering.get opts) with
  | some mode => mode
  | none => .sub

def subNumberingPrefix (opts : Lean.Options) : SubNumberingPrefix :=
  match SubNumberingPrefix.parse? (verso.blueprint.subNumberingPrefix.get opts) with
  | some mode => mode
  | none => .full

def subNumberingCounter (opts : Lean.Options) : SubNumberingCounter :=
  match SubNumberingCounter.parse? (verso.blueprint.subNumberingCounter.get opts) with
  | some mode => mode
  | none => .prefix

structure CodeDeclData where
  name : Name
  commandIndex : Nat := 0
  weight : Nat := 1
  provedStatus : Data.ProvedStatus := .proved
  sourceLocation : Data.SourceLocationResult :=
    Data.SourceLocationResult.unavailable "inline Lean declaration source location unavailable"
deriving Repr, Inhabited, FromJson, ToJson, Quote

def CodeDeclData.ofLiterateDef (d : Data.LiterateDef)
    (sourceLocation : Data.SourceLocationResult :=
      Data.SourceLocationResult.unavailable "inline Lean declaration source location unavailable") :
    CodeDeclData :=
  {
    name := d.name
    commandIndex := d.commandIndex
    weight := max d.commandLines 1
    provedStatus := d.provedStatus
    sourceLocation
  }

def CodeDeclData.ofLiterateThm (d : Data.LiterateThm)
    (sourceLocation : Data.SourceLocationResult :=
      Data.SourceLocationResult.unavailable "inline Lean declaration source location unavailable") :
    CodeDeclData :=
  {
    name := d.name
    commandIndex := d.commandIndex
    weight := max d.commandLines 1
    provedStatus := d.provedStatus
    sourceLocation
  }

structure InlineCodeData where
  /-- Source-module and source-position identity of this code block. -/
  blockId : Name
  label : Data.Label
  definedDefs : Array CodeDeclData := #[]
  definedTheorems : Array CodeDeclData := #[]
  foldCodeBlock : Bool := false
  foldProofs : Bool := true
deriving Repr, Inhabited, FromJson, ToJson, Quote

def InlineCodeData.declarations (code : InlineCodeData) : Array CodeDeclData :=
  code.definedDefs ++ code.definedTheorems

/-- The distinct literate blocks associated with one informal label, in document order. -/
abbrev InlineCodeBlocks := Array InlineCodeData

def InlineCodeBlocks.definedDefs (blocks : InlineCodeBlocks) : Array CodeDeclData :=
  blocks.flatMap (·.definedDefs)

def InlineCodeBlocks.definedTheorems (blocks : InlineCodeBlocks) : Array CodeDeclData :=
  blocks.flatMap (·.definedTheorems)

def InlineCodeBlocks.declarations (blocks : InlineCodeBlocks) : Array CodeDeclData :=
  blocks.flatMap (·.declarations)

/-- All Lean associations used by a heading or panel; neither category hides the other. -/
structure BlockCodeData where
  inlineBlocks : InlineCodeBlocks := #[]
  externalDecls : Array Data.ExternalRef := #[]
deriving Repr, Inhabited, FromJson, ToJson, Quote

def BlockCodeData.isEmpty (code : BlockCodeData) : Bool :=
  code.inlineBlocks.isEmpty && code.externalDecls.isEmpty

/-- Omit empty presentation inputs without selecting between association categories. -/
def BlockCodeData.nonempty? (code : BlockCodeData) : Option BlockCodeData :=
  if code.isEmpty then none else some code

/-- Prefer the rendered literate declaration when an external association names the same constant. -/
def BlockCodeData.summaryExternalDecls (code : BlockCodeData) : Array Data.ExternalRef :=
  let names := code.inlineBlocks.declarations.foldl
    (fun (names : NameSet) decl => names.insert decl.name.eraseMacroScopes) {}
  code.externalDecls.filter fun decl => !names.contains decl.canonical.eraseMacroScopes

/-- Shared semantic metadata; occurrence numbering, sources, and folding live separately. -/
structure BlockMetadata where
  /-- Canonical target label: informal label, Lean declaration name, citation label, or external-markup witness label. -/
  label : Data.Label
  /-- Parent/group label for this informal node, if any. -/
  parent : Option Data.Parent := none
  /-- Structured statement use metadata, preserving origin and intent tags. -/
  statementUses : Array Data.UseRef := #[]
  /-- Structured proof use metadata, preserving origin and intent tags. -/
  proofUses : Array Data.UseRef := #[]
  /-- Assigned owner identifier, if any. -/
  owner : Option Data.AuthorId := none
  /-- Resolved display name of the assigned owner, if available. -/
  ownerDisplayName : Option String := none
  /-- Link to the assigned owner, if available. -/
  ownerUrl : Option String := none
  /-- Image URL for the assigned owner, if available. -/
  ownerImageUrl : Option String := none
  /-- Normalized tags attached to this informal node. -/
  tags : Array String := #[]
  /-- Declared effort estimate for this informal node, if any. -/
  effort : Option String := none
  /-- Declared triage priority for this informal node, if any. -/
  priority : Option String := none
  /-- Pull request associated with this informal node, if any. -/
  prUrl : Option String := none
deriving Inhabited, Repr, BEq, FromJson, ToJson, Quote

/-- Source and presentation settings belonging to one document occurrence. -/
structure BlockPresentation where
  /-- Optional original-source provenance attached with directive-local metadata. -/
  sourceRef : Option Source.Ref := none
  /-- Source location result for the user-written label token. -/
  sourceLocation : Data.SourceLocationResult :=
    Data.SourceLocationResult.unavailable "label source location unavailable"
  foldProofBlock : Bool := false
  foldCodeBlock : Bool := false
  count : Nat
  numberingMode : NumberingMode := .sub
  /-- Prefix policy for `numberingMode = .sub`. -/
  subNumberingPrefix : SubNumberingPrefix := .full
  /-- Counter policy for `numberingMode = .sub`. -/
  subNumberingCounter : SubNumberingCounter := .prefix
  /--
  Rendered part prefix assigned during traversal (for example `3`, `A`, or `1.3`).

  This is stored as `String` rather than `Manual.Numbering` because it is a
  render-facing cache: the upstream part numbering may be numeric or alphabetic,
  and all downstream consumers need here is the final display prefix that should
  appear in cross-page references and HTML labels.
  -/
  partPrefix : Option String := none
  /-- Document-order global index assigned during traversal. -/
  globalCount : Option Nat := none
deriving FromJson, ToJson, Quote

/-- A compiled document occurrence: identity and presentation, without copied node semantics. -/
structure BlockOccurrence extends BlockPresentation where
  label : Data.Label
  isProof : Bool := false
deriving FromJson, ToJson, Quote

/--
The shared node record used by capture, traversal, and manifest construction.
Traversal supplies the canonical occurrence; semantic metadata is captured once.
-/
structure RenderNode extends BlockMetadata where
  kind : Data.NodeKind := .lemma
  externalRefs : Array Data.ExternalRef := #[]
  initialCount : Nat := 0
  occurrence : Option BlockOccurrence := none
deriving FromJson, ToJson, Quote

/-- A resolved rendering view, assembled from a node and a document occurrence. -/
structure BlockData extends BlockMetadata, BlockPresentation where
  /-- Mathematical kind, independent of the rendered facet. -/
  kind : Data.NodeKind := .lemma
  isProof : Bool := false
  codeData : Option BlockCodeData := none
deriving FromJson, ToJson, Quote

def RenderNode.ofNode (label : Data.Label) (node : Data.Node)
    (author : Option Data.AuthorInfo := none) : RenderNode := {
  label
  kind := node.kind
  initialCount := node.count
  externalRefs := node.externalRefs
  parent := node.parent
  statementUses := node.statement.map (·.deps) |>.getD #[]
  proofUses := node.proof.map (·.deps) |>.getD #[]
  owner := node.owner
  ownerDisplayName := author.map (·.displayName)
  ownerUrl := author.bind (·.url)
  ownerImageUrl := author.bind (·.imageUrl)
  tags := node.tags
  effort := node.effort
  priority := node.priority
  prUrl := node.prUrl
}

def BlockData.toOccurrence (data : BlockData) : BlockOccurrence := {
  label := data.label
  isProof := data.isProof
  toBlockPresentation := data.toBlockPresentation
}

def RenderNode.resolve (node : RenderNode) (occurrence : BlockOccurrence) : BlockData := {
  toBlockMetadata := node.toBlockMetadata
  kind := node.kind
  isProof := occurrence.isProof
  codeData := ({ externalDecls := node.externalRefs } : BlockCodeData).nonempty?
  toBlockPresentation := occurrence.toBlockPresentation
}

def RenderNode.toBlockData (node : RenderNode) : BlockData :=
  node.resolve (node.occurrence.getD { label := node.label, count := node.initialCount })

/-- Build a synthetic rendering node explicitly, without requiring a Lean environment. -/
def RenderNode.ofBlockData (data : BlockData) : RenderNode := {
  toBlockMetadata := data.toBlockMetadata
  kind := data.kind
  externalRefs := data.codeData.map (·.externalDecls) |>.getD #[]
  initialCount := data.count
  occurrence := some data.toOccurrence
}

/-- Resolved node identity for UI, with a number only when the document has an occurrence. -/
structure NodeDisplay where
  label : Data.Label
  kind : Data.NodeKind
  number? : Option String := none

def NodeDisplay.title (display : NodeDisplay) : String :=
  display.number?.map (fun number => s!"{display.kind} {number}") |>.getD (display.label.toString (escape := false))

def NodeDisplay.proofTitle (display : NodeDisplay) : String :=
  s!"Proof for {display.title}"

def BlockData.statementDeps (data : BlockData) : Array Data.Label :=
  Data.UseRef.labels data.statementUses

def BlockData.proofDeps (data : BlockData) : Array Data.Label :=
  Data.UseRef.labels data.proofUses

end Informal
