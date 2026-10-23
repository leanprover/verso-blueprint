/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean.Data.Lsp.Communication
import Parley.Protocol
import Std.Sync.Mutex

/-! An experimental stdio client for the adapter spike. No session cache or
Blueprint dependency. This is not yet a supported end-user API. -/
namespace Parley
open Lean

structure ClientConfig where
  command : String
  args : Array String := #[]
  root : System.FilePath
  env : Array (String × Option String) := #[]
  initializationOptions : Json := .null
  configuration : Array (String × Json) := #[]
  /-- Extension capabilities implemented by the owning profile through its
  notification/readiness hooks. The generic client does not interpret them. -/
  experimentalCapabilities : Json := .null
  timeoutMs : Nat := 5000

private def stdio : IO.Process.StdioConfig := {
  stdin := .piped, stdout := .piped, stderr := .piped }

private structure State where
  nextId : Nat := 0
  pending : Std.HashMap Nat (Option Json) := {}
  documents : Std.HashMap String OpenDocument := {}
  notifications : Array Json := #[]
  droppedNotifications : Nat := 0
  failure? : Option String := none
  closed : Bool := false

structure Client where
  private child : IO.Process.Child stdio
  private input : IO.FS.Stream
  private state : Std.Mutex State
  private reader : Task (Except IO.Error Unit)
  private stderrReader : Task (Except IO.Error Unit)
  private stderrBytes : IO.Ref ByteArray
  private initializeResult : IO.Ref Json
  private config : ClientConfig

private def send (input : IO.FS.Stream) (message : Json) : IO Unit :=
  input.writeSerializedLspMessage message.compress

private def configurationResult (config : ClientConfig) (params : Json) : Json :=
  let items := (params.getObjValAs? (Array Json) "items").toOption.getD #[]
  .arr <| items.map fun item =>
    let configSection := (item.getObjValAs? String "section").toOption.getD ""
    (config.configuration.find? (·.1 == configSection)).map (·.2) |>.getD .null

private def dispatch (config : ClientConfig) (input : IO.FS.Stream)
    (state : Std.Mutex State) (message : Json) : IO Unit :=
  state.atomically do
    if let .ok method := message.getObjValAs? String "method" then
      let params := (message.getObjVal? "params").toOption.getD .null
      if let .ok id := message.getObjVal? "id" then
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
        liftM <| send input reply
      else if method == "textDocument/publishDiagnostics" then
        match fromJson? (α := Lsp.PublishDiagnosticsParams) params with
        | .error error => modify fun s => { s with failure? := some s!"invalid diagnostics: {error}" }
        | .ok params => modify fun s =>
            match s.documents[params.uri]? with
            | none => s
            | some doc => { s with documents := s.documents.insert params.uri (doc.publish params) }
      else
        modify fun s =>
          if s.notifications.size < 512 then
            { s with notifications := s.notifications.push message }
          else { s with droppedNotifications := s.droppedNotifications + 1 }
    else
      let .ok id := message.getObjValAs? Nat "id"
        | modify fun s => { s with failure? := some "response has no numeric client request id" }
      modify fun s =>
        if s.pending.contains id then { s with pending := s.pending.insert id (some message) }
        else s -- A late response to a cancelled operation cannot answer another request.

private partial def receiveLoop (config : ClientConfig) (input output : IO.FS.Stream)
    (state : Std.Mutex State) : IO Unit := do
  try
    repeat
      -- Lean.JsonRpc.ErrorCode is closed over Lean's known codes. Decode the
      -- framed JSON directly so arbitrary legal server error codes survive.
      let raw ← output.readLspMessageAsString
      let message ← IO.ofExcept (Json.parse raw)
      dispatch config input state message
  catch error =>
    state.atomically do
      modify fun s => { s with failure? := some error.toString }

private partial def drainStderr (handle : IO.FS.Handle) (bytes : IO.Ref ByteArray) : IO Unit := do
  repeat
    let chunk ← handle.read 4096
    if chunk.isEmpty then break
    bytes.modify fun old =>
      let combined := old ++ chunk
      combined.extract (combined.size - min combined.size 65536) combined.size

def Client.capabilities (client : Client) : IO Json := do
  return ((← client.initializeResult.get).getObjVal? "capabilities").toOption.getD .null

def Client.stderr (client : Client) : IO String := do
  return (String.fromUTF8? (← client.stderrBytes.get)).getD "[stderr contains non-UTF-8 bytes]"

def Client.notify (client : Client) (method : String) (params : Json) : IO Unit :=
  client.state.atomically do
    if (← get).closed then throw <| IO.userError "client is closed"
    liftM <| send client.input <| Json.mkObj [
      ("jsonrpc", "2.0"), ("method", toJson method), ("params", params)]

private def Client.cancel (client : Client) (id : Nat) : IO Unit :=
  client.state.atomically do
    modify fun s => { s with pending := s.pending.erase id }
    liftM <| send client.input <| Json.mkObj [
      ("jsonrpc", "2.0"), ("method", "$/cancelRequest"),
      ("params", Json.mkObj [("id", toJson id)])]

/-- Return the entire response envelope, retaining arbitrary server error codes.
The deadline starts at admission and is never extended by server traffic.
Cancellation is caller-owned; no hidden global cancellation state exists. -/
def Client.request (client : Client) (method : String) (params : Json)
    (timeoutMs : Nat := client.config.timeoutMs) (cancelled : IO Bool := pure false) : IO Json := do
  let deadline := (← IO.monoMsNow) + timeoutMs
  let id ← client.state.atomically do
    let s ← get
    if s.closed then throw <| IO.userError "client is closed"
    if let some failure := s.failure? then throw <| IO.userError failure
    let id := s.nextId
    liftM <| send client.input <| Json.mkObj [
      ("jsonrpc", "2.0"), ("id", toJson id), ("method", toJson method), ("params", params)]
    set { s with nextId := id + 1, pending := s.pending.insert id none }
    return id
  try
    repeat
      if ← cancelled then throw <| IO.userError "request cancelled"
      if (← IO.monoMsNow) ≥ deadline then throw <| IO.userError s!"request deadline exceeded: {method}"
      let (response?, failure?) ← client.state.atomically do
        let s ← get
        return (s.pending[id]?.join, s.failure?)
      if let some response := response? then
        client.state.atomically do modify fun s => { s with pending := s.pending.erase id }
        return response
      if let some failure := failure? then throw <| IO.userError failure
      IO.sleep 2
    throw <| IO.userError "unreachable request loop"
  catch error =>
    try client.cancel id catch _ => pure ()
    throw error

def Client.call (client : Client) (method : String) (params : Json)
    (timeoutMs : Nat := client.config.timeoutMs) : IO Json := do
  let response ← client.request method params timeoutMs
  if let .ok error := response.getObjVal? "error" then
    throw <| IO.userError s!"{method}: {error.compress}"
  IO.ofExcept <| response.getObjVal? "result"

def Client.openDocument (client : Client) (uri languageId text : String) : IO Unit := do
  client.state.atomically do
    let s ← get
    if s.closed then throw <| IO.userError "client is closed"
    if s.documents.contains uri then throw <| IO.userError "document is already open"
    liftM <| send client.input <| Json.mkObj [
      ("jsonrpc", "2.0"), ("method", "textDocument/didOpen"),
      ("params", Json.mkObj [("textDocument", Json.mkObj [
        ("uri", toJson uri), ("languageId", toJson languageId), ("version", toJson (1 : Nat)),
        ("text", toJson text)])])]
    set { s with documents := s.documents.insert uri { version := 1, text } }

/-- Use full replacement for full sync and one whole-document range edit for
incremental sync. State/version admission and writing are serialized together. -/
def Client.changeDocument (client : Client) (uri text : String) : IO Unit := do
  let caps ← client.capabilities
  let sync := (caps.getObjVal? "textDocumentSync").toOption.getD .null
  let kind := (fromJson? (α := Nat) sync).toOption <|>
    (sync.getObjValAs? Nat "change").toOption
  unless kind == some 1 || kind == some 2 do
    throw <| IO.userError "document synchronization is unsupported"
  client.state.atomically do
    let s ← get
    if s.closed then throw <| IO.userError "client is closed"
    let some doc := s.documents[uri]? | throw <| IO.userError "document is not open"
    let version := doc.version + 1
    let change := if kind == some 1 then Json.mkObj [("text", toJson text)] else
      let oldRange : Lsp.Range := {
        start := ⟨0, 0⟩
        «end» := (FileMap.ofString doc.text).utf8PosToLspPos ⟨doc.text.utf8ByteSize⟩ }
      Json.mkObj [("range", toJson oldRange), ("text", toJson text)]
    liftM <| send client.input <| Json.mkObj [
      ("jsonrpc", "2.0"), ("method", "textDocument/didChange"),
      ("params", Json.mkObj [
        ("textDocument", Json.mkObj [("uri", toJson uri), ("version", toJson version)]),
        ("contentChanges", toJson #[change])])]
    set { s with documents := s.documents.insert uri { version, text } }

def Client.diagnostics (client : Client) (uri : String) : IO (Option DiagnosticSnapshot) :=
  client.state.atomically do return (← get).documents[uri]? >>= (·.diagnostics?)

/-- Bounded trace for profile-specific readiness experiments. A dropped count
prevents callers from mistaking an incomplete trace for complete evidence. -/
def Client.notifications (client : Client) : IO (Array Json × Nat) :=
  client.state.atomically do return ((← get).notifications, (← get).droppedNotifications)

private def waitForExit (client : Client) (timeoutMs : Nat) : IO Bool := do
  let deadline := (← IO.monoMsNow) + timeoutMs
  repeat
    if (← client.child.tryWait).isSome then return true
    if (← IO.monoMsNow) ≥ deadline then return false
    IO.sleep 2
  return false

/-- True means the child was reaped. Lean's process API sends SIGTERM; if the
server ignores it, return false instead of blocking indefinitely or claiming
successful cleanup. Concurrent close/request is outside this spike's contract. -/
def Client.close (client : Client) : IO Bool := do
  if ← client.state.atomically (return (← get).closed) then
    return (← client.child.tryWait).isSome
  let uris ← client.state.atomically (return (← get).documents.toList.map (·.1))
  for uri in uris do
    try client.notify "textDocument/didClose" (Json.mkObj [
      ("textDocument", Json.mkObj [("uri", toJson uri)])]) catch _ => pure ()
  try discard <| client.call "shutdown" .null 500 catch _ => pure ()
  try client.notify "exit" .null catch _ => pure ()
  client.state.atomically do modify fun s => { s with closed := true, documents := {} }
  if ← waitForExit client 500 then return true
  try client.child.kill catch _ => pure ()
  waitForExit client 500

def Client.start (config : ClientConfig) : IO Client := do
  let root ← IO.FS.realPath config.root
  let config := { config with root }
  let child ← IO.Process.spawn {
    toStdioConfig := stdio, cmd := config.command, args := config.args,
    cwd := some config.root, env := config.env, setsid := true }
  let input := IO.FS.Stream.ofHandle child.stdin
  let state ← Std.Mutex.new ({} : State)
  let stderrBytes ← IO.mkRef ByteArray.empty
  let stderrReader ← IO.asTask (drainStderr child.stderr stderrBytes) .dedicated
  let reader ← IO.asTask
    (receiveLoop config input (IO.FS.Stream.ofHandle child.stdout) state) .dedicated
  let initializeResult ← IO.mkRef Json.null
  let client : Client := {
    child, input, state, reader, stderrReader, stderrBytes, initializeResult, config }
  try
    let rootUri := (System.Uri.pathToUri config.root : String)
    let result ← client.call "initialize" <| Json.mkObj [
      ("processId", Json.null), ("clientInfo", Json.mkObj [("name", "Parley")]),
      ("rootUri", toJson rootUri),
      ("workspaceFolders", toJson #[Json.mkObj [("uri", toJson rootUri), ("name", "project")]]),
      ("initializationOptions", config.initializationOptions),
      ("capabilities", Json.mkObj [
        ("experimental", config.experimentalCapabilities),
        ("general", Json.mkObj [("positionEncodings", toJson #["utf-16"])]),
        ("workspace", Json.mkObj [("configuration", toJson true), ("workspaceFolders", toJson true)]),
        ("textDocument", Json.mkObj [
          ("publishDiagnostics", Json.mkObj [("versionSupport", toJson true)]),
          ("definition", Json.mkObj [("linkSupport", toJson true)]),
          ("diagnostic", Json.mkObj [("relatedDocumentSupport", toJson false)]),
          ("semanticTokens", Json.mkObj [
            ("requests", Json.mkObj [("full", toJson true)]),
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
    unless encoding == "utf-16" do throw <| IO.userError s!"unsupported position encoding: {encoding}"
    client.notify "initialized" (Json.mkObj [])
    return client
  catch error =>
    discard <| client.close
    throw error

end Parley
