/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Rosetta.Protocol
import Lean

namespace Rosetta
open Lean

/-- An exact authored line start. Kept as scalar fields to quote requests without
introducing global quotation instances for protocol types. -/
structure LineOrigin where
  uri : String
  line : Nat
  character : Nat
deriving Inhabited, BEq, ToJson, FromJson

inductive RequestKind where
  | code
  | reference
deriving Inhabited, BEq, ToJson, FromJson

/-- Inert, serializable author intent. Contains neither process configuration nor
results. `origins` describes the lines of `text`, including a final empty line. -/
structure Request where
  key : String
  context : String
  kind : RequestKind
  text : String
  origins : Array LineOrigin
deriving Inhabited, BEq, ToJson, FromJson

/-- Feature support, operational failure, and a successful empty result are
distinct. The successful value may itself be optional, e.g. a missing hover. -/
inductive Outcome (α : Type) where
  | unsupported
  | failed (message : String)
  | ok (value : α)
deriving ToJson, FromJson

structure Hover where
  format : String
  text : String
deriving ToJson, FromJson

def decodeHover (value : Json) : Except String (Option Hover) := do
  if value == .null then return none
  let contents ← value.getObjVal? "contents"
  match contents with
  | .str text => return some { format := "plaintext", text }
  | .arr items =>
    let texts ← items.mapM fun item => match item with
      | .str text => pure text
      | _ => item.getObjValAs? String "value"
    return some { format := "plaintext", text := String.intercalate "\n\n" texts.toList }
  | _ =>
    let text ← contents.getObjValAs? String "value"
    let format := (contents.getObjValAs? String "kind").toOption.getD "plaintext"
    return some { format, text }

structure QuerySnapshot where
  range : Lsp.Range
  hover : Outcome (Option Hover)
  definitions : Outcome (Array DefinitionTarget)
  /-- Targets within this composed document, identified without renderer URLs. -/
  localTargets : Array String := #[]
deriving ToJson, FromJson

structure AuthoredLocation where
  uri : String
  range : Lsp.Range
deriving ToJson, FromJson

structure MappedDiagnostic where
  diagnostic : Lsp.Diagnostic
  authored : Array AuthoredLocation
deriving ToJson, FromJson

/-- Facts for one request; source text is owned by `request` once. -/
structure RequestSnapshot where
  request : Request
  languageId : String
  tokens : Outcome (Array SemanticSpan)
  diagnostics : Array MappedDiagnostic
  queries : Array QuerySnapshot
deriving ToJson, FromJson

structure ContextObservation where
  key : String
  languageId : String
  /-- Names the evidence collected, not a proof/completeness verdict. -/
  diagnosticCoverage : String
  completion : Json
  generatedDiagnostics : Array Lsp.Diagnostic
deriving ToJson, FromJson

structure Bundle where
  formatRevision : Nat := 1
  requests : Array RequestSnapshot
  contexts : Array ContextObservation
deriving ToJson, FromJson

def Bundle.find (bundle : Bundle) (request : Request) : Except String RequestSnapshot := do
  let some snapshot := bundle.requests.find? (·.request.key == request.key)
    | throw s!"missing analysis for {request.key}"
  unless snapshot.request == request do throw s!"analysis request changed: {request.key}"
  return snapshot

/-- Map each involved text line independently, retaining deindentation gaps. -/
def Request.authoredLocations (request : Request) (range : Lsp.Range) :
    Except String (Array AuthoredLocation) := do
  let some _ := byteRange? request.text range | throw "invalid request-relative diagnostic range"
  let lines := request.text.splitOn "\n" |>.toArray
  let mut locations := #[]
  for line in [range.start.line:range.end.line + 1] do
    let some origin := request.origins[line]? | throw "request lacks an authored line origin"
    let start := if line == range.start.line then range.start.character else 0
    let stop := if line == range.end.line then range.end.character else
      ((lines[line]!).dropSuffix "\r").copy.utf16Length
    if start < stop || range.start == range.end then
      locations := locations.push {
        uri := origin.uri
        range := { start := ⟨origin.line, origin.character + start⟩,
                   «end» := ⟨origin.line, origin.character + stop⟩ } }
  return locations

/-- Validate the portable boundary before replay, including unique ownership and
request-relative ranges. It does not certify the mathematical content. -/
def Bundle.validate (bundle : Bundle) : Except String Unit := do
  unless bundle.formatRevision == 1 do throw "unsupported analysis bundle revision"
  let mut contextKeys : Std.HashSet String := {}
  for context in bundle.contexts do
    if contextKeys.contains context.key then throw s!"duplicate context: {context.key}"
    contextKeys := contextKeys.insert context.key
  let mut requestKeys : Std.HashSet String := {}
  for snapshot in bundle.requests do
    let request := snapshot.request
    if requestKeys.contains request.key then throw s!"duplicate snapshot: {request.key}"
    requestKeys := requestKeys.insert request.key
    unless contextKeys.contains request.context do throw s!"missing context: {request.context}"
    unless request.origins.size == (request.text.splitOn "\n").length do
      throw s!"invalid authored line map: {request.key}"
    if let .ok tokens := snapshot.tokens then
      for token in tokens do
        unless (byteRange? request.text token.range).isSome do throw "invalid saved token range"
    for query in snapshot.queries do
      unless (byteRange? request.text query.range).isSome do throw "invalid saved query range"
      for target in query.localTargets do
        unless bundle.requests.any (fun snapshot => snapshot.request.key == target &&
            snapshot.request.context == request.context) do throw "unknown local definition target"
    for diagnostic in snapshot.diagnostics do
      let authored ← request.authoredLocations diagnostic.diagnostic.range
      unless toJson authored == toJson diagnostic.authored do throw "saved diagnostic source map disagrees"

end Rosetta
