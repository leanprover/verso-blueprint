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

/--
Resolved block-level code semantics used by informal block rendering.

This unifies directive hints and inline code payloads (`InlineCodeData`)
for the HTML phase:
- `inline` takes precedence whenever code-block data exists,
- otherwise we fall back to optional external declaration hints.
-/
inductive BlockCodeData where
  /-- Inline/literate code block associated with this label. -/
  | inline (code : InlineCodeData)
  /-- External Lean declarations associated with this label. -/
  | external (decls : Array Data.ExternalRef)
deriving Repr, Inhabited, FromJson, ToJson, Quote

def BlockCodeData.ofExternalRefs (decls : Array Data.ExternalRef) : Option BlockCodeData :=
  if decls.isEmpty then
    none
  else
    some (.external decls)

/-- Resolve inline precedence at render time by combining optional hint + inline payload. -/
def BlockCodeData.ofHintAndInline (hint? : Option BlockCodeData) (inline? : Option InlineCodeData)
    : Option BlockCodeData :=
  match inline? with
  | some code => some (.inline code)
  | Option.none => hint?

def BlockCodeData.inlineData? : BlockCodeData → Option InlineCodeData
  | .inline code => some code
  | _ => Option.none

def BlockCodeData.externalDecls : BlockCodeData → Array Data.ExternalRef
  | .external decls => decls
  | _ => #[]

structure BlockData where
  kind : Data.InProgressKind := .proof
  /-- Optional code hint used for statement blocks (`.proof` always ignores this). -/
  codeData : Option BlockCodeData := none
  /-- Optional original-source provenance attached with directive-local metadata. -/
  sourceRef : Option Source.Ref := none
  label : Data.Label
  /-- Source location result for the user-written label token. -/
  sourceLocation : Data.SourceLocationResult :=
    Data.SourceLocationResult.unavailable "label source location unavailable"
  foldProofBlock : Bool := false
  foldCodeBlock : Bool := false
  parent : Option Data.Parent := none
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
  /-- Structured statement-side use metadata for this labeled block. -/
  statementUses : Array Data.UseRef := #[]
  /-- Structured proof-side use metadata for this labeled block. -/
  proofUses : Array Data.UseRef := #[]
  owner : Option Data.AuthorId := none
  ownerDisplayName : Option String := none
  ownerUrl : Option String := none
  ownerImageUrl : Option String := none
  tags : Array String := #[]
  effort : Option String := none
  priority : Option String := none
  prUrl : Option String := none
  foreignRefs : Array Data.ForeignAttachment := #[]
deriving FromJson, ToJson, Quote

/--
Slim traversal-store payload for Blueprint node metadata.

Unlike `BlockData`, this intentionally excludes `codeData`. Code-specific
render/runtime payloads belong to dedicated traversal indexes rather than the
main semantic node index.
-/
structure StoredBlockData where
  kind : Data.InProgressKind := .proof
  label : Data.Label
  /-- Source location result for the user-written label token. -/
  sourceLocation : Data.SourceLocationResult :=
    Data.SourceLocationResult.unavailable "label source location unavailable"
  parent : Option Data.Parent := none
  count : Nat
  numberingMode : NumberingMode := .sub
  /-- Prefix policy for `numberingMode = .sub`. -/
  subNumberingPrefix : SubNumberingPrefix := .full
  /-- Counter policy for `numberingMode = .sub`. -/
  subNumberingCounter : SubNumberingCounter := .prefix
  partPrefix : Option String := none
  globalCount : Option Nat := none
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
  foreignRefs : Array Data.ForeignAttachment := #[]
deriving FromJson, ToJson, Quote

def BlockData.toStoredData (data : BlockData) : StoredBlockData := {
  kind := data.kind
  label := data.label
  sourceLocation := data.sourceLocation
  parent := data.parent
  count := data.count
  numberingMode := data.numberingMode
  subNumberingPrefix := data.subNumberingPrefix
  subNumberingCounter := data.subNumberingCounter
  partPrefix := data.partPrefix
  globalCount := data.globalCount
  statementUses := data.statementUses
  proofUses := data.proofUses
  owner := data.owner
  ownerDisplayName := data.ownerDisplayName
  ownerUrl := data.ownerUrl
  ownerImageUrl := data.ownerImageUrl
  tags := data.tags
  effort := data.effort
  priority := data.priority
  prUrl := data.prUrl
  foreignRefs := data.foreignRefs
}

def StoredBlockData.toBlockData (data : StoredBlockData)
    (codeData : Option BlockCodeData := none) : BlockData := {
  kind := data.kind
  codeData
  label := data.label
  sourceLocation := data.sourceLocation
  parent := data.parent
  count := data.count
  numberingMode := data.numberingMode
  subNumberingPrefix := data.subNumberingPrefix
  subNumberingCounter := data.subNumberingCounter
  partPrefix := data.partPrefix
  globalCount := data.globalCount
  statementUses := data.statementUses
  proofUses := data.proofUses
  owner := data.owner
  ownerDisplayName := data.ownerDisplayName
  ownerUrl := data.ownerUrl
  ownerImageUrl := data.ownerImageUrl
  tags := data.tags
  effort := data.effort
  priority := data.priority
  prUrl := data.prUrl
  foreignRefs := data.foreignRefs
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
