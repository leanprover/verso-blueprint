/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean

namespace RealizationParserFixture

namespace Tokens
scoped notation "⦉" p "⦊" => p
end Tokens

namespace Nested.Proofs
section
open Tokens

/-- The parser replays a standalone namespace opening. -/
theorem opened : ⦉ True ⦊ := True.intro
end

section
open scoped Tokens

/-- The parser replays a standalone scoped opening. -/
theorem scopedOpen : ⦉ True ⦊ := True.intro
end
end Nested.Proofs

section
variable {n : Nat}

variable (n) in
/-- An own comment, with Unicode 😀 before the name. -/ noncomputable def wrappedVariable : Nat := n
end

seal Nat.add in
/-- The inner declaration owns the original range inside `seal`. -/
theorem sealed : True := True.intro

attribute [local simp] Nat.add_zero in
/-- The inner declaration owns the original range inside `attribute`. -/
theorem attributed : True := True.intro

section
set_option doc.verso true

/-- Verso syntax with *emphasis*. -/
theorem verso : True := True.intro
end

/-- The previous parser option is restored to Markdown. -/
theorem afterScope : True := True.intro

/-- The selected declaration must itself parse. -/
theorem damaged : True := True.intro -- parser recovery control

theorem intervening : True := True.intro

/-- A valid command after recovery has its own exact source range. -/
theorem afterRecovery : True := True.intro

namespace Other

/--
A different declaration with the same final name.
Its original comment contains Unicode 😀 and a second line.
-/
theorem afterScope : True := True.intro

end Other

end RealizationParserFixture
