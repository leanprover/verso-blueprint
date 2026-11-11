/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Rosetta.Workspace
import Rosetta.Client
import Rosetta.Source

open Lean Rosetta

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

private def failsWith (action : EIO ClientError α) (accept : ClientError → Bool) : EIO ClientError Bool := do
  try
    discard action
    return false
  catch error => return accept error

private def heldParams (document : Document) (tag : String) : Json := Json.mkObj [
  ("textDocument", Json.mkObj [("uri", toJson document.uri)]), ("tag", toJson tag)]

/-- Deliberately create an escaped descendant, outside Rosetta's ownership, so
cleanup fails honestly. The test owns and kills that descendant in all cases. -/
private def cleanupFailureChecks (server : String) : EIO ClientError Unit := do
  for failAction in #[false, true] do
    let escaped ← IO.mkRef (none : Option Nat)
    try
      let result ← (Client.withSession
        { command := "python3", args := #[server], root := "." } fun client => do
          let value ← client.request "test/escaped-descendant" .null
          let pid ← EIO.ofExcept <| (fromJson? (α := Nat) value).mapError ClientError.protocol
          escaped.set (some pid)
          if failAction then discard <| client.request "test/error" .null
        ).toBaseIO
      match result with
      | .error (.cleanup report original?) =>
        check (report.reaped && !report.workersStopped && !report.complete)
          "incomplete cleanup falsely claimed successful resource ownership"
        if failAction then
          check (original? matches some (.server (-32097) "server-specific" none))
            "cleanup erased the original typed server error"
        else check original?.isNone "cleanup invented an original action error"
      | _ => check false "incomplete scoped cleanup did not return a structured failure"
    finally
      if let some pid ← escaped.get then
        let result ← IO.Process.output { cmd := "kill", args := #["-KILL", "--", toString pid] }
        check (result.exitCode == 0) "test-owned escaped descendant was not killed"

private def mockChecks (server : String) : EIO ClientError Unit := do
  let mut chattyElapsed := 0
  let client ← Client.start { command := "python3", args := #[server], root := "." }
  try
    let uri := "file:///mock"
    let mut document ← client.openDocument uri "third-language" "x"
    discard <| client.request "test/barrier" .null
    let some diagnostic ← document.diagnostics | throw <| ClientError.io <| IO.userError "missing diagnostics"
    check (diagnostic.version? == some 1 && diagnostic.diagnostics.isEmpty)
      "diagnostics were appended, or stale diagnostics accepted"
    document ← document.change "y"
    discard <| client.request "test/barrier" .null
    let some diagnostic ← document.diagnostics | throw <| ClientError.io <| IO.userError "missing changed diagnostics"
    check (diagnostic.version? == some 2 && diagnostic.diagnostics.size == 1 &&
      diagnostic.diagnostics[0]!.message == "current warning") "incorrect edited diagnostics"
    discard <| client.request "test/unversioned" (Json.mkObj [("uri", toJson uri)])
    let some unversioned ← document.diagnostics | throw <| ClientError.io <| IO.userError "missing unversioned diagnostics"
    check (unversioned.version?.isNone) "invented a version for unversioned diagnostics"
    check (← failsWith (client.request "test/error" .null) (fun
      | .server code message data? => code == -32097 && message == "server-specific" && data?.isNone
      | _ => false)) "lost a server-specific error code"
    for data in #[Json.null, Json.mkObj [("detail", toJson #[1, 2]), ("nested", Json.null)]] do
      check (← failsWith (client.request "test/error" (Json.mkObj [
        ("code", toJson (739 : Int)), ("data", data)])) (fun
          | .server code message data? => code == 739 && message == "server-specific" && data? == some data
          | _ => false)) "structured server error data was lost"
    check ((← client.request "test/null" .null) == Json.null) "successful null result became an error"
    check ((← client.request "test/cancellations" .null) == toJson (#[] : Array Nat))
      "completed server errors emitted spurious cancellation notifications"
    check ((← client.request "test/client-request" .null) == toJson true)
      "unsupported server request was acknowledged as successful"
    discard <| client.request "test/stderr" .null
    check ((← client.stderr).utf8ByteSize ≤ 65536) "stderr exceeded retention limit"
    let old := document
    let held ← EIO.asTask (old.request "test/hold-document" (heldParams old "edit")) .dedicated
    awaitNotification client "test/held-edit"
    document ← document.change "z"
    check ((← IO.wait held) matches .error (.staleDocument _ _ _)) "edit delivered an obsolete response"
    check (← failsWith old.diagnostics (fun
      | .staleDocument actualUri expected actual? =>
        actualUri == uri && expected == old.version && actual? == some document.version
      | _ => false)) "old diagnostics handle was accepted"
    check (← failsWith (old.change "oops") (fun error => error matches .staleDocument _ _ _)) "stale edit was accepted"
    check (← failsWith (old.close) (fun error => error matches .staleDocument _ _ _)) "stale close was accepted"
    discard <| client.request "test/release-document" .null
    let old := document
    let held ← EIO.asTask (old.request "test/hold-document" (heldParams old "close")) .dedicated
    awaitNotification client "test/held-close"
    old.close
    document ← client.openDocument uri "third-language" "reopened"
    check (document.version > old.version) "reopening reused a document version"
    check ((← IO.wait held) matches .error (.staleDocument _ _ _)) "close/reopen delivered an obsolete response"
    discard <| client.request "test/release-document" .null
    check (← failsWith (old.request "test/barrier" (heldParams old "old")) (fun error => error matches .staleDocument _ _ _))
      "reopening revived an old handle"
    check (← failsWith (document.request "test/barrier" (Json.mkObj [
      ("textDocument", Json.mkObj [("uri", "file:///another")])])) (fun error => error matches .invalidInput _))
      "mismatched document URI was accepted"
    check (← failsWith (client.request "test/barrier" (heldParams document "unbound")) (fun error => error matches .invalidInput _))
      "unbound document query was admitted"
    for version in #[toJson (document.version - 1), toJson "invalid"] do
      check (← failsWith (document.request "test/die" (Json.mkObj [
        ("textDocument", Json.mkObj [("uri", toJson uri), ("version", version)])])) (fun error => error matches .invalidInput _))
        "mismatched or malformed document version was admitted"
    let first ← EIO.asTask (client.request "test/first" .null) .dedicated
    let heldDeadline := (← IO.monoMsNow) + 2000
    repeat
      let (notifications, _) ← client.notifications
      if notifications.any (fun message =>
          (message.getObjValAs? String "method").toOption == some "test/held") then break
      check ((← IO.monoMsNow) < heldDeadline) "first request was not admitted"
      IO.sleep 2
    let second ← client.request "test/second" .null
    let first ← EIO.ofExcept first.get
    check (first == toJson "first" && second == toJson "second") "responses were routed incorrectly"
    let before ← IO.monoMsNow
    let timedOut ← try
      discard <| client.request "test/chatter" .null 100
      pure false
    catch error => pure <| error matches .deadline _
    let elapsed := (← IO.monoMsNow) - before
    chattyElapsed := elapsed
    check (timedOut && elapsed < 1500) s!"chatty server defeated deadline ({elapsed}ms)"
    let precancelled ← Std.CancellationToken.new
    precancelled.cancel
    check (← failsWith (client.request "test/die" .null 1000 (some precancelled)) (fun error => error matches .cancelled _))
      "pre-cancelled request was admitted"
    check (← failsWith (client.request "test/die" .null 0) (fun error => error matches .deadline _)) "zero deadline was admitted"
    discard <| client.request "test/barrier" .null
    let cancel ← Std.CancellationToken.new
    let task ← EIO.asTask (client.request "test/chatter" .null 5000 (some cancel)) .dedicated
    IO.sleep 30
    cancel.cancel
    check ((← IO.wait task) matches .error (.cancelled "test/chatter")) "explicit cancellation was misclassified"
    check ((← client.request "test/barrier" .null) == toJson true) "late response contaminated next request"
  finally
    check (← client.close).complete "mock process was not reaped"
  let dying ← Client.start { command := "python3", args := #[server], root := "." }
  let dead ← try
    discard <| dying.request "test/die" .null
    pure false
  catch error => pure <| error matches .disconnected
  check dead "server death was not observed"
  check (← dying.close).complete "dead server was not reaped"
  let rejected ← try
    let wrong ← Client.start {
      command := "python3", args := #[server], root := "."
      initializationOptions := Json.mkObj [("mode", "wrong-encoding")] }
    discard <| wrong.close
    pure false
  catch error => pure <| error matches .unsupported _
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
  let pending ← EIO.asTask (stubborn.request "test/chatter" .null 15000) .dedicated
  IO.sleep 30
  let before ← IO.monoMsNow
  let closeA ← EIO.asTask (show EIO ClientError CloseReport from stubborn.close) .dedicated
  let closeB ← EIO.asTask (show EIO ClientError CloseReport from stubborn.close) .dedicated
  IO.sleep 20
  check (← failsWith (stubborn.request "test/barrier" .null) (fun error => error matches .closed)) "closing admitted new work"
  check ((← IO.wait pending) matches .error .closed) "closing did not report its typed failure"
  let reportA ← EIO.ofExcept (← IO.wait closeA)
  let reportB ← EIO.ofExcept (← IO.wait closeB)
  let forcedElapsed := (← IO.monoMsNow) - before
  check (reportA.complete && reportA.forced && reprStr reportA == reprStr reportB)
    s!"concurrent cleanup did not share a successful report: {repr reportA}; {repr reportB}"
  check (reprStr (← stubborn.close) == reprStr reportA) "repeated cleanup changed its report"
  check (forcedElapsed < 3000) "SIGKILL cleanup exceeded its deadline"
  let inherited ← Client.start { command := "python3", args := #[server], root := "." }
  discard <| inherited.request "test/descendant" .null
  let inheritedReport ← inherited.close
  check (inheritedReport.complete && inheritedReport.forced)
    s!"leader exit left a descendant holding stdio: {repr inheritedReport}"
  let blocked ← Client.start {
    command := "python3", args := #[server], root := ".", timeoutMs := 2000 }
  discard <| blocked.request "test/stop-reading" .null
  let large := String.ofList (List.replicate (2 * 1024 * 1024) 'x')
  -- Encode/queue a notification first, so payload preparation cannot consume
  -- the query's deadline before backpressure has even been exercised.
  blocked.notify "test/blocked" (toJson large)
  IO.sleep 20
  let before ← IO.monoMsNow
  check (← failsWith (blocked.request "test/barrier" .null 120) (fun error => error matches .deadline _))
    "backpressure defeated the request deadline"
  let blockedElapsed := (← IO.monoMsNow) - before
  check (blockedElapsed < 1500) s!"blocked write took {blockedElapsed}ms"
  check (← blocked.close).complete "blocked writer/reader tasks were not stopped"
  let active ← Client.start {
    command := "python3", args := #[server], root := ".", timeoutMs := 2000 }
  discard <| active.request "test/stop-reading" .null
  let before ← IO.monoMsNow
  check (← failsWith (active.request "test/blocked" (toJson large) 500) (fun error => error matches .deadline _))
    "active write defeated its deadline"
  let activeElapsed := (← IO.monoMsNow) - before
  -- If encoding alone exhausted the deadline, notify would still be admitted.
  -- This assertion proves that the active frame actually retired the session.
  check (← failsWith (active.notify "test/after-interruption" .null) (fun
    | .disconnected | .deadline _ | .io _ => true
    | _ => false))
    "active write was not exercised or its interrupted transport was reused"
  check (activeElapsed < 1500) "active write deadline was unbounded"
  check (← active.close).complete "interrupted active writer was not stopped"
  let small ← Client.start { command := "python3", args := #[server], root := ".", maxQueuedBytes := 4096 }
  check (← failsWith (small.request "test/large" (toJson large)) (fun error => error matches .queueFull)) "outbound bytes were unbounded"
  check ((← small.request "test/barrier" .null) == toJson true) "rejected frame corrupted the transport"
  check (← small.close).complete "outbound capacity test did not clean up"
  let capped ← Client.start {
    command := "python3", args := #[server], root := "."
    maxPendingRequests := 1 }
  let pending ← EIO.asTask (capped.request "test/first" .null) .dedicated
  awaitNotification capped "test/held"
  check (← failsWith (capped.request "test/barrier" .null) (fun error => error matches .pendingFull)) "pending requests were unbounded"
  check (← capped.close).complete "capacity test did not clean up"
  check ((← IO.wait pending) matches .error .closed) "pending capacity test request survived close"
  for method in #["test/bad-envelope", "test/bad-error", "test/oversized", "test/partial"] do
    let broken ← Client.start { command := "python3", args := #[server], root := "." }
    let before ← IO.monoMsNow
    check (← failsWith (broken.request method .null 120) (fun
      | .deadline _ => method == "test/partial"
      | .protocol _ => method != "test/partial"
      | _ => false)) s!"malformed server succeeded: {method}"
    check ((← IO.monoMsNow) - before < 1500) "malformed input blocked its caller"
    check (← broken.close).complete s!"malformed server left IO workers: {method}"
  let scopedFailure ← failsWith (Client.withSession
    { command := "python3", args := #[server], root := "." }
    (fun _ => throw <| ClientError.invalidInput "original action failure") : EIO ClientError Unit)
    (fun | .invalidInput message => message == "original action failure" | _ => false)
  check scopedFailure "scoped cleanup lost the action failure"
  let cause := IO.Error.noFileOrDirectory "fixture-owned-input" 2 "preserved cause"
  check (← failsWith (do (throw cause : IO Unit)) (fun
    | .io (.noFileOrDirectory filename code details) =>
      filename == "fixture-owned-input" && code == 2 && details == "preserved cause"
    | _ => false)) "lifting IO erased its structured cause"
  let startup ← (Client.start { command := "/rosetta-missing-fixture/server", root := "." }).toBaseIO
  let startupTyped := match startup with
    | .error (.io _) | .error .disconnected => true
    | _ => false
  let startupDetail := match startup with | .error error => toString error | .ok _ => "unexpected success"
  check startupTyped s!"process startup failure escaped the typed interface: {startupDetail}"
  cleanupFailureChecks server
  IO.println <| (Json.mkObj [("mock", "passed"), ("chattyDeadlineMs", toJson chattyElapsed),
    ("blockedWriteDeadlineMs", toJson blockedElapsed), ("activeWriteDeadlineMs", toJson activeElapsed),
    ("forcedCloseMs", toJson forcedElapsed)]).compress

private def queryParams (uri : String) (line character : Nat) : Json := Json.mkObj [
  ("textDocument", Json.mkObj [("uri", toJson uri)]),
  ("position", toJson (⟨line, character⟩ : Lsp.Position))]

private def rocqDocument (document : Document) : EIO ClientError Json :=
  document.request "coq/getDocument" <| Json.mkObj [("textDocument", Json.mkObj [
    ("uri", toJson document.uri), ("version", toJson document.version)])]

private def pushDiagnostics (document : Document) :
    EIO ClientError (Array Lsp.Diagnostic) := do
  let deadline := (← IO.monoMsNow) + 3000
  repeat
    if let some snapshot ← document.diagnostics then
      if snapshot.version? == some document.version then return snapshot.diagnostics
    check ((← IO.monoMsNow) < deadline) "missing current-version push diagnostics"
    IO.sleep 2
  throw <| ClientError.io <| IO.userError "unreachable diagnostics loop"

private def pullDiagnostics (document : Document) : EIO ClientError (Array Lsp.Diagnostic) := do
  let report ← document.request "textDocument/diagnostic" <| Json.mkObj [
    ("textDocument", Json.mkObj [("uri", toJson document.uri)])]
  IO.ofExcept <| report.getObjValAs? (Array Lsp.Diagnostic) "items"

private def probe (language command root : String) : EIO ClientError Unit := do
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
        result ← document.request "textDocument/definition" (queryParams uri line character) 3000
        targets ← IO.ofExcept <| definitionTargets result
      catch _ => pure ()
      if !targets.isEmpty then break
      IO.sleep 100
    let hover ← document.request "textDocument/hover" (queryParams uri line character)
    let (blockLine, blockCharacter) := if language == "rust" then (4, 36) else (2, 20)
    let blockDefinition ← document.request "textDocument/definition" (queryParams uri blockLine blockCharacter)
    let blockTargets ← IO.ofExcept <| definitionTargets blockDefinition
    check (targets.any fun target => blockTargets.any fun block =>
      target.uri == block.uri && target.selectionRange == block.selectionRange)
      "block and named reference did not resolve to the same declaration"
    let caps ← client.capabilities
    let mut spans : Array SemanticSpan := #[]
    if let .ok provider := caps.getObjVal? "semanticTokensProvider" then
      let tokens ← document.request "textDocument/semanticTokens/full" <| Json.mkObj [
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
        "use rosetta_spike::step;\nfn probe() { let _ = step; }\n"
      detachedDefinition ← detached.request "textDocument/definition" (queryParams detachedUri 1 22)
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


private def assertCheck (condition : Bool) (message : String) : EIO ClientError Unit :=
  unless condition do throw <| ClientError.invalidInput message

/-- A workspace result in one file resolves into a differently located definition.
Unicode and CRLF exercise token slicing without using any Rust-specific syntax. -/
def workspaceChecks (server : String) : EIO ClientError Unit :=
  IO.FS.withTempFile fun indexHandle indexFile => IO.FS.withTempFile fun targetHandle targetFile => do
    indexHandle.putStr "index\n"
    indexHandle.flush
    targetHandle.putStr "😀fn measure() { 1 }\r\n"
    targetHandle.flush
    let sourceUri := (System.Uri.pathToUri indexFile : String)
    let targetUri := (System.Uri.pathToUri targetFile : String)
    Client.withSession {
        command := "python3", args := #[server], root := "."
        initializationOptions := Json.mkObj [
          ("mode", "workspace"), ("sourceUri", toJson sourceUri), ("targetUri", toJson targetUri)] } fun client => do
      let definition ← client.sourceDefinition "test-language" "Container::measure" "::"
      assertCheck (definition.definition.uri == targetUri) "definition location was ignored"
      assertCheck (String.join (definition.pieces.toList.map HighlightedPiece.text) == "fn measure() { 1 }")
        "source slice did not preserve the exact definition range"
      assertCheck (definition.pieces.any (fun piece => piece.tokenType == "function" &&
          piece.text == "measure" && piece.modifiers == #["declaration"])) "semantic coloring was lost"
      for reference in #["missing", "measure", "::measure", "Container::"] do
        let result ← (client.workspaceDefinition "test-language" reference "::").toBaseIO
        assertCheck (match result with | .error (.invalidInput _) => true | _ => false)
          s!"expected unresolved, ambiguous, or malformed reference: {reference}"
      let deferred ← client.workspaceSymbols "deferred"
      assertCheck (deferred.size == 1 && (deferred[0]?).any (fun symbol => symbol.location.uri == sourceUri))
        "deferred workspace symbol location was not resolved"
      let clipped ← client.highlightDefinition "test-language" {
        definition.definition with range := { start := ⟨0, 3⟩, «end» := ⟨0, 10⟩ } }
      assertCheck (String.join (clipped.pieces.toList.map HighlightedPiece.text) == "n measu")
        "tokens intersecting source boundaries were discarded"
      let multiline ← client.highlightDefinition "test-language" {
        definition.definition with range := { start := ⟨0, 2⟩, «end» := ⟨1, 0⟩ } }
      assertCheck (String.join (multiline.pieces.toList.map HighlightedPiece.text) == "fn measure() { 1 }\r\n")
        "source slice lost its CRLF terminator"
      discard <| client.request "test/readiness" (Json.mkObj [])
      client.waitForNotification "test/status" (fun params =>
        (params.getObjValAs? Bool "ready").toOption == some true) 1000
      let (notifications, dropped) ← client.notifications
      assertCheck (notifications.size == 512 && dropped > 0) "notification trace was not bounded"
      let timedOut ← (client.waitForNotification "missing/readiness" (fun _ => true) 0).toBaseIO
      assertCheck (match timedOut with | .error (.deadline _) => true | _ => false)
        "readiness wait did not respect its deadline"
      IO.println "Workspace lookup, definition following, ambiguity and Unicode highlighting passed"
    for tokenMode in #["range", "full", "null", "none"] do
      Client.withSession {
          command := "python3", args := #[server], root := "."
          initializationOptions := Json.mkObj [
            ("mode", "workspace"), ("sourceUri", toJson sourceUri), ("targetUri", toJson targetUri),
            ("tokenMode", toJson tokenMode)] } fun client => do
        let result ← (client.sourceDefinition "test-language" "Container::measure" "::").toBaseIO
        if tokenMode == "none" then
          assertCheck (match result with | .error (.unsupported _) => true | _ => false)
            "unsupported token methods were requested"
        else
          let definition ← EIO.ofExcept result
          assertCheck (String.join (definition.pieces.toList.map HighlightedPiece.text) == "fn measure() { 1 }")
            s!"{tokenMode}: source slice changed"
          assertCheck ((definition.pieces.any (fun piece => piece.tokenType == "function")) == (tokenMode != "null"))
            s!"{tokenMode}: token result was mishandled"
        if tokenMode == "range" then
          let document ← client.openDocument targetUri "test-language" "😀fn measure() { 1 }\r\n"
          let full ← try (document.semanticTokens "😀fn measure() { 1 }\r\n").toBaseIO finally document.close
          assertCheck (match full with | .error (.unsupported _) => true | _ => false)
            "range-only server received a full-document request"
    IO.println "Semantic token negotiation, full fallback, null results and readiness passed"

def main (args : List String) : IO Unit := do
  match args with
  | ["mock", server] => pureChecks; (mockChecks server *> workspaceChecks server).toIO (IO.userError ∘ toString)
  | ["probe", language, command, root] => (probe language command root).toIO (IO.userError ∘ toString)
  | _ => throw <| IO.userError "usage: rosetta-spike mock SERVER.py | probe LANGUAGE COMMAND ROOT"
