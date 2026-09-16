/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoBlueprintVir.Preview.Component.Session
public import VersoBlueprintVir.Preview.Component.Shell
public import VersoBlueprintVir.Preview.Renderer

public section

namespace VersoBlueprint.Experimental.VirPreview

open Lean.Vir
open Lean.Vir.React
open scoped Lean.Vir.Js Lean.Vir.ProofWidgets.Jsx

private def instrumentationCss (document : Document) : String :=
  let animationName := s!"virVersoChanged{document.version}"
  "@keyframes " ++ animationName ++ "{" ++
  "0%{background:var(--vscode-editor-findMatchHighlightBackground,rgba(255,196,0,.30));box-shadow:0 0 0 3px var(--vscode-editor-findMatchBorder,rgba(154,103,0,.45));}" ++
  "100%{background:transparent;box-shadow:none;}}" ++
  "#vir-verso-preview .vir-verso-block-changed{animation:" ++ animationName ++
  " 1100ms ease-out;}" ++
  "#vir-verso-preview .vir-verso-block-focused{outline:1px solid var(--vscode-focusBorder,#0969da);outline-offset:3px;border-radius:3px;}" ++
  "@media (prefers-reduced-motion:reduce){#vir-verso-preview .vir-verso-block-changed{animation:none;background:var(--vscode-editor-findMatchHighlightBackground,rgba(255,196,0,.20));}}"

private def instrumentationStyleNode (document : Document) : ReactM (Js Node) := do
  let text ← Node.text (← JsValue.ofString (instrumentationCss document))
  return ← <style>{pure text}</style>

namespace Session

structure ContentProps where
  preview : Preview
  dependency : String
  changedIds : Array String
  identities : VersoReact.Fingerprint.State
  blockCount : Nat
  followCursor : Bool
  highlightChanges : Bool
  diagnostics : Bool
  inputChanged : Bool
  timing? : Option ResponseTiming := none
  preparationMs : Float := 0
  onCommit : DebugSample → Browser.DomM Unit

private structure RenderOutcome where
  node : Js Node
  status : String
  version : Nat := 0
  correlationId : String := ""
  serverTiming? : Option ServerTiming := none
  blockCount : Nat := 0

private def renderContent (mathComponent? : Option (FunctionComponent Props))
    (props : ContentProps) : ReactM RenderOutcome := do
  match props.preview with
  | .loading message =>
      let node ← renderStatus "loading" message
      pure { node, status := "loading" }
  | .unavailable message =>
      let node ← renderStatus "unavailable" message
      pure { node, status := "unavailable" }
  | .error message =>
      let node ← renderStatus "error" message
      pure { node, status := "error" }
  | .ready document =>
      let highlightedIds := if props.highlightChanges then props.changedIds else #[]
      let focus := if props.followCursor then document.focus else none
      let instrumentation ← instrumentationStyleNode document
      let rendered ← Renderer.render document {
        identities? := some props.identities
        changedIds := highlightedIds
        focus
      } mathComponent?
      let node ← Node.fragment (← Js.Object.empty) (← Js.Array.ofArray #[instrumentation, rendered])
      pure {
        node
        status := "ready"
        version := document.version
        correlationId := document.correlationId
        serverTiming? := document.serverTiming?
        blockCount := props.blockCount
      }

def createContentComponent (clock : RuntimeM Float := pure 0)
    (mathComponent? : Option (FunctionComponent Props) := none) : RuntimeM (FunctionComponent (Props.WithData ContentProps)) :=
  FunctionComponent.ofLean fun props => do
    let props ← LeanRef.fromJSL (← Props.WithData.data props)
    let started ← if props.diagnostics then clock else pure 0
    let outcome ← renderContent mathComponent? props
    let rendered ← if props.diagnostics then clock else pure 0
    -- Keep hook order stable when diagnostics are toggled. The normal path
    -- does not construct a sample or update state. This observes a committed
    -- preview, not paint. The optional demo clock brackets element construction
    -- and observes this passive effect; without a clock no duration is published.
    let effect ← EffectCallback.ofLean {
      setup := do
        if props.diagnostics then
          let observed ← clock
          props.onCommit {
            status := outcome.status
            version := outcome.version
            correlationId := outcome.correlationId
            serverTiming? := outcome.serverTiming?
            blockCount := outcome.blockCount
            changedCount := props.changedIds.size
            highlightChanges := props.highlightChanges
            inputChanged := props.inputChanged
            browserTiming? := props.timing?.map fun response => {
              response, preparationMs := props.preparationMs,
              renderMs := rendered - started, observedMs := observed
            }
          }
        JsValue.ofBool false
      cleanup := fun _ => pure ()
    }
    let deps ← Hooks.DependencyList.ofArray #[
      Js.erase (← JsValue.ofString props.dependency), Js.erase (← JsValue.ofBool props.diagnostics)]
    Hooks.useEffect effect (Js.UndefinedOr.ofJs deps)
    pure outcome.node

end Session
end VersoBlueprint.Experimental.VirPreview
