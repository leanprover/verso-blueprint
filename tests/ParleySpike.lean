/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Parley.Client
import Parley.Source

open Lean Parley

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

private def awaitNotification (client : Client) (method : String) : IO Unit := do
  let deadline := (← IO.monoMsNow) + 2000
  repeat
    let (notifications, _) ← client.notifications
    if notifications.any (fun message =>
        (message.getObjValAs? String "method").toOption == some method) then return
    check ((← IO.monoMsNow) < deadline) s!"missing notification: {method}"
    IO.sleep 2

private def failsWith (action : IO α) (message : String) : IO Bool := do
  try
    discard action
    return false
  catch error => return error.toString.contains message

private def heldParams (document : Document) (tag : String) : Json := Json.mkObj [
  ("textDocument", Json.mkObj [("uri", toJson document.uri)]), ("tag", toJson tag)]

private def mockChecks (server : String) : IO Unit := do
  let mut chattyElapsed := 0
  let client ← Client.start { command := "python3", args := #[server], root := "." }
  try
    let uri := "file:///mock"
    let mut document ← client.openDocument uri "third-language" "x"
    discard <| client.call "test/barrier" .null
    let some diagnostic ← document.diagnostics | throw <| IO.userError "missing diagnostics"
    check (diagnostic.version? == some 1 && diagnostic.diagnostics.isEmpty)
      "diagnostics were appended, or stale diagnostics accepted"
    document ← document.change "y"
    discard <| client.call "test/barrier" .null
    let some diagnostic ← document.diagnostics | throw <| IO.userError "missing changed diagnostics"
    check (diagnostic.version? == some 2 && diagnostic.diagnostics.size == 1 &&
      diagnostic.diagnostics[0]!.message == "current warning") "incorrect edited diagnostics"
    discard <| client.call "test/unversioned" (Json.mkObj [("uri", toJson uri)])
    let some unversioned ← document.diagnostics | throw <| IO.userError "missing unversioned diagnostics"
    check (unversioned.version?.isNone) "invented a version for unversioned diagnostics"
    let error ← client.request "test/error" .null
    check ((error.getObjVal? "error" >>= (·.getObjValAs? Int "code")).toOption == some (-32097))
      "lost a server-specific error code"
    check ((← client.call "test/client-request" .null) == toJson true)
      "unsupported server request was acknowledged as successful"
    discard <| client.call "test/stderr" .null
    check ((← client.stderr).utf8ByteSize ≤ 65536) "stderr exceeded retention limit"
    let old := document
    let held ← IO.asTask (old.call "test/hold-document" (heldParams old "edit")) .dedicated
    awaitNotification client "test/held-edit"
    document ← document.change "z"
    check (!(← IO.wait held).isOk) "edit delivered an obsolete response"
    check (← failsWith (old.diagnostics) "stale document") "old diagnostics handle was accepted"
    check (← failsWith (old.change "oops") "stale document") "stale edit was accepted"
    check (← failsWith (old.close) "stale document") "stale close was accepted"
    discard <| client.call "test/release-document" .null
    let old := document
    let held ← IO.asTask (old.call "test/hold-document" (heldParams old "close")) .dedicated
    awaitNotification client "test/held-close"
    old.close
    document ← client.openDocument uri "third-language" "reopened"
    check (document.version > old.version) "reopening reused a document version"
    check (!(← IO.wait held).isOk) "close/reopen delivered an obsolete response"
    discard <| client.call "test/release-document" .null
    check (← failsWith (old.call "test/barrier" (heldParams old "old")) "stale document")
      "reopening revived an old handle"
    check (← failsWith (document.call "test/barrier" (Json.mkObj [
      ("textDocument", Json.mkObj [("uri", "file:///another")])])) "URI")
      "mismatched document URI was accepted"
    check (← failsWith (client.call "test/barrier" (heldParams document "unbound")) "handle")
      "unbound document query was admitted"
    for version in #[toJson (document.version - 1), toJson "invalid"] do
      check (← failsWith (document.call "test/die" (Json.mkObj [
        ("textDocument", Json.mkObj [("uri", toJson uri), ("version", version)])])) "")
        "mismatched or malformed document version was admitted"
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
    let precancelled ← Std.CancellationToken.new
    precancelled.cancel
    check (← failsWith (client.request "test/die" .null 1000 (some precancelled)) "cancelled")
      "pre-cancelled request was admitted"
    check (← failsWith (client.request "test/die" .null 0) "deadline") "zero deadline was admitted"
    discard <| client.call "test/barrier" .null
    let cancel ← Std.CancellationToken.new
    let task ← IO.asTask (client.request "test/chatter" .null 5000 (some cancel)) .dedicated
    IO.sleep 30
    cancel.cancel
    check (!(← IO.wait task).isOk) "explicit cancellation did not interrupt request"
    check ((← client.call "test/barrier" .null) == toJson true) "late response contaminated next request"
  finally
    check (← client.close).complete "mock process was not reaped"
  let dying ← Client.start { command := "python3", args := #[server], root := "." }
  let dead ← try
    discard <| dying.call "test/die" .null
    pure false
  catch _ => pure true
  check dead "server death was not observed"
  check (← dying.close).complete "dead server was not reaped"
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
  check (← reluctant.close).complete "server ignoring shutdown was not terminated and reaped"
  check ((← IO.monoMsNow) - before < 3000) "forced cleanup exceeded its deadline"
  let stubborn ← Client.start {
    command := "python3", args := #[server], root := "."
    initializationOptions := Json.mkObj [("mode", "ignore-term")] }
  let pending ← IO.asTask (stubborn.call "test/chatter" .null 15000) .dedicated
  IO.sleep 30
  let before ← IO.monoMsNow
  let closeA ← IO.asTask stubborn.close .dedicated
  let closeB ← IO.asTask stubborn.close .dedicated
  IO.sleep 20
  check (← failsWith (stubborn.call "test/barrier" .null) "closing") "closing admitted new work"
  check (!(← IO.wait pending).isOk) "closing left a request waiting for its deadline"
  let reportA ← IO.ofExcept (← IO.wait closeA)
  let reportB ← IO.ofExcept (← IO.wait closeB)
  let forcedElapsed := (← IO.monoMsNow) - before
  check (reportA.complete && reportA.forced && reprStr reportA == reprStr reportB)
    s!"concurrent cleanup did not share a successful report: {repr reportA}; {repr reportB}"
  check (reprStr (← stubborn.close) == reprStr reportA) "repeated cleanup changed its report"
  check (forcedElapsed < 3000) "SIGKILL cleanup exceeded its deadline"
  let inherited ← Client.start { command := "python3", args := #[server], root := "." }
  discard <| inherited.call "test/descendant" .null
  let inheritedReport ← inherited.close
  check (inheritedReport.complete && inheritedReport.forced)
    s!"leader exit left a descendant holding stdio: {repr inheritedReport}"
  let blocked ← Client.start {
    command := "python3", args := #[server], root := ".", timeoutMs := 2000 }
  discard <| blocked.call "test/stop-reading" .null
  let large := String.ofList (List.replicate (2 * 1024 * 1024) 'x')
  -- Encode/queue a notification first, so payload preparation cannot consume
  -- the query's deadline before backpressure has even been exercised.
  blocked.notify "test/blocked" (toJson large)
  IO.sleep 20
  let before ← IO.monoMsNow
  check (← failsWith (blocked.call "test/barrier" .null 120) "deadline exceeded")
    "backpressure defeated the request deadline"
  let blockedElapsed := (← IO.monoMsNow) - before
  check (blockedElapsed < 1500) s!"blocked write took {blockedElapsed}ms"
  check (← blocked.close).complete "blocked writer/reader tasks were not stopped"
  let active ← Client.start {
    command := "python3", args := #[server], root := ".", timeoutMs := 2000 }
  discard <| active.call "test/stop-reading" .null
  let before ← IO.monoMsNow
  check (← failsWith (active.call "test/blocked" (toJson large) 500) "deadline exceeded")
    "active write defeated its deadline"
  let activeElapsed := (← IO.monoMsNow) - before
  -- If encoding alone exhausted the deadline, notify would still be admitted.
  -- This assertion proves that the active frame actually retired the session.
  check (← failsWith (active.notify "test/after-interruption" .null) "")
    "active write was not exercised or its interrupted transport was reused"
  check (activeElapsed < 1500) "active write deadline was unbounded"
  check (← active.close).complete "interrupted active writer was not stopped"
  let small ← Client.start { command := "python3", args := #[server], root := ".", maxQueuedBytes := 4096 }
  check (← failsWith (small.call "test/large" (toJson large)) "capacity") "outbound bytes were unbounded"
  check ((← small.call "test/barrier" .null) == toJson true) "rejected frame corrupted the transport"
  check (← small.close).complete "outbound capacity test did not clean up"
  let capped ← Client.start {
    command := "python3", args := #[server], root := "."
    maxPendingRequests := 1 }
  let pending ← IO.asTask (capped.call "test/first" .null) .dedicated
  awaitNotification capped "test/held"
  check (← failsWith (capped.call "test/barrier" .null) "capacity") "pending requests were unbounded"
  check (← capped.close).complete "capacity test did not clean up"
  check (!(← IO.wait pending).isOk) "pending capacity test request survived close"
  for method in #["test/bad-envelope", "test/oversized", "test/partial"] do
    let broken ← Client.start { command := "python3", args := #[server], root := "." }
    let before ← IO.monoMsNow
    check (← failsWith (broken.call method .null 120) "") s!"malformed server succeeded: {method}"
    check ((← IO.monoMsNow) - before < 1500) "malformed input blocked its caller"
    check (← broken.close).complete s!"malformed server left IO workers: {method}"
  let scopedFailure ← failsWith (Client.withSession
    { command := "python3", args := #[server], root := "." }
    (fun _ => throw <| IO.userError "original action failure") : IO Unit) "original action failure"
  check scopedFailure "scoped cleanup lost the action failure"
  IO.println <| (Json.mkObj [("mock", "passed"), ("chattyDeadlineMs", toJson chattyElapsed),
    ("blockedWriteDeadlineMs", toJson blockedElapsed), ("activeWriteDeadlineMs", toJson activeElapsed),
    ("forcedCloseMs", toJson forcedElapsed)]).compress

private def queryParams (uri : String) (line character : Nat) : Json := Json.mkObj [
  ("textDocument", Json.mkObj [("uri", toJson uri)]),
  ("position", toJson (⟨line, character⟩ : Lsp.Position))]

private def rocqDocument (document : Document) : IO Json :=
  document.call "coq/getDocument" <| Json.mkObj [("textDocument", Json.mkObj [
    ("uri", toJson document.uri), ("version", toJson document.version)])]

private def pushDiagnostics (document : Document) :
    IO (Array Lsp.Diagnostic) := do
  let deadline := (← IO.monoMsNow) + 3000
  repeat
    if let some snapshot ← document.diagnostics then
      if snapshot.version? == some document.version then return snapshot.diagnostics
    check ((← IO.monoMsNow) < deadline) "missing current-version push diagnostics"
    IO.sleep 2
  throw <| IO.userError "unreachable diagnostics loop"

private def pullDiagnostics (document : Document) : IO (Array Lsp.Diagnostic) := do
  let report ← document.call "textDocument/diagnostic" <| Json.mkObj [
    ("textDocument", Json.mkObj [("uri", toJson document.uri)])]
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
    let mut document ← client.openDocument uri (if language == "rust" then "rust" else "coq") text
    -- Each bounded query is retried only for transient startup evidence in this
    -- experiment. The library itself has no success-by-retry policy.
    let (line, character) := if language == "rust" then (7, 32) else (6, 7)
    let mut result := Json.null
    let mut targets := #[]
    for _ in [:20] do
      try
        result ← document.call "textDocument/definition" (queryParams uri line character) 3000
        targets ← IO.ofExcept <| definitionTargets result
      catch _ => pure ()
      if !targets.isEmpty then break
      IO.sleep 100
    let hover ← document.call "textDocument/hover" (queryParams uri line character)
    let (blockLine, blockCharacter) := if language == "rust" then (4, 36) else (2, 20)
    let blockDefinition ← document.call "textDocument/definition" (queryParams uri blockLine blockCharacter)
    let blockTargets ← IO.ofExcept <| definitionTargets blockDefinition
    check (targets.any fun target => blockTargets.any fun block =>
      target.uri == block.uri && target.selectionRange == block.selectionRange)
      "block and named reference did not resolve to the same declaration"
    let caps ← client.capabilities
    let mut spans : Array SemanticSpan := #[]
    if let .ok provider := caps.getObjVal? "semanticTokensProvider" then
      let tokens ← document.call "textDocument/semanticTokens/full" <| Json.mkObj [
        ("textDocument", Json.mkObj [("uri", toJson uri)])]
      spans ← IO.ofExcept <| semanticSpans text provider tokens
      check (!spans.isEmpty) "server advertised semantic tokens but returned no spans"
    let mut completion := Json.null
    if language == "rocq" then completion ← rocqDocument document
    let baselineDiagnostics ← if language == "rust" then pullDiagnostics document
      else pushDiagnostics document
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
    document ← document.change projection.text
    let mut invalidCompletion := Json.null
    if language == "rocq" then invalidCompletion ← rocqDocument document
    let invalidDiagnostics ← if language == "rust" then pullDiagnostics document
      else pushDiagnostics document
    let invalidHasError := invalidDiagnostics.any (·.severity? == some .error)
    let mut mappedLocations := #[]
    for diagnostic in invalidDiagnostics do
      let mapped ← IO.ofExcept <| projection.mapRange diagnostic.range
      for location in mapped.locations do
        mappedLocations := mappedLocations.push <| Json.mkObj [
          ("uri", toJson location.uri), ("range", toJson location.range),
          ("message", toJson diagnostic.message)]
    document ← document.change text
    if language == "rocq" then discard <| rocqDocument document
    let restoredDiagnostics ← if language == "rust" then pullDiagnostics document
      else pushDiagnostics document
    check (!(restoredDiagnostics.any (·.severity? == some .error))) "error survived document restoration"

    let mut detachedDefinition := Json.null
    if language == "rust" then
      let detachedUri := (System.Uri.pathToUri (root / "Detached.rs") : String)
      let detached ← client.openDocument detachedUri "rust"
        "use parley_spike::step;\nfn probe() { let _ = step; }\n"
      detachedDefinition ← detached.call "textDocument/definition" (queryParams detachedUri 1 22)
    let (notifications, dropped) ← client.notifications
    let diagnostics ← document.diagnostics
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
    check (← client.close).complete s!"{language}: process was not reaped"

def main (args : List String) : IO Unit := do
  match args with
  | ["mock", server] => pureChecks; mockChecks server
  | ["probe", language, command, root] => probe language command root
  | _ => throw <| IO.userError "usage: parley-spike mock SERVER.py | probe LANGUAGE COMMAND ROOT"
