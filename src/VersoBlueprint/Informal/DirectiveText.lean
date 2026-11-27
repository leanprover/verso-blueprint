/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual

open Lean Verso Doc Elab Lean.Doc.Syntax

namespace Informal

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

def blocksPlainText (contents : Array (TSyntax `block)) : DocElabM String := do
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

end Informal
