/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Parley.Client
import Parley.Document

namespace Parley
open Lean

structure DiagnosticEvidence where
  coverage : String
  completion : Json := .null
  diagnostics : Array Lsp.Diagnostic

/-- Profiles supply valid project membership, reference syntax, and diagnostic
readiness. No language switch or process defaults live in the analysis core.
The document must already belong to the configured project; it is opened with
an unsaved overlay and is never rewritten on disk by this library. -/
structure ContextProfile where
  key : String
  languageId : String
  client : ClientConfig
  document : System.FilePath
  referencePrefix : String
  referenceSuffix : String
  referenceQueryOffset : String → Nat := fun _ => 0
  collectDiagnostics : Document → IO DiagnosticEvidence

private structure Placement where
  request : Request
  bodyStart : Nat

private def fullRange (text : String) : Lsp.Range := {
  start := ⟨0, 0⟩
  «end» := (FileMap.ofString text).utf8PosToLspPos ⟨text.utf8ByteSize⟩ }

private def prepare (profile : ContextProfile) (requests : Array Request) :
    Except String (Projection × Array Placement) := do
  let mut pieces := #[]
  let mut offset := 0
  let mut placements := #[]
  for request in requests do
    let beforeText := if request.kind == .reference then profile.referencePrefix else ""
    let suffix := if request.kind == .reference then profile.referenceSuffix else ""
    pieces := pieces.push (.generated beforeText)
    offset := offset + beforeText.utf8ByteSize
    placements := placements.push { request, bodyStart := offset }
    pieces := pieces.push (.source {
      uri := request.key, source := request.text, range := fullRange request.text })
    pieces := pieces.push (.generated (suffix ++ "\n"))
    offset := offset + request.text.utf8ByteSize + suffix.utf8ByteSize + 1
  return (← compose pieces, placements)

private def attempt (action : IO α) : IO (Outcome α) := do
  try return .ok (← action)
  catch error => return .failed error.toString

private def supports (capabilities : Json) (key : String) : Bool :=
  match capabilities.getObjVal? key with
  | .error _ | .ok .null | .ok (.bool false) => false
  | _ => true

private def query (document : Document) (caps : Json) (projection : Projection)
    (position : Lsp.Position) (range : Lsp.Range) : IO QuerySnapshot := do
  let uri := document.uri
  let params := Json.mkObj [
    ("textDocument", Json.mkObj [("uri", toJson uri)]), ("position", toJson position)]
  let hover ← if supports caps "hoverProvider" then attempt do
      IO.ofExcept <| decodeHover (← document.call "textDocument/hover" params)
    else pure .unsupported
  let definitions ← if supports caps "definitionProvider" then attempt do
      IO.ofExcept <| definitionTargets (← document.call "textDocument/definition" params)
    else pure .unsupported
  let mut localTargets := #[]
  if let .ok targets := definitions then
    for target in targets do
      if target.uri != uri then continue
      if let .ok mapped := projection.mapRange target.selectionRange then
        for location in mapped.locations do
          unless localTargets.contains location.uri do localTargets := localTargets.push location.uri
  return { range, hover, definitions, localTargets }

private def analyzeContext (profile : ContextProfile) (requests : Array Request) :
    IO (Array RequestSnapshot × ContextObservation) := do
  let (projection, placements) ← IO.ofExcept <| prepare profile requests
  Client.withSession profile.client fun client => do
    let uri := (System.Uri.pathToUri profile.document : String)
    let document ← client.openDocument uri profile.languageId projection.text
    let evidence ← profile.collectDiagnostics document
    let caps ← client.capabilities
    let tokens ← match caps.getObjVal? "semanticTokensProvider" with
      | .ok provider =>
        if supports provider "full" then attempt do
          let raw ← document.call "textDocument/semanticTokens/full" <|
            Json.mkObj [("textDocument", Json.mkObj [("uri", toJson uri)])]
          IO.ofExcept <| semanticSpans projection.text provider raw
        else pure .unsupported
      | .error _ => pure .unsupported
    let mut snapshots := #[]
    let mut generatedDiagnostics := #[]
    let mut mappedDiagnostics : Array (String × MappedDiagnostic) := #[]
    for diagnostic in evidence.diagnostics do
      let mapped ← IO.ofExcept <| projection.mapRange diagnostic.range
      if mapped.containsGenerated || mapped.locations.isEmpty then
        generatedDiagnostics := generatedDiagnostics.push diagnostic
      for location in mapped.locations do
        let some request := requests.find? (·.key == location.uri)
          | throw <| IO.userError "projection contains an unknown request"
        mappedDiagnostics := mappedDiagnostics.push (request.key, {
          diagnostic := { diagnostic with range := location.range }
          authored := ← IO.ofExcept <| request.authoredLocations location.range })
    let fileMap := FileMap.ofString projection.text
    for placement in placements do
      let request := placement.request
      let mut spans := #[]
      if let .ok tokens := tokens then
        for token in tokens do
          let mapped ← IO.ofExcept <| projection.mapRange token.range
          if mapped.containsGenerated then continue
          for location in mapped.locations do
            if location.uri == request.key then
              spans := spans.push { token with range := location.range }
      let localTokens := match tokens with
        | .ok _ => Outcome.ok spans
        | .unsupported => .unsupported
        | .failed message => .failed message
      let mut queries := #[]
      if request.kind == .reference then
        let offset := profile.referenceQueryOffset request.text
        unless offset < request.text.utf8ByteSize do
          throw <| IO.userError "reference query offset is outside its text"
        let position := fileMap.utf8PosToLspPos ⟨placement.bodyStart + offset⟩
        queries := queries.push (← query document caps projection position (fullRange request.text))
      else
        -- Bound eager hover/navigation work. No token support means plain code,
        -- while explicit reference queries continue to work independently.
        for token in spans do
          unless #["function", "method", "variable", "parameter", "type", "namespace"].contains token.tokenType do
            continue
          if queries.size ≥ 32 then break
          let some (start, _) := byteRange? request.text token.range
            | throw <| IO.userError "invalid projected token"
          let position := fileMap.utf8PosToLspPos ⟨placement.bodyStart + start⟩
          queries := queries.push (← query document caps projection position token.range)
      snapshots := snapshots.push {
        request, languageId := profile.languageId, tokens := localTokens, queries
        diagnostics := (mappedDiagnostics.filter (·.1 == request.key)).map (·.2) }
    return (snapshots, {
      key := profile.key, languageId := profile.languageId,
      diagnosticCoverage := evidence.coverage, completion := evidence.completion, generatedDiagnostics })

/-- Analyze a complete plan once at the generator boundary. Duplicate identical
requests are shared; conflicting identities and unregistered contexts fail.
This function has no persistent result cache. -/
def analyze (profiles : Array ContextProfile) (requests : Array Request) : IO Bundle := do
  let mut unique := #[]
  for request in requests do
    if let some previous := unique.find? (fun previous : Request => previous.key == request.key) then
      unless previous == request do throw <| IO.userError s!"conflicting request identity: {request.key}"
    else unique := unique.push request
  let mut contexts : Array String := #[]
  for request in unique do
    unless contexts.contains request.context do contexts := contexts.push request.context
  let mut bundle : Bundle := { requests := #[], contexts := #[] }
  for context in contexts do
    let profilesForContext := profiles.filter (·.key == context)
    unless profilesForContext.size == 1 do throw <| IO.userError s!"expected one profile for context {context}"
    let some profile := profilesForContext[0]? | throw <| IO.userError "missing context profile"
    let (snapshots, observation) ← analyzeContext profile (unique.filter (·.context == context))
    bundle := { requests := bundle.requests ++ snapshots, contexts := bundle.contexts.push observation }
  IO.ofExcept bundle.validate
  return bundle

end Parley
