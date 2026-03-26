/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import VersoBlueprint.Data
import VersoBlueprint.ProvedStatus
import VersoBlueprint.DocGenNameRender

namespace Informal

open Lean

/--
Template used to build source links for external declarations.
Supported placeholders are: path, relpath, module, line, column.

Empty template disables source link generation.
-/
register_option verso.blueprint.externalCode.sourceLinkTemplate : String := {
  defValue := ""
  descr := "Template for external declaration source links ({path},{relpath},{module},{line},{column})"
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

private def sourceLinkHref? (opts : Lean.Options) (workspaceRoot : System.FilePath)
    (moduleName? : Option Lean.Name) (sourcePath? : Option System.FilePath)
    (range? : Option Lean.DeclarationRange) : Option String := do
  let template := (externalSourceLinkTemplate opts).trimAscii.toString
  if template.isEmpty then
    none
  else
    let sourcePath ← sourcePath?
    let relPath := (workspaceRelativeSourcePath? workspaceRoot sourcePath).getD sourcePath.toString
    let line := (range?.map (fun r => toString r.pos.line)).getD ""
    let column := (range?.map (fun r => toString r.pos.column)).getD ""
    let href :=
      instantiateSourceLinkTemplate template #[
        ("path", sourcePath.toString),
        ("relpath", relPath),
        ("module", (moduleName?.map toString).getD ""),
        ("line", line),
        ("column", column)
      ]
    let href := href.trimAscii.toString
    if href.isEmpty then none else some href

private def moduleNameForDecl? (env : Lean.Environment) (decl : Lean.Name) : Option Lean.Name := do
  let moduleIdx ← env.getModuleIdxFor? decl
  env.header.moduleNames[moduleIdx.toNat]?

private def sourcePathForModule? (moduleName : Lean.Name) : IO (Option System.FilePath) := do
  let srcSearchPath ← Lean.getSrcSearchPath
  srcSearchPath.findModuleWithExt "lean" moduleName

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
      | some moduleName => liftM <| sourcePathForModule? moduleName
      | none => pure none
    let provenance := mkProvenance workspaceRoot moduleName? sourcePath?
    let selectionRange? := ranges?.map (·.selectionRange)
    let sourceHref? := sourceLinkHref? opts workspaceRoot moduleName? sourcePath? selectionRange?
    let render : Data.ExternalDeclRender ←
      (renderDeclHtmlDirectFromInfoE canonical cinfo).run'
    pure {
      ref with
      provenance
      range? := ranges?.map (·.range)
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
