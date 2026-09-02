/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Lean
public import VersoManual
public import VersoBlueprint.Lib.HoverRender

public section

namespace Informal

private def callbackLogger (logMessage : String → IO Unit) : Verso.Logger IO where
  log _severity text _loc := logMessage text
  errors := pure #[]
  warnings := pure #[]

structure RenderedManualHtml where
  html : Verso.Output.Html
  hoverState : Verso.Code.Hover.State Verso.Output.Html

private def initTraverseState (impls : Verso.Genre.Manual.ExtensionImpls) : Verso.Genre.Manual.TraverseState :=
  Id.run do
    let mut st : Verso.Genre.Manual.TraverseState := Verso.Genre.Manual.TraverseState.initialize {}
    for ⟨_, b⟩ in impls.blockDescrs do
      if let some descr := b.get? Verso.Genre.Manual.BlockDescr then
        st := descr.init st
    for ⟨_, i⟩ in impls.inlineDescrs do
      if let some descr := i.get? Verso.Genre.Manual.InlineDescr then
        st := descr.init st
    return st

def traverseManualBlocks
    (blocks : Array (Verso.Doc.Block Verso.Genre.Manual))
    (impls : Verso.Genre.Manual.ExtensionImpls)
    (logError : String → IO Unit := fun _ => pure ()) :
    IO (Array (Verso.Doc.Block Verso.Genre.Manual) × Verso.Genre.Manual.TraverseState) := do
  let ctxt : Verso.Genre.Manual.TraverseContext := {}
  let mut st := initTraverseState impls
  let mut cur := blocks
  for _ in [0:4] do
    let (next, st') ←
      (Verso.Genre.Manual.TraverseM.run impls ctxt st <| cur.mapM Verso.Genre.Manual.traverseBlock)
        |>.run (callbackLogger logError)
    if next == cur && st' == st then
      return (next, st')
    cur := next
    st := st'
  return (cur, st)

def renderManualHtmlWithStateAndHovers
    (htmlState : Verso.Doc.Html.HtmlT Verso.Genre.Manual
      (ReaderT Verso.Multi.AllRemotes (ReaderT Verso.Genre.Manual.ExtensionImpls (Verso.BuildLogT IO)))
      Verso.Output.Html)
    (impls : Verso.Genre.Manual.ExtensionImpls)
    (st : Verso.Genre.Manual.TraverseState)
    (linkTargets : Verso.Code.LinkTargets Verso.Genre.Manual.TraverseContext := st.localTargets)
    (logError : String → IO Unit := fun _ => pure ())
    (hoverState : Verso.Code.Hover.State Verso.Output.Html := {}) :
    IO RenderedManualHtml := do
  let opts : Verso.Doc.Html.Options := {
    headerLevel := 1
  }
  let ctxt : Verso.Genre.Manual.TraverseContext := {}
  let definitionIds : Lean.NameMap String := {}
  let codeOptions : Verso.Code.HighlightHtmlM.Options := {}
  let remotes : Verso.Multi.AllRemotes := {}
  let htmlContext : Verso.Doc.Html.HtmlT.Context Verso.Genre.Manual := {
    options := opts
    traverseContext := ctxt
    traverseState := st
    definitionIds := definitionIds
    linkTargets := linkTargets
    codeOptions := codeOptions
  }
  let htmlState := Informal.HoverRender.withInlinePreviewRenderContext htmlState
  let (html, hoverState) ←
    ((htmlState htmlContext).run hoverState)
      |>.run remotes
      |>.run impls
      |>.run (callbackLogger logError)
  pure { html, hoverState }

def renderManualHtmlWithState
    (htmlState : Verso.Doc.Html.HtmlT Verso.Genre.Manual
      (ReaderT Verso.Multi.AllRemotes (ReaderT Verso.Genre.Manual.ExtensionImpls (Verso.BuildLogT IO)))
      Verso.Output.Html)
    (impls : Verso.Genre.Manual.ExtensionImpls)
    (st : Verso.Genre.Manual.TraverseState)
    (linkTargets : Verso.Code.LinkTargets Verso.Genre.Manual.TraverseContext := st.localTargets)
    (logError : String → IO Unit := fun _ => pure ()) :
    IO Verso.Output.Html := do
  return (← renderManualHtmlWithStateAndHovers htmlState impls st linkTargets (logError := logError)).html

def renderManualBlocksHtmlWithStateAndHovers
    (blocks : Array (Verso.Doc.Block Verso.Genre.Manual))
    (impls : Verso.Genre.Manual.ExtensionImpls)
    (st : Verso.Genre.Manual.TraverseState)
    (linkTargets : Verso.Code.LinkTargets Verso.Genre.Manual.TraverseContext := st.localTargets)
    (logError : String → IO Unit := fun _ => pure ())
    (hoverState : Verso.Code.Hover.State Verso.Output.Html := {}) :
    IO RenderedManualHtml := do
  let block := Verso.Doc.Block.concat blocks
  renderManualHtmlWithStateAndHovers
    (Verso.Doc.Html.ToHtml.toHtml (genre := Verso.Genre.Manual) block)
    impls st linkTargets (logError := logError) (hoverState := hoverState)

def renderManualBlocksHtmlWithState
    (blocks : Array (Verso.Doc.Block Verso.Genre.Manual))
    (impls : Verso.Genre.Manual.ExtensionImpls)
    (st : Verso.Genre.Manual.TraverseState)
    (linkTargets : Verso.Code.LinkTargets Verso.Genre.Manual.TraverseContext := st.localTargets)
    (logError : String → IO Unit := fun _ => pure ()) :
    IO Verso.Output.Html := do
  return (← renderManualBlocksHtmlWithStateAndHovers blocks impls st linkTargets
    (logError := logError)).html

private def renderManualBlocksHtml
    (blocks : Array (Verso.Doc.Block Verso.Genre.Manual))
    (impls : Verso.Genre.Manual.ExtensionImpls)
    (logError : String → IO Unit := fun _ => pure ()) : IO Verso.Output.Html := do
  let (blocks, st) ← traverseManualBlocks blocks impls logError
  renderManualBlocksHtmlWithState blocks impls st (logError := logError)

private unsafe def evalElaboratedBlocksUnsafe (stxs : Array Lean.Syntax) :
    Lean.Elab.Term.TermElabM (Array (Verso.Doc.Block Verso.Genre.Manual)) := do
  if stxs.isEmpty then
    pure #[]
  else
    let tyExpr ← Lean.Elab.Term.elabType (← `(Verso.Doc.Block Verso.Genre.Manual))
    stxs.mapM fun stx => do
      let expr ← Lean.Elab.Term.elabTermAndSynthesize stx (some tyExpr)
      Lean.Meta.evalExpr (Verso.Doc.Block Verso.Genre.Manual) tyExpr expr

/-- Evaluate elaborated Manual block terms back into Manual blocks. -/
@[implemented_by evalElaboratedBlocksUnsafe]
opaque evalElaboratedBlocks
    (stxs : Array Lean.Syntax) :
    Lean.Elab.Term.TermElabM (Array (Verso.Doc.Block Verso.Genre.Manual))

private unsafe def getExtensionImpls : Lean.Elab.Term.TermElabM Verso.Genre.Manual.ExtensionImpls := do
  let tyExpr ← Lean.Elab.Term.elabType (← `(Verso.Genre.Manual.ExtensionImpls))
  let implExpr ← Lean.Elab.Term.elabTermAndSynthesize (← `(extension_impls%)) (some tyExpr)
  Lean.Meta.evalExpr Verso.Genre.Manual.ExtensionImpls tyExpr implExpr

private unsafe def renderPreviewBlocksHtmlUnsafe
    (blocks : Array (Verso.Doc.Block Verso.Genre.Manual)) : Lean.Elab.Term.TermElabM Verso.Output.Html := do
  let impls ← getExtensionImpls
  monadLift <| renderManualBlocksHtml blocks impls

/-- Render manual preview blocks to HTML using the manual renderer. -/
@[implemented_by renderPreviewBlocksHtmlUnsafe]
opaque renderPreviewBlocksHtml
    (blocks : Array (Verso.Doc.Block Verso.Genre.Manual)) : Lean.Elab.Term.TermElabM Verso.Output.Html

/-- Render cached elaborated statement blocks to HTML using the manual renderer. -/
private unsafe def renderStatementElabHtmlUnsafe (stxs : Array Lean.Syntax) : Lean.Elab.Term.TermElabM Verso.Output.Html := do
  let blocks ← evalElaboratedBlocks stxs
  renderPreviewBlocksHtml blocks

/-- Render cached elaborated statement blocks to HTML using the manual renderer. -/
@[implemented_by renderStatementElabHtmlUnsafe]
opaque renderStatementElabHtml (stxs : Array Lean.Syntax) : Lean.Elab.Term.TermElabM Verso.Output.Html

end Informal
