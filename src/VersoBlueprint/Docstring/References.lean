/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public meta import Lean.Elab.DocString
public meta import VersoBlueprint.Informal.Uses

public meta section

namespace Informal.Docstring

open Lean

/-- A prose link or a dependency, with fallback text for ordinary docstring consumers. -/
structure Reference where
  target : Data.Label ⊕ Data.UseRef
  /-- Empty authored text uses automatic Blueprint numbering when placed in a Manual. -/
  hasCustomText : Bool
deriving TypeName

def Reference.label (reference : Reference) : Data.Label :=
  reference.target.elim id (·.label)

private def referenceInline (target : Data.Label ⊕ Data.UseRef)
    (contents : TSyntaxArray `inline) :
    Lean.Doc.DocM (Lean.Doc.Inline Lean.ElabInline) := do
  let reference : Reference := { target, hasCustomText := !contents.isEmpty }
  let contents ← contents.mapM Lean.Doc.elabInline
  -- Fallback consumers, including declaration panels and editor hovers, have
  -- no Blueprint traversal state from which to obtain an automatic title.
  let fallback :=
    if contents.isEmpty then #[.code (reference.label.toString (escape := false))]
    else contents
  return .custom reference fallback

/-- Preserve dependency metadata without requiring an enclosing Manual directive. -/
@[doc_role Informal.uses]
def uses (label : StrLit) (origin : String := "manual") (intent : String := "regular")
    (contents : TSyntaxArray `inline) :
    Lean.Doc.DocM (Lean.Doc.Inline Lean.ElabInline) := do
  let cfg := UsesConfig.ofArgs { val := label.getString, «syntax» := label.raw }
    (some origin) (some intent)
  let dependency? ← cfg.validate
  referenceInline (dependency?.map Sum.inr |>.getD (.inl cfg.label)) contents

/-- Preserve a Blueprint prose link without creating a dependency edge. -/
@[doc_role Informal.bpref]
def bpref (label : StrLit) (contents : TSyntaxArray `inline) :
    Lean.Doc.DocM (Lean.Doc.Inline Lean.ElabInline) :=
  referenceInline (.inl (LabelNameParsing.parse label.getString)) contents

end Informal.Docstring
