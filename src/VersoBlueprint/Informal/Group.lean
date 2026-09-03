/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoManual

public import VersoBlueprint.Data
public import VersoBlueprint.Environment
public import VersoBlueprint.Informal.GroupData
public import VersoBlueprint.LabelNameParsing
public import VersoBlueprint.Lib.ExtensionDecode
public import VersoBlueprint.Profiling
public import VersoBlueprint.Resolve
public import VersoBlueprint.TraversalIndex
public meta import VersoManual
public meta import VersoBlueprint.Data
public meta import VersoBlueprint.Environment
public meta import VersoBlueprint.Informal.GroupData
public meta import VersoBlueprint.LabelNameParsing
public meta import VersoBlueprint.Lib.ExtensionDecode
public meta import VersoBlueprint.Profiling
public meta import VersoBlueprint.Resolve
public meta import VersoBlueprint.TraversalIndex

public section

open Verso Doc Elab
open Verso.Genre Manual
open Verso.ArgParse
open Lean.Doc.Syntax
open Lean Elab

namespace Informal

meta section

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

meta section

private def collapseWhitespace (s : String) : String :=
  let s := s.replace "\n" " "
  let s := s.replace "\r" " "
  let s := s.replace "\t" " "
  String.intercalate " " <| (s.splitOn " ").filter (fun chunk => !chunk.isEmpty)

private def blockChunkText (env : Environment) (block : TSyntax `block) : String :=
  match block with
  | `(block|para[$inlines*]) =>
    Verso.Doc.Elab.inlinesToString env inlines
  | `(block|header($_){$inlines*}) =>
    Verso.Doc.Elab.inlinesToString env inlines
  | _ =>
    (Syntax.reprint block.raw).getD ""

private def groupHeaderFromContents (contents : Array (TSyntax `block)) : DocElabM String := do
  let env ← getEnv
  let raw := contents.foldl (init := "") fun acc block =>
    let chunk := (blockChunkText env block).trimAscii.toString
    if chunk.isEmpty then
      acc
    else if acc.isEmpty then
      chunk
    else
      acc ++ "\n" ++ chunk
  pure (collapseWhitespace raw)

private def groupExpanderImpl : DirectiveExpanderOf GroupConfig
  | cfg, contents => do
    let header ← groupHeaderFromContents contents
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

end

end Informal
