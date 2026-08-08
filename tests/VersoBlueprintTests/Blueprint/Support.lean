/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint
import VersoManual

namespace Verso.VersoBlueprintTests.Blueprint.Support

open Verso
open Verso.Genre.Manual

def hasSubstr (s needle : String) : Bool :=
  (s.splitOn needle).length > 1

def countSubstr (s needle : String) : Nat :=
  (s.splitOn needle).length.pred

def appearsBefore (s lhs rhs : String) : Bool :=
  match s.splitOn lhs with
  | _ :: tail => hasSubstr (String.intercalate lhs tail) rhs
  | [] => false

def hasSummaryCardValue (s label value : String) : Bool :=
  hasSubstr s s!"{label}</span><span class=\"bp_summary_value\">{value}</span>"

def hasSummaryMetricBadge (s label value : String) : Bool :=
  hasSubstr s s!"{label}: {value}"

private partial def collectBlocks (part : Doc.Part Genre.Manual) : Array (Doc.Block Genre.Manual) :=
  let childBlocks := part.subParts.foldl (init := #[]) fun acc child =>
    acc ++ collectBlocks child
  part.content ++ childBlocks

def traverseManualDocBlocksAndState
    (impls : ExtensionImpls)
    (doc : Doc.VersoDoc Genre.Manual)
    (logError : String → IO Unit := fun _ => pure ()) :
    IO (Array (Doc.Block Genre.Manual) × TraverseState) :=
  Informal.traverseManualBlocks (collectBlocks doc.toPart) impls logError

private def discardLogger : Logger IO where
  log _severity _text _loc := pure ()
  errors := pure #[]
  warnings := pure #[]

/-- Keep extension impls explicit so each test renders with its own imported extension set. -/
def renderManualDocHtmlAndState
    (impls : ExtensionImpls)
    (doc : Doc.VersoDoc Genre.Manual) : IO (Output.Html × TraverseState) := do
  let opts : Doc.Html.Options := {
    headerLevel := 1
  }
  let (blocks, st) ← traverseManualDocBlocksAndState impls doc
  let ctxt : TraverseContext := {}
  let definitionIds : Lean.NameMap String := {}
  let linkTargets : Code.LinkTargets TraverseContext := {}
  let codeOptions : Code.HighlightHtmlM.Options := {}
  let remotes : Multi.AllRemotes := {}
  let block := Doc.Block.concat blocks
  let htmlState :
      StateT (Code.Hover.State Output.Html)
        (ReaderT Multi.AllRemotes (ReaderT ExtensionImpls (BuildLogT IO)))
        Output.Html :=
    Verso.Genre.Manual.toHtml opts ctxt st definitionIds linkTargets codeOptions block
  let (html, _hover) ←
    ((htmlState.run {}).run remotes)
      |>.run impls
      |>.run discardLogger
  pure (html, st)

def renderManualDocHtml (impls : ExtensionImpls) (doc : Doc.VersoDoc Genre.Manual) : IO Output.Html := do
  let (html, _st) ← renderManualDocHtmlAndState impls doc
  pure html

def renderManualDocHtmlStringAndState
    (impls : ExtensionImpls)
    (doc : Doc.VersoDoc Genre.Manual) : IO (String × TraverseState) := do
  let (html, st) ← renderManualDocHtmlAndState impls doc
  pure (html.asString, st)

def renderManualDocHtmlString (impls : ExtensionImpls) (doc : Doc.VersoDoc Genre.Manual) : IO String := do
  let html ← renderManualDocHtml impls doc
  pure html.asString

def buildManualPreviewDataFiles
    (impls : ExtensionImpls)
    (doc : Doc.VersoDoc Genre.Manual)
    (logError : String → IO Unit := fun _ => pure ()) :
    IO Informal.PreviewManifest.Files := do
  let (_html, st) ← renderManualDocHtmlStringAndState impls doc
  Informal.PreviewManifest.buildPreviewDataFiles impls logError
    (Informal.PreviewManifest.PreparedPreviewState.prepare st)

def findExtraJsContaining? (st : TraverseState) (needle : String) : Option String :=
  st.toHtmlAssets.extraJs.toArray.findSome? fun js =>
    if hasSubstr js.js needle then some js.js else none

def hasExtraJs (st : TraverseState) (needle : String) : Bool :=
  st.toHtmlAssets.extraJs.toArray.any fun js => hasSubstr js.js needle

def hasExtraCss (st : TraverseState) (needle : String) : Bool :=
  st.toHtmlAssets.extraCss.toArray.any fun css => hasSubstr css.css needle

end Verso.VersoBlueprintTests.Blueprint.Support
