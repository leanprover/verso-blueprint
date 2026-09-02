/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.LabelNameParsing
import VersoBlueprint.PreviewCache
public meta import Verso.Doc.ArgParse
public meta import Verso.Doc.Elab
meta import Verso.Instances.Deriving -- shake: keep

public section

namespace Informal.Graft

open Lean
open Verso Doc Elab ArgParse

private def nodeMarkerAttr : String := "data-bp-blueprint-node"
private def nodeMarkerValue : String := "true"

private def nodeMarkerAttrs : Array (String × String) :=
  #[(nodeMarkerAttr, nodeMarkerValue)]

public structure BlueprintNode where
  label : String
  facet : String := "statement"
  key : String
  displayLabel? : Option String := none
  compact : Bool := false
  showHeader : Bool := true
  siteBase? : Option String := none
deriving Repr, BEq

private def attrValue? (attrs : Array (String × String)) (name : String) : Option String :=
  (attrs.find? fun attr => attr.1 == name).map (·.2)

/--
Set the CSS class in an HTML attribute array, replacing an existing `class`
attribute or creating one when needed.
-/
public def setClassAttr (attrs : Array (String × String)) (className : String) :
    Array (String × String) :=
  Id.run do
    let className := className.trimAscii.toString
    if className.isEmpty then
      return attrs
    let mut out := #[]
    let mut found := false
    for attr in attrs do
      if attr.1 == "class" then
        out := out.push ("class", className)
        found := true
      else
        out := out.push attr
    if found then
      out
    else
      out.push ("class", className)

/-- Append a CSS class to an HTML attribute array, creating the `class` attribute if needed. -/
public def appendClassAttr (attrs : Array (String × String)) (className : String) :
    Array (String × String) :=
  let className := className.trimAscii.toString
  if className.isEmpty then
    attrs
  else
    let current := (attrValue? attrs "class").map (·.trimAscii.toString) |>.getD ""
    let value :=
      if current.isEmpty then
        className
      else
        current ++ " " ++ className
    setClassAttr attrs value

private def BlueprintNode.domClassName (node : BlueprintNode) : String :=
  if node.compact then
    "bp_graft_manifest_node bp_graft_manifest_node_compact"
  else
    "bp_graft_manifest_node"

def BlueprintNode.toAttrs (node : BlueprintNode) : Array (String × String) :=
  nodeMarkerAttrs ++
    #[ ("class", node.domClassName)
     , ("data-bp-label", node.label)
     , ("data-bp-facet", node.facet)
     , ("data-bp-preview-key", node.key)
     , ("data-bp-compact", if node.compact then "true" else "false")
     , ("data-bp-show-header", if node.showHeader then "true" else "false")
     ] ++
    (node.displayLabel?.map (fun label => #[("data-bp-display-label", label)] ) |>.getD #[]) ++
    (node.siteBase?.map (fun siteBase => #[("data-bp-site-base", siteBase)] ) |>.getD #[])

def BlueprintNode.fromAttrs? (attrs : Array (String × String)) : Option BlueprintNode := do
  let marker ← attrValue? attrs nodeMarkerAttr
  guard (marker == nodeMarkerValue)
  let label ← attrValue? attrs "data-bp-label"
  let facet := attrValue? attrs "data-bp-facet" |>.getD "statement"
  let key ← attrValue? attrs "data-bp-preview-key"
  let displayLabel? := attrValue? attrs "data-bp-display-label"
  let compact := attrValue? attrs "data-bp-compact" == some "true"
  let showHeader := attrValue? attrs "data-bp-show-header" != some "false"
  let siteBase? := attrValue? attrs "data-bp-site-base"
  some { label, facet, key, displayLabel?, compact, showHeader, siteBase? }

def BlueprintNode.renderedAttrs (node : BlueprintNode) : Array (String × String) :=
  node.toAttrs ++ #[("data-bp-rendered", "static")]

/-- Rendered DOM attributes with one additional CSS class. -/
def BlueprintNode.renderedAttrsWithClass (node : BlueprintNode) (className : String) :
    Array (String × String) :=
  appendClassAttr node.renderedAttrs className

def BlueprintNode.fallbackText (node : BlueprintNode) : String :=
  s!"Loading Blueprint node {node.label}..."

def BlueprintNode.selectionDescription (node : BlueprintNode) : String :=
  s!"label `{node.label}`, facet `{node.facet}`, key `{node.key}`"

public structure BlueprintNodeConfig where
  label : String
  facet : Option String := none
  displayLabel : Option String := none
  compact : Bool := false
  showHeader : Bool := true
  siteBase : Option String := none
deriving Repr, BEq, ToJson, FromJson, Quote

public meta instance : FromArgs BlueprintNodeConfig DocElabM where
  fromArgs :=
    BlueprintNodeConfig.mk <$>
      .positional `label .string <*>
      .named `facet .string true <*>
      .named `displayLabel .string true <*>
      .flag `compact false <*>
      .flag `header true <*>
      .named `siteBase .string true

private def previewKey (label facet : String) : String :=
  let label := Informal.LabelNameParsing.parse label
  match facet with
  | "statement" => Informal.PreviewCache.statementKey label
  | "proof" => Informal.PreviewCache.proofKey label
  | other => s!"{label}--{other}"

def BlueprintNodeConfig.toNode (cfg : BlueprintNodeConfig) : BlueprintNode :=
  let facet := cfg.facet.getD "statement"
  {
    label := cfg.label
    facet
    key := previewKey cfg.label facet
    displayLabel? := cfg.displayLabel
    compact := cfg.compact
    showHeader := cfg.showHeader
    siteBase? := cfg.siteBase
  }

public structure SideBySideConfig where
  boxed : Bool := false
deriving Repr, BEq, Inhabited, ToJson, FromJson, Quote

public meta instance : FromArgs SideBySideConfig DocElabM where
  fromArgs :=
    SideBySideConfig.mk <$>
      .flag `boxed false

namespace SideBySideConfig

public def className (cfg : SideBySideConfig) : String :=
  if cfg.boxed then
    "bp_graft_side_by_side bp_graft_side_by_side_boxed"
  else
    "bp_graft_side_by_side"

public def attrs (cfg : SideBySideConfig) : Array (String × String) :=
  #[("class", cfg.className)]

end SideBySideConfig

end Informal.Graft
