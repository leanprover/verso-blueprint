/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Verso.Output.Html
import VersoBlueprint.Lib.PreviewKey

namespace Informal.PreviewResources

open Verso.Output

/-- A pure presentation decision over the completed preview resource set.
Availability may change preview affordances, but must preserve body presence. -/
abbrev View := (PreviewKey → Bool) → Html

/-- Render now for pages, or retain the decision while constructing resources.
Semantic lookup and body rendering happen before this hook. -/
abbrev Render := View → IO Html

def immediate (available : PreviewKey → Bool := fun _ => true) : Render :=
  fun view => pure (view available)

/-- An output-local collection of deferred presentation decisions. It never
enters saved traversal state or the manifest/cache wire format. -/
structure Deferred where
  private mk ::
  private views : IO.Ref (Array View)

def Deferred.create : IO Deferred :=
  return ⟨← IO.mkRef #[]⟩

-- This tag exists only in the intermediate Html tree. Its contents preserve
-- the candidate presentation for blank-body detection; it is never serialized.
private def marker := "verso-blueprint-deferred-preview"

def Deferred.render (deferred : Deferred) : Render := fun view => do
  let index ← deferred.views.modifyGet fun views => (views.size, views.push view)
  return .tag marker #[("index", toString index)] (view (fun _ => true))

/-- Test rendered content without serializing deferred markers. Availability
only changes preview affordances, never the presence of authored body content. -/
partial def htmlIsBlank : Html → Bool
  | .text _ text => text.all Char.isWhitespace
  | .seq children => children.all htmlIsBlank
  | .tag name _ contents => name == marker && htmlIsBlank contents

private partial def resolve (views : Array View) (available : PreviewKey → Bool) :
    Html → Html
  | .text escape text => .text escape text
  | .seq children => .seq (children.map (resolve views available))
  | .tag name attrs contents =>
    if name == marker then
      match attrs[0]?.bind (fun (_, value) => value.toNat?) >>= (fun index => views[index]?) with
      | some view => resolve views available (view available)
      | none => panic! "Unbound deferred Blueprint preview view"
    else .tag name attrs (resolve views available contents)

/-- Freeze this render session's decisions, then resolve structured fragments
before serialization. Nested decisions are resolved too, without re-elaborating
or re-rendering their document bodies. -/
def Deferred.finish (deferred : Deferred) (available : PreviewKey → Bool) :
    IO (Html → Html) := do
  return resolve (← deferred.views.get) available

end Informal.PreviewResources
