import VersoBlueprint.PreviewManifest

namespace Verso.VersoBlueprintTests.BlueprintPreviewSchema

open Lean
open Informal.PreviewManifest

private def stringSchema (schema : Json) : Bool :=
  (schema.getObjValAs? String "type" |>.toOption) == some "string"

private def stringSchemaHasMinLengthOne (schema : Json) : Bool :=
  stringSchema schema && (schema.getObjValAs? Nat "minLength" |>.toOption) == some 1

private def integerSchema (schema : Json) : Bool :=
  (schema.getObjValAs? String "type" |>.toOption) == some "integer"

private def refSchema (expected : String) (schema : Json) : Bool :=
  (schema.getObjValAs? String "$ref" |>.toOption) == some expected

private def schemaHasValueNull (valueSchema : Json → Bool) (schema : Json) : Bool :=
  match schema.getObjValAs? (Array Json) "anyOf" with
  | .error _ => false
  | .ok schemas =>
      schemas.any valueSchema &&
        schemas.any (fun schema =>
          (schema.getObjValAs? String "type" |>.toOption) == some "null")

private def schemaHasStringNull : Json → Bool := schemaHasValueNull stringSchema

private def schemaHasNonEmptyStringNull : Json → Bool :=
  schemaHasValueNull stringSchemaHasMinLengthOne

private def schemaHasIntegerNull : Json → Bool := schemaHasValueNull integerSchema

private def schemaHasRefNull (expected : String) : Json → Bool :=
  schemaHasValueNull (refSchema expected)

/-- Check required properties with structure- and field-specific failure messages. -/
private def checkObjectSchema (name : String) (fields : Array (String × (Json → Bool)))
    (absent : Array String := #[]) : IO Unit := do
  let .ok defs := schemaJson.getObjVal? "$defs"
    | throw <| IO.userError "Schema is missing $defs"
  let .ok schema := defs.getObjVal? name
    | throw <| IO.userError s!"Missing schema: {name}"
  let .ok propertiesJson := schema.getObjVal? "properties"
    | throw <| IO.userError s!"{name}: missing properties"
  let .ok properties := propertiesJson.getObj?
    | throw <| IO.userError s!"{name}: properties is not an object"
  let .ok required := schema.getObjValAs? (Array String) "required"
    | throw <| IO.userError s!"{name}: missing or invalid required fields"
  for (field, predicate) in fields do
    unless required.contains field do
      throw <| IO.userError s!"{name}.{field}: not required"
    unless (properties.get? field).any predicate do
      throw <| IO.userError s!"{name}.{field}: missing or unexpected property schema"
  for field in absent do
    if properties.contains field || required.contains field then
      throw <| IO.userError s!"{name}.{field}: obsolete field still present"

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
      let previewKeySchemaHasNonEmptyStringNull (schema : Json) : Bool :=
        match Json.getObjVal? schema "properties" with
        | Except.error _ => false
        | Except.ok propsJson =>
            match propsJson.getObj? with
            | Except.error _ => false
            | Except.ok props =>
                match props.get? "previewKey" with
                | none => false
                | some previewKeyJson => schemaHasNonEmptyStringNull previewKeyJson
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
      let foldCodeBlockDesc? := do
        let foldCodeBlockJson ← entryProps.get? "foldCodeBlock"
        foldCodeBlockJson.getObjValAs? String "description" |>.toOption
      let foldProofBlockDesc? := do
        let foldProofBlockJson ← entryProps.get? "foldProofBlock"
        foldProofBlockJson.getObjValAs? String "description" |>.toOption
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
        fileProps.contains "groups" &&
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
        entryProps.contains "foldProofBlock" &&
        entryProps.contains "foldCodeBlock" &&
        entryProps.contains "externalMarkup" &&
        entryProps.contains "sources" &&
        !entryProps.contains "source" &&
        !entryProps.contains "blocks" &&
        !entryProps.contains "leanCode" &&
        entryProps.contains "uses" &&
        entryProps.contains "usedBy" &&
        !entryProps.contains "group" &&
        entryProps.contains "ownerDisplayName" &&
        entryProps.contains "ownerUrl" &&
        entryProps.contains "ownerImageUrl" &&
        entryProps.contains "prUrl" &&
        !entryProps.contains "toBlockMetadata" &&
        entryProps.contains "tags" &&
        entryProps.contains "priority" &&
        entryProps.contains "effort" &&
        !entryProps.contains "html" &&
        labelDesc? == some "Canonical target label: informal label, Lean declaration name, citation label, or external-markup witness label." &&
        authoredLabelDesc? == some "Authored/display label text, preserving string-authored punctuation without pretty-name quoting." &&
        proofUsesDesc? == some "Structured proof use metadata, preserving origin and intent tags." &&
        displayCaptionDesc? == some "Structured heading caption for renderers that need to lay out the title." &&
        leanCodePreviewKeysDesc? == some "Manifest/cache-backed preview keys for Lean code previews associated with this entry." &&
        foldProofBlockDesc? ==
          some "Whether the canonical proof shell is collapsed when this is a proof entry." &&
        foldCodeBlockDesc? ==
          some "Whether the associated Lean code panel is collapsed for this canonical traversal entry." &&
        (internalSchemaDesc?.getD "").contains "Internal generated-data schema marker" &&
        sourceLocationDesc? == some "Source location lookup result for this manifest entry." &&
        kindDesc? == some "Kind (definition, proposition, lemma, theorem, corollary)." &&
        !schemaText.contains "Lean `Name`" &&
        entryKindText.contains "inlineLeanCode" &&
        entryKindText.contains "externalMarkup" &&
        previewKeySchemaHasNonEmptyStringNull relatedEntrySchema &&
        (relatedEntrySchema.compress.contains "dependencies") &&
        !(relatedEntrySchema.compress.contains "\"axes\"") &&
        previewKeySchemaHasNonEmptyStringNull graphNodeSchema &&
        defs.contains "Informal.PreviewManifest.EntryKind" &&
        defs.contains "Informal.Data.UseRef" &&
        defs.contains "Informal.Data.UseOrigin" &&
        defs.contains "Informal.Data.UseIntent" &&
        defs.contains "Informal.PreviewManifest.RelatedEntry" &&
        defs.contains "Informal.PreviewManifest.GroupRelation" &&
        defs.contains "Informal.Relation.Dependency" &&
        !defs.contains "Informal.PreviewManifest.RelationAxis" &&
        defs.contains "Informal.Data.ExternalMarkup" &&
        defs.contains "Informal.Data.ExternalMarkupLanguage" &&
        defs.contains "Informal.Data.ExternalMarkupLocation" &&
        defs.contains "Informal.Source.DocumentKind" &&
        defs.contains "Informal.Source.Ref" &&
        defs.contains "Informal.Source.PdfBox" &&
        defs.contains "Informal.Data.SourceLocation" &&
        defs.contains "Informal.Data.SourceLocationResult" &&
        defs.contains "Lean.Lsp.Range" &&
        defs.contains "Lean.Lsp.Position" &&
        defs.contains "Informal.Data.NodeKind" &&
        defs.contains "Informal.PreviewCache.Facet"

#guard_msgs in
#eval checkObjectSchema "Informal.Source.Document" #[
  ("id", stringSchema),
  ("title", stringSchema),
  ("kind", refSchema "#/$defs/Informal.Source.DocumentKind"),
  ("pdf", schemaHasStringNull),
  ("pageRoot", schemaHasStringNull),
  ("imageRoot", schemaHasStringNull)
] #["toDocumentMetadata"]

#guard_msgs in
#eval checkObjectSchema "Informal.Source.Span" #[
  ("page", schemaHasStringNull),
  ("anchor", schemaHasStringNull),
  ("citation", schemaHasStringNull),
  ("text", schemaHasRefNull "#/$defs/Informal.Source.TextRange"),
  ("pdf", schemaHasRefNull "#/$defs/Informal.Source.PdfSpan")
]

#guard_msgs in
#eval checkObjectSchema "Informal.Source.TextRange" #[
  ("path", stringSchema),
  ("startLine", integerSchema),
  ("endLine", integerSchema),
  ("startCharacter", schemaHasIntegerNull),
  ("endCharacter", schemaHasIntegerNull)
]

#guard_msgs in
#eval checkObjectSchema "Informal.Source.PdfSpan" #[
  ("path", stringSchema),
  ("image", schemaHasStringNull),
  ("box", schemaHasRefNull "#/$defs/Informal.Source.PdfBox")
]

end Verso.VersoBlueprintTests.BlueprintPreviewSchema
