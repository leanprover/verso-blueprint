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
  statementUses : Array Data.UseRef := #[]
  proofUses : Array Data.UseRef := #[]
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

/--
Resolved block-level code semantics used by informal block rendering.

This unifies directive hints and inline code payloads (`InlineCodeData`)
for the HTML phase:
- `inline` takes precedence whenever code-block data exists,
- otherwise we fall back to optional external declaration hints.
-/
inductive BlockCodeData where
  /-- Distinct inline/literate code blocks associated with this label. -/
  | inline (blocks : InlineCodeBlocks)
  /-- External Lean declarations associated with this label. -/
  | external (decls : Array Data.ExternalRef)
deriving Repr, Inhabited, FromJson, ToJson, Quote

def BlockCodeData.ofExternalRefs (decls : Array Data.ExternalRef) : Option BlockCodeData :=
  if decls.isEmpty then
    none
  else
    some (.external decls)

/-- Prefer rendered literate blocks over an optional external-code hint. -/
def BlockCodeData.ofHintAndInline (hint? : Option BlockCodeData) (blocks : InlineCodeBlocks)
    : Option BlockCodeData :=
  if blocks.isEmpty then hint? else some (.inline blocks)

def BlockCodeData.inlineData? : BlockCodeData → Option InlineCodeBlocks
  | .inline code => some code
  | _ => Option.none

def BlockCodeData.externalDecls : BlockCodeData → Array Data.ExternalRef
  | .external decls => decls
  | _ => #[]

/-- Shared semantic metadata; occurrence numbering, sources, and folding live separately. -/
structure BlockMetadata where
  label : Data.Label
  parent : Option Data.Parent := none
  statementUses : Array Data.UseRef := #[]
  proofUses : Array Data.UseRef := #[]
  owner : Option Data.AuthorId := none
  ownerDisplayName : Option String := none
  ownerUrl : Option String := none
  ownerImageUrl : Option String := none
  tags : Array String := #[]
  effort : Option String := none
  priority : Option String := none
  prUrl : Option String := none
deriving BEq, FromJson, ToJson, Quote

/-- Runtime semantic node projection, without document occurrence settings. -/
structure NodeSnapshot extends BlockMetadata where
  kind : Data.NodeKind := .lemma
  externalRefs : Array Data.ExternalRef := #[]
  /-- Initial numbering fallback for references without a traversed occurrence. -/
  initialCount : Nat := 0
deriving FromJson, ToJson, Quote

structure BlockData extends BlockMetadata where
  kind : Data.InProgressKind := .proof
  /-- Optional code hint used for statement blocks (`.proof` always ignores this). -/
  codeData : Option BlockCodeData := none
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

/-- Project the assembled node's semantic fields into the renderer's block representation. -/
def NodeSnapshot.ofNode (label : Data.Label) (node : Data.Node)
    (author : Option Data.AuthorInfo := none) : NodeSnapshot := {
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

def NodeSnapshot.toBlockData (node : NodeSnapshot) : BlockData := {
  toBlockMetadata := node.toBlockMetadata
  kind := .statement node.kind
  codeData := BlockCodeData.ofExternalRefs node.externalRefs
  count := node.initialCount
}

def BlockData.ofNode (label : Data.Label) (node : Data.Node)
    (author : Option Data.AuthorInfo := none) : BlockData :=
  (NodeSnapshot.ofNode label node author).toBlockData

/-- Refresh semantics while retaining this occurrence's facet, source, and numbering. -/
def BlockData.withSemanticData (data : BlockData) (semantic : NodeSnapshot) : BlockData := {
  data with
  toBlockMetadata := semantic.toBlockMetadata
  kind := match data.kind with | .proof => .proof | .statement _ => .statement semantic.kind
  codeData := match data.kind with
    | .proof => none
    | .statement _ => BlockCodeData.ofExternalRefs semantic.externalRefs
}

/--
Slim traversal-store payload for Blueprint node metadata.

Unlike `BlockData`, this intentionally excludes `codeData`. Code-specific
render/runtime payloads belong to dedicated traversal indexes rather than the
main semantic node index.
-/
structure StoredBlockData extends BlockMetadata where
  kind : Data.InProgressKind := .proof
  /-- Source location result for the user-written label token. -/
  sourceLocation : Data.SourceLocationResult :=
    Data.SourceLocationResult.unavailable "label source location unavailable"
  count : Nat
  numberingMode : NumberingMode := .sub
  /-- Prefix policy for `numberingMode = .sub`. -/
  subNumberingPrefix : SubNumberingPrefix := .full
  /-- Counter policy for `numberingMode = .sub`. -/
  subNumberingCounter : SubNumberingCounter := .prefix
  partPrefix : Option String := none
  globalCount : Option Nat := none
deriving FromJson, ToJson, Quote

def BlockData.toStoredData (data : BlockData) : StoredBlockData := {
  toBlockMetadata := data.toBlockMetadata
  kind := data.kind
  sourceLocation := data.sourceLocation
  count := data.count
  numberingMode := data.numberingMode
  subNumberingPrefix := data.subNumberingPrefix
  subNumberingCounter := data.subNumberingCounter
  partPrefix := data.partPrefix
  globalCount := data.globalCount
}

def StoredBlockData.toBlockData (data : StoredBlockData)
    (codeData : Option BlockCodeData := none) : BlockData := {
  toBlockMetadata := data.toBlockMetadata
  kind := data.kind
  codeData
  sourceLocation := data.sourceLocation
  count := data.count
  numberingMode := data.numberingMode
  subNumberingPrefix := data.subNumberingPrefix
  subNumberingCounter := data.subNumberingCounter
  partPrefix := data.partPrefix
  globalCount := data.globalCount
}

def BlockData.statementDeps (data : BlockData) : Array Data.Label :=
  Data.UseRef.labels data.statementUses

def BlockData.proofDeps (data : BlockData) : Array Data.Label :=
  Data.UseRef.labels data.proofUses

def StoredBlockData.statementDeps (data : StoredBlockData) : Array Data.Label :=
  Data.UseRef.labels data.statementUses

def StoredBlockData.proofDeps (data : StoredBlockData) : Array Data.Label :=
  Data.UseRef.labels data.proofUses

end Informal
