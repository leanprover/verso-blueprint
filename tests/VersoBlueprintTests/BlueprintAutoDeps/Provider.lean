/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint

namespace Verso.VersoBlueprintTests.BlueprintAutoDeps.Provider

/-- Source declaration used from another theorem's type. -/
@[blueprint "auto.type.source"]
def typeSource : Prop := True

/-- Source declaration used from another theorem's proof. -/
@[blueprint "auto.proof.source"]
theorem proofSource : True := by
  trivial

/-- Source declaration used from another definition's body. -/
@[blueprint "auto.def.source"]
def defSource : Nat := 1

/-- Source declaration intentionally associated with two Blueprint labels. -/
@[blueprint "auto.shared.source.primary", blueprint "auto.shared.source.secondary"]
def sharedSource : Prop := True

/-- Extra explicit dependency target. -/
@[blueprint "auto.manual.extra"]
theorem manualExtra : True := by
  trivial

/-- The type mentions a tagged Blueprint declaration. -/
@[blueprint "auto.type.target" (autoDeps := true)]
theorem typeTarget : typeSource := by
  trivial

@[blueprint "auto.proof.target" (autoDeps := true)]
theorem proofTarget : True := by
  exact proofSource

@[blueprint "auto.def.target" (autoDeps := true)]
def defTarget : Nat := defSource + 1

@[blueprint "auto.shared.target" (autoDeps := true)]
theorem sharedTarget : sharedSource := by
  trivial

theorem untaggedSource : True := by
  trivial

@[blueprint "auto.untagged.target" (autoDeps := true)]
theorem untaggedTarget : True := by
  exact untaggedSource

def untaggedTypeAlias : Prop := typeSource

@[blueprint "auto.untagged.type_target" (autoDeps := true)]
theorem untaggedTypeTarget : untaggedTypeAlias := by
  trivial

def untaggedProofHelper : True := proofSource

@[blueprint "auto.untagged.proof_target" (autoDeps := true)]
theorem untaggedProofTarget : True := by
  exact untaggedProofHelper

@[blueprint "auto.duplicate_axis.target" (autoDeps := true)]
def duplicateAxisTarget : { n : Nat // n = defSource } :=
  ⟨defSource, rfl⟩

@[blueprint "auto.manual.target"
  (autoDeps := true)
  (uses := ["auto.manual.extra", -"auto.type.source"])
  (proofUses := [proofSource, -"auto.proof.source"])]
theorem manualTarget : typeSource := by
  exact proofSource

@[blueprint "auto.manual.same_axis"
  (autoDeps := true)
  (uses := [typeSource])]
theorem manualSameAxisTarget : typeSource := by
  trivial

@[blueprint "auto.add_exclude.same_axis"
  (autoDeps := true)
  (uses := [typeSource, -typeSource])]
theorem addExcludeSameAxisTarget : typeSource := by
  trivial

@[blueprint "auto.overlap.target" (autoDeps := true) (proofUses := [typeSource])]
theorem overlapTarget : typeSource := by
  trivial

@[blueprint "auto.decl.manual_no_auto" (uses := [typeSource])]
theorem declManualNoAuto : True := by
  trivial

@[blueprint "auto.string.target" (uses := ["auto.synthetic.label"])]
theorem stringTarget : True := by
  trivial

@[blueprint "auto.string.proof_only" (proofUses := ["auto.synthetic.proof"])]
theorem stringProofOnly : True := by
  trivial

@[blueprint "auto.manual.proof_only" (proofUses := [proofSource])]
theorem manualProofOnly : True := by
  trivial

@[blueprint "auto.self.string_target" (uses := ["auto.self.string_target"])]
theorem selfStringTarget : True := by
  trivial

@[blueprint "auto.self.decl_target" (uses := [selfDeclTarget])]
theorem selfDeclTarget : True := by
  trivial

end Verso.VersoBlueprintTests.BlueprintAutoDeps.Provider
