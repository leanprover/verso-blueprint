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
    (logError : String → IO Unit := fun message => throw <| IO.userError message)
    (model : Informal.RenderModel := by exact blueprint_render_model%) :
    IO (Array (Doc.Block Genre.Manual) × TraverseState) :=
  Informal.traverseManualBlocks (collectBlocks doc.toPart) (model.withExtensions impls) logError

private def testLogger : Logger IO where
  log severity text _loc :=
    if severity == .error then throw <| IO.userError text else pure ()
  errors := pure #[]
  warnings := pure #[]

def renderManualBlocksTeXWithState (impls : ExtensionImpls)
    (blocks : Array (Doc.Block Genre.Manual)) (state : TraverseState) : IO String := do
  let (tex, _) ← ((Doc.Block.concat blocks).toTeX
    (m := ReaderT ExtensionImpls (BuildLogT IO))
      ({ headerLevel := none }, {}, state, {}) {}).run impls |>.run testLogger
  pure tex.asString

/-- Keep extension impls explicit so each test renders with its own imported extension set. -/
def renderManualDocHtmlAndState
    (impls : ExtensionImpls)
    (doc : Doc.VersoDoc Genre.Manual)
    (model : Informal.RenderModel := by exact blueprint_render_model%) : IO (Output.Html × TraverseState) := do
  let opts : Doc.Html.Options := {
    headerLevel := 1
  }
  let (blocks, st) ← traverseManualDocBlocksAndState impls doc (model := model)
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
      |>.run testLogger
  pure (html, st)

def renderManualDocHtml (impls : ExtensionImpls) (doc : Doc.VersoDoc Genre.Manual)
    (model : Informal.RenderModel := by exact blueprint_render_model%) : IO Output.Html := do
  let (html, _st) ← renderManualDocHtmlAndState impls doc (model := model)
  pure html

def renderManualDocHtmlStringAndState
    (impls : ExtensionImpls)
    (doc : Doc.VersoDoc Genre.Manual)
    (model : Informal.RenderModel := by exact blueprint_render_model%) : IO (String × TraverseState) := do
  let (html, st) ← renderManualDocHtmlAndState impls doc (model := model)
  pure (html.asString, st)

def renderManualDocHtmlString (impls : ExtensionImpls) (doc : Doc.VersoDoc Genre.Manual)
    (model : Informal.RenderModel := by exact blueprint_render_model%) : IO String := do
  let html ← renderManualDocHtml impls doc (model := model)
  pure html.asString

def buildManualPreviewDataFiles
    (impls : ExtensionImpls)
    (doc : Doc.VersoDoc Genre.Manual)
    (logError : String → IO Unit := fun _ => pure ())
    (model : Informal.RenderModel := by exact blueprint_render_model%) :
    IO Informal.PreviewManifest.Files := do
  let (_html, st) ← renderManualDocHtmlStringAndState impls doc (model := model)
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
