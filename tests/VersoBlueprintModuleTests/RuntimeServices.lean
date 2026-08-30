/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Commands.Common
import VersoBlueprint.Git
import VersoBlueprint.PreviewCache
import VersoBlueprint.Resolve
import VersoBlueprint.Rust
import VersoBlueprint.RuntimeCache
meta import VersoBlueprint.Commands.Common
meta import VersoBlueprint.PreviewCache
meta import VersoBlueprint.Resolve
meta import VersoBlueprint.Rust

namespace VersoBlueprintModuleTests.RuntimeServices

open Lean

/-- info: true -/
#guard_msgs in
#eval
  let label := `Contract.label
  let decl := `Contract.declaration
  Informal.Resolve.externalRenderedDeclTargetKey label decl ==
      "14:Contract.label|20:Contract.declaration" &&
    Informal.Resolve.informalDomainName == Name.mkSimple "Informal.Block.informal" &&
    Informal.Resolve.informalPreviewDomainName == Name.mkSimple "Informal.Block.informalPreview"

local macro "previewKeyContract" : term => do
  return quote <| Informal.PreviewCache.key (Name.mkSimple "runtime.preview") .proof

local macro "rustDataContract" : term => do
  let data : Informal.Rust.InlineCodeData := {
    label := Name.mkSimple "module.rust"
    raw := "pub fn contract() -> u32 { 7 }"
    foldCodeBlock := true
  }
  return quote data

/-- info: true -/
#guard_msgs in
#eval
  let data : Informal.Rust.InlineCodeData := rustDataContract
  data.label == Name.mkSimple "module.rust" && data.foldCodeBlock &&
    data.raw.contains "contract" &&
    Informal.Rust.informalRustCodeDomain == Informal.Resolve.informalRustCodeDomainName &&
    Informal.Rust.css.contains "bp_rust_kw"

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
