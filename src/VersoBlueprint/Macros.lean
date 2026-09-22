/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoBlueprint.Macros.Data
public meta import Lean
public meta import VersoBlueprint.Macros.Data

public meta section

namespace Informal.Macros

open Lean Elab Command

private def normalizeChunk (chunk : String) : String :=
  chunk.trimAscii.toString

syntax (name := texPreludeTableJsTerm) "tex_prelude_table_js%" : term

@[term_elab texPreludeTableJsTerm]
def elabTexPreludeTableJsTerm : Lean.Elab.Term.TermElab
  | _stx, _expectedType? => do
    let prelude ← getTexPrelude
    return Lean.ToExpr.toExpr (texPreludeTableJs prelude)

syntax (name := texPreludeCmd) "tex_prelude" str : command

@[command_elab texPreludeCmd]
def elabTexPrelude : CommandElab
  | `(tex_prelude $chunk:str) => do
    let chunk := normalizeChunk chunk.getString
    if !chunk.isEmpty then
      modifyEnv fun env =>
        texPreludeExt.addEntry env chunk
  | _ => throwUnsupportedSyntax

end Informal.Macros
