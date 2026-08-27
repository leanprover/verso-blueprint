import Lean.Compiler.IR.CompilerM
import VersoBlueprint.PreviewManifest
import VersoBlueprint.Commands.Bibliography
import VersoBlueprint.Commands.Graph
import VersoBlueprint.Commands.Summary
import VersoBlueprint.Informal.Code
import VersoBlueprint.Informal.Uses
import VersoBlueprint.Math

open Lean
open Verso Doc
open Verso.Genre Manual

private def runtimeModule : Name := `VersoBlueprint.RuntimeBundle

private def documentName : Name := Verso.Doc.docName `FLTBlueprint

private unsafe def loadDocument (bundlePath : System.FilePath) : IO (VersoDoc Manual) := do
  Lean.enableInitializersExecution
  let artifacts : Lean.NameMap ImportArtifacts :=
    ({} : Lean.NameMap ImportArtifacts).insert runtimeModule (.ofArrays #[#[bundlePath]])
  let env ← Lean.importModules
    #[{ module := runtimeModule }]
    {}
    (leakEnv := true)
    (arts := artifacts)
  match env.evalConst (VersoDoc Manual) {} documentName (checkMeta := false) with
  | .ok document => pure document
  | .error error => throw <| IO.userError error

unsafe def main (args : List String) : IO UInt32 := do
  let bundlePath :: rendererArgs := args
    | IO.eprintln "usage: runtimeBundleHost <bundle.olean> [vbp options]"
      return 2
  let document ← loadDocument bundlePath
  Informal.PreviewManifest.blueprintMainWithPreviewData
    document.toPart
    rendererArgs
    (extensionImpls := by exact extension_impls%)
    (config := { htmlDepth := 1 })
