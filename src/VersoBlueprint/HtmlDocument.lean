/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoManual
public import VersoBlueprint.RenderModel

public section

open Lean Verso Doc Genre Manual

namespace Informal

/-- A document and its captured traversal state, checked at a fixed point for one
HTML layout. Construction runs traversal; loading rechecks the saved pair. This
does not certify rendered resources or arbitrary extension implementations. -/
structure HtmlDocument where private mk ::
  text : Part Manual
  state : TraverseState
  config : RenderConfig
  mode : Mode

namespace HtmlDocument

private def effectiveConfig (mode : Mode) (config : RenderConfig) : Config :=
  match mode with
  | .single => { config.toConfig with htmlDepth := 0 }
  | .multi => config.toConfig

/-- Output location, scheduling and logging may change on resume. All other
serializable settings must match, including draft selection and HTML assets. -/
private def bindingConfig (config : Config) : Config :=
  { config with toOutputConfig := { draft := config.draft }, maxTraversals := 20 }

/-- Assets are sets: their JSON array order can change after decoding. Keep
ordered configuration fields (such as extraHead) order-sensitive, while using
Verso's set-aware equality for the asset bundle. -/
private def sameBindingConfig (saved requested : Config) : Bool :=
  saved.toHtmlAssets == requested.toHtmlAssets &&
    toJson { saved with toHtmlAssets := {} } ==
      toJson { requested with toHtmlAssets := {} }

private def withoutErrors (action : EmitM (Option α)) : EmitM (Option α) := do
  let logger ← readThe (Logger IO)
  let failed ← IO.mkRef false
  let logger := { logger with log := fun severity message location => do
    if severity == .error then failed.set true
    logger.log severity message location }
  let result ← action.run (← readThe ExtensionImpls) |>.run logger
  return if ← failed.get then none else result

private def check (mode : Mode) (config : RenderConfig)
    (text : Part Manual) (state : TraverseState) : EmitM (Option HtmlDocument) := do
  let captured : Except String Unit := do
    let _ ← TraversalIndex.RenderOverviews.required (α := Graph.GraphModel) state `graph
    let _ ← TraversalIndex.RenderOverviews.required (α := Commands.Summary) state `summary
  if let .error error := captured then
    reportError error
    return none
  let cfg := effectiveConfig mode config
  let (text', state') ← traverseMulti cfg.htmlDepth #[] text
    |>.run (← readThe ExtensionImpls) { draft := cfg.draft } state
  unless text' == text && state' == state do
    reportError "Blueprint HTML traversal has not converged; increase maxTraversals or fix an unstable traversal extension"
    return none
  return some (HtmlDocument.mk text state config mode)

/-- Run Manual traversal and verify convergence before making the result available
to emitters. Traversal diagnostics also prevent admission. -/
def traverse (mode : Mode) (config : RenderConfig) (text : Part Manual) :
    EmitM (Option HtmlDocument) := withoutErrors do
  let (text, state) ← Verso.Genre.Manual.traverse text (effectiveConfig mode config)
  check mode config text state

private structure Checkpoint where
  version : Nat
  singlePage : Bool
  config : Config
  saved : SavedState
deriving ToJson, FromJson

/-- Save the unpatched completed traversal with its layout. The saved document and
captured project model are authoritative on resume; current model initializers
are not run over them. -/
def save (document : HtmlDocument) (path : System.FilePath) : IO Unit := do
  let checkpoint : Checkpoint := {
    version := 1
    singlePage := match document.mode with | .single => true | .multi => false
    config := bindingConfig (effectiveConfig document.mode document.config)
    saved := { text := document.text, traverseState := document.state }
  }
  IO.FS.writeFile path (toJson checkpoint).compress

/-- Reject incompatible or incomplete checkpoints before HTML emission. Legacy
unbound Verso SavedState files must be regenerated. Function-valued render hooks
are supplied by the current generator and are not serialized. -/
def load (mode : Mode) (config : RenderConfig) (path : System.FilePath) :
    EmitM (Option HtmlDocument) := withoutErrors do
  let decoded := Json.parse (← IO.FS.readFile path) >>= fromJson? (α := Checkpoint)
  let checkpoint ← match decoded with
    | .ok checkpoint => pure checkpoint
    | .error error =>
      reportError s!"Invalid Blueprint HTML checkpoint {path}: {error}; regenerate the saved traversal"
      return none
  unless checkpoint.version == 1 do
    reportError s!"Unsupported Blueprint HTML checkpoint version {checkpoint.version}; regenerate the saved traversal"
    return none
  let singlePage := match mode with | .single => true | .multi => false
  unless checkpoint.singlePage == singlePage &&
      sameBindingConfig checkpoint.config (bindingConfig (effectiveConfig mode config)) do
    reportError "Blueprint HTML checkpoint layout/configuration does not match this output; regenerate the saved traversal"
    return none
  check mode config checkpoint.saved.text checkpoint.saved.traverseState

end HtmlDocument
end Informal
