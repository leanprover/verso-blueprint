import VersoBlueprint.PreviewManifest

namespace Verso.VersoBlueprintTests.BlueprintPreviewSchema

open Lean
open Informal.PreviewManifest

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let schema := schemaJson
    let defs? := Json.getObjVal? schema "$defs"
    let rootRef? := Json.getObjVal? schema "$ref"
    pure <| Id.run do
      let Except.ok defsJson := defs? | return false
      let Except.ok defs := defsJson.getObj? | return false
      let Except.ok rootRefJson := rootRef? | return false
      let Except.ok rootRef := fromJson? (α := String) rootRefJson | return false
      let some fileSchema := defs.get? "Informal.PreviewManifest.File" | return false
      let some entrySchema := defs.get? "Informal.PreviewManifest.Entry" | return false
      let Except.ok filePropsJson := Json.getObjVal? fileSchema "properties" | return false
      let Except.ok fileProps := filePropsJson.getObj? | return false
      let Except.ok entryPropsJson := Json.getObjVal? entrySchema "properties" | return false
      let Except.ok entryProps := entryPropsJson.getObj? | return false
      let schemaText := schema.compress
      let proofDepsDesc? := do
        let proofDepsJson ← entryProps.get? "proofDeps"
        proofDepsJson.getObjValAs? String "description" |>.toOption
      let kindDesc? := do
        let kindJson ← entryProps.get? "kind"
        kindJson.getObjValAs? String "description" |>.toOption
      let labelDesc? := do
        let labelJson ← entryProps.get? "label"
        labelJson.getObjValAs? String "description" |>.toOption
      rootRef == "#/$defs/Informal.PreviewManifest.File" &&
        defs.size == 5 &&
        !fileProps.contains "version" &&
        fileProps.contains "previews" &&
        entryProps.contains "key" &&
        entryProps.contains "targetKind" &&
        entryProps.contains "label" &&
        entryProps.contains "facet" &&
        entryProps.contains "kind" &&
        entryProps.contains "title" &&
        entryProps.contains "href" &&
        entryProps.contains "parent" &&
        entryProps.contains "parentTitle" &&
        entryProps.contains "statementDeps" &&
        entryProps.contains "proofDeps" &&
        entryProps.contains "ownerDisplayName" &&
        entryProps.contains "tags" &&
        entryProps.contains "priority" &&
        entryProps.contains "effort" &&
        entryProps.contains "html" &&
        labelDesc? == some "Canonical target label: informal label, Lean declaration name, or citation label." &&
        proofDepsDesc? == some "Informal nodes used by the proof." &&
        kindDesc? == some "Kind (definition, lemma, theorem, corollary)." &&
        !schemaText.contains "Lean `Name`" &&
        defs.contains "Informal.PreviewManifest.EntryKind" &&
        defs.contains "Informal.Data.NodeKind" &&
        defs.contains "Informal.PreviewCache.Facet"

end Verso.VersoBlueprintTests.BlueprintPreviewSchema
