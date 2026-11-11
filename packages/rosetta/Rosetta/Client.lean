/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
module

public import Rosetta.Framing
public import Rosetta.Protocol
public import Std.Sync.Mutex
public import Std.Sync.CancellationToken

public section

/-! Experimental stdio client. Transport state never protects blocking IO.
Document handles belong to one client and one admitted document version. -/
namespace Rosetta
open Lean

structure ClientConfig where
  command : String
  args : Array String := #[]
  root : System.FilePath
  env : Array (String × Option String) := #[]
  initializationOptions : Json := .null
  configuration : Array (String × Json) := #[]
  experimentalCapabilities : Json := .null
  timeoutMs : Nat := 5000
  maxQueuedMessages : Nat := 128
  maxQueuedBytes : Nat := 8 * 1024 * 1024
  maxPendingRequests : Nat := 128
  maxInboundBytes : Nat := 16 * 1024 * 1024

def stdio : IO.Process.StdioConfig := {
  stdin := .piped, stdout := .piped, stderr := .piped }

private structure Outbound where
  payload : String
  requestId? : Option Nat := none
  deadline : Nat

private structure State where
  nextId : Nat := 0
  nextVersion : Int := 1
  pending : Std.HashMap Nat (Option (Except ClientError Json)) := {}
  documents : Std.HashMap String OpenDocument := {}
  queue : Array Outbound := #[]
  queuedBytes : Nat := 0
  active? : Option Outbound := none
  stopWriter : Bool := false
  notifications : Array Json := #[]
  droppedNotifications : Nat := 0
  failure? : Option ClientError := none
  closing : Bool := false

structure Client where
  private mk ::
  private child : IO.Process.Child stdio
  private state : Std.Mutex State
  private reader : Task (Except ClientError Unit)
  private writer : Task (Except ClientError Unit)
  private watchdog : Task (Except IO.Error Unit)
  private stderrReader : Task (Except IO.Error Unit)
  private stderrBytes : IO.Ref ByteArray
  private initializeResult : IO.Ref Json
  config : ClientConfig
  private cleanup : IO.Promise CloseReport

/-- A document version in its owning session. Obtain a new handle after an edit;
closing/reopening a URI never revives an older handle. -/
structure Document where
  private mk ::
  client : Client
  uri : String
  version : Int

private def fail (s : State) (error : ClientError) : State :=
  { s with failure? := s.failure? <|> some error, queue := #[], queuedBytes := 0, stopWriter := true }

private def admit (s : State) (internal : Bool := false) : EIO ClientError Unit := do
  if s.closing && !internal then throw ClientError.closed
  if let some failure := s.failure? then throw failure

private def enqueue (config : ClientConfig) (s : State) (frame : Outbound) : EIO ClientError State := do
  if s.stopWriter then throw ClientError.disconnected
  if s.queue.size ≥ config.maxQueuedMessages ||
      s.queuedBytes + frame.payload.utf8ByteSize > config.maxQueuedBytes then
    throw ClientError.queueFull
  return { s with queue := s.queue.push frame, queuedBytes := s.queuedBytes + frame.payload.utf8ByteSize }

private def checkDocument (s : State) (document? : Option (String × Int)) : EIO ClientError Unit := do
  if let some (uri, expected) := document? then
    let actual? := s.documents[uri]?.map (·.version)
    unless actual? == some expected do throw <| ClientError.staleDocument uri expected actual?

private def protocol (value : Except String α) : EIO ClientError α :=
  EIO.ofExcept (value.mapError ClientError.protocol)

private def notification (method : String) (params : Json) : String :=
  (Json.mkObj [("jsonrpc", "2.0"), ("method", toJson method), ("params", params)]).compress

private partial def writeLoop (input : IO.FS.Stream) (state : Std.Mutex State) : EIO ClientError Unit := do
  try
    repeat
      let (frame?, stopped) ← state.atomically do
        let s ← get
        if s.stopWriter && s.queue.isEmpty then return (none, true)
        let some frame := s.queue[0]? | return (none, false)
        set { s with
          queue := s.queue.extract 1 s.queue.size
          queuedBytes := s.queuedBytes - frame.payload.utf8ByteSize }
        -- Cancelled requests that have not started writing never reach the peer.
        if frame.requestId?.any (fun id => !s.pending.contains id) then return (none, false)
        modify fun s => { s with active? := some frame }
        return (some frame, false)
      if stopped then break
      if let some frame := frame? then
        input.writeSerializedLspMessage frame.payload
        state.atomically do modify fun s => { s with active? := none }
      else IO.sleep 2
  catch error => state.atomically do
    modify fun s => { (fail s error) with active? := none }

/-- A partially written frame cannot be cancelled and followed by another frame.
Retire the transport instead, waking request waiters without taking a pipe lock. -/
private partial def watchWrites (child : IO.Process.Child stdio) (state : Std.Mutex State) : IO Unit := do
  repeat
    let now ← IO.monoMsNow
    let (expired, stopped) ← state.atomically do
      let s ← get
      -- Cleanup owns termination once closing starts. The tracked watchdog is
      -- the only other signal sender; close must join it before reaping.
      if s.closing then return (false, true)
      if s.active?.any (fun frame => s.failure?.isSome || now ≥ frame.deadline) then
        set <| fail s (.deadline "write")
        return (true, false)
      return (false, s.stopWriter && s.active?.isNone)
    if expired then
      try child.kill catch _ => pure ()
      break
    if stopped then break
    IO.sleep 2

private def configurationResult (config : ClientConfig) (params : Json) : Json :=
  let items := (params.getObjValAs? (Array Json) "items").toOption.getD #[]
  .arr <| items.map fun item =>
    let configSection := (item.getObjValAs? String "section").toOption.getD ""
    (config.configuration.find? (·.1 == configSection)).map (·.2) |>.getD .null

private def dispatch (config : ClientConfig) (state : Std.Mutex State) (message : Json) : EIO ClientError Unit := do
  unless (message.getObjValAs? String "jsonrpc").toOption == some "2.0" do
    throw <| ClientError.protocol "invalid JSON-RPC version"
  if let .ok method := message.getObjValAs? String "method" then
    let params := (message.getObjVal? "params").toOption.getD .null
    if let .ok id := message.getObjVal? "id" then
      unless (fromJson? (α := String) id).isOk || (fromJson? (α := Int) id).isOk do
        throw <| ClientError.protocol "invalid server request id"
      let result? := match method with
        | "workspace/configuration" => some <| configurationResult config params
        | "workspace/workspaceFolders" => some <| toJson #[Json.mkObj [
            ("uri", toJson (System.Uri.pathToUri config.root : String)),
            ("name", toJson (config.root.fileName.getD "project"))]]
        | "window/showMessageRequest" => some Json.null
        | _ => none
      let reply := match result? with
        | some result => Json.mkObj [("jsonrpc", "2.0"), ("id", id), ("result", result)]
        | none => Json.mkObj [("jsonrpc", "2.0"), ("id", id),
            ("error", Json.mkObj [("code", toJson (-32601 : Int)),
              ("message", toJson s!"unsupported client method: {method}")])]
      let payload := reply.compress
      let deadline := (← IO.monoMsNow) + config.timeoutMs
      state.atomically do
        let s ← get
        unless s.stopWriter do set (← enqueue config s { payload, deadline })
    else if method == "textDocument/publishDiagnostics" then
      let params ← protocol <| fromJson? (α := Lsp.PublishDiagnosticsParams) params
      state.atomically do
        modify fun s => match s.documents[params.uri]? with
          | none => s
          | some doc => { s with documents := s.documents.insert params.uri (doc.publish params) }
    else state.atomically do
      modify fun s =>
        if s.notifications.size < 512 then { s with notifications := s.notifications.push message }
        else { s with
          notifications := (s.notifications.extract 1 s.notifications.size).push message
          droppedNotifications := s.droppedNotifications + 1 }
  else
    let id ← protocol <| message.getObjValAs? Nat "id"
    let result := message.getObjVal? "result"
    let error := message.getObjVal? "error"
    unless result.isOk != error.isOk do throw <| ClientError.protocol "response must contain exactly one result or error"
    let response ← if let .ok error := error then do
        let code ← protocol <| error.getObjValAs? Int "code"
        let message ← protocol <| error.getObjValAs? String "message"
        pure <| Except.error <| ClientError.server code message (error.getObjVal? "data").toOption
      else pure <| Except.ok (← protocol result)
    state.atomically do
      modify fun s =>
        if s.pending.contains id then { s with pending := s.pending.insert id (some response) }
        else s -- Late responses never answer another operation.

private partial def receiveLoop (config : ClientConfig) (output : IO.FS.Stream)
    (state : Std.Mutex State) : EIO ClientError Unit := do
  try
    repeat
      let raw ← Internal.readFrame output config.maxInboundBytes
      let message ← protocol (Json.parse raw)
      dispatch config state message
  catch error => state.atomically do modify (fail · error)

private partial def drainStderr (handle : IO.FS.Handle) (bytes : IO.Ref ByteArray) : IO Unit := do
  repeat
    let chunk ← handle.read 4096
    if chunk.isEmpty then break
    bytes.modify fun old =>
      let combined := old ++ chunk
      combined.extract (combined.size - min combined.size 65536) combined.size

def Client.capabilities (client : Client) : BaseIO Json := do
  return ((← client.initializeResult.get).getObjVal? "capabilities").toOption.getD .null

def Client.stderr (client : Client) : BaseIO String := do
  return (String.fromUTF8? (← client.stderrBytes.get)).getD "[stderr contains non-UTF-8 bytes]"

private def Client.notifyCore (client : Client) (method : String) (params : Json)
    (internal : Bool := false) : EIO ClientError Unit := do
  let payload := notification method params
  let deadline := (← IO.monoMsNow) + client.config.timeoutMs
  client.state.atomically do
    let s ← get
    admit s internal
    set (← enqueue client.config s { payload, deadline })

/-- Admission to the bounded writer queue, not an acknowledgement by the peer.
Document lifecycle notifications must use the document operations below. -/
def Client.notify (client : Client) (method : String) (params : Json) : EIO ClientError Unit := do
  if #["textDocument/didOpen", "textDocument/didChange", "textDocument/didClose"].contains method then
    throw <| ClientError.invalidInput "use document lifecycle operations"
  client.notifyCore method params

private def Client.cancel (client : Client) (id : Nat) : EIO ClientError Unit := do
  let deadline := (← IO.monoMsNow) + client.config.timeoutMs
  let payload := notification "$/cancelRequest" (Json.mkObj [("id", toJson id)])
  client.state.atomically do
    let s ← get
    unless s.pending.contains id do return ()
    modify fun s => { s with pending := s.pending.erase id }
    let s ← get
    if s.closing then return ()
    if s.active?.any (·.requestId? == some id) then
      set <| fail s .disconnected
      return () -- The tracked watchdog handles termination, never this caller.
    unless s.stopWriter do
      try set (← enqueue client.config s { payload, deadline })
      catch _ => set <| fail s .queueFull

private def cancellationRequested (cancel? : Option Std.CancellationToken) : IO Bool :=
  match cancel? with
  | none => pure false
  | some token => token.isCancelled

private def Client.requestCore (client : Client) (method : String) (params : Json)
    (timeoutMs : Nat) (cancel? : Option Std.CancellationToken)
    (document? : Option (String × Int) := none) (internal : Bool := false) : EIO ClientError Json := do
  let deadline := (← IO.monoMsNow) + timeoutMs
  if ← cancellationRequested cancel? then throw <| ClientError.cancelled method
  let encodedParams := params.compress
  let encodedMethod := (toJson method).compress
  if (← IO.monoMsNow) ≥ deadline then throw <| ClientError.deadline method
  let id ← client.state.atomically do
    let s ← get
    admit s internal
    checkDocument s document?
    if s.pending.size ≥ client.config.maxPendingRequests then
      throw ClientError.pendingFull
    let id := s.nextId
    let payload := "{\"jsonrpc\":\"2.0\",\"id\":" ++ toString id ++
      ",\"method\":" ++ encodedMethod ++ ",\"params\":" ++ encodedParams ++ "}"
    let s ← enqueue client.config s { payload, requestId? := some id, deadline }
    set { s with nextId := id + 1, pending := s.pending.insert id none }
    return id
  try
    repeat
      if ← cancellationRequested cancel? then throw <| ClientError.cancelled method
      if (← IO.monoMsNow) ≥ deadline then throw <| ClientError.deadline method
      let response? ← client.state.atomically do
        let s ← get
        admit s internal
        checkDocument s document?
        let response? := s.pending[id]?.join
        if response?.isSome then modify fun s => { s with pending := s.pending.erase id }
        return response?
      if let some response := response? then return ← EIO.ofExcept response
      IO.sleep 2
    throw <| ClientError.protocol "unreachable request loop"
  catch error =>
    client.cancel id
    throw error

/-- Workspace/session operation. Document operations require a versioned handle.
Return its result, or a structured server error retaining the code and data. -/
def Client.request (client : Client) (method : String) (params : Json)
    (timeoutMs : Nat := client.config.timeoutMs) (cancel? : Option Std.CancellationToken := none) : EIO ClientError Json := do
  if (params.getObjVal? "textDocument").isOk then
    throw <| ClientError.invalidInput "document requests require a document handle"
  client.requestCore method params timeoutMs cancel?

/-- Reject mismatched URIs and stale handles at both admission and delivery.
The handle itself selects the owning client; it cannot be reused in another one. -/
def Document.request (document : Document) (method : String) (params : Json)
    (timeoutMs : Nat := document.client.config.timeoutMs) (cancel? : Option Std.CancellationToken := none) : EIO ClientError Json := do
  unless (params.getObjVal? "textDocument" >>= (·.getObjValAs? String "uri")).toOption == some document.uri do
    throw <| ClientError.invalidInput "request URI does not match document handle"
  if let .ok raw := params.getObjVal? "textDocument" >>= (·.getObjVal? "version") then
    let version ← EIO.ofExcept <| (fromJson? (α := Int) raw).mapError ClientError.invalidInput
    unless version == document.version do throw <| ClientError.invalidInput "request version does not match document handle"
  document.client.requestCore method params timeoutMs cancel? (some (document.uri, document.version))

def Client.openDocument (client : Client) (uri languageId text : String) : EIO ClientError Document := do
  let deadline := (← IO.monoMsNow) + client.config.timeoutMs
  let version ← client.state.atomically do
    let s ← get
    admit s
    if s.documents.contains uri then throw <| ClientError.invalidInput "document is already open"
    let version := s.nextVersion
    let payload := notification "textDocument/didOpen" <| Json.mkObj [
      ("textDocument", Json.mkObj [("uri", toJson uri), ("languageId", toJson languageId),
        ("version", toJson version), ("text", toJson text)])]
    let s ← enqueue client.config s { payload, deadline }
    set { s with nextVersion := version + 1, documents := s.documents.insert uri { version, text } }
    return version
  return { client, uri, version }

/-- Full replacement for full sync, a whole-document range for incremental sync.
The returned handle supersedes the old version atomically with queue admission. -/
def Document.change (document : Document) (text : String) : EIO ClientError Document := do
  let client := document.client
  let caps ← client.capabilities
  let sync := (caps.getObjVal? "textDocumentSync").toOption.getD .null
  let kind := (fromJson? (α := Nat) sync).toOption <|> (sync.getObjValAs? Nat "change").toOption
  unless kind == some 1 || kind == some 2 do throw <| ClientError.unsupported "document synchronization"
  let deadline := (← IO.monoMsNow) + client.config.timeoutMs
  let version ← client.state.atomically do
    let s ← get
    admit s
    checkDocument s (some (document.uri, document.version))
    let some doc := s.documents[document.uri]? | throw <| ClientError.staleDocument document.uri document.version none
    let version := s.nextVersion
    let change := if kind == some 1 then Json.mkObj [("text", toJson text)] else
      let oldRange : Lsp.Range := {
        start := ⟨0, 0⟩
        «end» := (FileMap.ofString doc.text).utf8PosToLspPos ⟨doc.text.utf8ByteSize⟩ }
      Json.mkObj [("range", toJson oldRange), ("text", toJson text)]
    let payload := notification "textDocument/didChange" <| Json.mkObj [
      ("textDocument", Json.mkObj [("uri", toJson document.uri), ("version", toJson version)]),
      ("contentChanges", toJson #[change])]
    let s ← enqueue client.config s { payload, deadline }
    set { s with nextVersion := version + 1, documents := s.documents.insert document.uri { version, text } }
    return version
  return { document with version }

def Document.close (document : Document) : EIO ClientError Unit := do
  let client := document.client
  let deadline := (← IO.monoMsNow) + client.config.timeoutMs
  let payload := notification "textDocument/didClose" (Json.mkObj [
    ("textDocument", Json.mkObj [("uri", toJson document.uri)])])
  client.state.atomically do
    let s ← get
    admit s
    checkDocument s (some (document.uri, document.version))
    let s ← enqueue client.config s { payload, deadline }
    set { s with documents := s.documents.erase document.uri }

def Document.diagnostics (document : Document) : EIO ClientError (Option DiagnosticSnapshot) :=
  document.client.state.atomically do
    let s ← get
    admit s
    checkDocument s (some (document.uri, document.version))
    return s.documents[document.uri]? >>= (·.diagnostics?)

def Client.notifications (client : Client) : BaseIO (Array Json × Nat) :=
  client.state.atomically do return ((← get).notifications, (← get).droppedNotifications)

private def Client.workersStopped (client : Client) : IO Bool := do
  return (← IO.hasFinished client.reader) && (← IO.hasFinished client.writer) &&
    (← IO.hasFinished client.stderrReader) && (← IO.hasFinished client.watchdog)

private def Client.waitWorkers (client : Client) (timeoutMs : Nat) : IO Bool := do
  let deadline := (← IO.monoMsNow) + timeoutMs
  repeat
    if ← client.workersStopped then return true
    if (← IO.monoMsNow) ≥ deadline then return false
    IO.sleep 2
  return false

private def Client.closeCore (client : Client) : IO CloseReport := do
  let uris ← client.state.atomically do
    let s ← get
    set { s with pending := {}, documents := {} }
    return s.documents.toList.map (·.1)
  for uri in uris do
    discard <| (client.notifyCore "textDocument/didClose" (Json.mkObj [
      ("textDocument", Json.mkObj [("uri", toJson uri)])]) true).toBaseIO
  discard <| (client.requestCore "shutdown" .null 500 none none true).toBaseIO
  discard <| (client.notifyCore "exit" .null true).toBaseIO
  client.state.atomically do modify fun s => { s with stopWriter := true }
  -- Do not reap the leader while inherited pipes may still be open: its PID
  -- reserves our process-group identity until escalation is complete.
  if ← client.waitWorkers 500 then
    if (← client.child.tryWait).isSome then return { reaped := true, workersStopped := true }
  let mut errors := #[]
  try client.child.kill catch error => errors := errors.push error.toString
  discard <| client.waitWorkers 100
  -- Lean only exposes SIGTERM on Unix. Invoke the POSIX utility directly,
  -- without a shell, against the session/process group created by spawn.
  -- Always escalate before reaping, including when the leader exited first.
  if !System.Platform.isWindows then
    try
      let killer ← IO.Process.spawn {
        cmd := "kill", args := #["-KILL", "--", s!"-{client.child.pid}"]
        stdout := .null, stderr := .null }
      let deadline := (← IO.monoMsNow) + 500
      repeat
        if (← killer.tryWait).isSome then break
        if (← IO.monoMsNow) ≥ deadline then
          killer.kill
          errors := errors.push "force-termination helper did not exit"
          break
        IO.sleep 2
    catch error => errors := errors.push s!"force termination failed: {error}"
  let workersStopped ← client.waitWorkers 500
  -- A delayed signal sender must never retain a PID after we reap its owner.
  unless ← IO.hasFinished client.watchdog do
    return {
      workersStopped, forced := true
      errors := errors.push "termination watchdog still running; child not reaped" }
  let deadline := (← IO.monoMsNow) + 500
  let mut reaped := false
  repeat
    if (← client.child.tryWait).isSome then
      reaped := true
      break
    if (← IO.monoMsNow) ≥ deadline then break
    IO.sleep 2
  return { reaped, workersStopped, forced := true, errors }

/-- One caller owns cleanup; concurrent and repeated callers share its report.
Closing rejects new work and invalidates all document handles immediately. -/
def Client.close (client : Client) : BaseIO CloseReport := do
  let owner ← client.state.atomically do
    let s ← get
    if s.closing then return false
    set { s with closing := true }
    return true
  if !owner then return (← IO.wait client.cleanup.result?).getD {}
  let report ← client.closeCore.catchExceptions fun error => pure { errors := #[error.toString] }
  client.cleanup.resolve report
  return report

def Client.start (config : ClientConfig) : EIO ClientError Client := do
  let root ← IO.FS.realPath config.root
  let config := { config with root }
  let child ← IO.Process.spawn {
    toStdioConfig := stdio, cmd := config.command, args := config.args,
    cwd := some config.root, env := config.env, setsid := true }
  let input := IO.FS.Stream.ofHandle child.stdin
  let state ← Std.Mutex.new ({} : State)
  let stderrBytes ← IO.mkRef ByteArray.empty
  let stderrReader ← IO.asTask (drainStderr child.stderr stderrBytes) .dedicated
  let reader ← EIO.asTask
    (receiveLoop config (IO.FS.Stream.ofHandle child.stdout) state) .dedicated
  let writer ← EIO.asTask (writeLoop input state) .dedicated
  let watchdog ← IO.asTask (watchWrites child state) .dedicated
  let cleanup ← IO.Promise.new
  let initializeResult ← IO.mkRef Json.null
  let client : Client := {
    child, state, reader, writer, watchdog, stderrReader, stderrBytes, initializeResult, config, cleanup }
  try
    let rootUri := (System.Uri.pathToUri config.root : String)
    let result ← client.request "initialize" <| Json.mkObj [
      ("processId", toJson (← IO.Process.getPID).toNat), ("clientInfo", Json.mkObj [("name", "Rosetta")]),
      ("rootUri", toJson rootUri),
      ("workspaceFolders", toJson #[Json.mkObj [("uri", toJson rootUri), ("name", "project")]]),
      ("initializationOptions", config.initializationOptions),
      ("capabilities", Json.mkObj [
        ("experimental", config.experimentalCapabilities),
        ("general", Json.mkObj [("positionEncodings", toJson #["utf-16"])]),
        ("workspace", Json.mkObj [("configuration", toJson true), ("workspaceFolders", toJson true),
          ("symbol", Json.mkObj [("resolveSupport", Json.mkObj [
            ("properties", toJson #["location.range"])])])]),
        ("textDocument", Json.mkObj [
          ("publishDiagnostics", Json.mkObj [("versionSupport", toJson true)]),
          ("definition", Json.mkObj [("linkSupport", toJson true)]),
          ("diagnostic", Json.mkObj [("relatedDocumentSupport", toJson false)]),
          ("semanticTokens", Json.mkObj [
            ("requests", Json.mkObj [("full", toJson true), ("range", toJson true)]),
            ("tokenTypes", toJson #["namespace", "type", "class", "enum", "interface", "struct",
              "typeParameter", "parameter", "variable", "property", "enumMember", "event",
              "function", "method", "macro", "keyword", "modifier", "comment", "string",
              "number", "regexp", "operator", "decorator"]),
            ("tokenModifiers", toJson #["declaration", "definition", "readonly", "static",
              "deprecated", "abstract", "async", "modification", "documentation", "defaultLibrary"]),
            ("formats", toJson #["relative"]), ("overlappingTokenSupport", toJson false),
            ("multilineTokenSupport", toJson false)]),
          ("hover", Json.mkObj [("contentFormat", toJson #["plaintext", "markdown"])])])])]
    initializeResult.set result
    let caps ← client.capabilities
    let encoding := (caps.getObjValAs? String "positionEncoding").toOption.getD "utf-16"
    unless encoding == "utf-16" do throw <| ClientError.unsupported s!"position encoding: {encoding}"
    client.notify "initialized" (Json.mkObj [])
    return client
  catch error =>
    let report ← client.close
    if report.complete then throw error
    throw <| ClientError.cleanup report (some error)

/-- Preserve the action's failure if cleanup also fails. -/
def Client.withSession (config : ClientConfig) (action : Client → EIO ClientError α) : EIO ClientError α := do
  let client ← Client.start config
  let result : Except ClientError α ← try pure (.ok (← action client)) catch error => pure (.error error)
  let report ← client.close
  match result with
  | .ok value =>
    unless report.complete do throw <| ClientError.cleanup report none
    return value
  | .error error =>
    if report.complete then throw error
    throw <| ClientError.cleanup report (some error)

end Rosetta
