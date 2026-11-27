/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import VersoBlueprint.Data
import VersoBlueprint.ProvedStatus
import VersoBlueprint.ExternalDeclRender
import VersoBlueprint.ExternalModuleSource
import VersoBlueprint.Git
import VersoBlueprint.RuntimeCache

namespace Informal

open Lean

/--
Template used to build source links for external declarations.
Supported placeholders are: path, relpath, repoRelpath, module, line, column, endLine, endColumn.

Empty template uses automatic GitHub source link generation when the source file
belongs to a Git checkout with a GitHub `origin` remote.
-/
register_option verso.blueprint.externalCode.sourceLinkTemplate : String := {
  defValue := ""
  descr := "Template for external declaration source links ({path},{relpath},{repoRelpath},{module},{line},{column},{endLine},{endColumn}); empty uses automatic GitHub links when available"
}

private def externalSourceLinkTemplate (opts : Lean.Options) : String :=
  opts.get
    verso.blueprint.externalCode.sourceLinkTemplate.name
    verso.blueprint.externalCode.sourceLinkTemplate.defValue

private def workspaceRelativeSourcePath? (workspaceRoot sourcePath : System.FilePath) : Option String :=
  let root := workspaceRoot.toString
  let sep := System.FilePath.pathSeparator.toString
  let rootPrefix := if root.endsWith sep then root else root ++ sep
  let sourcePathText := sourcePath.toString
  if sourcePathText.startsWith rootPrefix then
    some (sourcePathText.drop rootPrefix.length).toString
  else
    none

private def instantiateSourceLinkTemplate (template : String) (vars : Array (String × String)) : String :=
  vars.foldl (init := template) fun acc kv =>
    acc.replace ("{" ++ kv.1 ++ "}") kv.2

private def sourceLineFragment? (range? : Option Lean.DeclarationRange) : Option String := do
  let range ← range?
  let startLine := range.pos.line
  let endLine := range.endPos.line
  if startLine == 0 then
    none
  else if endLine > startLine then
    some s!"#L{startLine}-L{endLine}"
  else
    some s!"#L{startLine}"

private def absoluteSourcePath (workspaceRoot sourcePath : System.FilePath) : System.FilePath :=
  if sourcePath.isAbsolute then
    sourcePath
  else
    workspaceRoot / sourcePath.toString

private def normalizeSourcePath? (workspaceRoot sourcePath : System.FilePath) :
    IO (Option System.FilePath) := do
  let sourcePath := absoluteSourcePath workspaceRoot sourcePath
  try
    some <$> IO.FS.realPath sourcePath
  catch _ =>
    pure (some sourcePath)

private def gitRootForSource? (sourcePath : System.FilePath) : IO (Option System.FilePath) := do
  let sourceDir := sourcePath.parent.getD sourcePath
  RuntimeCache.cachedGitRoot? sourceDir (Git.toplevelAt? sourceDir)

private def gitHubSourceHref? (workspaceRoot sourcePath : System.FilePath)
    (range? : Option Lean.DeclarationRange) : IO (Option String) := do
  let sourcePath := absoluteSourcePath workspaceRoot sourcePath
  let some gitRoot ← gitRootForSource? sourcePath
    | return none
  let some repoInfo ← RuntimeCache.cachedGitRepoInfo? gitRoot (Git.repositoryInfoAtRoot? gitRoot)
    | return none
  let relPath := (workspaceRelativeSourcePath? repoInfo.root sourcePath).getD sourcePath.toString
  let fragment := sourceLineFragment? range? |>.getD ""
  pure <| some s!"{repoInfo.githubUrl}/blob/{repoInfo.commit}/{relPath}{fragment}"

private def sourceLinkHref? (opts : Lean.Options) (workspaceRoot : System.FilePath)
    (moduleName? : Option Lean.Name) (sourcePath? : Option System.FilePath)
    (range? : Option Lean.DeclarationRange) : IO (Option String) := do
  let template := (externalSourceLinkTemplate opts).trimAscii.toString
  if template.isEmpty then
    match sourcePath? with
    | some sourcePath => gitHubSourceHref? workspaceRoot sourcePath range?
    | none => pure none
  else
    match sourcePath? with
    | none => pure none
    | some sourcePath =>
      let relPath := (workspaceRelativeSourcePath? workspaceRoot sourcePath).getD sourcePath.toString
      let repoRelPath ← if template.contains "{repoRelpath}" then do
        let gitRoot? ← gitRootForSource? sourcePath
        pure <| (gitRoot?.bind (workspaceRelativeSourcePath? · sourcePath)).getD relPath
      else pure relPath
      let line := (range?.map (fun r => toString r.pos.line)).getD ""
      let column := (range?.map (fun r => toString r.pos.column)).getD ""
      let endLine := (range?.map (fun r => toString r.endPos.line)).getD ""
      let endColumn := (range?.map (fun r => toString r.endPos.column)).getD ""
      let href :=
        instantiateSourceLinkTemplate template #[
          ("path", sourcePath.toString),
          ("relpath", relPath),
          ("repoRelpath", repoRelPath),
          ("module", (moduleName?.map toString).getD ""),
          ("line", line),
          ("column", column),
          ("endLine", endLine),
          ("endColumn", endColumn)
        ]
      let href := href.trimAscii.toString
      if href.isEmpty then pure none else pure (some href)

private def moduleSourcePathText (moduleName : Lean.Name) : String :=
  (toString moduleName).replace "." "/" ++ ".lean"

private def dropFirstPathComponent? (pathText : String) : Option String :=
  match pathText.splitOn "/" with
  | _pkg :: next :: rest => some (String.intercalate "/" (next :: rest))
  | _ => none

private def dropLakePackagesPrefix? (pathText : String) : Option String :=
  match pathText.splitOn ".lake/packages/" with
  | _ :: rest :: _ => dropFirstPathComponent? rest
  | _ => none

private def elegantSourcePath (workspaceRoot : System.FilePath)
    (moduleName? : Option Lean.Name) (sourcePath : System.FilePath) : String :=
  let relPath := (workspaceRelativeSourcePath? workspaceRoot sourcePath).getD sourcePath.toString
  match dropLakePackagesPrefix? relPath with
  | some path => path
  | none =>
    match moduleName? with
    | some moduleName =>
      let modulePath := moduleSourcePathText moduleName
      if relPath.endsWith modulePath then
        modulePath
      else
        modulePath
    | none => relPath

private def externalDeclHeaderSource?
    (workspaceRoot : System.FilePath) (moduleName? : Option Lean.Name)
    (sourcePath? : Option System.FilePath) (sourceHref? : Option String) :
    Option ExternalDeclHeaderSource := do
  match sourcePath? with
  | some sourcePath =>
    some {
      text := elegantSourcePath workspaceRoot moduleName? sourcePath
      href? := sourceHref?
    }
  | none =>
    let moduleName ← moduleName?
    some {
      text := moduleSourcePathText moduleName
      href? := sourceHref?
    }

private def currentSourcePath? (workspaceRoot : System.FilePath) : Lean.CoreM (Option System.FilePath) := do
  let fileName ← Lean.getFileName
  if fileName.isEmpty || fileName.startsWith "<" then
    pure none
  else
    liftM <| normalizeSourcePath? workspaceRoot (System.FilePath.mk fileName)

private def existingSourcePath? (workspaceRoot path : System.FilePath) :
    IO (Option System.FilePath) := do
  let path := absoluteSourcePath workspaceRoot path
  if ← path.pathExists then
    normalizeSourcePath? workspaceRoot path
  else
    pure none

private def workspaceModuleSourcePath? (workspaceRoot : System.FilePath)
    (moduleName : Lean.Name) : IO (Option System.FilePath) := do
  let modulePath := moduleSourcePathText moduleName
  if let some path ← existingSourcePath? workspaceRoot (System.FilePath.mk modulePath) then
    return some path
  try
    for entry in ← workspaceRoot.readDir do
      if ← entry.path.isDir then
        if let some path ← existingSourcePath? workspaceRoot (entry.path / modulePath) then
          return some path
    pure none
  catch _ =>
    pure none

private def sourcePathForModule? (workspaceRoot : System.FilePath)
    (moduleName : Lean.Name) (moduleIdx? : Option Lean.ModuleIdx) : Lean.CoreM (Option System.FilePath) := do
  let env ← getEnv
  if moduleIdx?.isNone && moduleName == env.mainModule then
    return ← currentSourcePath? workspaceRoot
  if let some idx := moduleIdx? then
    if (env.getModulePackageByIdx? idx).isSome then
      let .ok (owner, _) ← liftM (ExternalModuleSource.verifiedSource env idx) | return none
      return ← liftM <| normalizeSourcePath? workspaceRoot owner.path
  RuntimeCache.cachedModuleSourcePath? workspaceRoot moduleName do
    let srcSearchPath ← Lean.getSrcSearchPath
    match ← srcSearchPath.findModuleWithExt "lean" moduleName with
    | some path =>
      liftM <| normalizeSourcePath? workspaceRoot path
    | none =>
      liftM <| workspaceModuleSourcePath? workspaceRoot moduleName

private def workspacePathPrefix (workspaceRoot : System.FilePath) : String :=
  let root := workspaceRoot.toString
  let sep := System.FilePath.pathSeparator.toString
  if root.endsWith sep then root else root ++ sep

private def isPathInWorkspace (workspaceRoot sourcePath : System.FilePath) : Bool :=
  let root := workspaceRoot.toString
  let rootPrefix := workspacePathPrefix workspaceRoot
  let src := sourcePath.toString
  src == root || src.startsWith rootPrefix

private def mkProvenance (workspaceRoot : System.FilePath)
    (moduleName? : Option Lean.Name) (sourcePath? : Option System.FilePath) : Data.ExternalDeclProvenance :=
  match moduleName? with
  | none => .unknown
  | some moduleName =>
    match sourcePath? with
    | some sourcePath =>
      if isPathInWorkspace workspaceRoot sourcePath then
        .inWorkspace moduleName sourcePath.toString
      else
        .outWorkspace moduleName (some sourcePath.toString)
    | none =>
      .outWorkspace moduleName none

/-- Register source and presentation information for a native attachment.
Current proof inspection belongs to capture. -/
def registerExternalRef (opts : Lean.Options) (workspaceRoot : System.FilePath)
    (ref : Data.ExternalRef) : Lean.CoreM Data.ExternalRef := do
  let env ← getEnv
  let canonical := ref.canonical.eraseMacroScopes
  match env.find? canonical with
  | none =>
    pure {
      ref with
      canonical
      present := false
      provedStatus := some .missing
      render := .error (.moduleUnavailable canonical)
    }
  | some cinfo =>
    let nodeKind ←
      match Informal.Data.ConstantInfo.blueprintNodeKind? cinfo with
      | some nodeKind => pure nodeKind
      | none =>
        match cinfo with
        | .axiomInfo _ =>
          -- Imported module-system theorems and definitions can appear as axioms
          -- in the exported environment; recover their original declaration kind.
          match Lean.getOriginalConstKind? env canonical with
          | some .thm => pure .theorem
          | some .defn => pure .definition
          | _ => pure ref.kind
        | .opaqueInfo _ =>
          pure ref.kind
        | _ =>
          throwError m!"Unsupported external Lean reference '{ref.written}' (canonical '{canonical}') with kind '{Informal.Data.ConstantInfo.blueprintKindText cinfo}'. Only definition-like declarations, theorems, and axiom-like placeholders are currently supported."
    let ref : Data.ExternalRef := {
      ref with
      canonical
      present := true
      provedStatus := none
      kind := nodeKind
    }
    let ranges? ← findDeclarationRanges? canonical
    let moduleName? := ExternalModuleSource.moduleNameForDecl? env canonical
    let sourcePath? ←
      match moduleName? with
      | some moduleName => sourcePathForModule? workspaceRoot moduleName (env.getModuleIdxFor? canonical)
      | none => pure none
    let provenance := mkProvenance workspaceRoot moduleName? sourcePath?
    let selectionRange? := ranges?.map (fun r => r.selectionRange)
    let sourceHref? ←
      liftM <| sourceLinkHref? opts workspaceRoot moduleName? sourcePath? (ranges?.map (fun r => r.range))
    let headerSource? := externalDeclHeaderSource? workspaceRoot moduleName? sourcePath? sourceHref?
    let renderResult ←
      (renderDeclHtmlDirectFromInfoE canonical cinfo
        (hasHeaderBadge := true)
        (headerSource? := headerSource?)).run'
    let render : Data.ExternalDeclRender :=
      match renderResult with
      | .ok html => .ok html
      | .error err => .error err
    pure {
      ref with
      provenance
      range? := ranges?.map (fun r => r.range)
      selectionRange?
      sourceHref?
      render
    }

def workspaceRoot : Lean.CoreM System.FilePath := do
  let cwd ← liftM <| IO.currentDir
  liftM <| IO.FS.realPath cwd

def registerExternalRefAtCurrentDir (opts : Lean.Options)
    (ref : Data.ExternalRef) : Lean.CoreM Data.ExternalRef := do
  registerExternalRef opts (← workspaceRoot) ref

/-- Record chapter references in their authoring environment, deferring proof
inspection to the project capture that can see the selected import view. -/
def registerExternalRefsAtCurrentDir (opts : Lean.Options)
    (refs : Array Data.ExternalRef) : Lean.CoreM (Array Data.ExternalRef) := do
  let root ← workspaceRoot
  refs.mapM fun ref => registerExternalRef opts root ref

end Informal
