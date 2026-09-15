/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Lean.Data.Json.Printer
import all Lean.Data.Json.Printer

public section

namespace VersoReact.Json

-- Experimental only: reuse the pinned printer's private byte-escape policy.
private partial def escapeLoop (s : String) (pos : String.Pos.Raw) (acc : String) : String :=
  if pos.atEnd s then acc
  else escapeLoop s (pos.next s) (Lean.Json.escapeAux acc (pos.get s))

private def renderString (s acc : String) : String :=
  let acc := acc ++ "\""
  let acc := if Lean.Json.needEscape s then escapeLoop s ⟨0⟩ acc else acc ++ s
  acc ++ "\""

/-- Experimental compact JSON writer. A single explicit work list keeps traversal
tail-recursive while reusing Lean's exact string and number formatting. -/
partial def compress (value : Lean.Json) : String :=
  go "" [.inl value]
where
  go (acc : String) : List (Lean.Json ⊕ String) → String
    | [] => acc
    | .inr literal :: rest => go (acc ++ literal) rest
    | .inl value :: rest =>
      match value with
      | .null => go (acc ++ "null") rest
      | .bool b => go (acc ++ toString b) rest
      | .num n => go (acc ++ toString n) rest
      | .str s => go (renderString s acc) rest
      | .arr values =>
        let (work, _) := values.foldr (init := ((.inr "]" :: rest), true)) fun value (work, last) =>
          (.inl value :: (if last then work else .inr "," :: work), false)
        go (acc ++ "[") work
      | .obj fields =>
        let (work, _) := fields.foldr (init := ((.inr "}" :: rest), true)) fun key value (work, last) =>
          (.inl (.str key) :: .inr ":" :: .inl value ::
            (if last then work else .inr "," :: work), false)
        go (acc ++ "{") work

end VersoReact.Json
