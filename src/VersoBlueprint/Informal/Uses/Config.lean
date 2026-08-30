/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public meta import Lean
public meta import VersoManual
public meta import VersoBlueprint.Data
public meta import VersoBlueprint.Informal.LabelArg
public meta import VersoBlueprint.Informal.UseConfig

public meta section

open Verso Doc Elab
open Verso.ArgParse
open Lean

namespace Informal

/--
Arguments accepted by the inline `{uses ...}` role.

This role renders a reference and registers a dependency edge from the enclosing
block. Its `origin` and `intent` options share the same metadata semantics as
block-level `(uses_origin := ...)` and `(uses_intent := ...)`.
-/
structure UsesConfig where
  label : Data.Label
  labelSyntax : Syntax := Syntax.missing
  origin : Data.UseOrigin := .manual
  invalidOrigin : Option String := none
  intent : Data.UseIntent := .regular
  invalidIntent : Option String := none

/--
Arguments accepted by the inline `{bpref ...}` role.

`bpref` renders the same kind of hoverable Blueprint reference as `{uses ...}`,
but deliberately does not accept dependency metadata or register a use edge.
-/
structure BprefConfig where
  label : Data.Label
  labelSyntax : Syntax := Syntax.missing

section
variable [Monad m] [MonadError m]

def UsesConfig.parse : ArgParse m UsesConfig :=
  (fun (labelArg : Verso.ArgParse.WithSyntax String) origin intent =>
    let parsedLabel := LabelArg.parse labelArg
    let metadata := UseConfig.parseMetadata origin intent
    {
      label := parsedLabel.label
      labelSyntax := parsedLabel.labelSyntax
      origin := metadata.origin
      invalidOrigin := metadata.invalidOrigin
      intent := metadata.intent
      invalidIntent := metadata.invalidIntent
    }) <$> .positional `label (.withSyntax .string)
        <*> .named `origin .string true <*> .named `intent .string true

instance : FromArgs UsesConfig m where
  fromArgs := UsesConfig.parse

def BprefConfig.parse : ArgParse m BprefConfig :=
  (fun (labelArg : Verso.ArgParse.WithSyntax String) =>
    let parsedLabel := LabelArg.parse labelArg
    {
      label := parsedLabel.label
      labelSyntax := parsedLabel.labelSyntax
    }) <$> .positional `label (.withSyntax .string)

instance : FromArgs BprefConfig m where
  fromArgs := BprefConfig.parse

end

end Informal
