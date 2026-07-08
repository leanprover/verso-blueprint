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
      let fileRequired? := do
        let requiredJson ← fileSchema.getObjVal? "required" |>.toOption
        fromJson? (α := Array String) requiredJson |>.toOption
      let entryRequired? := do
        let requiredJson ← entrySchema.getObjVal? "required" |>.toOption
        fromJson? (α := Array String) requiredJson |>.toOption
      let some relatedEntrySchema := defs.get? "Informal.PreviewManifest.RelatedEntry" | return false
      let some graphNodeSchema := defs.get? "Informal.Graph.NodeData" | return false
      let schemaText := schema.compress
      let stringSchemaHasMinLengthOne (schema : Json) : Bool :=
        (schema.getObjValAs? String "type" |>.toOption) == some "string" &&
          (schema.getObjValAs? Nat "minLength" |>.toOption) == some 1
      let previewKeySchemaHasNonEmptyStringNull (schema : Json) : Bool :=
        match Json.getObjVal? schema "properties" with
        | Except.error _ => false
        | Except.ok propsJson =>
            match propsJson.getObj? with
            | Except.error _ => false
            | Except.ok props =>
                match props.get? "previewKey" with
                | none => false
                | some previewKeyJson =>
                    match Json.getObjVal? previewKeyJson "anyOf" with
                    | Except.error _ => false
                    | Except.ok anyOfJson =>
                        match anyOfJson.getArr? with
                        | Except.error _ => false
                        | Except.ok schemas =>
                            schemas.any stringSchemaHasMinLengthOne &&
                            schemas.any (fun (schema : Json) =>
                              (schema.getObjValAs? String "type" |>.toOption) == some "null")
      let internalSchemaDesc? := do
        let internalSchemaJson ← fileProps.get? "vbpInternalSchemaVersion"
        internalSchemaJson.getObjValAs? String "description" |>.toOption
      let proofUsesDesc? := do
        let proofUsesJson ← entryProps.get? "proofUses"
        proofUsesJson.getObjValAs? String "description" |>.toOption
      let useRefProps? := do
        let useRefJson ← defs.get? "Informal.Data.UseRef"
        let useRefPropsJson ← useRefJson.getObjVal? "properties" |>.toOption
        useRefPropsJson.getObj? |>.toOption
      let leanCodePreviewKeysDesc? := do
        let leanCodePreviewKeysJson ← entryProps.get? "leanCodePreviewKeys"
        leanCodePreviewKeysJson.getObjValAs? String "description" |>.toOption
      let sourceLocationDesc? := do
        let sourceLocationJson ← entryProps.get? "sourceLocation"
        sourceLocationJson.getObjValAs? String "description" |>.toOption
      let kindDesc? := do
        let kindJson ← entryProps.get? "kind"
        kindJson.getObjValAs? String "description" |>.toOption
      let labelDesc? := do
        let labelJson ← entryProps.get? "label"
        labelJson.getObjValAs? String "description" |>.toOption
      let authoredLabelDesc? := do
        let authoredLabelJson ← entryProps.get? "authoredLabel"
        authoredLabelJson.getObjValAs? String "description" |>.toOption
      let some fileRequired := fileRequired? | return false
      let some entryRequired := entryRequired? | return false
      let some useRefProps := useRefProps? | return false
      let displayCaptionDesc? := do
        let displayCaptionJson ← entryProps.get? "displayCaption"
        displayCaptionJson.getObjValAs? String "description" |>.toOption
      let entryKindText := (defs.get? "Informal.PreviewManifest.EntryKind").map (·.compress) |>.getD ""
      rootRef == "#/$defs/Informal.PreviewManifest.File" &&
        !fileProps.contains "version" &&
        !fileProps.contains "schemaVersion" &&
        !fileProps.contains "traverseState" &&
        fileProps.contains "vbpInternalSchemaVersion" &&
        fileRequired.contains manifestInternalSchemaVersionField &&
        fileProps.contains "previews" &&
        fileProps.contains "sourceDocuments" &&
        entryProps.contains "key" &&
        entryProps.contains "targetKind" &&
        entryProps.contains "label" &&
        entryProps.contains "authoredLabel" &&
        entryProps.contains "facet" &&
        entryProps.contains "kind" &&
        entryProps.contains "title" &&
        entryProps.contains "displayCaption" &&
        entryProps.contains "displayLabel" &&
        entryProps.contains "href" &&
        entryProps.contains "sourceLocation" &&
        entryRequired.contains "sourceLocation" &&
        entryProps.contains "parent" &&
        entryProps.contains "parentTitle" &&
        entryProps.contains "statementUses" &&
        entryProps.contains "proofUses" &&
        !entryProps.contains "statementDeps" &&
        !entryProps.contains "proofDeps" &&
        useRefProps.contains "label" &&
        useRefProps.contains "origin" &&
        useRefProps.contains "intent" &&
        !useRefProps.contains "intents" &&
        entryProps.contains "leanCodePreviewKeys" &&
        entryProps.contains "codeData" &&
        entryProps.contains "externalMarkup" &&
        entryProps.contains "sources" &&
        !entryProps.contains "source" &&
        !entryProps.contains "blocks" &&
        !entryProps.contains "leanCode" &&
        entryProps.contains "uses" &&
        entryProps.contains "usedBy" &&
        entryProps.contains "group" &&
        entryProps.contains "ownerDisplayName" &&
        entryProps.contains "tags" &&
        entryProps.contains "priority" &&
        entryProps.contains "effort" &&
        !entryProps.contains "html" &&
        labelDesc? == some "Canonical target label: informal label, Lean declaration name, citation label, or external-markup witness label." &&
        authoredLabelDesc? == some "Authored/display label text, preserving string-authored punctuation without pretty-name quoting." &&
        proofUsesDesc? == some "Structured proof use metadata, preserving origin and intent tags." &&
        displayCaptionDesc? == some "Structured heading caption for renderers that need to lay out the title." &&
        leanCodePreviewKeysDesc? == some "Rendered-fragment cache keys for Lean declaration previews associated with this entry." &&
        (internalSchemaDesc?.getD "").contains "not a public" &&
        (internalSchemaDesc?.getD "").contains "compatibility promise" &&
        sourceLocationDesc? == some "Source location lookup result for this manifest entry." &&
        kindDesc? == some "Kind (definition, proposition, lemma, theorem, corollary)." &&
        !schemaText.contains "Lean `Name`" &&
        entryKindText.contains "externalMarkup" &&
        previewKeySchemaHasNonEmptyStringNull relatedEntrySchema &&
        previewKeySchemaHasNonEmptyStringNull graphNodeSchema &&
        defs.contains "Informal.PreviewManifest.EntryKind" &&
        defs.contains "Informal.Data.UseRef" &&
        defs.contains "Informal.Data.UseOrigin" &&
        defs.contains "Informal.Data.UseIntent" &&
        defs.contains "Informal.PreviewManifest.RelatedEntry" &&
        defs.contains "Informal.PreviewManifest.GroupRelation" &&
        defs.contains "Informal.PreviewManifest.RelationAxis" &&
        defs.contains "Informal.Data.ExternalMarkup" &&
        defs.contains "Informal.Data.ExternalMarkupLanguage" &&
        defs.contains "Informal.Data.ExternalMarkupLocation" &&
        defs.contains "Informal.Source.Document" &&
        defs.contains "Informal.Source.DocumentKind" &&
        defs.contains "Informal.Source.Ref" &&
        defs.contains "Informal.Source.Span" &&
        defs.contains "Informal.Source.TextRange" &&
        defs.contains "Informal.Source.PdfSpan" &&
        defs.contains "Informal.Source.PdfBox" &&
        defs.contains "Informal.Data.SourceLocation" &&
        defs.contains "Informal.Data.SourceLocationResult" &&
        defs.contains "Lean.Lsp.Range" &&
        defs.contains "Lean.Lsp.Position" &&
        defs.contains "Informal.Data.NodeKind" &&
        defs.contains "Informal.PreviewCache.Facet"

end Verso.VersoBlueprintTests.BlueprintPreviewSchema
