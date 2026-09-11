/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.Statement

open Verso.Genre Informal

#doc (Manual) "Statement markup" =>

```tex "key_theorem" (slot := statement)
Statement witness.
```

```rust "key_theorem"
pub fn witness() -> bool { true }
```
