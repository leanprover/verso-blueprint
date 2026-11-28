/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean.DocString.Extension
import VersoBlueprint.ConceptMetadata

namespace Informal.Docstring

open Lean

/-- A prose link or a dependency, with fallback text for ordinary docstring consumers. -/
structure Reference where
  target : Data.Label ⊕ Data.UseRef
  /-- Empty authored text uses automatic Blueprint numbering when placed in a Manual. -/
  hasCustomText : Bool
deriving TypeName

inductive DirectDocstringIssue where
  | missing
  | ambiguous

/-- Read only direct compiled metadata for the given canonical declaration.
Inheritance and builtin or synthesized documentation use separate providers. -/
def directCompiled (env : Environment) (name : Name) :
    Except DirectDocstringIssue (String ⊕ Lean.VersoDocString) :=
  match Lean.docStringExt.find? (level := .server) env name,
      Lean.versoDocStringExt.find? (level := .server) env name with
  | some markdown, none => .ok (.inl markdown)
  | none, some verso => .ok (.inr verso)
  | none, none => .error .missing
  | some _, some _ => .error .ambiguous

end Informal.Docstring
