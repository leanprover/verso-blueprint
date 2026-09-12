/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoBlueprint.Commands.Common
import VersoBlueprint.Data
import VersoBlueprint.Environment
import VersoBlueprint.Informal.Block
import VersoBlueprint.Informal.Block.Store
import VersoBlueprint.Informal.LabelArg
import VersoBlueprint.Informal.UseConfig
import VersoBlueprint.Lib.ExtensionDecode
import VersoBlueprint.Lib.HoverRender
import VersoBlueprint.Lib.PreviewSource
import VersoBlueprint.PreviewCache
import VersoBlueprint.Profiling
import VersoBlueprint.TeX
import VersoBlueprint.TraversalIndex

open Verso Doc Elab
open Verso.Genre Manual
open Verso.ArgParse
open Lean Lean.Elab
open Lean.Doc.Syntax

namespace Informal

def usesAssetBundle : Informal.Commands.BlueprintAssetBundle :=
  Informal.Commands.inlinePreviewAssetBundle

/--
Arguments accepted by the inline `{uses ...}` role.

This role renders a reference and registers a dependency edge from the enclosing
block. Its `origin` and `intent` options share the same metadata semantics as
block-level `(uses_origin := ...)` and `(uses_intent := ...)`.
-/
structure UsesConfig where
  label : Data.Label
  labelSyntax : Syntax := Syntax.missing
  origin : Data.UseOrigin := .manual
  invalidOrigin : Option String := none
  intent : Data.UseIntent := .regular
  invalidIntent : Option String := none

/--
Arguments accepted by the inline `{bpref ...}` role.

`bpref` renders the same kind of hoverable Blueprint reference as `{uses ...}`,
but deliberately does not accept dependency metadata or register a use edge.
-/
structure BprefConfig where
  label : Data.Label
  labelSyntax : Syntax := Syntax.missing

section
variable [Monad m] [MonadError m]

def UsesConfig.ofArgs (labelArg : Verso.ArgParse.WithSyntax String)
    (origin intent : Option String) : UsesConfig :=
  let parsedLabel := LabelArg.parse labelArg
  let metadata := UseConfig.parseMetadata origin intent
  {
    label := parsedLabel.label
    labelSyntax := parsedLabel.labelSyntax
    origin := metadata.origin
    invalidOrigin := metadata.invalidOrigin
    intent := metadata.intent
    invalidIntent := metadata.invalidIntent
  }

def UsesConfig.parse : ArgParse m UsesConfig :=
  UsesConfig.ofArgs <$> .positional `label (.withSyntax .string)
        <*> .named `origin .string true <*> .named `intent .string true

instance : FromArgs UsesConfig m where
  fromArgs := UsesConfig.parse

def BprefConfig.parse : ArgParse m BprefConfig :=
  (fun (labelArg : Verso.ArgParse.WithSyntax String) =>
    let parsedLabel := LabelArg.parse labelArg
    {
      label := parsedLabel.label
      labelSyntax := parsedLabel.labelSyntax
    }) <$> .positional `label (.withSyntax .string)

instance : FromArgs BprefConfig m where
  fromArgs := BprefConfig.parse

end

def UsesConfig.useRef? (cfg : UsesConfig) : Option Data.UseRef :=
  if cfg.invalidOrigin.isNone && cfg.invalidIntent.isNone then
    some { label := cfg.label, origin := cfg.origin, intent := cfg.intent }
  else none

def UsesConfig.validate [Monad m] [MonadLog m] [AddMessageContext m] [MonadOptions m]
    (cfg : UsesConfig) : m (Option Data.UseRef) := do
  if let some raw := cfg.invalidOrigin then
    logErrorAt cfg.labelSyntax m!"uses reference to {cfg.label} has invalid '(origin := \"{raw}\")'; expected one of {UseConfig.allowedOriginValues}"
  if let some raw := cfg.invalidIntent then
    logErrorAt cfg.labelSyntax m!"uses reference to {cfg.label} has invalid '(intent := \"{raw}\")'; expected one of {UseConfig.allowedIntentValues}"
  return cfg.useRef?

structure InlineData where
  label : Data.Label
deriving FromJson, ToJson, Quote

/-- A reference uses document numbering only for rendered nodes, and previews only
when prose or a code-backed preview is available. HTML and TeX share the same title resolution. -/
private structure NodeReference where
  title : String
  href : Option String
  previewKey : Option PreviewKey

private def resolveNodeReference (state : TraverseState) (label : Data.Label) : NodeReference := {
  title := ((TraversalIndex.Nodes.renderedData? state label).map (·.displayTitle state)).getD
    (label.toString (escape := false))
  href := TraversalIndex.Nodes.href? state label
  previewKey := PreviewSource.traversalPreviewCandidateKey? state label
}

private def NodeReference.withPreview (reference : NodeReference) (node : Verso.Output.Html) :
    Verso.Output.Html :=
  match reference.previewKey with
  | none => node
  | some key =>
      let id := s!"bp-uses-{HoverRender.previewKey (toString key)}"
      let target := HoverRender.InlinePreviewTarget.withLookupKey id reference.title (toString key)
      HoverRender.inlinePreviewTargetNode node target

inline_extension Inline.informal (data : InlineData) where
  data := toJson data
  usePackages := Informal.TeX.standardMathUsePackages
  traverse _id data _contents := do
    let some reference ← ExtensionDecode.decode? (α := InlineData) data
        (fun _ => s!"Malformed data in Inline.informal traversal: {data}")
      | pure none
    if let .error message := TraversalIndex.Nodes.required (← get) reference.label then
      Verso.reportError message
    pure none
  extraCss := usesAssetBundle.css
  extraJs := usesAssetBundle.js
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun goI _id data inlines => do
      let some { label } ← ExtensionDecode.decode? (α := InlineData) data
          (fun _ => "Malformed data in Inline.informal traversal")
        | pure .empty
      let reference := resolveNodeReference (← HtmlT.state) label
      let content ← if inlines.isEmpty then pure #[.text true reference.title] else inlines.mapM goI
      let labelText := label.toString (escape := false)
      let node := match reference.href with
        | some href => {{<a href={{href}} title={{labelText}}>{{content}}</a>}}
        | none => {{<span title={{labelText}}>{{content}}</span>}}
      return {{<span>{{reference.withPreview node}}</span>}}
  toTeX :=
    open Verso.Output.TeX in
    some <| fun goI _id data inlines => do
      let .ok inlineData := fromJson? (α := InlineData) data
        | Verso.reportError s!"Malformed data in Inline.informal.toTeX: {data}"
          pure .empty
      if inlines.isEmpty then
        let reference := resolveNodeReference (← Verso.Doc.TeX.state) inlineData.label
        pure <| .text reference.title
      else
        inlines.mapM goI

def nodeReferenceTerm (label : Data.Label) (contents : Array Term) : CoreM Term := do
    let data : InlineData := { label }
    ``(Inline.other (Inline.informal $(quote data)) #[$contents,*])

@[role]
def uses : RoleExpanderOf UsesConfig
  | cfg, contents => do
    Profile.withDocElab "role" "uses" <| do
      let dependency? ← cfg.validate
      let term ← nodeReferenceTerm cfg.label (← contents.mapM elabInline)
      let useRef ← getRef
      if let some dependency := dependency? then
        Environment.addUse useRef dependency
      pure term

/-- Reference a Blueprint node without registering a dependency edge. -/
@[role]
def bpref : RoleExpanderOf BprefConfig
  | cfg, contents => do
    Profile.withDocElab "role" "bpref" <|
      nodeReferenceTerm cfg.label (← contents.mapM elabInline)

end Informal
