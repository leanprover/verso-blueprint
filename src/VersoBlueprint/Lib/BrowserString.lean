/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public section

namespace Informal.BrowserString

/-- ECMAScript whitespace and line terminators used by `String.trim()`. -/
def isWhitespace (char : Char) : Bool :=
  let code := char.toNat
  (0x0009 ≤ code && code ≤ 0x000D) ||
  (0x2000 ≤ code && code ≤ 0x200A) ||
  #[0x0020, 0x00A0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF].contains code

/-- Blank text under the browser's `String.trim()` contract. -/
def isBlank (text : String) : Bool := text.all isWhitespace

/-- Trim only the edges, preserving non-whitespace and interior characters. -/
def trim (text : String) : String :=
  (text.dropWhile isWhitespace |>.dropEndWhile isWhitespace).toString

end Informal.BrowserString
