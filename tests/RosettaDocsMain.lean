/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Rosetta
import RosettaDocs.Blueprint
import VersoBlueprint.PreviewManifest

open Lean Verso Verso.Doc Verso.Genre.Manual Rosetta

private def requests : IO (Array Request) := do
  let plain ← IO.ofExcept <| VersoRosetta.collect RosettaDocs.plain.toPart
  let blueprint ← IO.ofExcept <| VersoRosetta.collect RosettaDocs.blueprintDocument.text
  unless plain == blueprint do throw <| IO.userError "Blueprint changed the compiled analysis requests"
  return plain

private def awaitRust (client : Client) : EIO ClientError Json := do
  let deadline := (← IO.monoMsNow) + 15000
  repeat
    if let some params ← client.latestNotification "experimental/serverStatus" then
      if (params.getObjValAs? Bool "quiescent").toOption == some true then
        unless (params.getObjValAs? String "health").toOption == some "ok" do
          throw <| ClientError.io <| IO.userError s!"Rust workspace is not healthy: {params.compress}"
        return params
    unless (← IO.monoMsNow) < deadline do throw <| ClientError.io <| IO.userError "Rust workspace readiness timed out"
    IO.sleep 5
  throw <| ClientError.io <| IO.userError "unreachable readiness loop"

private def rustDiagnostics (document : Document) : EIO ClientError DiagnosticEvidence := do
  let uri := document.uri
  let completion ← awaitRust document.client
  let result ← document.request "textDocument/diagnostic" <| Json.mkObj [
    ("textDocument", Json.mkObj [("uri", toJson uri)])]
  return {
    coverage := "rust-analyzer native diagnostics; compiler checks disabled"
    completion
    diagnostics := ← IO.ofExcept <| result.getObjValAs? (Array Lsp.Diagnostic) "items" }

private def rocqDiagnostics (document : Document) : EIO ClientError DiagnosticEvidence := do
  let uri := document.uri
  let completion ← document.request "coq/getDocument" <| Json.mkObj [
    ("textDocument", Json.mkObj [("uri", toJson uri), ("version", toJson document.version)])]
  let status := completion.getObjVal? "completed" >>= (·.getObjValAs? (Array String) "status")
  unless status.toOption == some #["Yes"] do
    throw <| ClientError.io <| IO.userError "Rocq document processing did not complete"
  let deadline := (← IO.monoMsNow) + 3000
  repeat
    if let some snapshot ← document.diagnostics then
      if snapshot.version? == some document.version then
        return {
          coverage := "Rocq document processing and versioned push diagnostics"
          completion, diagnostics := snapshot.diagnostics }
    unless (← IO.monoMsNow) < deadline do throw <| ClientError.io <| IO.userError "missing Rocq diagnostics"
    IO.sleep 2
  throw <| ClientError.io <| IO.userError "unreachable diagnostics loop"

/-- Only this fixture runner creates project scaffolding, under the requested
experiment output. The reusable analyzer never writes project source. -/
private def profiles (root : System.FilePath) (rust rocq : String) : IO (Array ContextProfile) := do
  IO.FS.createDirAll root
  let root ← IO.FS.realPath root
  let rustRoot := root / "rust-values"
  IO.FS.createDirAll (rustRoot / "src")
  unless ← (rustRoot / "Cargo.toml").pathExists do
    IO.FS.writeFile (rustRoot / "Cargo.toml")
      "[package]\nname = \"rosetta-docs\"\nversion = \"0.0.0\"\nedition = \"2021\"\n[workspace]\n"
  unless ← (rustRoot / "src/lib.rs").pathExists do
    IO.FS.writeFile (rustRoot / "src/lib.rs") "// Owned analysis overlay target.\n"
  let rustProfile : ContextProfile := {
    key := "rust-values", languageId := "rust"
    client := {
      command := rust, root := rustRoot, timeoutMs := 15000
      retainedNotificationMethods := #["experimental/serverStatus"]
      initializationOptions := Json.mkObj [
        ("checkOnSave", toJson false),
        ("cargo", Json.mkObj [("buildScripts", Json.mkObj [("enable", toJson false)])]),
        ("procMacro", Json.mkObj [("enable", toJson false)])]
      experimentalCapabilities := Json.mkObj [("serverStatusNotification", toJson true)] }
    provenance := Json.mkObj [("profile", toJson "vbp-rust-fixture"), ("serverCommand", toJson rust)]
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
      provenance := Json.mkObj [("profile", toJson "vbp-rocq-fixture"), ("serverCommand", toJson rocq)]
      document := rocqRoot / "Probe.v"
      referencePrefix := "Check ", referenceSuffix := "."
      collectDiagnostics := rocqDiagnostics }
  return result

private def loadBundle (path : String) : IO Bundle := do
  let bundle ← IO.ofExcept <| Json.parse (← IO.FS.readFile path) >>= fromJson? (α := Bundle)
  IO.ofExcept bundle.validate
  return bundle

/-- Reuse exact compiled requests on separate pages and include one twice.
The logical analysis plan remains five requests; render occurrences are distinct. -/
private def navigationPart : IO (Part Verso.Genre.Manual) := do
  let plan ← requests
  let blocks : Array (Verso.Doc.Block Verso.Genre.Manual) := plan.filterMap fun request =>
    if request.kind == .code then some (.other (VersoRosetta.Block.lspCode request) #[]) else none
  let references : Array (Verso.Doc.Block Verso.Genre.Manual) := plan.filterMap fun request =>
    if request.kind == .reference then
      some (.para #[.other (VersoRosetta.Inline.lspReference request) #[]]) else none
  let page : String → Array (Verso.Doc.Block Verso.Genre.Manual) → Part Verso.Genre.Manual := fun name content => Part.mk #[.text name] name
    (some { file := some name, htmlSplit := .default }) content #[]
  let repeated := blocks.extract 0 1
  return Part.mk #[.text "Rosetta navigation"] "Rosetta navigation" none #[] #[
    page "definitions" blocks, page "references" references, page "repeated" repeated]

private def render (bundlePath output kind : String) : IO UInt32 := do
  let bundle ← loadBundle bundlePath
  let arguments := ["--output", output, "--with-html-single", "--without-html-multi", "--with-tex"]
  if kind == "navigation" then
    let text ← IO.ofExcept <| VersoRosetta.enrich bundle (← navigationPart)
    manualMain text (extensionImpls := by exact extension_impls%)
      ["--output", output, "--with-html-single", "--with-html-multi", "--without-tex"]
  else if kind == "plain" then
    let text ← IO.ofExcept <| VersoRosetta.enrich bundle RosettaDocs.plain.toPart
    manualMain text (extensionImpls := by exact extension_impls%) arguments
  else if kind == "blueprint" then
    let document := RosettaDocs.blueprintDocument
    let text ← IO.ofExcept <| VersoRosetta.enrich bundle document.text
    Informal.PreviewManifest.blueprintMainWithPreviewData text arguments
      (extensionImpls := by exact extension_impls%) (model := document.model)
  else throw <| IO.userError "expected plain, blueprint or navigation"

def main (args : List String) : IO UInt32 := do
  match args with
  | ["plan", output] =>
    IO.FS.writeFile output (toJson (← requests)).pretty
    return 0
  | ["analyze", output, runtimeRoot, rust, rocq] =>
    let bundle ← (analyze (← profiles runtimeRoot rust rocq) (← requests)).toIO (IO.userError ∘ toString)
    IO.FS.writeFile output (toJson bundle).pretty
    IO.println s!"Analyzed {bundle.requests.size} requests in {bundle.contexts.size} contexts"
    return 0
  | ["render", bundle, output, kind] => render bundle output kind
  | ["baseline", output] =>
    let document := RosettaDocs.blueprintDocument
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
    let once ← IO.ofExcept <| VersoRosetta.enrich bundle RosettaDocs.plain.toPart
    let twice ← IO.ofExcept <| VersoRosetta.enrich bundle once
    unless toJson once == toJson twice do throw <| IO.userError "snapshot replay is not idempotent"
    IO.println "Compiled plans agree, snapshot replay matches, and changed source is rejected"
    return 0
  | _ => throw <| IO.userError "usage: rosetta-docs plan FILE | analyze FILE RUNTIME_ROOT RUST ROCQ | render BUNDLE OUTPUT plain|blueprint|navigation | check BUNDLE | baseline OUTPUT"
