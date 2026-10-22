/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintRuntimeClientTests.Resources
import VersoBlueprintVirClientTests.Site

def main (args : List String) : IO Unit := do
  let [output] := args
    | throw <| IO.userError "usage: manifest-resolver-client OUTPUT"
  -- The native writer imports resources, not browser-only host bindings.
  let entry := fun name => "VersoBlueprintRuntimeClientTests.Program." ++ name
  VersoBlueprintVirClientTests.publishSite VersoBlueprintRuntimeClientTests.resources
    (entry "resolve") output
    [("prepareEntry", Lean.toJson (entry "prepare")),
     ("lookupEntry", Lean.toJson (entry "lookup"))]
