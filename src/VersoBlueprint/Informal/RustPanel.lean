/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Informal.Block.Common
import VersoBlueprint.Rust

namespace Informal.Rust

open Verso.Output.Html

def codePanelHeader (display : NodeDisplay) : CodePanelHeader :=
  Informal.codePanelHeaderFor "Rust" display

def fallbackCodePanelHeader : CodePanelHeader :=
  Informal.fallbackCodePanelHeaderFor "Rust"

def renderRawCodePanel
    (header : CodePanelHeader) (summaryTitle raw : String)
    (attrs : Array (String × String) := #[]) (folded : Bool := false) :
    Verso.Output.Html :=
  mkCodePanel header summaryTitle .empty (highlightHtml raw) attrs (folded := folded)

end Informal.Rust
