/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Commands.Common
import VersoBlueprint.Git
import VersoBlueprint.PreviewCache
import VersoBlueprint.RuntimeCache
meta import VersoBlueprint.Commands.Common
meta import VersoBlueprint.PreviewCache

namespace VersoBlueprintModuleTests.RuntimeServices

open Lean

local macro "previewKeyContract" : term => do
  return quote <| Informal.PreviewCache.key (Name.mkSimple "runtime.preview") .proof

local macro "assetBundleContract" : term => do
  let assets := Informal.Commands.inlinePreviewAssetBundle
    (cssExtras := ["contract-css"])
    (jsBefore := ["before-js"])
    (jsAfter := ["after-js"])
  return quote (assets.css.length, assets.js)

/-- info: true -/
#guard_msgs in
#eval
  let assets := Informal.Commands.inlinePreviewAssetBundle
    (cssExtras := ["contract-css"])
    (jsBefore := ["before-js"])
    (jsAfter := ["after-js"])
  (assetBundleContract : Nat × List String) == (assets.css.length, assets.js) &&
    assets.css == [
      Informal.Commands.blueprintTokensCss,
      "contract-css",
      Informal.Commands.previewHeaderCss,
      Informal.Commands.inlinePreviewCss
    ] &&
    assets.js == ["before-js", "after-js"]

/-- info: true -/
#guard_msgs in
#eval
  let label := Name.mkSimple "runtime.preview"
  let entry := Informal.PreviewCache.Entry.ofBlocks label .proof #[]
    (leanCodePreviewKeys := #["lean-preview"])
  let jsonRoundTrip :=
    match fromJson? (α := Informal.PreviewCache.Entry) (toJson entry) with
    | .ok decoded =>
      decoded.label == label && decoded.facet == .proof &&
        decoded.leanCodePreviewKeys == #["lean-preview"]
    | .error _ => false
  (previewKeyContract : String) == Informal.PreviewCache.proofKey label &&
    entry.metadata.label == label && entry.metadata.facet == .proof &&
    !entry.hasRenderedBody && jsonRoundTrip

/-- Pure Git URL normalization remains part of the runtime service contract. -/
example : Option String :=
  Informal.Git.githubRepositoryUrl? "git@github.com:leanprover/verso-blueprint.git"

/-- Repository discovery remains an ordinary runtime operation. -/
example (root : System.FilePath) : IO (Option Informal.Git.RepositoryInfo) :=
  Informal.Git.repositoryInfoAtRoot? root

/-- The cache exposes operations, not its storage representation. -/
example : IO Unit :=
  Informal.RuntimeCache.clear

example (root : System.FilePath) (moduleName : Name)
    (resolve : CoreM (Option System.FilePath)) : CoreM (Option System.FilePath) :=
  Informal.RuntimeCache.cachedModuleSourcePath? root moduleName resolve

example (sourceDir : System.FilePath) (resolve : IO (Option System.FilePath)) :
    IO (Option System.FilePath) :=
  Informal.RuntimeCache.cachedGitRoot? sourceDir resolve

example (gitRoot : System.FilePath) (resolve : IO (Option Informal.Git.RepositoryInfo)) :
    IO (Option Informal.Git.RepositoryInfo) :=
  Informal.RuntimeCache.cachedGitRepoInfo? gitRoot resolve

end VersoBlueprintModuleTests.RuntimeServices
