/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso
import VersoManual
import VersoBlueprint.Data
import VersoBlueprint.Informal.LeanDeclPreviewKey
import VersoBlueprint.Informal.ExternalCode
import VersoBlueprint.PreviewRender
import VersoBlueprint.TraversalIndex

namespace Informal.LeanCodePreview

open Lean

abbrev ManualBlock := Verso.Doc.Block Verso.Genre.Manual

/--
Dedicated traversal domain for Lean declaration previews emitted as preview data.

Unlike `PreviewCache`, this domain is only for previews attached to links that
target Lean declarations/definitions.
-/
def domainName : Name := Informal.LeanDeclPreviewKey.domainName
/--
Canonical internal preview target for one Lean declaration.

The preview namespace mirrors regular Lean names so the preview-data keys stay
declaration-centric rather than blueprint-label-centric.
-/
def targetName (decl : Name) : Name :=
  Informal.LeanDeclPreviewKey.targetName decl

def lookupKey (decl : Name) : String :=
  Informal.LeanDeclPreviewKey.lookupKey decl

inductive Source where
  | inlineBlocks (blocks : Array ManualBlock) (sourceLocation : Informal.Data.SourceLocationResult)
  | externalDecl (decl : Informal.Data.ExternalRef)
deriving Inhabited, Repr, ToJson, FromJson

/--
Canonical declaration-preview payload.

Multiple Lean declaration names may legitimately point to the same inline code
block preview body, but each declaration keeps its own manifest key.
-/
structure Entry where
  target : Name
  source : Source
deriving Inhabited, Repr, ToJson, FromJson

def Entry.ofInlineBlocks
    (target : Name)
    (blocks : Array ManualBlock)
    (sourceLocation : Informal.Data.SourceLocationResult) : Entry :=
  { target := target.eraseMacroScopes, source := .inlineBlocks blocks sourceLocation }

def Entry.ofExternalDecl (target : Name) (decl : Informal.Data.ExternalRef) : Entry :=
  { target := target.eraseMacroScopes, source := .externalDecl decl }

def title (decl : Name) : String :=
  s!"Lean declaration {decl}"

def renderWithState
    (entry : Entry)
    (impls : Verso.Genre.Manual.ExtensionImpls)
    (state : Verso.Genre.Manual.TraverseState)
    (logError : String → IO Unit := fun _ => pure ())
    (hoverState : Verso.Code.Hover.State Verso.Output.Html := {}) :
    IO Informal.RenderedManualHtml := do
  match entry.source with
  | .inlineBlocks blocks _sourceLocation =>
    Informal.renderManualBlocksHtmlWithStateAndHovers blocks impls state
      (logError := logError) (hoverState := hoverState)
  | .externalDecl decl =>
    pure { html := Informal.ExternalCode.renderPreviewHtml #[decl], hoverState }

def renderHtmlWithState
    (entry : Entry)
    (impls : Verso.Genre.Manual.ExtensionImpls)
    (state : Verso.Genre.Manual.TraverseState)
    (logError : String → IO Unit := fun _ => pure ()) : IO Verso.Output.Html := do
  return (← renderWithState entry impls state (logError := logError)).html

end Informal.LeanCodePreview

namespace Informal.TraversalIndex.LeanCodePreviews

/-- Decode one Lean-code preview entry while retaining malformed-entry diagnostics. -/
def decodedEntry? (state : Verso.Genre.Manual.TraverseState) (previewKey : String) :
    Option (Except Informal.TraversalIndex.DecodeError
      (Informal.TraversalIndex.StoredEntry Informal.LeanCodePreview.Entry)) := do
  let obj ← object? state previewKey
  pure <| Informal.TraversalIndex.decodeObjectData obj

/-- Decode one Lean-code preview entry, returning `none` when the entry is missing or malformed. -/
def entry? (state : Verso.Genre.Manual.TraverseState) (previewKey : String) :
    Option Informal.LeanCodePreview.Entry := do
  let decoded ← decodedEntry? state previewKey
  match decoded with
  | .error _ => none
  | .ok stored => some stored.data

/-- Decode every Lean-code preview store entry, preserving per-entry decode errors. -/
def entries (state : Verso.Genre.Manual.TraverseState) :
    Array (Except Informal.TraversalIndex.DecodeError
      (Informal.TraversalIndex.StoredEntry Informal.LeanCodePreview.Entry)) :=
  Informal.TraversalIndex.decodeStoreEntries state domainName

end Informal.TraversalIndex.LeanCodePreviews
