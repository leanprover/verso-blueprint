/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual

import VersoBlueprint.Informal.DirectiveText
import VersoBlueprint.Data
import VersoBlueprint.Environment
import VersoBlueprint.Informal.GroupData
import VersoBlueprint.LabelNameParsing
import VersoBlueprint.Lib.ExtensionDecode
import VersoBlueprint.Profiling
import VersoBlueprint.Resolve
import VersoBlueprint.TraversalIndex

open Verso Doc Elab
open Verso.Genre Manual
open Verso.ArgParse
open Lean.Doc.Syntax
open Lean Elab

namespace Informal

structure GroupConfig where
  label : Data.Label
  labelSyntax : Syntax := Syntax.missing
deriving Inhabited

section
variable [Monad m] [MonadError m]

def GroupConfig.parse : ArgParse m GroupConfig :=
  (fun (labelArg : Verso.ArgParse.WithSyntax String) =>
    {
      label := LabelNameParsing.parse labelArg.val
      labelSyntax := labelArg.syntax
    }) <$> .positional `label (.withSyntax .string)

instance : FromArgs GroupConfig m where
  fromArgs := GroupConfig.parse

end

open Verso Doc Elab Genre Manual in
block_extension Block.groupMetadata (groupData : GroupBlockData) where
  data := toJson groupData
  traverse _id data _contents := do
    let some groupData ← ExtensionDecode.decode? (α := GroupBlockData) data
        (fun _ => "Malformed data in Block.groupMetadata.traverse")
      | return none
    modify fun st =>
      Informal.TraversalIndex.Groups.saveData st groupData.label (toJson groupData)
    return none
  toTeX := some <| fun _ _ _ _ _ => pure .empty
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun _ _ _ data _ => do
      let some _ ← ExtensionDecode.decode? (α := GroupBlockData) data
          (fun _ => "Malformed data in Block.groupMetadata.toHtml")
        | pure .empty
      pure .empty

private def groupExpanderImpl : DirectiveExpanderOf GroupConfig
  | cfg, contents => do
    let header ← blocksPlainText contents
    let headerWasEmpty := header.isEmpty
    let header := if headerWasEmpty then cfg.label.toString else header
    if headerWasEmpty then
      logWarningAt cfg.labelSyntax m!"Group {cfg.label} has an empty body; using the group label as header text"
    let groupData : GroupBlockData := { label := cfg.label, header }
    Environment.registerGroup cfg.label header
    ``(Block.other (Block.groupMetadata $(quote groupData)) #[])

@[directive] def «group» : DirectiveExpanderOf GroupConfig
  | cfg, contents => do
    Profile.withDocElab "directive" "group" <|
      groupExpanderImpl cfg contents

end Informal
