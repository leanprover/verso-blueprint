/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.DirectiveArgParsing
import VersoBlueprint.LabelNameParsing
import VersoBlueprint.LeanNameParsing
import VersoBlueprint.Lib.HtmlId
meta import VersoBlueprint.DirectiveArgParsing
meta import VersoBlueprint.LabelNameParsing
meta import VersoBlueprint.LeanNameParsing
meta import VersoBlueprint.Lib.HtmlId

namespace VersoBlueprintModuleTests.Foundation

open Lean

/-- info: true -/
#guard_msgs in
#eval
  let directiveArgs :=
    Informal.DirectiveArgParsing.splitCommaSeparatedList " alpha, , beta,gamma "
  let leanNameOk :=
    match Informal.LeanNameParsing.parseE " Example.contract " with
    | .ok name => name == `Example.contract
    | .error _ => false
  let emptyLeanNameRejected :=
    match Informal.LeanNameParsing.parseE " " with
    | .error message => message == "empty name"
    | .ok _ => false
  directiveArgs == #["alpha", "beta", "gamma"] &&
    leanNameOk &&
    emptyLeanNameRejected &&
    Informal.LabelNameParsing.parse "thm:contract" == Name.mkSimple "thm:contract" &&
    Informal.HtmlId.key "alpha.beta" == "alpha-002Ebeta" &&
    Informal.HtmlId.prefixed "bp" "" == "bp"

set_option verso.blueprint.trimTeXLabelPrefix true in
/-- info: true -/
#guard_msgs in
#eval true

end VersoBlueprintModuleTests.Foundation
