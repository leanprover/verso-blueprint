/- Copyright (c) 2026 Lean FRO LLC. Released under Apache 2.0 license. -/
module
import MatchedPreview
meta import MatchedPreview
meta import MatchedPreview.Server
public import VersoBlueprint

namespace MatchedPreview.Demo
def useFir : Bool := false
def selectedWidget := if useFir then MatchedPreview.firWidget else MatchedPreview.virWidget
end MatchedPreview.Demo

show_panel_widgets [local MatchedPreview.Demo.selectedWidget with MatchedPreview.panelProps]

-- rpc-position-a
example : True := by
  trivial

-- rpc-position-b
example : True := by
  trivial

open Verso.Genre Informal
#doc (Manual) "Matched Blueprint preview" =>

# A live Blueprint document

This paragraph comes from the open file's elaborated document.

* A preview list item.
  * A nested preview list item with $`x + 1`.
* Another preview list item.

:::theorem "matched_preview_identity"
An informal statement with inline math $`a + 0 = a`.
:::

:::proof "matched_preview_identity"
This proof body remains visible while editing the document.
:::

```md "matched_preview_identity" (slot := summary) (display := summary)
External Markdown summary for the matched preview.
```
