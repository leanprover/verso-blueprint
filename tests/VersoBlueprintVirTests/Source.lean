/- Copyright (c) 2026 Lean FRO LLC. Released under Apache 2.0 license. -/
module

meta import VersoBlueprintVir.Preview.Source

open Lean Verso.Doc.Elab VersoBlueprint.Experimental.VirPreview

private meta def atRange (start stop : Nat) : Syntax :=
  .atom (.synthetic ⟨start⟩ ⟨stop⟩ false) "source"

private meta def child : FinishedPart :=
  .mk (atRange 20 25) (atRange 21 25) #[] "Section" none
    #[⟨atRange 30 40⟩, ⟨atRange 45 60⟩] #[] ⟨60⟩

private meta def document : FinishedPart :=
  .mk (atRange 5 15) (atRange 7 14) #[] "Document" none #[]
    #[child, .included ⟨atRange 70 80⟩] ⟨90⟩

#guard Source.focusAt document ⟨0⟩ == none
#guard Source.focusAt document ⟨5⟩ == some "part-root-heading"
#guard Source.focusAt document ⟨20⟩ == some "part-root-part-0-heading"
#guard Source.focusAt document ⟨30⟩ == some "part-root-part-0-block-0"
#guard Source.focusAt document ⟨39⟩ == some "part-root-part-0-block-0"
#guard Source.focusAt document ⟨40⟩ == none
#guard Source.focusAt document ⟨45⟩ == some "part-root-part-0-block-1"
#guard Source.focusAt document ⟨70⟩ == some "part-root-part-1-heading"
#guard Source.focusAt document ⟨80⟩ == none
#guard Source.focusAt document ⟨90⟩ == none
#guard Source.focusAt (.mk .missing .missing #[] "" none #[⟨.missing⟩] #[] ⟨0⟩) ⟨0⟩ == none

-- LSP columns count UTF-16 units, whereas retained syntax ranges count UTF-8 bytes.
#guard (FileMap.ofString "α😀x").lspPosToUtf8Pos ⟨0, 3⟩ == (⟨6⟩ : String.Pos.Raw)
