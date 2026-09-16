/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoBlueprintVir.Preview.Component.Style

public section

namespace VersoBlueprint.Experimental.VirPreview

open Lean.Vir Lean.Vir.React
open scoped Lean.Vir.Js Lean.Vir.ProofWidgets.Jsx

/-- Shared presentation only. Callers own reply values, controls and rendering;
the header is a sibling of the document so it stays visible during scrolling. -/
def renderShell (attributes : Js Props) (headerChildren : Array (Js Node))
    (content : Js Node) : ReactM (Js Node) := do
  Js.Object.set attributes (← js#"id") (← js#"vir-verso-preview")
  Js.Object.set attributes (← js#"role") (← js#"region")
  Js.Object.set attributes (← js#"aria-label") (← js#"Incremental Verso document preview")
  Js.Object.set attributes (← js#"style") (← ComponentStyle.shell)
  let header ← <header id="vir-verso-shell" style={(← ComponentStyle.stickyHeader)}>
    {Js.Array.ofArray headerChildren}
  </header>
  let body ← <div id="vir-verso-content">{pure content}</div>
  Node.createElement (← ElementType.tag (← js#"section")) attributes
    (← Js.Array.ofArray #[header, body])

def renderStatus (kind message : String) : ReactM (Js Node) := do
  return ← <div data-verso-preview-status={(← JsValue.ofString kind)}
    role={(← JsValue.ofString (if kind == "error" then "alert" else "status"))}
    aria-live="polite" style={(← ComponentStyle.status)}>
    {Node.text (← JsValue.ofString message)}
  </div>

end VersoBlueprint.Experimental.VirPreview
