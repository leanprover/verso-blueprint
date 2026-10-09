/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoManual
public import VersoBlueprint.Commands.SerializedExtension
public import VersoBlueprint.Commands.Summary.Collect
public import VersoBlueprint.Commands.Summary.Sections
meta import Lean
meta import Lean.Elab.Command
meta import Verso
public meta import VersoManual
meta import VersoBlueprint.Commands.Common
meta import VersoBlueprint.Commands.SerializedExtension
meta import VersoBlueprint.Commands.Summary.Collect
public meta import VersoBlueprint.Commands.Summary.Sections
public meta import VersoBlueprint.Environment

public section

namespace Informal.Commands

open Lean Elab Command
open Informal Environment

open Verso Doc Elab Syntax in
private meta def mkSummaryPart (stx : Syntax) (endPos : String.Pos.Raw) : PartElabM FinishedPart := do
  let titlePreview := "Blueprint Summary"
  let titleInlines ← `(inline | "Blueprint Summary")
  let expandedTitle ← #[titleInlines].mapM (elabInline ·)
  let metadata : Option (TSyntax `term) := some (← `(term| { number := false }))
  reportImportedConflicts
  let options ← Lean.getOptions
  if verso.blueprint.debug.commands.get (← Lean.getOptions) then
    let count := (informalExt.getState (← getEnv)).data.size
    logInfo m!"Blueprint summary for {count} entries"
  let block ← serializedBlockTerm `Informal.Commands.Block.summary
    ({ showDebugDiagnostics := verso.blueprint.summary.debugDiagnostics.get options } : SummaryBlockData)
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
