/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public meta import Lean
public meta import VersoBlueprint.Data
public meta import VersoBlueprint.ProvedStatus
public meta import VersoBlueprint.ExternalDeclRender
public meta import VersoBlueprint.Git
public meta import VersoBlueprint.RuntimeCache

public meta section

namespace Informal

open Lean

/--
Template used to build source links for external declarations.
Supported placeholders are: path, relpath, module, line, column, endLine, endColumn.

Empty template uses automatic GitHub source link generation when the source file
belongs to a Git checkout with a GitHub `origin` remote.
-/
register_option verso.blueprint.externalCode.sourceLinkTemplate : String := {
  defValue := ""
  descr := "Template for external declaration source links ({path},{relpath},{module},{line},{column},{endLine},{endColumn}); empty uses automatic GitHub links when available"
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

private def gitHubSourceHref? (workspaceRoot sourcePath : System.FilePath)
    (range? : Option Lean.DeclarationRange) : IO (Option String) := do
  let sourcePath := absoluteSourcePath workspaceRoot sourcePath
  let sourceDir := sourcePath.parent.getD sourcePath
  let some gitRoot ← RuntimeCache.cachedGitRoot? sourceDir (Git.toplevelAt? sourceDir)
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
      let line := (range?.map (fun r => toString r.pos.line)).getD ""
      let column := (range?.map (fun r => toString r.pos.column)).getD ""
      let endLine := (range?.map (fun r => toString r.endPos.line)).getD ""
      let endColumn := (range?.map (fun r => toString r.endPos.column)).getD ""
      let href :=
        instantiateSourceLinkTemplate template #[
          ("path", sourcePath.toString),
          ("relpath", relPath),
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

private def moduleNameForDecl? (env : Lean.Environment) (decl : Lean.Name) : Option Lean.Name := do
  match env.getModuleIdxFor? decl with
  | some moduleIdx => env.header.moduleNames[moduleIdx.toNat]?
  | none =>
    if env.mainModule.isAnonymous then
      none
    else
      some env.mainModule

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
    (moduleName : Lean.Name) : Lean.CoreM (Option System.FilePath) := do
  RuntimeCache.cachedModuleSourcePath? workspaceRoot moduleName do
    let srcSearchPath ← Lean.getSrcSearchPath
    match ← srcSearchPath.findModuleWithExt "lean" moduleName with
    | some path =>
      liftM <| normalizeSourcePath? workspaceRoot path
    | none =>
      if moduleName == (← getEnv).mainModule then
        currentSourcePath? workspaceRoot
      else
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

private def externalDeclStatusBadge (status : Data.ProvedStatus) : ExternalDeclHeaderBadge :=
  let view := status.presentation
  { className := view.externalDeclClass, text := view.externalHeaderText }

/--
Build a full snapshot for one external declaration reference using the environment
available at elaboration/registration time.
-/
def externalRefSnapshot (opts : Lean.Options) (workspaceRoot : System.FilePath)
    (ref : Data.ExternalRef) : Lean.CoreM Data.ExternalRef := do
  let env ← getEnv
  let canonical := ref.canonical.eraseMacroScopes
  match env.find? canonical with
  | none =>
    pure {
      ref with
      canonical
      present := false
      provedStatus := .missing
      render := .error (.moduleUnavailable canonical)
    }
  | some cinfo =>
    let nodeKind ←
      match Informal.Data.ConstantInfo.blueprintNodeKind? cinfo with
      | some nodeKind => pure nodeKind
      | none =>
        match cinfo with
        | .axiomInfo _ | .opaqueInfo _ =>
          pure ref.kind
        | _ =>
          throwError m!"Unsupported external Lean reference '{ref.written}' (canonical '{canonical}') with kind '{Informal.Data.ConstantInfo.blueprintKindText cinfo}'. Only definition-like declarations, theorems, and axiom-like placeholders are currently supported."
    let ref : Data.ExternalRef := {
      ref with
      canonical
      present := true
      provedStatus := Informal.Data.ConstantInfo.blueprintProvedStatus cinfo (allowOpaque := true)
      kind := nodeKind
    }
    let ranges? ← findDeclarationRanges? canonical
    let moduleName? := moduleNameForDecl? env canonical
    let sourcePath? ←
      match moduleName? with
      | some moduleName => sourcePathForModule? workspaceRoot moduleName
      | none => pure none
    let provenance := mkProvenance workspaceRoot moduleName? sourcePath?
    let selectionRange? := ranges?.map (fun r => r.selectionRange)
    let sourceHref? ←
      liftM <| sourceLinkHref? opts workspaceRoot moduleName? sourcePath? (ranges?.map (fun r => r.range))
    let headerSource? := externalDeclHeaderSource? workspaceRoot moduleName? sourcePath? sourceHref?
    let renderResult ←
      (renderDeclHtmlDirectFromInfoE canonical cinfo
        (headerBadge? := some (externalDeclStatusBadge ref.provedStatus))
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

def externalRefSnapshotAtCurrentDir (opts : Lean.Options)
    (ref : Data.ExternalRef) : Lean.CoreM Data.ExternalRef := do
  externalRefSnapshot opts (← workspaceRoot) ref

end Informal
