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

A [structural docstring link](https://example.com/qualified-docstring) remains
clickable.

> A quoted structural docstring paragraph.

* First qualified-label list item.
* Second qualified-label list item.

# Qualified structural subsection

Subsection content remains part of the imported statement.
-/
@[blueprint (uses := ["attr.exported.theorem"])]
theorem qualifiedDefaultLabel : True := by
  trivial

@[blueprint]
def qualifiedDefaultDefinition : Nat := 23

end Verso.VersoBlueprintTests.BlueprintAttribute.DefaultLabelProvider
