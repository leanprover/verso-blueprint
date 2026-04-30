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
deriving Inhabited, Repr

instance : Lean.ToJson Source where
  toJson
    | .inlineBlocks blocks => .arr #[.str "i", toJson blocks]
    | .externalDecl decl => .arr #[.str "e", toJson decl]

instance : Lean.FromJson Source where
  fromJson? v := do
    match v with
    | .arr arr =>
      let some tag := arr[0]? | throw "expected Lean-code preview source tag"
      let some payload := arr[1]? | throw "expected Lean-code preview source payload"
      match ← fromJson? tag with
      | "i" => .inlineBlocks <$> fromJson? payload
      | "e" => .externalDecl <$> fromJson? payload
      | other => throw s!"unknown Lean-code preview source tag {other}"
    | .obj obj =>
      match obj.get? "inlineBlocks", obj.get? "externalDecl" with
      | some blocks, none =>
        match fromJson? (α := Array ManualBlock) blocks with
        | .ok data => return .inlineBlocks data
        | .error _ => .inlineBlocks <$> blocks.getObjValAs? (Array ManualBlock) "blocks"
      | none, some decl =>
        match fromJson? (α := Informal.Data.ExternalRef) decl with
        | .ok data => return .externalDecl data
        | .error _ => .externalDecl <$> decl.getObjValAs? Informal.Data.ExternalRef "decl"
      | _, _ => throw "expected object with exactly one Lean-code preview source constructor"
    | _ => throw "expected Lean-code preview source"

/--
Canonical declaration-preview payload.

Multiple Lean declaration names may legitimately point to the same inline code
block preview body, but each declaration keeps its own manifest key.
-/
structure Entry where
  target : Name
  source : Source
deriving Inhabited, Repr

instance : Lean.ToJson Entry where
  toJson entry := .arr #[toJson entry.target, toJson entry.source]

instance : Lean.FromJson Entry where
  fromJson? v := do
    match v with
    | .arr arr =>
      let some target := arr[0]? | throw "expected Lean-code preview target"
      let some source := arr[1]? | throw "expected Lean-code preview source"
      return {
        target := ← fromJson? target
        source := ← fromJson? source
      }
    | _ =>
      return {
        target := ← v.getObjValAs? Name "target"
        source := ← v.getObjValAs? Source "source"
      }

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
