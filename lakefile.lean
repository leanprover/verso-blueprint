import Lake
open Lake DSL

require verso from git "https://github.com/leanprover/verso"@"v4.33.0-rc2"
require «verso-slides» from git "https://github.com/leanprover/verso-slides"@"v4.33.0-rc2"
require proofwidgets from git "https://github.com/leanprover-community/ProofWidgets4"@"v0.0.104"

package VersoBlueprint where
  precompileModules := false
  leanOptions := #[⟨`experimental.module, true⟩]

-- Blueprint core library.
@[default_target]
lean_lib VersoBlueprint where
  srcDir := "src"
  roots := #[`VersoBlueprint]

@[default_target]
lean_exe «vbp» where
  root := `VersoBlueprint.VbpMain
  srcDir := "src"
  supportInterpreter := true

@[default_target, test_driver]
lean_lib VersoBlueprintTests where
  srcDir := "tests"
  globs := #[.submodules `VersoBlueprintTests]

lean_lib VersoBlueprintTestDocs where
  srcDir := "tests"
  roots := #[`VersoBlueprintTests.TestBlueprintRegistry]

lean_exe «blueprint-test-docs» where
  root := `BlueprintTestDocsMain
  srcDir := "tests"
  supportInterpreter := true
