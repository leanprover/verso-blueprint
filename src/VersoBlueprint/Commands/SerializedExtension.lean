/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean.Data.Json.Parser
import Verso.Doc.Elab
import VersoManual.Basic

namespace Informal.Commands

open Lean

/--
Construct a Manual block from extension data serialized while elaborating a document command.

Keeping a large computed payload in a string literal avoids generating and then re-elaborating an
equivalent constructor-sized Lean term. This is an internal document-construction helper, not a
persisted VBP artifact format.
-/
def blockFromJsonString! (name : Name) (serialized : String) : Verso.Genre.Manual.Block :=
  let data :=
    match Json.parse serialized with
    | .ok data => data
    | .error error => panic! s!"invalid serialized Blueprint extension data: {error}"
  { name, data }

/--
Serialize extension data into a compact string literal and reconstruct its Manual block when the
generated document term is evaluated.
-/
def serializedBlockTerm [ToJson α] (name : Name) (data : α) :
    Verso.Doc.Elab.PartElabM (TSyntax `term) := do
  let serialized := (toJson data).compress
  ``(Verso.Doc.Block.other
    (Informal.Commands.blockFromJsonString! $(quote name) $(quote serialized)) #[])

end Informal.Commands
