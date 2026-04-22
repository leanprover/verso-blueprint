/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.TestBlueprintRegistryMeta

namespace Verso.VersoBlueprintTests.TestBlueprintRegistryChecks

open Verso.VersoBlueprintTests.TestBlueprintRegistryMeta

/-- info: true -/
#guard_msgs in
#eval
  let metas := curatedTestBlueprintMetas
  let categories := metas.map (·.category)
  let kinds := metas.map (·.kind)
  let tags := metas.foldl (fun acc => fun docMeta => acc ++ docMeta.tags) #[]
  !metas.isEmpty &&
    categories.all (fun c => c.trimAscii.toString.length > 0) &&
    tags.all (fun t => t.trimAscii.toString.length > 0) &&
    kinds.all (· == "curated_doc") &&
    categories.contains "Preview" &&
    categories.contains "Relationships" &&
    categories.contains "Summary" &&
    categories.contains "Metadata" &&
    categories.contains "Imports" &&
    categories.contains "Graph" &&
    categories.contains "Runtime" &&
    categories.contains "Code"

end Verso.VersoBlueprintTests.TestBlueprintRegistryChecks
