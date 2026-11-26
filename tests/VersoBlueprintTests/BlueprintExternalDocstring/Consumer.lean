/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint
import VersoBlueprintTests.BlueprintExternalDocstring.Owner

open Verso.Genre Informal

namespace ExternalDocstringFixture

set_option verso.blueprint.project "externalDocstringFixture"

#docs (Manual) chapter "Imported declaration statements" :=
:::::::
:::theorem "external.docstring.one" (lean := "ExternalDocstringFixture.selected, ExternalDocstringFixture.alternative") (leanDocstring := "ExternalDocstringFixture.selected")
:::

:::proof "external.docstring.one"
A separate *consumer proof marker*.
:::

:::theorem "external.docstring.two" (lean := "ExternalDocstringFixture.selected") (leanDocstring := "ExternalDocstringFixture.selected")
:::

:::theorem "external.docstring.verso" (lean := "ExternalDocstringFixture.versoSelected") (leanDocstring := "ExternalDocstringFixture.versoSelected")
:::

:::theorem "external.docstring.undocumented" (lean := "ExternalDocstringFixture.undocumented") (leanDocstring := "ExternalDocstringFixture.undocumented")
:::

:::theorem "external.docstring.empty" (lean := "ExternalDocstringFixture.emptyComment") (leanDocstring := "ExternalDocstringFixture.emptyComment")
:::

:::theorem "external.docstring.inherited" (lean := "ExternalDocstringFixture.inherited") (leanDocstring := "ExternalDocstringFixture.inherited")
:::
:::::::

end ExternalDocstringFixture
