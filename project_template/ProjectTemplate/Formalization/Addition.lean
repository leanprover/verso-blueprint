import VersoBlueprint

namespace ProjectTemplate.Formalization.Addition

/-- Addition of natural numbers is commutative. -/
@[blueprint "addition_comm_compiled" (uses := ["addition_spec"])]
theorem addition_comm_compiled (a b : Nat) : a + b = b + a := by
  simpa using Nat.add_comm a b

/-- Zero is a left identity for addition of natural numbers. -/
@[blueprint "addition_zero_compiled" (uses := ["addition_right_identity"])]
theorem addition_zero_compiled (a : Nat) : 0 + a = a := by
  simp

end ProjectTemplate.Formalization.Addition
