/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoSlides
public import VersoBlueprint.Slides.Node.Attrs
public meta import VersoSlides
public meta import Verso.Doc.Elab
public meta import VersoBlueprint.Slides.Node.Attrs

public section

namespace Informal.Slides

open Lean
open Verso Doc Elab

public meta def blueprintNodeBlock (cfg : Informal.Graft.BlueprintNodeConfig) : DocElabM Term := do
  let node := cfg.toNode
  let attrs := blueprintNodeAttrs node
  let fallback := node.fallbackText
  ``(Verso.Doc.Block.other (VersoSlides.BlockExt.wrap $(quote attrs))
      #[Verso.Doc.Block.para #[Verso.Doc.Inline.text $(quote fallback)]])

end Informal.Slides
