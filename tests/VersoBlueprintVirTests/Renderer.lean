/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoBlueprintVir.Preview.Renderer
meta import VersoBlueprintVir.Preview.Renderer
meta import Vir.Attributes

public section

namespace VersoBlueprintVirTests.Renderer

open Verso Verso.Doc Lean.Vir Lean.Vir.React
open VersoBlueprint.Experimental.VirPreview

private def block (name : Lean.Name) (data : Lean.Json)
    (content : Array (Block Genre.Manual) := #[]) : Block Genre.Manual :=
  .other { name, data } content

private def informal (body : String) : Block Genre.Manual :=
  block `Informal.Block.informal
    (Lean.toJson ({ label := `independent, isProof := true, count := 0 } : Informal.BlockOccurrence))
    #[.para #[.text body]]

private def markup (display : Informal.ExternalMarkupDisplayMode) : Block Genre.Manual :=
  block `Informal.Block.externalMarkup (Lean.toJson ({
    label := `independent
    markup := { language := .markdown, slot := "source", raw := "<script>raw source</script>" }
    display
  } : Informal.ExternalMarkupBlockData)) #[.para #[.text "not rendered"]]

private def document (content : Array (Block Genre.Manual)) : Document := {
  version := 7
  correlationId := "renderer-package-7"
  cursorToken := "1:0"
  document := .mk #[.text "Blueprint adapter"] "Blueprint adapter" none content #[]
}

private def math (source prelude : String) : Inline Genre.Manual :=
  .other { name := `Informal.Math.Inline.bpMath, data := Lean.toJson ({
    mode := .inline, source, texPrelude := prelude
  } : Informal.Math.BpMathData) } #[]

#guard Renderer.changedBlockIds (document #[informal "old"]) (document #[informal "new"]) ==
  #["part-root-block-0", "part-root-block-0-block-0"]

private def rich := document #[
  .para #[math "\\RR" "\\newcommand{\\RR}{R}",
    math "\\RR + 1" "\\newcommand{\\RR}{R}",
    math "a" "\\newcommand{\\AA}{A}", math "b" "\\newcommand{\\RR}{R}",
    math "c" ""],
  informal "retained proof body",
  markup .hidden, markup .summary, markup .source,
  block `Informal.Block.informal .null #[.para #[.text "malformed child"]],
  block `Informal.Block.externalMarkup .null,
  .para #[.other { name := `Informal.Math.Inline.bpMath, data := .null } #[]]
]

@[vir_export]
def render : ReactM (Js Node) := do
  VersoBlueprint.Experimental.VirPreview.Renderer.render
    (← VersoBlueprint.Experimental.VirPreview.Renderer.Styles.create) rich

end VersoBlueprintVirTests.Renderer
