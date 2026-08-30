import Lake
open Lake DSL

-- Pin the matching post-RC2 Verso/SubVerso API and the split-page section
-- anchor fix until a release tag includes both.
require verso from git "https://github.com/leanprover/verso"@"52c8c9557bcb5cc8c0edc0ee37e74311a3d53ee9"
require «verso-slides» from git "https://github.com/leanprover/verso-slides"@"v4.34.0-rc2"
require subverso from git "https://github.com/leanprover/subverso"@"fda188f7329fa18ce4b2e8cc96c9b0a8f0c78c46"
require proofwidgets from git "https://github.com/leanprover-community/ProofWidgets4"@"v0.0.110"

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
    `VersoBlueprintTests.BlueprintContributions,
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
    `VersoBlueprintTests.BlueprintInlinePrecision,
    `VersoBlueprintTests.BlueprintLinkHover,
    `VersoBlueprintTests.BlueprintMainWrapper,
    `VersoBlueprintTests.BlueprintPreviewResources,
    `VersoBlueprintTests.BlueprintMathLint,
    `VersoBlueprintTests.BlueprintMetadataPanel,
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
    `VersoBlueprintModuleTests.BlockCommon,
    `VersoBlueprintModuleTests.BlockStore,
    `VersoBlueprintModuleTests.Data,
    `VersoBlueprintModuleTests.DependencyAnalysis,
    `VersoBlueprintModuleTests.ExternalDeclRender,
    `VersoBlueprintModuleTests.ExternalDeclRenderData,
    `VersoBlueprintModuleTests.ExternalRefSnapshot,
    `VersoBlueprintModuleTests.Foundation,
    `VersoBlueprintModuleTests.Graph,
    `VersoBlueprintModuleTests.GroupAuthoring,
    `VersoBlueprintModuleTests.HoverRender,
    `VersoBlueprintModuleTests.Math,
    `VersoBlueprintModuleTests.MathLeaves,
    `VersoBlueprintModuleTests.RuntimeServices,
    `VersoBlueprintModuleTests.SourceData,
    `VersoBlueprintModuleTests.TraversalIndex,
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
