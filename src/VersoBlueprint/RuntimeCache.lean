/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Lean.CoreM
public import Std.Data.HashMap
public import VersoBlueprint.Git

public section

namespace Informal.RuntimeCache

open Lean

/--
Process-local runtime facts that are expensive enough to avoid recomputing but
should not be serialized into the Lean environment.

This is intentionally a small in-process backend. The public helpers below take
fallback resolver actions, which keeps callers independent of the storage
strategy and leaves room for a later Lake/build-local file cache.
-/
private structure State where
  moduleSourcePaths : Std.HashMap String (Option System.FilePath) := {}
  gitRootsBySourceDir : Std.HashMap String (Option System.FilePath) := {}
  gitRepoInfoByRoot : Std.HashMap String (Option Git.RepositoryInfo) := {}
deriving Inhabited

private initialize stateRef : IO.Ref State ← IO.mkRef {}

/--
Clear the in-process runtime cache.

This is mainly useful for tests and for future long-lived tooling that wants to
start a new logical build without restarting the Lean process.
-/
def clear : IO Unit :=
  stateRef.set {}

private def pathKey (path : System.FilePath) : String :=
  path.toString

private def moduleSourcePathKey (workspaceRoot : System.FilePath) (moduleName : Name) : String :=
  workspaceRoot.toString ++ "\n" ++ toString moduleName

/--
Cache a source-path lookup for a module in one workspace root.

Negative results are cached too, so fallback probing does not repeat for every
external declaration that mentions the same missing module source.
-/
def cachedModuleSourcePath?
    (workspaceRoot : System.FilePath) (moduleName : Name)
    (resolve : CoreM (Option System.FilePath)) : CoreM (Option System.FilePath) := do
  let key := moduleSourcePathKey workspaceRoot moduleName
  let state ← liftM (m := CoreM) (stateRef.get : IO State)
  if let some cached := state.moduleSourcePaths[key]? then
    return cached
  let resolved ← resolve
  liftM (m := CoreM) <| (stateRef.modify (fun state =>
    { state with moduleSourcePaths := state.moduleSourcePaths.insert key resolved }) : IO Unit)
  pure resolved

/--
Cache the nearest Git root for a source directory.

This cache is directory-scoped rather than file-scoped because `git -C dir
rev-parse --show-toplevel` answers a directory question.
-/
def cachedGitRoot?
    (sourceDir : System.FilePath)
    (resolve : IO (Option System.FilePath)) : IO (Option System.FilePath) := do
  let key := pathKey sourceDir
  if let some cached := (← stateRef.get).gitRootsBySourceDir[key]? then
    return cached
  let resolved ← resolve
  stateRef.modify fun state =>
    { state with gitRootsBySourceDir := state.gitRootsBySourceDir.insert key resolved }
  pure resolved

/--
Cache repository metadata for one Git root.

The commit is part of the cached value. This is process-local, so it assumes the
checkout does not move during a single Lean elaboration process.
-/
def cachedGitRepoInfo?
    (gitRoot : System.FilePath)
    (resolve : IO (Option Git.RepositoryInfo)) : IO (Option Git.RepositoryInfo) := do
  let key := pathKey gitRoot
  if let some cached := (← stateRef.get).gitRepoInfoByRoot[key]? then
    return cached
  let resolved ← resolve
  stateRef.modify fun state =>
    { state with gitRepoInfoByRoot := state.gitRepoInfoByRoot.insert key resolved }
  pure resolved

end Informal.RuntimeCache
