/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint
import VersoManual

open Verso
open Verso.Genre.Manual
open Informal

set_option doc.verso true

namespace Verso.VersoBlueprintTests.BlueprintPreviewSource.Provider

#docs (Genre.Manual) importedPreviewSourceDoc "Imported Preview Source" :=
:::::::
:::definition "preview.imported"
Imported preview body.
:::
:::::::

#docs (Genre.Manual) proofFallbackPreviewSourceDoc "Proof Fallback Preview Source" :=
:::::::
:::theorem "preview.proof_fallback"
:::

:::proof "preview.proof_fallback"
Proof fallback body.
:::
:::::::

#docs (Genre.Manual) externalMarkupPreviewSourceDoc "External Markup Preview Source" :=
:::::::
:::theorem "preview.external_bodyless"
:::

```md "preview.external_bodyless" (slot := statement)
External-markup body for a graph preview.
```
:::::::

#docs (Genre.Manual) externalMarkupGraphPreviewSourceDoc "External Markup Graph Preview Source" :=
:::::::
:::theorem "preview.external_graph_bodyless"
:::

```md "preview.external_graph_bodyless" (slot := statement)
External-markup body for a generated graph preview.
```

{blueprint_graph}
:::::::

end Verso.VersoBlueprintTests.BlueprintPreviewSource.Provider
