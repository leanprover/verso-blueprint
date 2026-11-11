/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module
public import Rosetta.Client
public section
namespace Rosetta
open Lean

/-- Search results are candidates, not compiler name resolution. -/
def Client.workspaceSymbols (client : Client) (query : String) :
    EIO ClientError (Array Lsp.SymbolInformation) := do
  let result ← client.request "workspace/symbol" <| Json.mkObj [("query", toJson query)]
  if result == .null then return #[]
  let values ← EIO.ofExcept <| result.getArr?.mapError ClientError.protocol
  values.mapM fun value => do
    -- LSP WorkspaceSymbol may defer its location range until resolve.
    let value ← if (value.getObjVal? "location" >>= (·.getObjVal? "range")).isOk then
        pure value
      else client.request "workspaceSymbol/resolve" value
    -- LSP tags are optional; Lean's SymbolInformation decoder expects an array.
    let value := if value.getObjValD "tags" == .null then
        value.setObjVal! "tags" (.arr #[]) else value
    EIO.ofExcept <| (fromJson? value).mapError ClientError.protocol

/-- Ask for definitions at a position in an admitted document version. -/
def Document.definitions (document : Document) (position : Lsp.Position) :
    EIO ClientError (Array DefinitionTarget) := do
  let result ← document.request "textDocument/definition" <| Json.mkObj [
    ("textDocument", Json.mkObj [("uri", toJson document.uri)]), ("position", toJson position)]
  EIO.ofExcept <| (definitionTargets result).mapError ClientError.protocol

/-- Decode the server's semantic token legend against the exact opened text. -/
def Document.semanticTokens (document : Document) (text : String) (range? : Option Lsp.Range := none) :
    EIO ClientError (Array SemanticSpan) := do
  let caps ← document.client.capabilities
  let some provider := (caps.getObjVal? "semanticTokensProvider").toOption
    | throw <| ClientError.unsupported "semantic tokens"
  let useRange := range?.isSome && (provider.getObjValD "range" != .null) &&
    (provider.getObjValD "range" != .bool false)
  unless useRange || (provider.getObjValD "full" != .null &&
      provider.getObjValD "full" != .bool false) do
    throw <| ClientError.unsupported "full-document semantic tokens"
  let method := if useRange then "textDocument/semanticTokens/range" else "textDocument/semanticTokens/full"
  let params := [("textDocument", Json.mkObj [("uri", toJson document.uri)])]
  let params := if useRange then params ++ [("range", toJson range?)] else params
  let result ← document.request method (Json.mkObj params)
  EIO.ofExcept <| (semanticSpans text provider result).mapError ClientError.protocol

/-- Await the latest notification of a given method satisfying a readiness predicate.
The caller owns server-specific readiness semantics; waiting is bounded. -/
def Client.waitForNotification (client : Client) (method : String) (accept : Json → Bool)
    (timeoutMs : Nat := 30000) : EIO ClientError Unit := do
  let deadline := (← IO.monoMsNow) + timeoutMs
  repeat
    let (messages, _) ← client.notifications
    let latest := (messages.filter fun (message : Json) =>
      (message.getObjValAs? String "method").toOption == some method).back?
    if let some message := latest then
      if accept ((message.getObjVal? "params").toOption.getD .null) then return
    if (← IO.monoMsNow) ≥ deadline then throw <| ClientError.deadline method
    IO.sleep 20

private def readSource (uri : String) : EIO ClientError String := do
  let some file := System.Uri.fileUriToPath? uri
    | throw <| ClientError.unsupported s!"reading non-file source URI: {uri}"
  IO.FS.readFile file

/-- Find an exact name/container pair among workspace search candidates, then ask
`definition` at its returned position. Never choose an arbitrary fuzzy match.
`separator` describes the author's reference syntax, not a server query syntax. -/
def Client.workspaceDefinition (client : Client) (languageId reference separator : String) :
    EIO ClientError DefinitionTarget := do
  unless !separator.isEmpty do throw <| ClientError.invalidInput "empty reference separator"
  let parts := reference.splitOn separator
  unless parts.all (!·.isEmpty) do throw <| ClientError.invalidInput "empty reference component"
  let name := parts.getLast!
  let container := String.intercalate separator parts.dropLast
  let candidates ← client.workspaceSymbols name
  let candidates := candidates.filter fun symbol => symbol.name == name &&
    (container.isEmpty || symbol.containerName? == some container)
  let mut locations : Array Lsp.Location := #[]
  for candidate in candidates do
    unless locations.any (fun location => toJson location == toJson candidate.location) do
      locations := locations.push candidate.location
  unless locations.size == 1 do
    throw <| ClientError.invalidInput s!"Expected one workspace symbol for {reference}, found {locations.size}"
  let location := locations[0]!
  let text ← readSource location.uri
  let document ← client.openDocument location.uri languageId text
  let targets ← try document.definitions location.range.start finally document.close
  unless targets.size == 1 do
    throw <| ClientError.invalidInput s!"Expected one definition for {reference}, found {targets.size}"
  return targets[0]!

/-- A lossless source slice with optional LSP semantic coloring. -/
structure HighlightedPiece where
  text : String
  tokenType : String := ""
  modifiers : Array String := #[]
  deriving Inhabited, ToJson, FromJson

structure HighlightedDefinition where
  definition : DefinitionTarget
  languageId : String
  pieces : Array HighlightedPiece
  deriving ToJson, FromJson

/-- Read and highlight the exact range returned by the server. LocationLink
preserves a full definition range; a Location-only server controls its own extent. -/
def Client.highlightDefinition (client : Client) (languageId : String) (target : DefinitionTarget) :
    EIO ClientError HighlightedDefinition := do
  let text ← readSource target.uri
  let some (start, stop) := byteRange? text target.range
    | throw <| ClientError.protocol "invalid definition range"
  let document ← client.openDocument target.uri languageId text
  let spans ← try document.semanticTokens text (some target.range) finally document.close
  let mut pieces := #[]
  let mut offset := start
  for span in spans do
    let some (left, right) := byteRange? text span.range
      | throw <| ClientError.protocol "invalid semantic token range"
    let left := max start left
    let right := min stop right
    if left ≥ right then continue
    if offset < left then
      pieces := pieces.push { text := String.Pos.Raw.extract text ⟨offset⟩ ⟨left⟩ }
    pieces := pieces.push {
      text := String.Pos.Raw.extract text ⟨left⟩ ⟨right⟩
      tokenType := span.tokenType, modifiers := span.modifiers }
    offset := right
  if offset < stop then pieces := pieces.push { text := String.Pos.Raw.extract text ⟨offset⟩ ⟨stop⟩ }
  return { definition := target, languageId, pieces }

/-- Resolve an authored workspace reference and highlight its returned definition. -/
def Client.sourceDefinition (client : Client) (languageId reference separator : String) :
    EIO ClientError HighlightedDefinition := do
  client.highlightDefinition languageId (← client.workspaceDefinition languageId reference separator)

end Rosetta
