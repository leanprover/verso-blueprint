/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Verso.Output.Html
import VersoBlueprint.Lib.PreviewKey

namespace Informal.PreviewResources

open Verso.Output

/-- Select a preview affordance while preserving the underlying content.
Branches are lazy so immediate page rendering constructs only the selected one. -/
abbrev Render := PreviewKey → (Unit → Html) → (Unit → Html) → Bool → Html

def immediate (available : PreviewKey → Bool := fun _ => true)
    (defaultAvailable : PreviewKey → Bool := available) : Render :=
  fun key present absent defaultOnly =>
    if (if defaultOnly then defaultAvailable key else available key) then present () else absent ()

/-- Try candidate keys using exact resource availability or the prepared defaults. -/
def select (render : Render) (keys : Array PreviewKey)
    (present : PreviewKey → Html) (absent : Unit → Html) (defaultOnly : Bool := false) : Html :=
  (keys.foldr (fun key rest () => render key (fun _ => present key) rest defaultOnly) absent) ()

-- A self-contained choice in the intermediate Html tree, never emitted as HTML.
-- Unlike an index into a render session, it can be freely composed and copied.
private def marker := "verso-blueprint-preview-choice"

private def graphMarker := "verso-blueprint-graph-ref"

/-- A cached graph block retains its key and presentation until default
resource selection has finished. -/
def deferredGraph (key presentation : String) : Html :=
  .tag graphMarker #[("key", key), ("presentation", presentation)] (.seq #[])

/-- Retain both presentations until resource availability is known. There is no
mutable session, side table, or function stored in the resulting fragment. -/
def deferred (key : PreviewKey) (present absent : Unit → Html) (defaultOnly : Bool) : Html :=
  let attrs := #[("key", key.value)]
  let attrs := if defaultOnly then attrs.push ("default", "true") else attrs
  .tag marker attrs (.seq #[present (), absent ()])

private def choiceKey? : Array (String × String) → Option (String × Bool)
  | #[("key", key)] => some (key, false)
  | #[("key", key), ("default", "true")] => some (key, true)
  | _ => none

/-- Blank text under the browser cache's `String.trim()` contract. Includes
ECMAScript whitespace and line terminators, including nonbreaking space and BOM. -/
def textIsBlank (text : String) : Bool :=
  text.all fun char =>
    let code := char.toNat
    (0x0009 ≤ code && code ≤ 0x000D) ||
    (0x2000 ≤ code && code ≤ 0x200A) ||
    #[0x0020, 0x00A0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF].contains code

/-- Recognize blank fragments structurally, without serializing choices.
Finalization rejects choices whose branches disagree about body presence. -/
partial def htmlIsBlank : Html → Bool
  | .text _ text => textIsBlank text
  | .seq children => children.all htmlIsBlank
  | .tag name attrs contents =>
    if name != marker then false
    else
      match choiceKey? attrs, contents with
      | some (key, _), .seq #[present, absent] =>
        (PreviewKey.ofString? key).isSome && htmlIsBlank present && htmlIsBlank absent
      -- Keep malformed choices for finalization to diagnose, even if empty.
      | _, _ => false

/-- Resolve self-contained choices and prepared graphs before serialization. Invalid choices on the
selected path or branches that disagree about body presence are diagnosed.
Discarded alternatives are not recursively validated. Raw HTML stays opaque.
The result still has type `Html`: callers must enforce this serialization boundary. -/
partial def finish (available : PreviewKey → Bool) (html : Html)
    (defaultAvailable : PreviewKey → Bool := available)
    (resolveGraph : String → String → Except String Html :=
      fun key _ => .error s!"Missing prepared Blueprint graph {key}") : Except String Html :=
  match html with
  | .text escape text => pure (.text escape text)
  | .seq children => .seq <$> children.mapM (fun child => finish available child defaultAvailable resolveGraph)
  | .tag name attrs contents => do
    if name == marker then
      let (some (key, defaultOnly), .seq #[present, absent]) := (choiceKey? attrs, contents)
        | throw "Malformed Blueprint preview choice"
      unless htmlIsBlank present == htmlIsBlank absent do
        throw s!"Blueprint preview choice '{key}' changes body presence"
      let some key := PreviewKey.ofString? key
        | throw "Empty Blueprint preview choice key"
      let selected := if defaultOnly then defaultAvailable key else available key
      finish available (if selected then present else absent) defaultAvailable resolveGraph
    else if name == graphMarker then
      let (#[("key", key), ("presentation", presentation)], .seq #[]) := (attrs, contents)
        | throw "Malformed deferred Blueprint graph"
      resolveGraph key presentation
    else
      return .tag name attrs (← finish available contents defaultAvailable resolveGraph)

end Informal.PreviewResources
