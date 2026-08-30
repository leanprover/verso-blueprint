import Lake
open Lake DSL

-- Verso #971 landed after RC2; pin its merge and matching SubVerso API until
-- the next 4.34 release tag contains both.
require verso from git "https://github.com/leanprover/verso"@"99e9df791e46ec647f81d98b109965f166b9b6b4"
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
    `VersoBlueprintTests.BlueprintAutoDeps,
    `VersoBlueprintTests.BlueprintAttribute,
    `VersoBlueprintTests.BlueprintCodeRenderMatrix,
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
    `VersoBlueprintModuleTests.ExternalMarkupView,
    `VersoBlueprintModuleTests.Foundation,
    `VersoBlueprintModuleTests.Graph,
    `VersoBlueprintModuleTests.GroupAuthoring,
    `VersoBlueprintModuleTests.HoverRender,
    `VersoBlueprintModuleTests.Math,
    `VersoBlueprintModuleTests.MathLeaves,
    `VersoBlueprintModuleTests.RuntimeServices,
    `VersoBlueprintModuleTests.SourceData,
    `VersoBlueprintModuleTests.SourceMetadata,
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
