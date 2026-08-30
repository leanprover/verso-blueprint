/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Lib.HoverRender
meta import VersoBlueprint.Lib.HoverRender

namespace VersoBlueprintModuleTests.HoverRender

open Lean
open Informal.HoverRender

local macro "hoverPlacementContract" : term => do
  return quote (PreviewMode.hover, PreviewPlacement.anchored)

/-- info: true -/
#guard_msgs in
#eval
  let (mode, placement) : PreviewMode × PreviewPlacement := hoverPlacementContract
  let target := InlinePreviewTarget.withLookupKey
    "module-trigger" "Module preview" "module-lookup"
    (headerLabel? := some "module.label")
    (headerHref? := some "#module-label")
  let attrs := templatePreviewDescriptorAttrs
    ".panel" "template.preview" ".trigger" ".title" ".body" ".close"
    (mode := mode) (placement := placement)
  mode.dataValue == "hover" && placement.dataValue == "anchored" &&
    target.triggerId == "module-trigger" && target.lookupKey? == some "module-lookup" &&
    target.headerLabel? == some "module.label" && target.headerHref? == some "#module-label" &&
    attrs.contains ("data-bp-template-preview-mode", "hover") &&
    attrs.contains ("data-bp-template-preview-placement", "anchored") &&
    inlinePreviewRenderProperty == Name.mkSimple "Informal.inlinePreview.rendering"

end VersoBlueprintModuleTests.HoverRender
