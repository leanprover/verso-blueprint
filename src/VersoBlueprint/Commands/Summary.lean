/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Lean.Elab.Command
import Verso
import VersoManual
import VersoBlueprint.Commands.Common
import VersoBlueprint.Commands.Summary.Collect
import VersoBlueprint.Commands.Summary.Render

namespace Informal.Commands

open Lean Elab Command
open Informal Data Environment

open Verso Doc Elab Syntax in
def mkSummaryPart (stx : Syntax) (endPos : String.Pos.Raw) : PartElabM FinishedPart := do
  let titlePreview := "Blueprint Summary"
  let titleInlines ← `(inline | "Blueprint Summary")
  let expandedTitle ← #[titleInlines].mapM (elabInline ·)
  let metadata : Option (TSyntax `term) := some (← `(term| { number := false }))
  let summary ← buildSummary
  if verso.blueprint.debug.commands.get (← Lean.getOptions) then
    logInfo m!"Blueprint summary for {summary.totalEntries} entries"
  let block ← ``(Verso.Doc.Block.other (Informal.Commands.Block.summary $(quote summary)) #[])
  let subParts := #[]
  pure <| FinishedPart.mk stx stx expandedTitle titlePreview metadata #[block] subParts endPos

open Verso Doc Elab Syntax PartElabM in
@[part_command Lean.Doc.Syntax.command]
public meta def blueprintSummaryCmd : PartCommand
  | stx@`(block|command{blueprint_summary}) => do
    let endPos := stx.getTailPos?.get!
    closePartsUntil 1 endPos
    addPart (← mkSummaryPart stx endPos)
  | _ => (Lean.Elab.throwUnsupportedSyntax : PartElabM Unit)

end Informal.Commands
