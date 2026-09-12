/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoBlueprintVir.Preview.Widget

public section

namespace VersoBlueprintVirTests.EmbeddedPreview

vir_proof_widget
  (VersoBlueprint.Experimental.VirPreview.createWidgetComponent
    "VersoBlueprint.Experimental.VirPreview.Server.previewDocument")
  with mountId := "vbp-native-preview"

/-- Use the existing SDK facet's output; no manually copied WASM or asset polling. -/
def panelProps : Lean.Vir.Infoview.WidgetProps := {
  widgetProps with
  wasmPath := ".lake/build/vir/sdk/wasm/vir-upstream.wasm"
  autoReloadMs := 0
  setupHint := "Build the matched SDK with lake build :virSdk, then restart the Lean server."
}

end VersoBlueprintVirTests.EmbeddedPreview
