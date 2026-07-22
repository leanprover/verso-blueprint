/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import Verso.Doc.Elab
import VersoBlueprint.Environment
import VersoBlueprint.Graft

set_option doc.verso true

namespace Informal.ModuleInclude

open Lean
open Verso Doc Elab Syntax ArgParse

/-- Selection and presentation options for `{includeBlueprintModule ...}`. -/
public structure BlueprintModuleConfig where
  level? : Option Nat := none
  moduleName : Name
  title? : Option String := none
deriving Inhabited, Repr

public meta instance : FromArgs BlueprintModuleConfig PartElabM where
  fromArgs :=
    ((fun level moduleName title? =>
        { level? := some level, moduleName, title? })
      <$> .positional' `level
      <*> .positional' `module
      <*> .named' `title true) <|>
    ((fun moduleName title? => { moduleName, title? })
      <$> .positional' `module
      <*> .named' `title true)

private def moduleIsImported (env : Lean.Environment) (moduleName : Name) : Bool :=
  env.header.moduleNames.contains moduleName

private def defaultTitle (moduleName : Name) : String :=
  moduleName.getString!

private meta def mkBlueprintModulePart
    (stx : Syntax) (endPos : String.Pos.Raw) (cfg : BlueprintModuleConfig) :
    PartElabM FinishedPart := do
  unless ← PartElabM.liftDocElabM Informal.Graft.inManualGenre do
    throwErrorAt stx
      "Blueprint module include is only available in Manual documents"
  let env ← getEnv
  unless moduleIsImported env cfg.moduleName do
    throwErrorAt stx
      "Blueprint module include: module '{cfg.moduleName}' is not available through this Lean module's imports; add `import {cfg.moduleName}`"
  Informal.Environment.reportImportedConflicts
  let nodes ← Informal.Environment.blueprintAttributeNodesForModule cfg.moduleName
  if nodes.isEmpty then
    throwErrorAt stx
      "Blueprint module include: imported module '{cfg.moduleName}' has no declarations registered with `@[blueprint]`"
  let title := cfg.title?.getD (defaultTitle cfg.moduleName)
  let titleInline ← ``(Verso.Doc.Inline.text $(quote title))
  let blocks ← nodes.mapM fun label =>
    PartElabM.liftDocElabM <| Informal.Graft.blueprintNodeBlock {
      label := label.getString!
    }
  pure <| FinishedPart.mk stx stx #[titleInline] title none blocks #[] endPos

open PartElabM in
@[part_command Lean.Doc.Syntax.command]
public meta def includeBlueprintModuleCmd : PartCommand
  | stx@`(block|command{includeBlueprintModule $args*}) => do
    let cfg ← Verso.ArgParse.parseThe BlueprintModuleConfig (← parseArgs args)
    let endPos := stx.getTailPos?.get!
    let part ← mkBlueprintModulePart stx endPos cfg
    if let some level := cfg.level? then
      closePartsUntil level endPos
    addPart part
  | _ => (Lean.Elab.throwUnsupportedSyntax : PartElabM Unit)

end Informal.ModuleInclude
