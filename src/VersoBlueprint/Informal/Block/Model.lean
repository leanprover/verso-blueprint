/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import VersoBlueprint.Data

namespace Informal

open Lean

inductive NumberingMode where
  | sub
  | global
  | local
deriving Repr, Inhabited, BEq, FromJson, ToJson, Quote

def NumberingMode.parse? (raw : String) : Option NumberingMode :=
  match raw.trimAscii.toString.toLower with
  | "sub" | "chapter" | "section" | "subnumber" | "sub-number" => some .sub
  | "global" => some .global
  | "local" => some .local
  | _ => none

register_option verso.blueprint.numbering : String := {
  defValue := "sub"
  descr := "Numbering mode for blueprint informal blocks: `sub` (default; prefix with numbered part path), `global`, or `local`"
}

def numberingMode (opts : Lean.Options) : NumberingMode :=
  match NumberingMode.parse? (verso.blueprint.numbering.get opts) with
  | some mode => mode
  | none => .sub

structure CodeDeclData where
  name : Name
  commandIndex : Nat := 0
  weight : Nat := 1
  provedStatus : Data.ProvedStatus := .proved
deriving Repr, Inhabited, FromJson, ToJson, Quote

def CodeDeclData.ofLiterateDef (d : Data.LiterateDef) : CodeDeclData :=
  {
    name := d.name
    commandIndex := d.commandIndex
    weight := max d.commandLines 1
    provedStatus := d.provedStatus
  }

def CodeDeclData.ofLiterateThm (d : Data.LiterateThm) : CodeDeclData :=
  {
    name := d.name
    commandIndex := d.commandIndex
    weight := max d.commandLines 1
    provedStatus := d.provedStatus
  }

structure InlineCodeData where
  label : Data.Label
  definedDefs : Array CodeDeclData := #[]
  definedTheorems : Array CodeDeclData := #[]
  foldCodeBlock : Bool := false
  foldProofs : Bool := true
deriving Repr, Inhabited, FromJson, ToJson, Quote

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

/-- Projection from environment-level `Data.CodeRef` into JSON-safe block payload hints. -/
def BlockCodeData.ofCodeRefHint (codeRef? : Option Data.CodeRef) : Option BlockCodeData :=
  match codeRef? with
  | some (.external decls) => some (.external decls)
  | _ => none

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
  label : Data.Label
  foldProofBlock : Bool := false
  foldCodeBlock : Bool := false
  parent : Option Data.Parent := none
  count : Nat
  numberingMode : NumberingMode := .sub
  /--
  Top-level rendered part prefix assigned during traversal (for example `3` or `A`).

  This is stored as `String` rather than `Manual.Numbering` because it is a
  render-facing cache: the upstream part numbering may be numeric or alphabetic,
  and all downstream consumers need here is the final display prefix that should
  appear in cross-page references and HTML labels.
  -/
  partPrefix : Option String := none
  /-- Document-order global index assigned during traversal. -/
  globalCount : Option Nat := none
  /-- Statement-side `{uses ...}` dependencies declared for this labeled block. -/
  statementDeps : Array Data.Label := #[]
  /-- Proof-side `{uses ...}` dependencies declared for this labeled block. -/
  proofDeps : Array Data.Label := #[]
  owner : Option Data.AuthorId := none
  ownerDisplayName : Option String := none
  ownerUrl : Option String := none
  ownerImageUrl : Option String := none
  tags : Array String := #[]
  effort : Option String := none
  priority : Option String := none
  prUrl : Option String := none
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
  parent : Option Data.Parent := none
  count : Nat
  numberingMode : NumberingMode := .sub
  partPrefix : Option String := none
  globalCount : Option Nat := none
  statementDeps : Array Data.Label := #[]
  proofDeps : Array Data.Label := #[]
  owner : Option Data.AuthorId := none
  ownerDisplayName : Option String := none
  ownerUrl : Option String := none
  ownerImageUrl : Option String := none
  tags : Array String := #[]
  effort : Option String := none
  priority : Option String := none
  prUrl : Option String := none
deriving FromJson, ToJson, Quote

def BlockData.toStoredData (data : BlockData) : StoredBlockData := {
  kind := data.kind
  label := data.label
  parent := data.parent
  count := data.count
  numberingMode := data.numberingMode
  partPrefix := data.partPrefix
  globalCount := data.globalCount
  statementDeps := data.statementDeps
  proofDeps := data.proofDeps
  owner := data.owner
  ownerDisplayName := data.ownerDisplayName
  ownerUrl := data.ownerUrl
  ownerImageUrl := data.ownerImageUrl
  tags := data.tags
  effort := data.effort
  priority := data.priority
  prUrl := data.prUrl
}

def StoredBlockData.toBlockData (data : StoredBlockData)
    (codeData : Option BlockCodeData := none) : BlockData := {
  kind := data.kind
  codeData
  label := data.label
  parent := data.parent
  count := data.count
  numberingMode := data.numberingMode
  partPrefix := data.partPrefix
  globalCount := data.globalCount
  statementDeps := data.statementDeps
  proofDeps := data.proofDeps
  owner := data.owner
  ownerDisplayName := data.ownerDisplayName
  ownerUrl := data.ownerUrl
  ownerImageUrl := data.ownerImageUrl
  tags := data.tags
  effort := data.effort
  priority := data.priority
  prUrl := data.prUrl
}

end Informal
