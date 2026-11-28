import Lake
open Lake DSL

require VersoBlueprint from "../../../"

package VisualInspection where
  precompileModules := false
  leanOptions := #[⟨`experimental.module, true⟩, ⟨`weak.verso.blueprint.project, "VisualInspection"⟩]

@[default_target]
lean_lib VisualInspection
