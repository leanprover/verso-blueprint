import Lake
open Lake DSL

require VersoBlueprint from "../../../"

package PreviewRuntimeShowcase where
  precompileModules := false
  leanOptions := #[⟨`experimental.module, true⟩, ⟨`weak.verso.blueprint.project, "PreviewRuntimeShowcase"⟩]

input_dir previewRuntimeShowcaseAssets where
  path := "PreviewRuntimeShowcase/Chapters"
  text := true
  filter := .extension "js"

@[default_target]
lean_lib PreviewRuntimeShowcase where
  needs := #[previewRuntimeShowcaseAssets]
