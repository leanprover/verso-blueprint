(* Authored block. *)
Definition step (n : nat) : nat := S n.
Example step_two : step 2 = 3.
Proof. reflexivity. Qed.

(* Named reference in the same document and logical scope. *)
Check step.
