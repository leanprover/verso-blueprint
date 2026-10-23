/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoRosetta

open Verso Verso.Doc Verso.Genre.Manual VersoRosetta

namespace VersoRosettaTests

#docs (Genre.Manual) document "Inert foreign-language requests" :=
:::::::
```lspCode "body" (context := "demo")
foreign code
```

A named reference {lspRef "reference" "foreign" (context := "demo")}[] shares its context.
:::::::

#guard (collect document.toPart).toOption.any fun requests =>
  requests.size == 2 && requests[0]!.kind == .code && requests[1]!.kind == .reference &&
    requests.all (·.context == "demo") && requests[0]!.text == "foreign code\n" &&
    requests[1]!.text == "foreign"

end VersoRosettaTests
