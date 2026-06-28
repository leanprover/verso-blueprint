/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.PreviewManifest
import VersoBlueprintTests.BlueprintExternalMarkup

open Verso.Genre Manual
open Verso.VersoBlueprintTests.BlueprintExternalMarkup

def main (args : List String) : IO UInt32 :=
  Informal.PreviewManifest.blueprintMainWithPreviewData
    externalMarkdownWitnessDoc.toPart
    args
    (extensionImpls := by exact extension_impls%)
