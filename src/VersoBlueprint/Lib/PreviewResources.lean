/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Verso.Output.Html
public import VersoBlueprint.Lib.PreviewKey

public section

namespace Informal.PreviewResources

open Verso.Output

/-- Select a preview affordance while preserving the underlying content.
Branches are lazy so immediate page rendering constructs only the selected one. -/
abbrev Render := PreviewKey → (Unit → Html) → (Unit → Html) → Html

def immediate (available : PreviewKey → Bool := fun _ => true) : Render :=
  fun key present absent => if available key then present () else absent ()

-- A self-contained choice in the intermediate Html tree, never emitted as HTML.
-- Unlike an index into a render session, it can be freely composed and copied.
private def marker := "verso-blueprint-preview-choice"

/-- Retain both presentations until resource availability is known. There is no
mutable session, side table, or function stored in the resulting fragment. -/
def deferred : Render := fun key present absent =>
  .tag marker #[("key", key.value)] (.seq #[present (), absent ()])

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
      match attrs, contents with
      | #[("key", key)], .seq #[present, absent] =>
        (PreviewKey.ofString? key).isSome && htmlIsBlank present && htmlIsBlank absent
      -- Keep malformed choices for finalization to diagnose, even if empty.
      | _, _ => false

/-- Resolve self-contained choices before serialization. Invalid choices on the
selected path or branches that disagree about body presence are diagnosed.
Discarded alternatives are not recursively validated. Raw HTML stays opaque.
The result still has type `Html`: callers must enforce this serialization boundary. -/
partial def finish (available : PreviewKey → Bool) : Html → Except String Html
  | .text escape text => pure (.text escape text)
  | .seq children => .seq <$> children.mapM (finish available)
  | .tag name attrs contents => do
    if name == marker then
      let (#[ ("key", key) ], .seq #[present, absent]) := (attrs, contents)
        | throw "Malformed Blueprint preview choice"
      unless htmlIsBlank present == htmlIsBlank absent do
        throw s!"Blueprint preview choice '{key}' changes body presence"
      let some key := PreviewKey.ofString? key
        | throw "Empty Blueprint preview choice key"
      finish available (if available key then present else absent)
    else
      return .tag name attrs (← finish available contents)

end Informal.PreviewResources
