/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Parley
import ParleyDocs.Blueprint
import VersoBlueprint.PreviewManifest

open Lean Verso Verso.Doc Verso.Genre.Manual Parley

private def requests : IO (Array Request) := do
  let plain ← IO.ofExcept <| VersoParley.collect ParleyDocs.plain.toPart
  let blueprint ← IO.ofExcept <| VersoParley.collect ParleyDocs.blueprintDocument.text
  unless plain == blueprint do throw <| IO.userError "Blueprint changed the compiled analysis requests"
  return plain

private def awaitRust (client : Client) : IO Json := do
  let deadline := (← IO.monoMsNow) + 15000
  repeat
    let (notifications, dropped) ← client.notifications
    unless dropped == 0 do throw <| IO.userError "readiness trace overflow"
    if let some status := notifications.toList.reverse.find? (fun message =>
        (message.getObjValAs? String "method").toOption == some "experimental/serverStatus") then
      let params ← IO.ofExcept <| status.getObjVal? "params"
      if (params.getObjValAs? Bool "quiescent").toOption == some true then
        unless (params.getObjValAs? String "health").toOption == some "ok" do
          throw <| IO.userError s!"Rust workspace is not healthy: {params.compress}"
        return params
    unless (← IO.monoMsNow) < deadline do throw <| IO.userError "Rust workspace readiness timed out"
    IO.sleep 5
  throw <| IO.userError "unreachable readiness loop"

private def rustDiagnostics (document : Document) : IO DiagnosticEvidence := do
  let uri := document.uri
  let completion ← document.withClient awaitRust
  let result ← document.call "textDocument/diagnostic" <| Json.mkObj [
    ("textDocument", Json.mkObj [("uri", toJson uri)])]
  return {
    coverage := "rust-analyzer native diagnostics; compiler checks disabled"
    completion
    diagnostics := ← IO.ofExcept <| result.getObjValAs? (Array Lsp.Diagnostic) "items" }

private def rocqDiagnostics (document : Document) : IO DiagnosticEvidence := do
  let uri := document.uri
  let completion ← document.call "coq/getDocument" <| Json.mkObj [
    ("textDocument", Json.mkObj [("uri", toJson uri), ("version", toJson document.version)])]
  let status := completion.getObjVal? "completed" >>= (·.getObjValAs? (Array String) "status")
  unless status.toOption == some #["Yes"] do
    throw <| IO.userError "Rocq document processing did not complete"
  let deadline := (← IO.monoMsNow) + 3000
  repeat
    if let some snapshot ← document.diagnostics then
      if snapshot.version? == some document.version then
        return {
          coverage := "Rocq document processing and versioned push diagnostics"
          completion, diagnostics := snapshot.diagnostics }
    unless (← IO.monoMsNow) < deadline do throw <| IO.userError "missing Rocq diagnostics"
    IO.sleep 2
  throw <| IO.userError "unreachable diagnostics loop"

/-- Only this fixture runner creates project scaffolding, under the requested
experiment output. The reusable analyzer never writes project source. -/
private def profiles (root : System.FilePath) (rust rocq : String) : IO (Array ContextProfile) := do
  IO.FS.createDirAll root
  let root ← IO.FS.realPath root
  let rustRoot := root / "rust-values"
  IO.FS.createDirAll (rustRoot / "src")
  unless ← (rustRoot / "Cargo.toml").pathExists do
    IO.FS.writeFile (rustRoot / "Cargo.toml")
      "[package]\nname = \"parley-docs\"\nversion = \"0.0.0\"\nedition = \"2021\"\n[workspace]\n"
  unless ← (rustRoot / "src/lib.rs").pathExists do
    IO.FS.writeFile (rustRoot / "src/lib.rs") "// Owned analysis overlay target.\n"
  let rustProfile : ContextProfile := {
    key := "rust-values", languageId := "rust"
    client := {
      command := rust, root := rustRoot, timeoutMs := 15000
      initializationOptions := Json.mkObj [
        ("checkOnSave", toJson false),
        ("cargo", Json.mkObj [("buildScripts", Json.mkObj [("enable", toJson false)])]),
        ("procMacro", Json.mkObj [("enable", toJson false)])]
      experimentalCapabilities := Json.mkObj [("serverStatusNotification", toJson true)] }
    document := rustRoot / "src/lib.rs"
    referencePrefix := "const _: () = { let _ = "
    referenceSuffix := "; };"
    collectDiagnostics := rustDiagnostics }
  let mut result := #[rustProfile]
  for key in #["rocq-names", "rocq-invalid"] do
    let rocqRoot := root / key
    IO.FS.createDirAll rocqRoot
    unless ← (rocqRoot / "_CoqProject").pathExists do
      IO.FS.writeFile (rocqRoot / "_CoqProject") "-Q . VersoDocs\n"
    unless ← (rocqRoot / "Probe.v").pathExists do
      IO.FS.writeFile (rocqRoot / "Probe.v") "(* Owned analysis overlay target. *)\n"
    result := result.push {
      key, languageId := "coq"
      client := {
        command := rocq, root := rocqRoot, timeoutMs := 15000
        initializationOptions := Json.mkObj [("check_only_on_request", toJson false)] }
      document := rocqRoot / "Probe.v"
      referencePrefix := "Check ", referenceSuffix := "."
      collectDiagnostics := rocqDiagnostics }
  return result

private def loadBundle (path : String) : IO Bundle := do
  let bundle ← IO.ofExcept <| Json.parse (← IO.FS.readFile path) >>= fromJson? (α := Bundle)
  IO.ofExcept bundle.validate
  return bundle

private def render (bundlePath output kind : String) : IO UInt32 := do
  let bundle ← loadBundle bundlePath
  let arguments := ["--output", output, "--with-html-single", "--without-html-multi", "--with-tex"]
  if kind == "plain" then
    let text ← IO.ofExcept <| VersoParley.enrich bundle ParleyDocs.plain.toPart
    manualMain text (extensionImpls := by exact extension_impls%) arguments
  else if kind == "blueprint" then
    let document := ParleyDocs.blueprintDocument
    let text ← IO.ofExcept <| VersoParley.enrich bundle document.text
    Informal.PreviewManifest.blueprintMainWithPreviewData text arguments
      (extensionImpls := by exact extension_impls%) (model := document.model)
  else throw <| IO.userError "expected plain or blueprint"

def main (args : List String) : IO UInt32 := do
  match args with
  | ["plan", output] =>
    IO.FS.writeFile output (toJson (← requests)).pretty
    return 0
  | ["analyze", output, runtimeRoot, rust, rocq] =>
    let bundle ← analyze (← profiles runtimeRoot rust rocq) (← requests)
    IO.FS.writeFile output (toJson bundle).pretty
    IO.println s!"Analyzed {bundle.requests.size} requests in {bundle.contexts.size} contexts"
    return 0
  | ["render", bundle, output, kind] => render bundle output kind
  | ["baseline", output] =>
    let document := ParleyDocs.blueprintDocument
    Informal.PreviewManifest.blueprintMainWithPreviewData document.text
      ["--output", output, "--with-html-single", "--without-html-multi", "--with-tex"]
      (extensionImpls := by exact extension_impls%) (model := document.model)
  | ["check", bundlePath] =>
    let bundle ← loadBundle bundlePath
    let requestPlan ← requests
    for request in requestPlan do discard <| IO.ofExcept <| bundle.find request
    let request := requestPlan[0]!
    unless !(bundle.find { request with text := request.text ++ " " }).isOk do
      throw <| IO.userError "changed source accepted an obsolete snapshot"
    let some saved := bundle.requests[0]? | throw <| IO.userError "expected a nonempty analysis bundle"
    unless !({ bundle with requests := bundle.requests.push saved }.validate).isOk do
      throw <| IO.userError "duplicate snapshot identity was accepted"
    let once ← IO.ofExcept <| VersoParley.enrich bundle ParleyDocs.plain.toPart
    let twice ← IO.ofExcept <| VersoParley.enrich bundle once
    unless toJson once == toJson twice do throw <| IO.userError "snapshot replay is not idempotent"
    IO.println "Compiled plans agree, snapshot replay matches, and changed source is rejected"
    return 0
  | _ => throw <| IO.userError "usage: parley-docs plan FILE | analyze FILE RUNTIME_ROOT RUST ROCQ | render BUNDLE OUTPUT plain|blueprint | check BUNDLE | baseline OUTPUT"
