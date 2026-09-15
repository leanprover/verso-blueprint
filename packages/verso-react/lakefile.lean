import Lake
open Lake DSL

require verso from git "https://github.com/leanprover/verso" @
  "52c8c9557bcb5cc8c0edc0ee37e74311a3d53ee9"
-- Local-only 4.34 checkpoint; replace the URL once upstream publishes it.
require lean_vir from git "/home/egallego/lean/vir" @
  "6e91bed83168c9cddf4f85e97cf0c58fc1e01e3d"

package «verso-react» where
  leanOptions := #[⟨`experimental.module, true⟩]

@[default_target]
lean_lib VersoReact where
  requiresModuleSystem := true

@[test_driver]
lean_lib VersoReactTests where
  srcDir := "tests"
  requiresModuleSystem := true
