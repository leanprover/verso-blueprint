import Lake

open Lake DSL

require VersoBlueprint from "../.."

package RuntimeArtifactExperiment where
  precompileModules := true

lean_exe runtimeBundleHost where
  root := `RuntimeBundleHost
  supportInterpreter := true
