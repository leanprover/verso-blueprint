/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoManual
public meta import VersoManual
public meta import VersoBlueprint.Data
public meta import VersoBlueprint.Environment
public meta import VersoBlueprint.LabelNameParsing
public meta import VersoBlueprint.Profiling

public meta section

open Verso Doc Elab
open Verso.Genre Manual
open Verso.ArgParse
open Lean.Doc.Syntax
open Lean Elab

namespace Informal

structure AuthorConfig where
  label : Data.AuthorId
  labelSyntax : Syntax := Syntax.missing
  name : Option String := none
  url : Option String := none
  imageUrl : Option String := none

section
variable [Monad m] [MonadError m]

def AuthorConfig.parse : ArgParse m AuthorConfig :=
  (fun (labelArg : Verso.ArgParse.WithSyntax String) name url imageUrl =>
    {
      label := LabelNameParsing.parse labelArg.val
      labelSyntax := labelArg.syntax
      name
      url
      imageUrl
    }) <$> .positional `label (.withSyntax .string) <*> .named `name .string true
        <*> .named `url .string true <*> .named `image_url .string true

instance : FromArgs AuthorConfig m where
  fromArgs := AuthorConfig.parse

end

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

private def authorNameFromContents (contents : Array (TSyntax `block)) : DocElabM String := do
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

private def authorExpanderImpl : DirectiveExpanderOf AuthorConfig
  | cfg, contents => do
    let displayName :=
      match cfg.name with
      | some name => name.trimAscii.toString
      | none => ""
    let displayName ←
      if displayName.isEmpty then authorNameFromContents contents else pure displayName
    if displayName.isEmpty then
      logWarningAt cfg.labelSyntax m!"Author {cfg.label} has no display name; using the author id as fallback"
    Environment.registerAuthor cfg.label {
      displayName := if displayName.isEmpty then cfg.label.toString else displayName
      url := cfg.url.map (·.trimAscii.toString)
      imageUrl := cfg.imageUrl.map (·.trimAscii.toString)
    }
    ``(Block.concat #[])

@[directive] def «author» : DirectiveExpanderOf AuthorConfig
  | cfg, contents => do
    Profile.withDocElab "directive" "author" <|
      authorExpanderImpl cfg contents

end Informal
