/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.TestBlueprintRegistry
import VersoBlueprintTests.TestBlueprintRegistryMeta

namespace Verso.VersoBlueprintTests.TestBlueprintRegistryCoverage

open Verso.VersoBlueprintTests.TestBlueprintRegistry
open Verso.VersoBlueprintTests.TestBlueprintRegistryMeta

/-- info: true -/
#guard_msgs in
#eval
  let metaSlugs := curatedTestBlueprintMetas.map (·.slug)
  let docSlugs := curatedTestBlueprintDocSlugs
  let uniqueMetaSlugs := metaSlugs.all fun slug => (metaSlugs.filter (· == slug)).size == 1
  let uniqueDocSlugs := docSlugs.all fun slug => (docSlugs.filter (· == slug)).size == 1
  metaSlugs.size == docSlugs.size &&
    uniqueMetaSlugs &&
    uniqueDocSlugs &&
    metaSlugs.all (fun slug => docSlugs.contains slug && (findCuratedTestBlueprintDoc? slug).isSome) &&
    docSlugs.all (fun slug => metaSlugs.contains slug && (findCuratedTestBlueprintMeta? slug).isSome)

end Verso.VersoBlueprintTests.TestBlueprintRegistryCoverage
