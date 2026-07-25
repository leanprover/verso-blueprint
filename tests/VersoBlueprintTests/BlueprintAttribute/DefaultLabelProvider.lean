/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintAttribute.Provider

namespace Verso.VersoBlueprintTests.BlueprintAttribute.DefaultLabelProvider

set_option doc.verso true in
/--
A *qualified default-label theorem* whose structural external panel preserves
inline mathematics $`3 + 4 = 7`.

It also preserves display mathematics:
$$`3 + 5 = 8`

* First qualified-label list item.
* Second qualified-label list item.
-/
@[blueprint (uses := ["attr.exported.theorem"])]
theorem qualifiedDefaultLabel : True := by
  trivial

@[blueprint]
def qualifiedDefaultDefinition : Nat := 23

end Verso.VersoBlueprintTests.BlueprintAttribute.DefaultLabelProvider
