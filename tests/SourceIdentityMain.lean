import VersoBlueprintTests.BlueprintSourceIdentity

open Lean Informal
open Verso.VersoBlueprintTests.BlueprintSourceIdentity

-- Export the actual integration fixture through Lean's serializers, not a
-- hand-written JSON facsimile. The schema and instances come from one build.
def main (args : List String) : IO Unit := do
  let [output] := args
    | throw <| IO.userError "Usage: SourceIdentityMain.lean OUTPUT.json"
  let cases ← sourceCases.mapM fun (name, source) => do
    let snapshot ← render source
    pure <| Json.mkObj [("name", toJson name), ("manifest", toJson snapshot.files.manifest)]
  IO.FS.writeFile output <| (Json.mkObj [
    ("schema", PreviewManifest.schemaJson), ("cases", toJson cases)
  ]).compress
