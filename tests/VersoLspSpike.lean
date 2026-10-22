/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoLsp.Client
import VersoLsp.Source

open Lean VersoLsp

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def range (sl sc el ec : Nat) : Lsp.Range :=
  { start := ⟨sl, sc⟩, «end» := ⟨el, ec⟩ }

private def pureChecks : IO Unit := do
  let source := "😀alpha\r\n  βeta\n"
  check (byteOffset? source ⟨0, 1⟩ == none) "accepted half a surrogate pair"
  check (byteOffset? source ⟨0, 7⟩ == some 9) "incorrect UTF-16 end of line"
  check (byteOffset? source ⟨0, 8⟩ == none) "accepted CRLF as line content"
  check (byteOffset? source ⟨8, 0⟩ == none) "accepted nonexistent line"
  check (byteRange? source (range 1 2 0 0) == none) "accepted reversed range"
  let projection ← IO.ofExcept <| compose #[
    .generated "//\n", .source { uri := "source", source, range := range 0 0 0 7 },
    .generated "\n", .source { uri := "source-two", source, range := range 1 2 1 6 },
    .generated "\n}" ]
  check (projection.text == "//\n😀alpha\nβeta\n}") "projection changed source text"
  let mapped ← IO.ofExcept <| projection.mapRange (range 1 2 1 7)
  check (mapped.locations.size == 1 && !mapped.containsGenerated &&
    mapped.locations[0]!.range == range 0 2 0 7) "incorrect mapped source range"
  let cross ← IO.ofExcept <| projection.mapRange (range 1 6 2 2)
  check (cross.locations.size == 2 && cross.containsGenerated &&
    cross.locations[1]!.range == range 1 2 1 4 && cross.locations[1]!.uri == "source-two")
    "cross-piece mapping lost provenance"
  let point ← IO.ofExcept <| projection.mapRange (range 2 0 2 0)
  check (point.locations.size == 1 && point.locations[0]!.range == range 1 2 1 2)
    "empty range chose the preceding piece"
  check (!(projection.mapRange (range 1 1 1 2)).isOk) "mapped an invalid surrogate position"
  let empty ← IO.ofExcept <| compose #[.source {
    uri := "empty-source", source := "", range := range 0 0 0 0 }]
  let emptyMapped ← IO.ofExcept <| empty.mapRange (range 0 0 0 0)
  check (emptyMapped.locations.size == 1 && emptyMapped.locations[0]!.uri == "empty-source")
    "empty authored fragment lost its source identity"
  let targetRange := range 1 0 3 0
  let selection := range 1 4 1 8
  let targets ← IO.ofExcept <| definitionTargets <| .arr #[
    Json.mkObj [("uri", "file:///one"), ("range", toJson selection)],
    Json.mkObj [("targetUri", "file:///two"), ("targetRange", toJson targetRange),
      ("targetSelectionRange", toJson selection)]]
  check (targets.size == 2 && targets[1]!.range == targetRange &&
    targets[1]!.selectionRange == selection) "definition targets lost information"
  let provider := Json.mkObj [("legend", Json.mkObj [
    ("tokenTypes", toJson #["function"]), ("tokenModifiers", toJson #["declaration"])])]
  let validTokens := Json.mkObj [("data", toJson #[0, 2, 5, 0, 1])]
  let spans ← IO.ofExcept <| semanticSpans source provider validTokens
  check (spans.size == 1) "valid Unicode semantic token was rejected"
  for data in #[#[0, 1, 1, 0, 0], #[0, 2, 1, 9, 0], #[0, 2, 1, 0, 2], #[0, 2]] do
    check (!(semanticSpans source provider (Json.mkObj [("data", toJson data)])).isOk)
      "invalid semantic token was accepted"

private def mockChecks (server : String) : IO Unit := do
  let mut chattyElapsed := 0
  let client ← Client.start { command := "python3", args := #[server], root := "." }
  try
    let uri := "file:///mock"
    client.openDocument uri "third-language" "x"
    discard <| client.call "test/barrier" .null
    let some diagnostic ← client.diagnostics uri | throw <| IO.userError "missing diagnostics"
    check (diagnostic.version? == some 1 && diagnostic.diagnostics.isEmpty)
      "diagnostics were appended, or stale diagnostics accepted"
    client.changeDocument uri "y"
    discard <| client.call "test/barrier" .null
    let some diagnostic ← client.diagnostics uri | throw <| IO.userError "missing changed diagnostics"
    check (diagnostic.version? == some 2 && diagnostic.diagnostics.size == 1 &&
      diagnostic.diagnostics[0]!.message == "current warning") "incorrect edited diagnostics"
    discard <| client.call "test/unversioned" (Json.mkObj [("uri", toJson uri)])
    let some unversioned ← client.diagnostics uri | throw <| IO.userError "missing unversioned diagnostics"
    check (unversioned.version?.isNone) "invented a version for unversioned diagnostics"
    let error ← client.request "test/error" .null
    check ((error.getObjVal? "error" >>= (·.getObjValAs? Int "code")).toOption == some (-32097))
      "lost a server-specific error code"
    check ((← client.call "test/client-request" .null) == toJson true)
      "unsupported server request was acknowledged as successful"
    let first ← IO.asTask (client.call "test/first" .null) .dedicated
    let heldDeadline := (← IO.monoMsNow) + 2000
    repeat
      let (notifications, _) ← client.notifications
      if notifications.any (fun message =>
          (message.getObjValAs? String "method").toOption == some "test/held") then break
      check ((← IO.monoMsNow) < heldDeadline) "first request was not admitted"
      IO.sleep 2
    let second ← client.call "test/second" .null
    let first ← IO.ofExcept first.get
    check (first == toJson "first" && second == toJson "second") "responses were routed incorrectly"
    let before ← IO.monoMsNow
    let timedOut ← try
      discard <| client.call "test/chatter" .null 100
      pure false
    catch error => pure <| error.toString.contains "deadline exceeded"
    let elapsed := (← IO.monoMsNow) - before
    chattyElapsed := elapsed
    check (timedOut && elapsed < 1500) s!"chatty server defeated deadline ({elapsed}ms)"
    let cancel ← IO.mkRef false
    let task ← IO.asTask (client.request "test/chatter" .null 5000 cancel.get) .dedicated
    IO.sleep 30
    cancel.set true
    check (!(← IO.wait task).isOk) "explicit cancellation did not interrupt request"
    check ((← client.call "test/barrier" .null) == toJson true) "late response contaminated next request"
  finally
    check (← client.close) "mock process was not reaped"
  let dying ← Client.start { command := "python3", args := #[server], root := "." }
  let dead ← try
    discard <| dying.call "test/die" .null
    pure false
  catch _ => pure true
  check dead "server death was not observed"
  check (← dying.close) "dead server was not reaped"
  let rejected ← try
    let wrong ← Client.start {
      command := "python3", args := #[server], root := "."
      initializationOptions := Json.mkObj [("mode", "wrong-encoding")] }
    discard <| wrong.close
    pure false
  catch error => pure <| error.toString.contains "unsupported position encoding"
  check rejected "incompatible position encoding was accepted"
  let reluctant ← Client.start {
    command := "python3", args := #[server], root := "."
    initializationOptions := Json.mkObj [("mode", "ignore-shutdown")] }
  let before ← IO.monoMsNow
  check (← reluctant.close) "server ignoring shutdown was not terminated and reaped"
  check ((← IO.monoMsNow) - before < 3000) "forced cleanup exceeded its deadline"
  IO.println <| (Json.mkObj [("mock", "passed"), ("chattyDeadlineMs", toJson chattyElapsed)]).compress

private def queryParams (uri : String) (line character : Nat) : Json := Json.mkObj [
  ("textDocument", Json.mkObj [("uri", toJson uri)]),
  ("position", toJson (⟨line, character⟩ : Lsp.Position))]

private def rocqDocument (client : Client) (uri : String) (version : Nat) : IO Json :=
  client.call "coq/getDocument" <| Json.mkObj [("textDocument", Json.mkObj [
    ("uri", toJson uri), ("version", toJson version)])]

private def pushDiagnostics (client : Client) (uri : String) (version : Int) :
    IO (Array Lsp.Diagnostic) := do
  let deadline := (← IO.monoMsNow) + 3000
  repeat
    if let some snapshot ← client.diagnostics uri then
      if snapshot.version? == some version then return snapshot.diagnostics
    check ((← IO.monoMsNow) < deadline) "missing current-version push diagnostics"
    IO.sleep 2
  throw <| IO.userError "unreachable diagnostics loop"

private def pullDiagnostics (client : Client) (uri : String) : IO (Array Lsp.Diagnostic) := do
  let report ← client.call "textDocument/diagnostic" <| Json.mkObj [
    ("textDocument", Json.mkObj [("uri", toJson uri)])]
  IO.ofExcept <| report.getObjValAs? (Array Lsp.Diagnostic) "items"

private def probe (language command root : String) : IO Unit := do
  let root ← IO.FS.realPath root
  let file := root / if language == "rust" then "src/lib.rs" else "Probe.v"
  let text ← IO.FS.readFile file
  let uri := (System.Uri.pathToUri file : String)
  let client ← Client.start {
    command, root, timeoutMs := 15000
    initializationOptions := if language == "rust" then
      Json.mkObj [("checkOnSave", toJson false), ("cargo", Json.mkObj [("buildScripts", Json.mkObj [("enable", toJson false)])]),
        ("procMacro", Json.mkObj [("enable", toJson false)])]
    else Json.mkObj [("check_only_on_request", toJson false)] }
  try
    client.openDocument uri (if language == "rust" then "rust" else "coq") text
    -- Each bounded query is retried only for transient startup evidence in this
    -- experiment. The library itself has no success-by-retry policy.
    let (line, character) := if language == "rust" then (7, 32) else (6, 7)
    let mut result := Json.null
    let mut targets := #[]
    for _ in [:20] do
      try
        result ← client.call "textDocument/definition" (queryParams uri line character) 3000
        targets ← IO.ofExcept <| definitionTargets result
      catch _ => pure ()
      if !targets.isEmpty then break
      IO.sleep 100
    let hover ← client.call "textDocument/hover" (queryParams uri line character)
    let (blockLine, blockCharacter) := if language == "rust" then (4, 36) else (2, 20)
    let blockDefinition ← client.call "textDocument/definition" (queryParams uri blockLine blockCharacter)
    let blockTargets ← IO.ofExcept <| definitionTargets blockDefinition
    check (targets.any fun target => blockTargets.any fun block =>
      target.uri == block.uri && target.selectionRange == block.selectionRange)
      "block and named reference did not resolve to the same declaration"
    let caps ← client.capabilities
    let mut spans : Array SemanticSpan := #[]
    if let .ok provider := caps.getObjVal? "semanticTokensProvider" then
      let tokens ← client.call "textDocument/semanticTokens/full" <| Json.mkObj [
        ("textDocument", Json.mkObj [("uri", toJson uri)])]
      spans ← IO.ofExcept <| semanticSpans text provider tokens
      check (!spans.isEmpty) "server advertised semantic tokens but returned no spans"
    let mut completion := Json.null
    if language == "rocq" then completion ← rocqDocument client uri 1
    let baselineDiagnostics ← if language == "rust" then pullDiagnostics client uri
      else pushDiagnostics client uri 1
    check (!(baselineDiagnostics.any (·.severity? == some .error))) "valid authored block has errors"

    -- Analyze an unsaved invalid fragment in the real project. The prefix is
    -- generated context; only the fragment has an authored-source location.
    let invalid := if language == "rust" then "fn invalid( {\n"
      else "Check missing_name.\n"
    let invalidRange : Lsp.Range := {
      start := ⟨0, 0⟩
      «end» := (FileMap.ofString invalid).utf8PosToLspPos ⟨invalid.utf8ByteSize⟩ }
    let projection ← IO.ofExcept <| compose #[.generated (text ++ "\n"),
      .source { uri := "verso-source://spike/invalid", source := invalid, range := invalidRange }]
    client.changeDocument uri projection.text
    let mut invalidCompletion := Json.null
    if language == "rocq" then invalidCompletion ← rocqDocument client uri 2
    let invalidDiagnostics ← if language == "rust" then pullDiagnostics client uri
      else pushDiagnostics client uri 2
    let invalidHasError := invalidDiagnostics.any (·.severity? == some .error)
    let mut mappedLocations := #[]
    for diagnostic in invalidDiagnostics do
      let mapped ← IO.ofExcept <| projection.mapRange diagnostic.range
      for location in mapped.locations do
        mappedLocations := mappedLocations.push <| Json.mkObj [
          ("uri", toJson location.uri), ("range", toJson location.range),
          ("message", toJson diagnostic.message)]
    client.changeDocument uri text
    if language == "rocq" then discard <| rocqDocument client uri 3
    let restoredDiagnostics ← if language == "rust" then pullDiagnostics client uri
      else pushDiagnostics client uri 3
    check (!(restoredDiagnostics.any (·.severity? == some .error))) "error survived document restoration"

    let mut detachedDefinition := Json.null
    if language == "rust" then
      let detachedUri := (System.Uri.pathToUri (root / "Detached.rs") : String)
      client.openDocument detachedUri "rust"
        "use verso_lsp_spike::step;\nfn probe() { let _ = step; }\n"
      detachedDefinition ← client.call "textDocument/definition" (queryParams detachedUri 1 22)
    let (notifications, dropped) ← client.notifications
    let diagnostics ← client.diagnostics uri
    let output := Json.mkObj [
      ("language", toJson language), ("capabilities", caps),
      ("definition", result), ("targets", toJson targets), ("hover", hover),
      ("blockDefinition", blockDefinition), ("semanticSpans", toJson spans),
      ("baselineDiagnostics", toJson baselineDiagnostics), ("completion", completion),
      ("invalidCompletion", invalidCompletion), ("invalidDiagnostics", toJson invalidDiagnostics),
      ("mappedDiagnostics", toJson mappedLocations), ("restoredDiagnostics", toJson restoredDiagnostics),
      ("detachedDefinition", detachedDefinition),
      ("diagnostics", toJson diagnostics), ("notifications", toJson notifications),
      ("droppedNotifications", toJson dropped), ("stderr", toJson (← client.stderr))]
    IO.println output.compress
    check invalidHasError "invalid fragment produced no error"
    check (!mappedLocations.isEmpty) "real diagnostic did not map to the authored fragment"
    check (!targets.isEmpty) s!"{language}: no definition targets"
    check (hover != Json.null) s!"{language}: no hover"
  finally
    check (← client.close) s!"{language}: process was not reaped"

def main (args : List String) : IO Unit := do
  match args with
  | ["mock", server] => pureChecks; mockChecks server
  | ["probe", language, command, root] => probe language command root
  | _ => throw <| IO.userError "usage: verso-lsp-spike mock SERVER.py | probe LANGUAGE COMMAND ROOT"
