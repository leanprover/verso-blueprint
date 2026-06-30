import { createPreview } from "./api/preview.mjs";
import { startGraphRuntime } from "./Commands/graph.mjs";
import { startInlinePreview } from "./Commands/inline-preview.mjs";
import { startRelationPanels } from "./Informal/Block/relation-panel.mjs";
import { start as startBlueprintSlides } from "./Slides/blueprint-slides.mjs";

export function startBlueprintSlideRuntime(options = {}) {
  const preview = createPreview(options);
  startInlinePreview(preview);
  startRelationPanels(preview);
  startGraphRuntime(preview);
  startBlueprintSlides(preview);
  return preview;
}

export const blueprintSlideRuntime = startBlueprintSlideRuntime();

export default {
  blueprintSlideRuntime,
  startBlueprintSlideRuntime
};
