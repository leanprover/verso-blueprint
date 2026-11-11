/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
module

public import Lean.Data.Lsp
public import Rosetta.Source

public section

/-! Experimental normalization of external LSP results, without genre metadata. -/
namespace Rosetta
open Lean

structure DefinitionTarget where
  uri : String
  range : Lsp.Range
  selectionRange : Lsp.Range
  originSelectionRange? : Option Lsp.Range := none
deriving Inhabited, ToJson, FromJson

/-- Preserve every definition target and both LocationLink ranges. -/
def definitionTargets (result : Json) : Except String (Array DefinitionTarget) := do
  let values ← match result with
    | .null => pure #[]
    | .arr values => pure values
    | .obj _ => pure #[result]
    | _ => throw "invalid definition result"
  values.mapM fun value => do
    if let .ok uri := value.getObjValAs? String "uri" then
      let range ← value.getObjValAs? Lsp.Range "range"
      return { uri, range, selectionRange := range }
    else
      let uri ← value.getObjValAs? String "targetUri"
      let range ← value.getObjValAs? Lsp.Range "targetRange"
      let selectionRange ← value.getObjValAs? Lsp.Range "targetSelectionRange"
      let originSelectionRange? ← value.getObjValAs? (Option Lsp.Range) "originSelectionRange"
      return { uri, range, selectionRange, originSelectionRange? }

structure DiagnosticSnapshot where
  /-- None means the server supplied no version; freshness is unknown. -/
  version? : Option Int
  diagnostics : Array Lsp.Diagnostic
deriving ToJson, FromJson

structure OpenDocument where
  version : Int
  text : String := ""
  diagnostics? : Option DiagnosticSnapshot := none

/-- Only diagnostics for the currently open version are accepted. Unversioned
sets remain explicitly unversioned. Standard LSP replacement semantics apply. -/
def OpenDocument.publish (document : OpenDocument) (params : Lsp.PublishDiagnosticsParams) :
    OpenDocument :=
  if params.version?.any (· != document.version) then document
  else { document with diagnostics? := some {
    version? := params.version?, diagnostics := params.diagnostics } }

structure SemanticSpan where
  range : Lsp.Range
  tokenType : String
  modifiers : Array String
deriving ToJson, FromJson

/-- Decode full, non-overlapping, single-line semantic tokens using the server's
legend and the exact document. Unknown legend indexes and invalid ranges fail
explicitly, without changing the underlying source text. -/
def semanticSpans (source : String) (provider result : Json) :
    Except String (Array SemanticSpan) := do
  let legend ← provider.getObjVal? "legend"
  let types ← legend.getObjValAs? (Array String) "tokenTypes"
  let modifiers ← legend.getObjValAs? (Array String) "tokenModifiers"
  let data ← result.getObjValAs? (Array Nat) "data"
  unless data.size % 5 == 0 do throw "semantic token data is not a sequence of five-tuples"
  let mut line := 0
  let mut character := 0
  let mut previousStop := 0
  let mut spans := #[]
  for index in [:data.size / 5] do
    let offset := index * 5
    let deltaLine := data[offset]!
    line := line + deltaLine
    character := (if deltaLine == 0 then character else 0) + data[offset + 1]!
    let length := data[offset + 2]!
    unless length > 0 do throw "empty semantic token"
    let some tokenType := types[data[offset + 3]!]?
      | throw "semantic token has an invalid legend index"
    let mask := data[offset + 4]!
    unless mask / 2 ^ modifiers.size == 0 do throw "semantic token has unknown modifier bits"
    let range : Lsp.Range := {
      start := ⟨line, character⟩, «end» := ⟨line, character + length⟩ }
    let some (start, stop) := byteRange? source range | throw "invalid semantic token range"
    unless previousStop ≤ start do throw "overlapping semantic tokens"
    previousStop := stop
    spans := spans.push {
      range, tokenType
      modifiers := (modifiers.zipIdx.filter (fun (_, bit) => mask.testBit bit)).map (·.1) }
  return spans

end Rosetta
