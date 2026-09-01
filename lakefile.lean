import Lake
open Lake DSL

-- Verso #971 landed after RC2; pin its merge and matching SubVerso API until
-- the next 4.34 release tag contains both.
require verso from git "https://github.com/leanprover/verso"@"99e9df791e46ec647f81d98b109965f166b9b6b4"
require «verso-slides» from git "https://github.com/ejgallego/verso-slides"@"eba72ccb421f840a2501081381b17d39335e1a84"
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
    `VersoBlueprintModuleTests.AuthorAuthoring,
    `VersoBlueprintModuleTests.BibliographyAuthoring,
    `VersoBlueprintModuleTests.BlockAuthoring,
    `VersoBlueprintModuleTests.BlockCommon,
    `VersoBlueprintModuleTests.BlockStore,
    `VersoBlueprintModuleTests.CodeAuthoring,
    `VersoBlueprintModuleTests.CiteAuthoring,
    `VersoBlueprintModuleTests.CiteData,
    `VersoBlueprintModuleTests.Data,
    `VersoBlueprintModuleTests.DependencyAnalysis,
    `VersoBlueprintModuleTests.ExternalDeclRender,
    `VersoBlueprintModuleTests.ExternalDeclRenderData,
    `VersoBlueprintModuleTests.ExternalMarkupRender,
    `VersoBlueprintModuleTests.ExternalRefSnapshot,
    `VersoBlueprintModuleTests.ExternalMarkupView,
    `VersoBlueprintModuleTests.Foundation,
    `VersoBlueprintModuleTests.Graph,
    `VersoBlueprintModuleTests.GraphAuthoring,
    `VersoBlueprintModuleTests.GraphData,
    `VersoBlueprintModuleTests.GraftAssets,
    `VersoBlueprintModuleTests.GraftAuthoring,
    `VersoBlueprintModuleTests.GraftNode,
    `VersoBlueprintModuleTests.GraftRender,
    `VersoBlueprintModuleTests.GroupAuthoring,
    `VersoBlueprintModuleTests.HoverRender,
    `VersoBlueprintModuleTests.IncrementalAuthoring,
    `VersoBlueprintModuleTests.IncrementalOwner,
    `VersoBlueprintModuleTests.Math,
    `VersoBlueprintModuleTests.MathLeaves,
    `VersoBlueprintModuleTests.PreviewBlockRender,
    `VersoBlueprintModuleTests.PreviewCli,
    `VersoBlueprintModuleTests.PreviewExternalMarkupRender,
    `VersoBlueprintModuleTests.PreviewManifest,
    `VersoBlueprintModuleTests.PreviewRelatedPanel,
    `VersoBlueprintModuleTests.RuntimeServices,
    `VersoBlueprintModuleTests.RustAuthoring,
    `VersoBlueprintModuleTests.SerializedExtension,
    `VersoBlueprintModuleTests.Slides,
    `VersoBlueprintModuleTests.SlidesAssets,
    `VersoBlueprintModuleTests.SlidesNode,
    `VersoBlueprintModuleTests.SlidesRender,
    `VersoBlueprintModuleTests.SourceAuthoring,
    `VersoBlueprintModuleTests.SourceData,
    `VersoBlueprintModuleTests.SourceMetadata,
    `VersoBlueprintModuleTests.SummaryAuthoring,
    `VersoBlueprintModuleTests.SummaryCollect,
    `VersoBlueprintModuleTests.SummaryData,
    `VersoBlueprintModuleTests.SummaryHtml,
    `VersoBlueprintModuleTests.SummaryRender,
    `VersoBlueprintModuleTests.SummarySections,
    `VersoBlueprintModuleTests.TeXRuntime,
    `VersoBlueprintModuleTests.TraversalIndex,
    `VersoBlueprintModuleTests.UsesAuthoring,
    `VersoBlueprintModuleTests.UtilityLeaves,
    `VersoBlueprintModuleTests.VbpCli,
    `VersoBlueprintModuleTests.VbpLibrary,
    `VersoBlueprintModuleTests.Widget
  ]
  requiresModuleSystem := true

lean_lib VersoBlueprintTestDocs where
  srcDir := "tests"
  roots := #[`VersoBlueprintTests.TestBlueprintRegistry]

lean_exe «blueprint-test-docs» where
  root := `BlueprintTestDocsMain
  srcDir := "tests"
  supportInterpreter := true
