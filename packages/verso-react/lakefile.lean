import Lake
open Lake DSL

require verso from git "https://github.com/leanprover/verso" @
  "52c8c9557bcb5cc8c0edc0ee37e74311a3d53ee9"
-- Local-only 4.34 checkpoint; replace the URL once upstream publishes it.
require lean_vir from git "/home/egallego/lean/vir" @
  "36d26bc224f0c2a52cd586587b2c3e1b1ade70d6"

package «verso-react» where
  leanOptions := #[⟨`experimental.module, true⟩]

@[default_target]
lean_lib VersoReact where
  requiresModuleSystem := true

@[test_driver]
lean_lib VersoReactTests where
  srcDir := "tests"
  requiresModuleSystem := true
