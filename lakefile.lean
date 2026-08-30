import Lake
open Lake DSL

-- Pin the matching Lean 4.35 release-candidate dependency stack.
require verso from git "https://github.com/leanprover/verso"@"v4.35.0-rc4"
require «verso-slides» from git "https://github.com/leanprover/verso-slides"@"v4.35.0-rc4"
require subverso from git "https://github.com/leanprover/subverso"@"verso-v4.35.0-rc4"
require proofwidgets from git "https://github.com/leanprover-community/ProofWidgets4"@"v0.0.115"
require lean_vir from git "https://github.com/ejgallego/lean-vir"@"aa465b873387a0bf46669031da1af99f59b0f3b9"

package VersoBlueprint where
  leanOptions := #[⟨`experimental.module, true⟩]

input_dir embeddedBlueprintAssets where
  path := "src/VersoBlueprint"
  text := true
  filter := .extension <| .mem #["css", "js", "mjs"]

input_file blueprintMathJs where
  path := "static-web/math.js"
  text := true

input_file mathLintWorkerJs where
  path := "static-web/katex-lint.mjs"
  text := true

-- Optional VIR resource API; neither the core library nor generator imports it.
lean_lib VersoBlueprintVir where
  srcDir := "src"
  roots := #[`VersoBlueprintVir]

lean_lib VersoBlueprintVirClientTests where
  srcDir := "tests"
  roots := #[`VersoBlueprintVirClientTests.Program]

lean_lib VersoBlueprintVirClientResources where
  srcDir := "tests"
  roots := #[`VersoBlueprintVirClientTests.Resources]
  needs := #[`+VersoBlueprintVirClientTests.Program:virResourcePack]

lean_exe «vir-client-example» where
  srcDir := "tests"
  root := `VirClientExampleMain

-- Blueprint core library.
@[default_target]
lean_lib VersoBlueprint where
  srcDir := "src"
  roots := #[`VersoBlueprint]
  precompileModules := true
  needs := #[embeddedBlueprintAssets, blueprintMathJs, mathLintWorkerJs]

@[default_target]
lean_exe «vbp» where
  root := `VersoBlueprint.VbpMain
  srcDir := "src"
  supportInterpreter := true

@[default_target, test_driver]
lean_lib VersoBlueprintTests where
  srcDir := "tests"
  roots := #[
    `VersoBlueprintTests.Blueprint.Support,
    `VersoBlueprintTests.BlueprintAssets,
    `VersoBlueprintTests.BlueprintImportedContributions,
    `VersoBlueprintTests.BlueprintImportedContributions.ConflictingProofs,
    `VersoBlueprintTests.BlueprintImportedContributions.ConflictingProofsReverse,
    `VersoBlueprintTests.BlueprintImportedContributions.ConflictingStatements,
    `VersoBlueprintTests.BlueprintImportedContributions.ConflictingMetadata,
    `VersoBlueprintTests.BlueprintImportedContributions.ConflictingMarkup,
    `VersoBlueprintTests.BlueprintImportedContributions.ConflictingRust,
    `VersoBlueprintTests.BlueprintImportedContributions.ConflictingIntents,
    `VersoBlueprintTests.BlueprintImportedContributions.ConflictingIntentsReverse,
    `VersoBlueprintTests.BlueprintImportedContributions.AuthorityForward,
    `VersoBlueprintTests.BlueprintImportedContributions.AuthorityReverse,
    `VersoBlueprintTests.BlueprintAutoDeps,
    `VersoBlueprintTests.BlueprintAttribute,
    `VersoBlueprintTests.BlueprintAttributeRendering,
    `VersoBlueprintTests.BlueprintPlacementContracts,
    `VersoBlueprintTests.BlueprintAttributeLateRendering,
    `VersoBlueprintTests.BlueprintBlockFolding,
    `VersoBlueprintTests.BlueprintCodeRenderMatrix,
    `VersoBlueprintTests.BlueprintDocstringReferences,
    `VersoBlueprintTests.BlueprintImportedDuplicates.Direct,
    `VersoBlueprintTests.BlueprintImportedDuplicates.ProviderA,
    `VersoBlueprintTests.BlueprintImportedDuplicates.ProviderB,
    `VersoBlueprintTests.BlueprintImportedDuplicates.Reexport,
    `VersoBlueprintTests.BlueprintImportedDuplicates.Transitive,
    `VersoBlueprintTests.BlueprintExternalHeadingStatus,
    `VersoBlueprintTests.BlueprintGraft,
    `VersoBlueprintTests.BlueprintGraph,
    `VersoBlueprintTests.BlueprintHeaderExtras,
    `VersoBlueprintTests.BlueprintInformal,
    `VersoBlueprintTests.BlueprintProofLeanRefs,
    `VersoBlueprintTests.BlueprintInlinePrecision,
    `VersoBlueprintTests.BlueprintLinkHover,
    `VersoBlueprintTests.BlueprintMainWrapper,
    `VersoBlueprintTests.BlueprintPreviewResources,
    `VersoBlueprintTests.BlueprintMathLint,
    `VersoBlueprintTests.BlueprintMetadataPanel,
    `VersoBlueprintTests.BlueprintIssueUrl,
    `VersoBlueprintTests.BlueprintNumbering,
    `VersoBlueprintTests.BlueprintSlides,
    `VersoBlueprintTests.BlueprintPreviewPanels,
    `VersoBlueprintTests.BlueprintPreviewSchema,
    `VersoBlueprintTests.BlueprintPreviewSource,
    `VersoBlueprintTests.BlueprintPreviewWiring,
    `VersoBlueprintTests.BlueprintPublicRoot,
    `VersoBlueprintTests.BlueprintSource,
    `VersoBlueprintTests.BlueprintSourceIdentity,
    `VersoBlueprintTests.BlueprintRustCode,
    `VersoBlueprintTests.BlueprintSummaryLinks,
    `VersoBlueprintTests.BlueprintSummaryStatus,
    `VersoBlueprintTests.BlueprintTeXCleanup,
    `VersoBlueprintTests.BlueprintTexMacros,
    `VersoBlueprintTests.BlueprintExternalMarkup,
    `VersoBlueprintTests.ExternalDeclRender,
    `VersoBlueprintTests.RuntimeCache,
    `VersoBlueprintTests.SerializedExtension,
    `VersoBlueprintTests.TestBlueprintRegistryMeta,
    `VersoBlueprintTests.TestBlueprintRegistryChecks,
    `VersoBlueprintTests.TestBlueprintRegistryCoverage,
    `VersoBlueprintTests.Vbp
  ]

@[default_target]
lean_lib VersoBlueprintModuleTests where
  srcDir := "tests"
  roots := #[
    `VersoBlueprintModuleTests.Attribute,
    `VersoBlueprintModuleTests.AuthorAuthoring,
    `VersoBlueprintModuleTests.BlockAuthoring,
    `VersoBlueprintModuleTests.BlockCommon,
    `VersoBlueprintModuleTests.BlockStore,
    `VersoBlueprintModuleTests.CodeAuthoring,
    `VersoBlueprintModuleTests.Data,
    `VersoBlueprintModuleTests.DependencyAnalysis,
    `VersoBlueprintModuleTests.ExternalDeclRender,
    `VersoBlueprintModuleTests.ExternalDeclRenderData,
    `VersoBlueprintModuleTests.ExternalMarkupRender,
    `VersoBlueprintModuleTests.ExternalRefSnapshot,
    `VersoBlueprintModuleTests.ExternalMarkupView,
    `VersoBlueprintModuleTests.Foundation,
    `VersoBlueprintModuleTests.Graph,
    `VersoBlueprintModuleTests.GroupAuthoring,
    `VersoBlueprintModuleTests.HoverRender,
    `VersoBlueprintModuleTests.Math,
    `VersoBlueprintModuleTests.MathLeaves,
    `VersoBlueprintModuleTests.RuntimeServices,
    `VersoBlueprintModuleTests.RustAuthoring,
    `VersoBlueprintModuleTests.SourceData,
    `VersoBlueprintModuleTests.SourceMetadata,
    `VersoBlueprintModuleTests.TraversalIndex,
    `VersoBlueprintModuleTests.UsesAuthoring,
    `VersoBlueprintModuleTests.UtilityLeaves
  ]
  requiresModuleSystem := true

lean_lib VersoBlueprintTestDocs where
  srcDir := "tests"
  roots := #[`VersoBlueprintTests.TestBlueprintRegistry]

lean_exe «blueprint-test-docs» where
  root := `BlueprintTestDocsMain
  srcDir := "tests"
  supportInterpreter := true
