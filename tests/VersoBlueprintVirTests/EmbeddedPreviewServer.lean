/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprintVirTests.EmbeddedPreview
meta import VersoBlueprintVirTests.EmbeddedPreview
meta import VersoBlueprintVir.Preview.Server
public import VersoBlueprint

show_panel_widgets [local Lean.Vir.Infoview.widget with
  VersoBlueprintVirTests.EmbeddedPreview.panelProps]

-- rpc-position-a
example : True := by
  trivial

-- rpc-position-b
example : True := by
  trivial

open Verso.Genre
open Informal

#doc (Manual) "Native Blueprint preview" =>

# A live Blueprint document

This paragraph comes from the open file's elaborated document, not a fixed RPC payload.
Try changing it to see the retained preview update.

:::theorem "native_preview_identity"
An informal statement with inline math $`a + 0 = a`.
:::

:::proof "native_preview_identity"
This proof body remains visible while editing the document.
:::

```md "native_preview_identity" (slot := summary) (display := summary)
External Markdown summary for the native preview.
```

The browser test appends a paragraph below this one and checks its rendered text.
