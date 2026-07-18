import VersoBlueprint.Vbp
import VersoBlueprint.VbpMain

namespace Verso.VersoBlueprintTests.Vbp

open Lean
open Informal.Graph

abbrev ManifestFile := Informal.PreviewManifest.File
abbrev HtmlCacheFile := Informal.PreviewManifest.HtmlCache.File
abbrev PreviewDataFiles := Informal.PreviewManifest.Files
abbrev RelatedEntry := Informal.PreviewManifest.RelatedEntry

private def previewData (manifest : ManifestFile) (htmlCache : HtmlCacheFile) :
    PreviewDataFiles :=
  { manifest, htmlCache }

private def label (value : String) : Name :=
  Name.mkSimple value

private def related (value title key : String) : RelatedEntry :=
  {
    label := label value
    title := title
    previewKey := Informal.PreviewKey.ofString? key
    axes := #[.statement]
  }

private def relatedWithoutPreview (value title : String) : RelatedEntry :=
  {
    label := label value
    title := title
    href := some s!"{value}/"
    axes := #[.statement]
  }

private def finishedGraph (key : String) (nodes : Array NodeData) : GraphData :=
  ({ nodes } : GraphModel).finish key {}

private def sampleManifest : ManifestFile := {
  previews := #[
    {
      key := "informal:addition_spec:statement"
      targetKind := .block
      label := label "addition_spec"
      facet := .statement
      kind := some .definition
      title := "Definition 1"
      usedBy := #[related "addition_assoc" "Theorem 2" "informal:addition_assoc:statement"]
      tags := #["starter"]
    },
    {
      key := "informal:addition_assoc:statement"
      targetKind := .block
      label := label "addition_assoc"
      facet := .statement
      kind := some .theorem
      title := "Theorem 2"
      statementUses := #[{ label := label "addition_spec" }]
      uses := #[related "addition_spec" "Definition 1" "informal:addition_spec:statement"]
      leanCodePreviewKeys := #["lean:Nat.add_assoc"]
      ownerDisplayName := some "Project Author"
      tags := #["starter", "arithmetic"]
      priority := some "high"
      effort := some "small"
    },
    {
      key := "lean:Nat.add_assoc"
      targetKind := .leanDecl
      label := label "Nat.add_assoc"
      facet := .statement
      title := "Nat.add_assoc"
    }
  ]
}

private def sampleExternalManifest : ManifestFile := {
  previews := sampleManifest.previews.push {
    key := Informal.PreviewManifest.externalMarkupEntryKey (label "external_bodyless")
    targetKind := .externalMarkup
    label := label "external_bodyless"
    facet := .statement
    kind := some .corollary
    title := "Corollary 3"
    statementUses := #[{ label := label "addition_spec" }]
    uses := #[related "addition_spec" "Definition 1" "informal:addition_spec:statement"]
    leanCodePreviewKeys := #["lean:Nat.mul_assoc"]
    ownerDisplayName := some "Source Author"
    tags := #["external-source", "starter"]
    priority := some "medium"
  }
}

private def sampleInlineCodeManifest : ManifestFile := {
  previews := sampleManifest.previews.push {
    key := "informal:inline_code_label:statement"
    targetKind := .block
    label := label "inline_code_label"
    facet := .statement
    kind := some .definition
    title := "Inline code label"
    leanCodePreviewKeys := #["Informal.LeanCodePreview.Inline.inline_code_label"]
    codeData := some <| .inline {
      label := label "inline_code_label"
      definedDefs := #[{
        name := Name.str (Name.str .anonymous "Inline") "localDef"
      }]
    }
  }
}

private def sampleEmptyRelationManifest : ManifestFile := {
  previews := #[
    {
      key := "informal:relation_source:statement"
      targetKind := .block
      label := label "relation_source"
      facet := .statement
      kind := some .theorem
      title := "Theorem 1"
      uses := #[relatedWithoutPreview "relation_target" "Target without preview"]
    }
  ]
}

private def sampleEmptyRelationCache : HtmlCacheFile := {
  entries := #[
    { key := "informal:relation_source:statement", html := "<div>relation source</div>" }
  ]
}

private def sampleGroupManifest : ManifestFile := {
  previews := #[
    {
      key := "informal:group_member:statement"
      targetKind := .block
      label := label "group_member"
      facet := .statement
      kind := some .theorem
      title := "Group member"
      parent := some (label "sample_group")
      parentTitle := some "Sample group"
    },
    {
      key := "informal:group_peer:statement"
      targetKind := .block
      label := label "group_peer"
      facet := .statement
      kind := some .theorem
      title := "Group peer"
      parent := some (label "sample_group")
      parentTitle := some "Sample group"
    }
  ]
  groups := #[{
    label := label "sample_group"
    title := "Sample group"
    declared := true
    entries := #[
      relatedWithoutPreview "group_member" "Group member",
      relatedWithoutPreview "group_peer" "Group peer"
    ]
  }]
}

private def sampleGroupCache : HtmlCacheFile := {
  entries := #[
    { key := "informal:group_member:statement", html := "<div>group member</div>" },
    { key := "informal:group_peer:statement", html := "<div>group peer</div>" }
  ]
}

private def sampleExternalGroupManifest : ManifestFile := {
  sampleGroupManifest with
    previews := sampleGroupManifest.previews.map fun entry =>
      if entry.label == label "group_member" then
        {
          entry with
            key := Informal.PreviewManifest.externalMarkupEntryKey entry.label
            targetKind := .externalMarkup
        }
      else
        entry
}

private def sampleExternalGroupCache : HtmlCacheFile := {
  entries := #[
    { key := "informal:group_peer:statement", html := "<div>group peer</div>" }
  ]
}

private def sampleSemanticOnlyExternalManifest : ManifestFile := {
  previews := #[
    {
      key := Informal.PreviewManifest.externalMarkupEntryKey (label "semantic_only_external")
      targetKind := .externalMarkup
      label := label "semantic_only_external"
      facet := .statement
      kind := some .theorem
      title := "Semantic-only external theorem"
    }
  ]
}

private def sampleSemanticOnlyExternalCache : HtmlCacheFile := {
  entries := #[]
}

private def sampleCacheOnlyRelationManifest : ManifestFile := {
  previews := #[
    {
      key := "informal:relation_source:statement"
      targetKind := .block
      label := label "relation_source"
      facet := .statement
      kind := some .theorem
      title := "Theorem 1"
      uses := #[related "cache_only_relation" "Cache-only relation" "informal:cache_only_relation:statement"]
    }
  ]
}

private def sampleCacheOnlyRelationCache : HtmlCacheFile := {
  entries := #[
    { key := "informal:relation_source:statement", html := "<div>relation source</div>" },
    { key := "informal:cache_only_relation:statement", html := "<div>cache only</div>" }
  ]
}

private def sampleGraphReferenceManifest : ManifestFile := {
  previews := #[
    {
      key := Informal.PreviewManifest.externalMarkupEntryKey (label "semantic_graph_target")
      targetKind := .externalMarkup
      label := label "semantic_graph_target"
      facet := .statement
      kind := some .theorem
      title := "Semantic graph target"
    }
  ]
  graphs := #[finishedGraph "graph-fixture" #[
    {
      label := label "semantic_graph_target"
      title := "Semantic graph target"
      displayLabel := "Semantic graph target"
      previewKey :=
        Informal.PreviewKey.ofString?
          (Informal.PreviewManifest.externalMarkupEntryKey (label "semantic_graph_target"))
      visual := { fillcolor := "#ffffff" }
    },
    {
      label := label "cache_only_graph"
      title := "Cache-only graph target"
      displayLabel := "Cache-only graph target"
      previewKey := Informal.PreviewKey.ofString? "informal:cache_only_graph:statement"
      visual := { fillcolor := "#ffffff" }
    }
  ]]
}

private def sampleGraphReferenceCache : HtmlCacheFile := {
  entries := #[
    { key := "informal:cache_only_graph:statement", html := "<div>cache only graph</div>" }
  ]
}

private def sampleUnfinalizedReferenceManifest : ManifestFile := {
  previews := #[
    {
      key := "informal:reference_source:statement"
      targetKind := .block
      label := label "reference_source"
      facet := .statement
      kind := some .theorem
      title := "Reference source"
      parent := some (label "reference_group")
      parentTitle := some "Reference group"
      leanCodePreviewKeys := #[
        "lean:Valid",
        "lean:MissingManifest",
        "lean:MissingCache"
      ]
      uses := #[
        related "valid_target" "Valid target" "informal:valid_target:statement",
        related "cache_only_target" "Cache-only target" "informal:cache_only_target:statement",
        related "missing_cache_target" "Missing-cache target" "informal:missing_cache_target:statement"
      ]
      usedBy := #[
        related "valid_target" "Valid target" "informal:valid_target:statement",
        related "cache_only_target" "Cache-only target" "informal:cache_only_target:statement",
        related "missing_cache_target" "Missing-cache target" "informal:missing_cache_target:statement"
      ]
    },
    {
      key := "informal:valid_target:statement"
      targetKind := .block
      label := label "valid_target"
      facet := .statement
      kind := some .definition
      title := "Valid target"
    },
    {
      key := "informal:missing_cache_target:statement"
      targetKind := .block
      label := label "missing_cache_target"
      facet := .statement
      kind := some .definition
      title := "Missing-cache target"
    },
    {
      key := "lean:Valid"
      targetKind := .leanDecl
      label := label "Valid"
      facet := .statement
      title := "Valid"
    },
    {
      key := "lean:MissingCache"
      targetKind := .leanDecl
      label := label "MissingCache"
      facet := .statement
      title := "MissingCache"
    }
  ]
  groups := #[{
    label := label "reference_group"
    title := "Reference group"
    declared := true
    entries := #[
      related "valid_target" "Valid target" "informal:valid_target:statement",
      related "cache_only_target" "Cache-only target" "informal:cache_only_target:statement",
      related "missing_cache_target" "Missing-cache target" "informal:missing_cache_target:statement"
    ]
  }]
  graphs := #[finishedGraph "reference-finalization" #[
      {
        label := label "valid_target"
        title := "Valid target"
        displayLabel := "Valid target"
        previewKey := Informal.PreviewKey.ofString? "informal:valid_target:statement"
        visual := { fillcolor := "#ffffff" }
      },
      {
        label := label "cache_only_target"
        title := "Cache-only target"
        displayLabel := "Cache-only target"
        previewKey := Informal.PreviewKey.ofString? "informal:cache_only_target:statement"
        visual := { fillcolor := "#ffffff" }
      },
      {
        label := label "missing_cache_target"
        title := "Missing-cache target"
        displayLabel := "Missing-cache target"
        previewKey := Informal.PreviewKey.ofString? "informal:missing_cache_target:statement"
        visual := { fillcolor := "#ffffff" }
      }
    ]]
}

private def sampleUnfinalizedReferenceCache : HtmlCacheFile := {
  entries := #[
    { key := "informal:reference_source:statement", html := "<div>reference source</div>" },
    { key := "informal:valid_target:statement", html := "<div>valid target</div>" },
    { key := "informal:cache_only_target:statement", html := "<div>cache only target</div>" },
    { key := "lean:Valid", html := "<pre>Valid</pre>" }
  ]
}

private def sampleCache : HtmlCacheFile := {
  entries := #[
    { key := "informal:addition_spec:statement", html := "<div>addition spec</div>" },
    { key := "informal:addition_assoc:statement", html := "<div>addition assoc</div>" },
    { key := "lean:Nat.add_assoc", html := "<pre>Nat.add_assoc</pre>" }
  ]
}

private def sampleMetadataManifest : ManifestFile := {
  previews := #[
    {
      key := "informal:zeta_statement:statement"
      targetKind := .block
      label := label "zeta_statement"
      facet := .statement
      title := "Zeta"
      ownerDisplayName := some "Zed"
      tags := #["zeta", "alpha"]
    },
    {
      key := "informal:alpha_statement:statement"
      targetKind := .block
      label := label "alpha_statement"
      facet := .statement
      title := "Alpha"
      ownerDisplayName := some "Alpha"
      tags := #["beta"]
    },
    {
      key := "informal:proof_statement:statement"
      targetKind := .block
      label := label "proof_statement"
      facet := .statement
      kind := some .theorem
      title := "Proof statement"
    }
  ]
  graphs := #[finishedGraph "metadata-status" #[
      {
        label := label "zeta_statement"
        title := "Zeta"
        displayLabel := "Zeta"
        kind := some .definition
        statementStatus := .ready
        proofStatus := .ready
        visual := { fillcolor := "#ffffff" }
      },
      {
        label := label "alpha_statement"
        title := "Alpha"
        displayLabel := "Alpha"
        kind := some .definition
        statementStatus := .blocked
        visual := { fillcolor := "#ffffff" }
      },
      {
        label := label "proof_statement"
        title := "Proof statement"
        displayLabel := "Proof statement"
        kind := some .theorem
        statementStatus := .formalized
        proofStatus := .incomplete
        visual := { fillcolor := "#ffffff" }
      }
    ]]
}

private def jsonField? (json : Json) (field : String) : Option Json :=
  match json.getObjVal? field with
  | .ok value => some value
  | .error _ => none

private def jsonStringField? (json : Json) (field : String) : Option String :=
  match json.getObjValAs? String field with
  | .ok value => some value
  | .error _ => none

private def jsonBoolField? (json : Json) (field : String) : Option Bool :=
  match json.getObjValAs? Bool field with
  | .ok value => some value
  | .error _ => none

private def jsonNullField (json : Json) (field : String) : Bool :=
  match jsonField? json field with
  | some .null => true
  | _ => false

private def jsonNatField? (json : Json) (field : String) : Option Nat :=
  match json.getObjValAs? Nat field with
  | .ok value => some value
  | .error _ => none

private def jsonArrayField? (json : Json) (field : String) : Option (Array Json) :=
  match jsonField? json field with
  | some (.arr values) => some values
  | _ => none

private def jsonHasApiStability (json : Json) : Bool :=
  jsonStringField? json "apiStability" == some VersoBlueprint.Vbp.apiStability

private def jsonArrayContainsString (values : Array Json) (expected : String) : Bool :=
  values.any (fun
    | .str value => value == expected
    | _ => false)

private def jsonArrayHasStringField (values : Array Json) (field expected : String) : Bool :=
  values.any (fun json => jsonStringField? json field == some expected)

private def jsonArrayHasNullField (values : Array Json) (field : String) : Bool :=
  values.any (fun json => jsonNullField json field)

private def previewKeyValue? (key? : Option Informal.PreviewKey) : Option String :=
  key?.map (·.value)

private def relatedPreviewKeys (entries : Array RelatedEntry) : Array (String × Option String) :=
  entries.map fun entry =>
    (Informal.PreviewManifest.labelString entry.label, previewKeyValue? entry.previewKey)

private def graphNodePreviewKeys
    (nodes : Array Informal.Graph.NodeData) : Array (String × Option String) :=
  nodes.map fun node =>
    (Informal.PreviewManifest.labelString node.label, previewKeyValue? node.previewKey)

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let text := VersoBlueprint.Vbp.Main.helpText
    text.contains "lake exe vbp query [--site <dir>] <selector>" &&
      text.contains "Query selectors:" &&
      text.contains "selectors" &&
      text.contains "node <label>" &&
      !text.contains "all <label>" &&
      text.contains "search <text>" &&
      text.contains "lake exe vbp build [--output <dir>] [--pdf] [--verbose]" &&
      text.contains "--pdf builds _out/site/pdf/main.pdf" &&
      text.contains "--verbose shows Blueprint generation phase progress during build" &&
      text.contains "--serve --port <n>" &&
      text.contains "build writes _out/site" &&
      !text.contains "lake exe vbp query [--site <dir>] node <label>"

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let text := VersoBlueprint.Vbp.Main.buildHelpText
    text.contains "lake exe vbp build [--output <dir>] [--pdf] [--verbose]" &&
      text.contains "--verbose" &&
      text.contains "Show Blueprint generation phase progress" &&
      text.contains "--port <n>"

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    (VersoBlueprint.Vbp.Main.conventionalGeneratorFiles "ProjectTemplate").map (·.toString) ==
        #["ProjectTemplateMain.lean", "Main.lean", "BlueprintMain.lean"] &&
      VersoBlueprint.Vbp.Main.generatorModuleFromFile (System.FilePath.mk "ProjectTemplateMain.lean") ==
        "ProjectTemplateMain" &&
      VersoBlueprint.Vbp.Main.generatorModuleFromFile
          (System.FilePath.mk "Blueprint" / "Main.lean") ==
        "Blueprint.Main" &&
      VersoBlueprint.Vbp.Main.packageOLeanTarget "ProjectTemplate" == "+ProjectTemplate:olean" &&
      VersoBlueprint.Vbp.Main.packageOLeanTarget "Contents" == "+Contents:olean"

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let text := Informal.PreviewManifest.helpText
    text.contains "Blueprint PDF options:" &&
      text.contains "--pdf" &&
      text.contains "--pdf-engine <cmd>" &&
      text.contains "--pdf-runs <n>"

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match Informal.PreviewManifest.parsePdfOptions
        ["--output", "_out/custom", "--pdf", "--pdf-engine", "xelatex", "--pdf-runs", "3", "--verbose"] with
    | .ok (opts, rest) =>
        opts.enabled &&
          opts.engine == "xelatex" &&
          opts.runs == 3 &&
          rest == ["--output", "_out/custom", "--verbose"]
    | .error _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match Informal.PreviewManifest.parsePdfOptions ["--pdf-runs", "0"] with
    | .ok _ => false
    | .error err => err.contains "expected a positive integer"

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    sampleManifest.graphs.isEmpty && sampleManifest.workQueueItems.isEmpty

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match
      sampleExternalManifest.findPrimaryQueryableEntry? "external_bodyless",
      sampleManifest.findPrimaryQueryableEntry? "addition_assoc" with
    | some externalEntry, some blockEntry =>
        sampleManifest.blockStatementEntries.size == 2 &&
          sampleExternalManifest.queryableStatementEntries.size == 3 &&
          (sampleManifest.findPrimaryBlockEntry? "addition_assoc").map (·.key) ==
            some "informal:addition_assoc:statement" &&
          externalEntry.key ==
            Informal.PreviewManifest.externalMarkupEntryKey (label "external_bodyless") &&
          externalEntry.isQueryableStatement &&
          !externalEntry.requiresRenderedBody &&
          blockEntry.requiresRenderedBody &&
          sampleMetadataManifest.ownerValues == #["Alpha", "Zed"] &&
          sampleMetadataManifest.tagValues == #["alpha", "beta", "zeta"] &&
          sampleMetadataManifest.metadataEntries.map (·.authoredLabel) ==
            #["zeta_statement", "alpha_statement"]
    | _, _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let items := sampleMetadataManifest.workQueueItems
    items.map (fun item => (item.entry.authoredLabel, item.nextStep)) ==
        #[("zeta_statement", "statement"), ("proof_statement", "proof")] &&
      items.all fun item =>
        item.graphNode.label == item.entry.label &&
          item.graphNode.actionableStage? == some item.nextStep

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match
      sampleMetadataManifest.actionableGraphNode? (label "proof_statement"),
      sampleMetadataManifest.actionableGraphNode? (label "alpha_statement") with
    | some proofNode, none =>
        proofNode.label == label "proof_statement" &&
          proofNode.actionableStage? == some "proof"
    | _, _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let finalizedFiles :=
      Informal.PreviewManifest.Files.finalizePreviewReferences <|
        previewData sampleUnfinalizedReferenceManifest sampleUnfinalizedReferenceCache
    let finalized := finalizedFiles.manifest
    match finalized.findEntry? "informal:reference_source:statement",
        finalized.graphs.find? (fun graph => graph.key == "reference-finalization") with
    | some source, some graph =>
        let expectedRelatedKeys := #[
          ("valid_target", some "informal:valid_target:statement"),
          ("cache_only_target", none),
          ("missing_cache_target", none)
        ]
        let groupKeys :=
          match finalized.groupForEntry? source with
          | some group => relatedPreviewKeys group.entries
          | none => #[]
        let variantKeys :=
          match graph.variants[0]? with
          | some variant => variant.previewKeyByNodeId
          | none => #[]
        source.leanCodePreviewKeys == #["lean:Valid"] &&
          relatedPreviewKeys source.uses == expectedRelatedKeys &&
          relatedPreviewKeys source.usedBy == expectedRelatedKeys &&
          groupKeys == expectedRelatedKeys &&
          graphNodePreviewKeys graph.nodes == expectedRelatedKeys &&
          variantKeys == #[(graphNodeSvgId (label "valid_target"),
            "informal:valid_target:statement")]
    | _, _ => false

private partial def freshVbpFixtureRoot : IO System.FilePath := do
  let suffix ← IO.rand 0 1000000000000
  let root :=
    System.FilePath.mk ".lake" / "build" / "tmp" /
      "verso-blueprint-vbp-test" / toString suffix
  if ← root.pathExists then
    freshVbpFixtureRoot
  else
    pure root

private def writeManifestOnlySite (site : System.FilePath) : IO Unit := do
  let dataDir := site / "html-multi" / "-verso-data"
  IO.FS.createDirAll dataDir
  IO.FS.writeFile
    (dataDir / Informal.PreviewManifest.manifestFilename)
    (toJson sampleManifest).compress

private def writeRawManifestOnlySite (site : System.FilePath) (manifestJson : Json) : IO Unit := do
  let dataDir := site / "html-multi" / "-verso-data"
  IO.FS.createDirAll dataDir
  IO.FS.writeFile
    (dataDir / Informal.PreviewManifest.manifestFilename)
    manifestJson.compress

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let json := toJson sampleManifest
    match
      jsonNatField? json Informal.PreviewManifest.manifestInternalSchemaVersionField,
      jsonArrayField? json "previews",
      jsonArrayField? json "groups" with
    | some version, some previews, some groups =>
        version == Informal.PreviewManifest.manifestInternalSchemaVersion &&
          previews.foldl
            (fun ok entry =>
              ok && (jsonField? entry "sourceLocation").isSome &&
                (jsonField? entry "group").isNone)
            true &&
          groups == sampleManifest.groups.map toJson
    | _, _, _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.queryJson sampleManifest ["selectors"] with
    | .ok json =>
        match jsonArrayField? json "selectors" with
        | some selectors =>
            jsonHasApiStability json &&
              jsonArrayContainsString selectors "selectors" &&
              jsonArrayContainsString selectors "node <label>" &&
              !jsonArrayContainsString selectors "all <label>" &&
              jsonArrayContainsString selectors "work-queue" &&
              jsonArrayContainsString selectors "metadata" &&
              jsonArrayContainsString selectors "search <text>"
        | none => false
    | .error _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.queryJson sampleMetadataManifest ["work-queue"] with
    | .ok json =>
        match jsonArrayField? json "entries" with
        | some entries =>
            match
              entries.find? (fun entry => jsonStringField? entry "label" == some "zeta_statement"),
              entries.find? (fun entry => jsonStringField? entry "label" == some "proof_statement") with
            | some statementEntry, some proofEntry =>
                entries.size == 2 &&
                  jsonHasApiStability json &&
                  jsonStringField? statementEntry "nextStep" == some "statement" &&
                  jsonStringField? statementEntry "statementStatus" == some "ready to formalize" &&
                  jsonStringField? statementEntry "proofStatus" == some "ready to formalize" &&
                  jsonStringField? proofEntry "nextStep" == some "proof" &&
                  jsonStringField? proofEntry "statementStatus" == some "formalized" &&
                  jsonStringField? proofEntry "proofStatus" == some "Lean code incomplete"
            | _, _ => false
        | none => false
    | .error _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.queryJson sampleMetadataManifest ["metadata"] with
    | .ok json =>
        match jsonArrayField? json "entries" with
        | some entries =>
            entries.size == 2 &&
              jsonArrayHasStringField entries "label" "zeta_statement" &&
              jsonArrayHasStringField entries "label" "alpha_statement"
        | none => false
    | .error _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.queryJson sampleManifest ["labels"] with
    | .ok json =>
        match jsonArrayField? json "labels" with
        | some labels =>
            jsonHasApiStability json &&
              jsonArrayHasStringField labels "label" "addition_spec" &&
              jsonArrayHasStringField labels "authoredLabel" "addition_spec" &&
              jsonArrayHasStringField labels "label" "addition_assoc" &&
              jsonArrayHasStringField labels "authoredLabel" "addition_assoc" &&
              !jsonArrayHasStringField labels "label" "Nat.add_assoc"
        | none => false
    | .error _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.queryJson sampleExternalManifest ["labels"] with
    | .ok json =>
        match jsonArrayField? json "labels" with
        | some labels =>
            jsonHasApiStability json &&
              jsonArrayHasStringField labels "label" "external_bodyless" &&
              jsonArrayHasStringField labels "authoredLabel" "external_bodyless" &&
              !jsonArrayHasStringField labels "label" "Nat.add_assoc"
        | none => false
    | .error _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.queryJson sampleManifest ["node", "addition_assoc"] with
    | .ok json =>
        match jsonArrayField? json "statementUses" with
        | some statementUses =>
            jsonHasApiStability json &&
              jsonStringField? json "label" == some "addition_assoc" &&
              jsonStringField? json "authoredLabel" == some "addition_assoc" &&
              jsonStringField? json "ownerDisplayName" == some "Project Author" &&
              jsonArrayHasStringField statementUses "label" "addition_spec" &&
              jsonArrayContainsString (jsonArrayField? json "leanCodePreviewKeys" |>.getD #[]) "lean:Nat.add_assoc"
        | none => false
    | .error _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.queryJson sampleExternalManifest ["node", "external_bodyless"] with
    | .ok json =>
        match jsonArrayField? json "statementUses" with
        | some statementUses =>
            jsonHasApiStability json &&
              jsonStringField? json "targetKind" == some "externalMarkup" &&
              jsonStringField? json "label" == some "external_bodyless" &&
              jsonStringField? json "ownerDisplayName" == some "Source Author" &&
              jsonArrayHasStringField statementUses "label" "addition_spec"
        | none => false
    | .error _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.queryJson sampleManifest ["used-by", "addition_spec"] with
    | .ok json =>
        match jsonArrayField? json "usedBy" with
        | some usedBy =>
            jsonHasApiStability json &&
              jsonStringField? json "label" == some "addition_spec" &&
              jsonArrayHasStringField usedBy "label" "addition_assoc" &&
              jsonArrayHasStringField usedBy "previewKey" "informal:addition_assoc:statement"
        | none => false
    | .error _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.queryJson sampleEmptyRelationManifest ["uses", "relation_source"] with
    | .ok json =>
        match jsonArrayField? json "uses" with
        | some uses =>
            jsonHasApiStability json &&
              jsonArrayHasStringField uses "label" "relation_target" &&
              jsonArrayHasNullField uses "previewKey" &&
              !jsonArrayHasStringField uses "previewKey" ""
        | none => false
    | .error _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.queryJson sampleManifest ["all", "addition_assoc"] with
    | .ok _ => false
    | .error err => err == "unknown query selector 'all'"

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.queryJson sampleManifest ["search", "assoc"] with
    | .ok json =>
        match jsonArrayField? json "labels" with
        | some labels =>
            jsonStringField? json "query" == some "assoc" &&
              jsonArrayHasStringField labels "label" "addition_assoc" &&
              !jsonArrayHasStringField labels "label" "addition_spec"
        | none => false
    | .error _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.queryJson sampleManifest ["search", "THEOREM"] with
    | .ok json =>
        match jsonArrayField? json "labels" with
        | some labels =>
            jsonStringField? json "query" == some "THEOREM" &&
              jsonArrayHasStringField labels "label" "addition_assoc" &&
              !jsonArrayHasStringField labels "label" "addition_spec"
        | none => false
    | .error _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.queryJson sampleManifest ["code", "Nat.add_assoc"] with
    | .ok json =>
        match jsonArrayField? json "labels" with
        | some labels =>
            jsonStringField? json "query" == some "Nat.add_assoc" &&
              jsonArrayHasStringField labels "label" "addition_assoc"
        | none => false
    | .error _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.queryJson sampleExternalManifest ["code", "Nat.mul_assoc"] with
    | .ok json =>
        match jsonArrayField? json "labels" with
        | some labels =>
            jsonStringField? json "query" == some "Nat.mul_assoc" &&
              jsonArrayHasStringField labels "label" "external_bodyless"
        | none => false
    | .error _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.queryJson sampleInlineCodeManifest ["code", "Inline.localDef"] with
    | .ok json =>
        match jsonArrayField? json "labels" with
        | some labels =>
            jsonStringField? json "query" == some "Inline.localDef" &&
              jsonArrayHasStringField labels "label" "inline_code_label"
        | none => false
    | .error _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.queryJson sampleManifest ["stats"] with
    | .ok json =>
        match jsonField? json "byKind", jsonField? json "byTag" with
        | some byKind, some byTag =>
            jsonHasApiStability json &&
              jsonNatField? json "statements" == some 2 &&
              jsonNatField? byKind "definition" == some 1 &&
              jsonNatField? byKind "theorem" == some 1 &&
              jsonNatField? byTag "starter" == some 2
        | _, _ => false
    | .error _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.queryJson sampleExternalManifest ["stats"] with
    | .ok json =>
        match jsonField? json "byKind", jsonField? json "byTag" with
        | some byKind, some byTag =>
            jsonHasApiStability json &&
              jsonNatField? json "statements" == some 3 &&
              jsonNatField? byKind "corollary" == some 1 &&
              jsonNatField? byTag "external-source" == some 1
        | _, _ => false
    | .error _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.queryJson sampleManifest [] with
    | .ok _ => false
    | .error err => err == "missing query selector"

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.queryJson sampleManifest ["bogus"] with
    | .ok _ => false
    | .error err => err == "unknown query selector 'bogus'"

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.queryJson sampleManifest ["node", "missing_label"] with
    | .ok json =>
        jsonHasApiStability json &&
          jsonStringField? json "error" == some "unknown-label" &&
          jsonStringField? json "label" == some "missing_label"
    | .error _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    VersoBlueprint.Vbp.checkGeneratedData (previewData sampleManifest sampleCache) |>.isEmpty

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    VersoBlueprint.Vbp.checkGeneratedData
      (previewData sampleGroupManifest sampleGroupCache) |>.isEmpty

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    VersoBlueprint.Vbp.checkGeneratedData
      (previewData sampleExternalGroupManifest sampleExternalGroupCache) |>.isEmpty

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let orphanedManifest := { sampleGroupManifest with groups := #[] }
    let group := sampleGroupManifest.groups[0]!
    let duplicateGroupManifest := {
      sampleGroupManifest with groups := sampleGroupManifest.groups.push group
    }
    let firstMember := group.entries[0]!
    let duplicateMemberManifest := {
      sampleGroupManifest with
        groups := #[{ group with entries := group.entries.push firstMember }]
    }
    let secondGroup := {
      group with
        label := label "second_group"
        title := "Second group"
        entries := #[firstMember]
    }
    let crossGroupMemberManifest := {
      sampleGroupManifest with groups := sampleGroupManifest.groups.push secondGroup
    }
    let missingMemberManifest := {
      sampleGroupManifest with
        groups := #[{
          group with entries := group.entries.filter (·.label != label "group_member")
        }]
    }
    let orphanMemberManifest := {
      sampleGroupManifest with
        previews := sampleGroupManifest.previews.filter (·.label != label "group_peer")
    }
    let mismatchedParentManifest := {
      sampleGroupManifest with
        previews := sampleGroupManifest.previews.map fun entry =>
          if entry.label == label "group_member" then
            { entry with parent := some (label "second_group"), parentTitle := some "Second group" }
          else
            entry
        groups := sampleGroupManifest.groups.push { secondGroup with entries := #[] }
    }
    let mismatchedTitleManifest := {
      sampleGroupManifest with
        previews := sampleGroupManifest.previews.map fun entry =>
          if entry.label == label "group_member" then
            { entry with parentTitle := some "Stale group title" }
          else
            entry
    }
    let unparentedMemberManifest := {
      sampleGroupManifest with
        previews := sampleGroupManifest.previews.map fun entry =>
          if entry.label == label "group_member" then
            { entry with parent := none, parentTitle := none }
          else
            entry
    }
    let emptyGroupLabelManifest := {
      sampleGroupManifest with groups := #[{ group with label := .anonymous }]
    }
    let emptyGroupTitleManifest := {
      sampleGroupManifest with groups := #[{ group with title := "  " }]
    }
    let emptyMemberLabelManifest := {
      sampleGroupManifest with
        groups := #[{
          group with
            entries := group.entries.map fun member =>
              if member.label == firstMember.label then
                { member with label := .anonymous }
              else
                member
        }]
    }
    let emptyEntryLabelManifest := {
      sampleGroupManifest with
        previews := sampleGroupManifest.previews.map fun entry =>
          if entry.label == label "group_member" then
            { entry with label := .anonymous }
          else
            entry
    }
    let invalidParentManifest := {
      sampleGroupManifest with
        previews := sampleGroupManifest.previews.map fun entry =>
          if entry.label == label "group_member" then
            { entry with parent := some .anonymous }
          else
            entry
    }
    let checkGroups manifest :=
      VersoBlueprint.Vbp.checkGeneratedData (previewData manifest sampleGroupCache)
    let orphanErrors := checkGroups orphanedManifest
    let duplicateGroupErrors := checkGroups duplicateGroupManifest
    let duplicateMemberErrors := checkGroups duplicateMemberManifest
    let crossGroupMemberErrors := checkGroups crossGroupMemberManifest
    let missingMemberErrors := checkGroups missingMemberManifest
    let orphanMemberErrors := checkGroups orphanMemberManifest
    let mismatchedParentErrors := checkGroups mismatchedParentManifest
    let mismatchedTitleErrors := checkGroups mismatchedTitleManifest
    let unparentedMemberErrors := checkGroups unparentedMemberManifest
    let emptyGroupLabelErrors := checkGroups emptyGroupLabelManifest
    let emptyGroupTitleErrors := checkGroups emptyGroupTitleManifest
    let emptyMemberLabelErrors := checkGroups emptyMemberLabelManifest
    let emptyEntryLabelErrors := checkGroups emptyEntryLabelManifest
    let invalidParentErrors := checkGroups invalidParentManifest
    orphanErrors.any (fun err =>
      err == "entry informal:group_member:statement references missing manifest group: sample_group") &&
      duplicateGroupErrors.any (fun err =>
        err == "duplicate manifest group label: sample_group") &&
      duplicateMemberErrors.any (fun err =>
        err == "duplicate member group_member in manifest group sample_group") &&
      crossGroupMemberErrors.any (fun err =>
        err ==
          "manifest member group_member belongs to multiple groups: sample_group and second_group") &&
      missingMemberErrors.any (fun err =>
        err == "entry informal:group_member:statement is missing from manifest group: sample_group") &&
      orphanMemberErrors.any (fun err =>
        err == "manifest group sample_group member group_peer has no matching manifest entry") &&
      mismatchedParentErrors.any (fun err =>
        err ==
          "entry informal:group_member:statement belongs to manifest group sample_group but references second_group") &&
      mismatchedTitleErrors.any (fun err =>
        err ==
          "entry informal:group_member:statement has inconsistent parentTitle for manifest group: sample_group") &&
      unparentedMemberErrors.any (fun err =>
        err ==
          "entry informal:group_member:statement has no parent but is listed in manifest group: sample_group") &&
      emptyGroupLabelErrors.any (· == "manifest group has empty label") &&
      emptyGroupTitleErrors.any (· == "manifest group sample_group has empty title") &&
      emptyMemberLabelErrors.any (· == "manifest group sample_group has member with empty label") &&
      emptyEntryLabelErrors.any (· == "entry informal:group_member:statement is missing label") &&
      invalidParentErrors.any (· == "entry informal:group_member:statement has invalid parent")

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    VersoBlueprint.Vbp.checkGeneratedData
      (previewData sampleEmptyRelationManifest sampleEmptyRelationCache) |>.isEmpty

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    VersoBlueprint.Vbp.checkGeneratedData
      (previewData sampleSemanticOnlyExternalManifest sampleSemanticOnlyExternalCache) |>.isEmpty

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let errors := VersoBlueprint.Vbp.checkGeneratedData <|
      previewData sampleCacheOnlyRelationManifest sampleCacheOnlyRelationCache
    errors.any (fun err =>
      err.contains "missing manifest entry for uses of informal:relation_source:statement relation cache_only_relation" &&
        err.contains "informal:cache_only_relation:statement") &&
      !errors.any (fun err =>
        err.contains "missing HTML cache entry" &&
          err.contains "informal:cache_only_relation:statement")

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let errors := VersoBlueprint.Vbp.checkGeneratedData <|
      previewData sampleGraphReferenceManifest sampleGraphReferenceCache
    errors.any (fun err =>
      err.contains "missing HTML cache entry for graph graph-fixture node semantic_graph_target" &&
        err.contains (Informal.PreviewManifest.externalMarkupEntryKey (label "semantic_graph_target"))) &&
    errors.any (fun err =>
        err.contains "missing manifest entry for graph graph-fixture node cache_only_graph" &&
          err.contains "informal:cache_only_graph:statement") &&
      !errors.any (fun err =>
        err.contains "missing HTML cache entry for graph graph-fixture node cache_only_graph" &&
          err.contains "informal:cache_only_graph:statement")

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let json := VersoBlueprint.Vbp.checkJson (previewData sampleManifest sampleCache)
    jsonHasApiStability json &&
      jsonBoolField? json "ok" == some true &&
      jsonNatField? json "manifestEntries" == some 3 &&
      jsonNatField? json "htmlCacheEntries" == some 3

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let json := VersoBlueprint.Vbp.checkJsonFromErrors
      (previewData sampleManifest sampleCache) #["forced diagnostic"]
    let errors := jsonArrayField? json "errors" |>.getD #[]
    jsonBoolField? json "ok" == some false &&
      jsonArrayContainsString errors "forced diagnostic"

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let brokenCache : HtmlCacheFile := {
      entries := sampleCache.entries.filter (fun entry => entry.key != "lean:Nat.add_assoc")
    }
    VersoBlueprint.Vbp.checkGeneratedData (previewData sampleManifest brokenCache)
      |>.any (·.contains "lean:Nat.add_assoc")

/-- info: true -/
#guard_msgs in
#eval do
  let site ← freshVbpFixtureRoot
  writeManifestOnlySite site
  let manifest ← VersoBlueprint.Vbp.readManifestForSite site
  let queryOk :=
    match VersoBlueprint.Vbp.queryJson manifest ["labels"] with
    | .ok json =>
        let labels := jsonArrayField? json "labels" |>.getD #[]
        jsonArrayHasStringField labels "label" "addition_assoc"
    | .error _ => false
  let cacheMissing ←
    try
      let _ ← VersoBlueprint.Vbp.readHtmlCacheForSite site
      pure false
    catch err =>
      let message := IO.Error.toString err
      pure <| message.contains "run `lake exe vbp build` first" &&
        !message.contains "vbp check"
  pure (queryOk && cacheMissing)

/-- info: true -/
#guard_msgs in
#eval do
  let site ← freshVbpFixtureRoot
  writeRawManifestOnlySite site (toJson sampleGraphReferenceManifest)
  let strictManifest ← VersoBlueprint.Vbp.readManifestForSite site
  let queryManifest ← VersoBlueprint.Vbp.readManifestForQuery site ["labels"]
  let workQueueManifest ← VersoBlueprint.Vbp.readManifestForQuery site ["work-queue"]
  pure <|
    strictManifest.graphs.size == 1 &&
      queryManifest.graphs.isEmpty &&
      workQueueManifest.graphs.size == 1 &&
      queryManifest.previews.map
          (fun entry : Informal.PreviewManifest.Entry => entry.key) ==
        sampleGraphReferenceManifest.previews.map
          (fun entry : Informal.PreviewManifest.Entry => entry.key)

/-- info: true -/
#guard_msgs in
#eval do
  let site ← freshVbpFixtureRoot
  let malformedGraphManifest :=
    (toJson sampleManifest).setObjVal! "graphs" (Json.arr #[Json.str "malformed"])
  writeRawManifestOnlySite site malformedGraphManifest
  let queryManifest ← VersoBlueprint.Vbp.readManifestForQuery site ["labels"]
  let strictRejected ←
    try
      let _ ← VersoBlueprint.Vbp.readManifestForSite site
      pure false
    catch _ =>
      pure true
  let workQueueRejected ←
    try
      let _ ← VersoBlueprint.Vbp.readManifestForQuery site ["work-queue"]
      pure false
    catch _ =>
      pure true
  pure <|
    queryManifest.previews.size == sampleManifest.previews.size &&
      queryManifest.graphs.isEmpty &&
      strictRejected &&
      workQueueRejected

/-- info: true -/
#guard_msgs in
#eval do
  let site ← freshVbpFixtureRoot
  let staleManifestJson := Json.mkObj [
    ("previews", Json.arr #[]),
    ("graphs", Json.arr #[]),
    ("sourceDocuments", Json.arr #[])
  ]
  writeRawManifestOnlySite site staleManifestJson
  try
    let _ ← VersoBlueprint.Vbp.readManifestForSite site
    pure false
  catch err =>
    let message := IO.Error.toString err
    pure <|
      message.contains "unsupported internal Blueprint manifest schema" &&
        message.contains Informal.PreviewManifest.manifestInternalSchemaVersionField &&
        message.contains "lake exe vbp build"

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.Main.parseBuildOptions ["--output", "_out/custom", "--serve", "--port", "8080"] {} with
    | .ok opts =>
        opts.output.toString == "_out/custom" &&
          opts.serve &&
          opts.port? == some 8080
    | .error _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.Main.parseBuildOptions ["--port", "not-a-port"] {} with
    | .ok _ => false
    | .error err => err.contains "invalid --port value"

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.Main.parseBuildOptions ["--port", "8080"] {} with
    | .ok _ => false
    | .error err => err == "--port requires --serve"

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.Main.parseBuildOptions ["--port", "8080", "--serve"] {} with
    | .ok opts =>
        opts.serve &&
          opts.port? == some 8080
    | .error _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.Main.parseBuildOptions
        ["--output", "_out/custom", "--pdf", "--pdf-engine", "xelatex", "--pdf-runs", "3",
          "--verbose"] {} with
    | .ok opts =>
        opts.output.toString == "_out/custom" &&
          opts.pdf &&
          opts.pdfEngine? == some "xelatex" &&
          opts.pdfRuns? == some 3 &&
          opts.verbose
    | .error _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.Main.parseBuildOptions ["--port", "70000"] {} with
    | .ok _ => false
    | .error err =>
        err.contains "invalid --port value" &&
          err.contains "65535"

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.Main.parseBuildOptions ["--output"] {} with
    | .ok _ => false
    | .error err => err == "missing value after --output"

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.Main.parseBuildOptions ["--bogus"] {} with
    | .ok _ => false
    | .error err => err == "unknown build option '--bogus'"

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.Main.parseSiteOptions ["--site", "_out/custom", "node", "addition_assoc"] {} with
    | .ok opts =>
        opts.site.toString == "_out/custom" &&
          opts.rest == ["node", "addition_assoc"]
    | .error _ => false

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    match VersoBlueprint.Vbp.Main.parseSiteOptions ["--site"] {} with
    | .ok _ => false
    | .error err => err.contains "missing value after --site"

/-- info: discover does not accept arguments
---
info: true -/
#guard_msgs in
#eval do
  let code ← VersoBlueprint.Vbp.Main.main ["discover", "extra"]
  pure (code == 2)

end Verso.VersoBlueprintTests.Vbp
