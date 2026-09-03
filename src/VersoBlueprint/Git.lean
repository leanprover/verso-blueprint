/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Init.System.IO
import VersoBlueprint.Process

public section

namespace Informal.Git

/-- GitHub-backed repository metadata used for generated source links. -/
structure RepositoryInfo where
  root : System.FilePath
  githubUrl : String
  commit : String
deriving Inhabited, Repr

private def stripGitSuffix (url : String) : String :=
  if url.endsWith ".git" then
    match url.splitOn ".git" with
    | stem :: _ => stem
    | [] => url
  else
    url

/--
Normalize common GitHub remote URL spellings to browser URLs.

Non-GitHub remotes return `none`; current Blueprint source-link and build
metadata UI only know how to construct GitHub links.
-/
def githubRepositoryUrl? (url : String) : Option String :=
  let url := stripGitSuffix url.trimAscii.toString
  if url.startsWith "https://github.com/" then
    some url
  else if url.startsWith "http://github.com/" then
    some <| "https://github.com/" ++ (url.drop "http://github.com/".length).toString
  else if url.startsWith "git@github.com:" then
    some <| "https://github.com/" ++ (url.drop "git@github.com:".length).toString
  else if url.startsWith "ssh://git@github.com/" then
    some <| "https://github.com/" ++ (url.drop "ssh://git@github.com/".length).toString
  else
    none

def shortCommitAt? (dir : System.FilePath) : IO (Option String) :=
  Process.runTrimmedCommand? "git" #["-C", dir.toString, "rev-parse", "--short", "HEAD"]

def fullCommitAt? (dir : System.FilePath) : IO (Option String) :=
  Process.runTrimmedCommand? "git" #["-C", dir.toString, "rev-parse", "HEAD"]

def subjectAt? (dir : System.FilePath) : IO (Option String) :=
  Process.runTrimmedCommand? "git" #["-C", dir.toString, "log", "-1", "--pretty=%s"]

def toplevelAt? (dir : System.FilePath) : IO (Option System.FilePath) := do
  let some root ← Process.runTrimmedCommand? "git" #["-C", dir.toString, "rev-parse", "--show-toplevel"]
    | return none
  pure <| some (System.FilePath.mk root)

def repositoryUrlAt? (dir : System.FilePath) : IO (Option String) := do
  match ← Process.runTrimmedCommand? "git" #["-C", dir.toString, "remote", "get-url", "origin"] with
  | some url => pure <| githubRepositoryUrl? url
  | none => pure none

def commitUrl? (repositoryUrl? commit? : Option String) : Option String :=
  match repositoryUrl?, commit? with
  | some repositoryUrl, some commit => some s!"{repositoryUrl}/commit/{commit}"
  | _, _ => none

def repositoryInfoAtRoot? (gitRoot : System.FilePath) : IO (Option RepositoryInfo) := do
  let some repositoryUrl ← repositoryUrlAt? gitRoot
    | return none
  let some commit ← fullCommitAt? gitRoot
    | return none
  pure <| some {
    root := gitRoot
    githubUrl := repositoryUrl
    commit
  }

end Informal.Git
