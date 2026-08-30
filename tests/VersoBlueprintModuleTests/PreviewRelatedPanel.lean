/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.PreviewManifest.RelatedPanel
meta import VersoBlueprint.PreviewManifest.RelatedPanel

namespace VersoBlueprintModuleTests.PreviewRelatedPanel

/-- info: true -/
#guard_msgs in
#eval
  let entry : Informal.PreviewManifest.RelatedEntry := {
    label := `module.related
    title := "Module relation"
    axes := #[.statement, .proof]
  }
  let panel := entry.panelEntry entry.label "module-relation"
  entry.displayLabel == "module.related" &&
    entry.badgeCodes == #["s", "p"] &&
    panel.active && panel.previewTitle == "Module relation"

end VersoBlueprintModuleTests.PreviewRelatedPanel
