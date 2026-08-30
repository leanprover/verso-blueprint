/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.VbpMain
meta import VersoBlueprint.VbpMain

namespace VersoBlueprintModuleTests.VbpCli

/-- info: true -/
#guard_msgs in
#eval
  VersoBlueprint.Vbp.Main.helpText.contains "lake exe vbp build" &&
    VersoBlueprint.Vbp.Main.buildHelpText.contains "--pdf-engine" &&
    (match VersoBlueprint.Vbp.Main.parseBuildOptions
        ["--output", "_out/module", "--pdf", "--verbose"] {} with
    | .ok opts =>
        opts.output.toString == "_out/module" && opts.pdf && opts.verbose
    | .error _ => false) &&
    (match VersoBlueprint.Vbp.Main.parseSiteOptions
        ["--site", "_out/module", "stats"] {} with
    | .ok opts => opts.site.toString == "_out/module" && opts.rest == ["stats"]
    | .error _ => false)

end VersoBlueprintModuleTests.VbpCli
