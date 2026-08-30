/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import Lean

public section

namespace Informal.HtmlId

private def hexDigits : Array Char := "0123456789ABCDEF".toList.toArray

private theorem hexDigits_size : hexDigits.size = 16 := by
  native_decide

private def toHex (n : Nat) : String := Id.run do
  let mut n := n
  let mut digits := #[]
  repeat
    if h : n < 16 then
      digits := digits.push <| hexDigits[n]'(by
        simpa [hexDigits_size] using h)
      break
    else
      digits := digits.push <| hexDigits[n % 16]'(by
        simpa [hexDigits_size] using Nat.mod_lt n (by decide : 0 < 16))
      n := n >>> 4
  let padding := (4 - digits.size).fold (init := "") (fun _ _ p => p.push '0')
  digits.foldr (init := padding) fun c s => s.push c

/--
Encode arbitrary text as a stable DOM-id suffix.

This preserves distinctions that `String.sluggify` intentionally normalizes
away, which matters for ids derived from declaration names.
-/
def key (s : String) : String :=
  s.foldl (init := "") fun acc c =>
    if c.isAlphanum then
      acc.push c
    else if c == '-' then
      acc |>.push '-' |>.push '-'
    else
      acc ++ s!"-{toHex c.toNat}"

/-- Build a DOM id from a fixed prefix and an encoded value. -/
def prefixed (idPrefix value : String) : String :=
  let body := key value
  if body.isEmpty then idPrefix else s!"{idPrefix}-{body}"

end Informal.HtmlId
