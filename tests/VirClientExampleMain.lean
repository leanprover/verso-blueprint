/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean.Data.Json
import VersoBlueprintVirClientTests.Program
import VersoBlueprintVirClientTests.Resources
import VersoBlueprint.PreviewManifest

private def sampleEntry : Informal.PreviewManifest.Entry := {
  label := `external_markup_example
  key := "externalMarkup:external_markup_example"
  targetKind := .externalMarkup
  facet := .statement
  title := "External markup example"
  externalMarkup := #[
    { language := .markdown, slot := "statement", raw := "# A Blueprint attachment\n\nFor every natural number n, n + 0 = n." },
    { language := .tex, slot := "statement", raw := "\\forall n \\in \\mathbb{N},\\; n + 0 = n" },
    { language := .markdown, slot := "proof", raw := "By the defining equation of addition." }]
}

private def sampleEntries : Array Informal.PreviewManifest.Entry := #[
  sampleEntry,
  { sampleEntry with
    key := "external_markup_example--proof", facet := .proof
    externalMarkup := #[sampleEntry.externalMarkup[2]!] },
  { sampleEntry with
    label := `native_only_example, authoredLabel := "native_only_example"
    key := "native_only_example--statement", targetKind := .block
    title := "Native-only example", externalMarkup := #[] }]

private def selectionCases : IO Lean.Json := do
  let cases ← IO.ofExcept <| Lean.Json.parse (include_str "external_markup_selection_cases.json")
  for caseEntry in (← IO.ofExcept cases.getArr?) do
    let input ← IO.ofExcept <| caseEntry.getObjVal? "input"
    let expected ← IO.ofExcept <| caseEntry.getObjValAs? VersoBlueprint.ExternalMarkup.Selection "expected"
    let actual ← IO.ofExcept <| Lean.Json.parse (VersoBlueprint.ExternalMarkup.selectMarkup input.compress)
      >>= Lean.fromJson? (α := VersoBlueprint.ExternalMarkup.Selection)
    unless actual == expected do
      throw <| IO.userError s!"native external markup selection mismatch: {caseEntry.compress}"
  return cases

/-- Publish the VIR application example and native regression results. -/
def main (args : List String) : IO Unit := do
  let [output] := args
    | throw <| IO.userError "usage: vir-client-example OUTPUT"
  let directory := System.FilePath.mk output
  let site ← IO.ofExcept <|
    (VersoBlueprintVirClientTests.resources.forSite "lib/vir").mapError reprStr
  unless site.programManifests.size == 1 do
    throw <| IO.userError "the client example requires exactly one program"
  for file in site.files do
    let path := directory / file.path
    IO.FS.createDirAll (path.parent.getD directory)
    IO.FS.writeBinFile path file.bytes
  let inputs := #["", "FLT", "Fermat’s Last Theorem", "Προεπισκόπηση 🦀"]
  let cases := inputs.map fun input => Lean.Json.mkObj [
    ("input", Lean.toJson input),
    ("expected", Lean.toJson (VersoBlueprintVirClientTests.Program.title input))]
  let selectionCases ← selectionCases
  let client := Lean.Json.mkObj [
    ("runtimeModule", Lean.toJson site.runtimeModule),
    ("runtimeManifest", Lean.toJson site.runtimeManifest),
    ("programManifest", Lean.toJson site.programManifests[0]!),
    ("entry", Lean.toJson (``VersoBlueprintVirClientTests.Program.title).toString),
    ("cases", Lean.Json.arr cases),
    ("selectionCases", selectionCases)]
  IO.FS.writeFile (directory / "client.json") client.compress
  -- Use the existing generated-site asset writer, not a second JS bundler.
  Informal.PreviewManifest.writeBlueprintRuntimeModules (directory / "-verso-data")
  IO.FS.writeFile (directory / "example.json") <| (Lean.Json.mkObj [
    ("previews", Lean.toJson sampleEntries)]).compress
  IO.FS.writeFile (directory / "index.html") (include_str "../examples/external-markup/index.html")
  IO.FS.writeFile (directory / "client.mjs") (include_str "../examples/external-markup/client.mjs")
