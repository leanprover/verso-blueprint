/- Copyright (c) 2026 Lean FRO LLC. Released under Apache 2.0 license. -/
module

public meta import Verso.Doc.Concrete
public meta import VersoReact.RenderPath

public section

namespace VersoBlueprint.Experimental.VirPreview.Source

open Lean Verso.Doc.Elab

private meta def contains (stx : Syntax) (pos : String.Pos.Raw) : Bool :=
  -- Elaborated block terms carry noncanonical synthetic ranges from `withRef`.
  match stx.getRange? (canonicalOnly := false) with
  | some range => range.start ≤ pos && pos < range.stop
  | none => false

/-- Find the enclosing top-level block or heading in Verso's retained source
syntax. `FinishedPart.toSyntax` preserves these block/part indices in the
evaluated document. Nested list/directive content selects its enclosing block;
included documents select their local inclusion anchor, never foreign ranges.
Positions between source ranges or outside the document have no focus. -/
meta partial def focusAt (part : FinishedPart) (pos : String.Pos.Raw)
    (path : String := VersoReact.RenderPath.root) : Option String := do
  match part with
  | .included name =>
    if contains name.raw pos then some (VersoReact.RenderPath.heading path) else none
  | .mk heading _ _ _ _ blocks children _ =>
    if contains heading pos then return VersoReact.RenderPath.heading path
    for (block, index) in blocks.zipIdx do
      if contains block.raw pos then
        return VersoReact.RenderPath.child path "block" index
    for (child, index) in children.zipIdx do
      if let some found := focusAt child pos
          (VersoReact.RenderPath.child path "part" index) then
        return found
    none

end VersoBlueprint.Experimental.VirPreview.Source
