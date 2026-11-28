(* Local test adaptation of the translation-reuse Flag source family.
   This example reads source only; Qed is not a reported compiler result. *)
Inductive Flag : Type :=
| off : Flag
| on : Flag.

Definition toggle (flag : Flag) : Flag :=
  match flag with
  | off => on
  | on => off
  end.

Theorem toggle_involutive (flag : Flag) :
  toggle (toggle flag) = flag.
Proof.
  destruct flag.
  - reflexivity.
  - reflexivity.
Qed.
