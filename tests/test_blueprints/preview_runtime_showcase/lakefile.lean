import Lake
open Lake DSL

require VersoBlueprint from "../../../"

package PreviewRuntimeShowcase where
  precompileModules := false
  leanOptions := #[⟨`experimental.module, true⟩]

@[default_target]
lean_lib PreviewRuntimeShowcase where
