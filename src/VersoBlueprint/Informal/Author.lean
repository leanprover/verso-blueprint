/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual

import VersoBlueprint.Informal.DirectiveText
import VersoBlueprint.Data
import VersoBlueprint.Environment
import VersoBlueprint.LabelNameParsing
import VersoBlueprint.Profiling

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

private def authorExpanderImpl : DirectiveExpanderOf AuthorConfig
  | cfg, contents => do
    let displayName :=
      match cfg.name with
      | some name => name.trimAscii.toString
      | none => ""
    let displayName ←
      if displayName.isEmpty then blocksPlainText contents else pure displayName
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
