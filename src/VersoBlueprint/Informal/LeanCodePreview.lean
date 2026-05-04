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

namespace Informal.LeanCodePreview

open Lean

abbrev ManualBlock := Verso.Doc.Block Verso.Genre.Manual

/--
Dedicated traversal domain for manifest-backed Lean declaration previews.

Unlike `PreviewCache`, this domain is only for previews attached to links that
target Lean declarations/definitions.
-/
def domainName : Name := Informal.LeanDeclPreviewKey.domainName
/--
Canonical internal preview target for one Lean declaration.

The preview namespace mirrors regular Lean names so the manifest keys stay
declaration-centric rather than blueprint-label-centric.
-/
def targetName (decl : Name) : Name :=
  Informal.LeanDeclPreviewKey.targetName decl

def lookupKey (decl : Name) : String :=
  Informal.LeanDeclPreviewKey.lookupKey decl

inductive Source where
  | inlineBlocks (blocks : Array ManualBlock)
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

def Entry.ofInlineBlocks (target : Name) (blocks : Array ManualBlock) : Entry :=
  { target := target.eraseMacroScopes, source := .inlineBlocks blocks }

def Entry.ofExternalDecl (target : Name) (decl : Informal.Data.ExternalRef) : Entry :=
  { target := target.eraseMacroScopes, source := .externalDecl decl }

def title (decl : Name) : String :=
  s!"Lean declaration {decl}"

def renderHtmlWithState
    (entry : Entry)
    (impls : Verso.Genre.Manual.ExtensionImpls)
    (state : Verso.Genre.Manual.TraverseState)
    (logError : String → IO Unit := fun _ => pure ()) : IO Verso.Output.Html := do
  match entry.source with
  | .inlineBlocks blocks =>
    Informal.renderManualBlocksHtmlWithState blocks impls state (logError := logError)
  | .externalDecl decl =>
    pure <| Informal.ExternalCode.renderPreviewHtml #[decl]

end Informal.LeanCodePreview
