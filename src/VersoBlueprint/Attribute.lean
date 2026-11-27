/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Lean.DocString.Extension
import VersoManual
import VersoBlueprint.DependencyAnalysis
import VersoBlueprint.Docstring.Manual
import VersoBlueprint.Environment
import VersoBlueprint.ExternalRefSnapshot
import VersoBlueprint.LabelNameParsing

namespace Informal

open Lean

syntax blueprintDepTerm := "-"? (ident <|> str)
syntax blueprintDepList := "[" blueprintDepTerm,* "]"
declare_syntax_cat blueprintAttrOption
syntax (name := blueprintAutoDepsAttrOption) "(" &"autoDeps" " := " ident ")" : blueprintAttrOption
syntax (name := blueprintUsesAttrOption) "(" &"uses" " := " blueprintDepList ")" : blueprintAttrOption
syntax (name := blueprintProofUsesAttrOption) "(" &"proofUses" " := " blueprintDepList ")" : blueprintAttrOption
syntax (name := blueprint) "blueprint" (ppSpace str)? (ppSpace blueprintAttrOption)* : attr

private inductive AutoDepTarget where
  | label (label : Data.Label)
  | decl (decl : Name)
deriving Repr

private structure AutoDepEntries where
  add : Array AutoDepTarget := #[]
  exclude : Array AutoDepTarget := #[]
deriving Inhabited, Repr

private def AutoDepEntries.append (current incoming : AutoDepEntries) : AutoDepEntries :=
  {
    add := current.add ++ incoming.add
    exclude := current.exclude ++ incoming.exclude
  }

private structure BlueprintAttrConfig where
  label : Data.Label
  autoDeps : Option Bool := none
  uses : AutoDepEntries := {}
  proofUses : AutoDepEntries := {}
deriving Inhabited, Repr

private def validateDeclKind (decl : Name) (info : ConstantInfo) : CoreM Unit :=
  match Informal.Data.ConstantInfo.blueprintNodeKind? info with
  | some _ => pure ()
  | none =>
    throwError "invalid '[blueprint]' target '{decl}': expected a definition-like declaration or theorem, got {Informal.Data.ConstantInfo.blueprintKindText info}"

private def manualUseRef (label : Data.Label) : Data.UseRef :=
  { label }

private def pushTargetUnique (targets : Array AutoDepTarget) (target : AutoDepTarget) :
    Array AutoDepTarget :=
  match target with
  | .label label =>
    if targets.any (fun
      | .label existing => existing == label
      | _ => false) then targets else targets.push target
  | .decl decl =>
    let decl := decl.eraseMacroScopes
    if targets.any (fun
      | .decl existing => existing.eraseMacroScopes == decl
      | _ => false) then targets else targets.push (.decl decl)

private def parseLabel (label : String) : Data.Label :=
  LabelNameParsing.parse label

/--
Use a declaration's fully qualified spelling as an opaque Blueprint label.

The `Name.mkSimple` representation is deliberate: string-authored Blueprint
references use the same opaque-label parser rather than Lean namespace
resolution.
-/
private def defaultLabelForDecl (decl : Name) : Data.Label :=
  parseLabel decl.eraseMacroScopes.toString

private def parseDepList : TSyntax ``blueprintDepList → CoreM AutoDepEntries
  | `(blueprintDepList| [$[$deps:blueprintDepTerm],*]) => do
    deps.foldlM (init := {}) fun cfg dep => do
      match dep with
      | `(blueprintDepTerm| $id:ident) =>
        let decl ← Lean.Elab.realizeGlobalConstNoOverloadWithInfo id
        return { cfg with add := pushTargetUnique cfg.add (.decl decl) }
      | `(blueprintDepTerm| -$id:ident) =>
        let decl ← Lean.Elab.realizeGlobalConstNoOverloadWithInfo id
        return { cfg with exclude := pushTargetUnique cfg.exclude (.decl decl) }
      | `(blueprintDepTerm| $label:str) =>
        return { cfg with add := pushTargetUnique cfg.add (.label (parseLabel label.getString)) }
      | `(blueprintDepTerm| -$label:str) =>
        return { cfg with exclude := pushTargetUnique cfg.exclude (.label (parseLabel label.getString)) }
      | _ => throwError "unsupported dependency syntax in '[blueprint]' attribute"
  | _ => throwError "unsupported dependency list syntax in '[blueprint]' attribute"

private def elabBlueprintOptions
    (cfg : BlueprintAttrConfig)
    (opts : Array (TSyntax `blueprintAttrOption)) :
    CoreM BlueprintAttrConfig := do
  let mut cfg := cfg
  for opt in opts do
    match opt with
    | `(blueprintAttrOption| (autoDeps := $value:ident)) =>
      match value.getId.eraseMacroScopes with
      | `true => cfg := { cfg with autoDeps := some true }
      | `false => cfg := { cfg with autoDeps := some false }
      | _ => throwErrorAt value "'autoDeps' expects 'true' or 'false'"
    | `(blueprintAttrOption| (uses := $deps:blueprintDepList)) =>
      let deps ← parseDepList deps
      cfg := { cfg with uses := cfg.uses.append deps }
    | `(blueprintAttrOption| (proofUses := $deps:blueprintDepList)) =>
      let deps ← parseDepList deps
      cfg := { cfg with proofUses := cfg.proofUses.append deps }
    | _ => throwError "unsupported option syntax in '[blueprint]' attribute"
  return cfg

private def elabBlueprintConfig (decl : Name) : Syntax → CoreM BlueprintAttrConfig
  | `(attr| blueprint $label:str $[$opts:blueprintAttrOption]*) =>
    elabBlueprintOptions { label := parseLabel label.getString } opts
  | `(attr| blueprint $[$opts:blueprintAttrOption]*) =>
    elabBlueprintOptions { label := defaultLabelForDecl decl } opts
  | _ => throwError "invalid syntax for '[blueprint]' attribute"

private def statementFromDocstring? (decl : Name) (ref : Syntax) :
    CoreM (Option (Data.InformalBody × Array Data.UseRef × Name)) := do
  let env ← getEnv
  let some internalDoc ← liftM <| findInternalDocString? env decl | return none
  let (elabStx, deps, format) ← Informal.Docstring.statementBlocks internalDoc
  if elabStx.isEmpty then
    pure none
  else
    pure <| some ({
      stx := ref
      elabStx := elabStx.map (·.raw)
    }, deps, format)

private def labelsForManualTarget
    (currentDecl currentLabel : Name) (target : AutoDepTarget) : CoreM (Array Data.Label) := do
  match target with
  | .label label => return #[label]
  | .decl decl =>
    let decl := decl.eraseMacroScopes
    if decl == currentDecl.eraseMacroScopes then
      return #[currentLabel]
    let labels ← Environment.labelsForLeanDecl decl
    if labels.isEmpty then
      throwError
        "Blueprint dependency declaration '{decl}' does not have a registered Blueprint label; use a string label or tag that declaration with '[blueprint]' first"
    return labels

private def resolveManualTargets
    (currentDecl currentLabel : Name) (targets : Array AutoDepTarget) : CoreM (Array Data.Label) := do
  targets.foldlM (init := #[]) fun acc target => do
    let labels ← labelsForManualTarget currentDecl currentLabel target
    return labels.foldl pushUnique acc

private def collectAxisDeps
    (currentDecl currentLabel role : Name) (inferred : Array SourceData.UseDeclaration) (manual : AutoDepEntries)
    (docstringDeps : Array Data.UseRef := #[]) :
    CoreM (Array SourceData.UseDeclaration) := do
  let explicit ← resolveManualTargets currentDecl currentLabel manual.add
  let excluded ← resolveManualTargets currentDecl currentLabel manual.exclude
  let excluded := pushUnique excluded currentLabel
  let mut out := inferred.filter fun use => use.role == role && !excluded.contains use.reference.label
  for dependency in docstringDeps do
    if !excluded.contains dependency.label then
      out := out.push { node := currentLabel, role, reference := dependency }
  for label in explicit do
    if !excluded.contains label then
      out := out.push { node := currentLabel, role, reference := manualUseRef label }
  return out

private def resolveAutoDeps
    (decl : Name) (label : Data.Label) (cfg : BlueprintAttrConfig)
    (docstringDeps : Array Data.UseRef) :
    CoreM (Array SourceData.UseDeclaration) := do
  let inferred ←
    if DependencyAnalysis.enabled (← getOptions) cfg.autoDeps then
      DependencyAnalysis.inferDeclUses label #[decl]
    else
      pure #[]
  let statement ← collectAxisDeps decl label `statement inferred cfg.uses docstringDeps
  let proof ← collectAxisDeps decl label `proof inferred cfg.proofUses
  return statement ++ proof

private def registerBlueprintDecl (decl : Name) (cfg : BlueprintAttrConfig) (ref : Syntax) : CoreM Unit := do
  let decl := decl.eraseMacroScopes
  let label := cfg.label.eraseMacroScopes
  let some info := (← getEnv).find? decl
    | throwError "unknown declaration '{decl}'"
  validateDeclKind decl info
  -- Only the declaration introducing a label owns its implicit statement.
  -- Attachments never compete with or fill an existing node's informal prose.
  let current? ← Environment.getNodeInventory? label
  let docstring? ← if current?.isNone then statementFromDocstring? decl ref else pure none
  let deps ← resolveAutoDeps decl label cfg (docstring?.map (fun (_, deps, _) => deps) |>.getD #[])
  let opts ← getOptions
  let extRef ←
    registerExternalRefAtCurrentDir opts (Data.ExternalRef.ofName decl .blueprintAttr)

  let some position := ref.getPos?
    | throwError "'[blueprint]' attributes require a stable source position"
  let source ← Data.SourceLocation.ofSyntax? ref
  let project ← Environment.sourceProject
  let moduleName ← getMainModule
  let fact : Contributions.Record := {
    id := {
      moduleName
      producer := `blueprint.attribute
      subject := decl
      site := position.byteIdx
      slot := 0 }
    label
    nativeAssociations := #[{
      realization := ⟨label, `lean⟩, context := ⟨`lean, project⟩
      placement := `statement, reference := extRef }]
    priority := none
    source }
  let sources ← docstring?.toArray.mapM fun (body, _, format) => do
    let selection ← Environment.sourceAt label format (some `statement) format (.prose body) ref
    return { selection with ownDocstring := some { moduleName, canonical := decl } }
  discard <| Environment.contributeAttribute fact {
    sources
    uses := deps }

open Lean in
initialize
  registerBuiltinAttribute {
    name := `blueprint
    ref := by exact decl_name%
    applicationTime := .afterCompilation
    add := fun decl stx kind => do
      unless kind == AttributeKind.global do
        throwError "invalid attribute '[blueprint]', must be global"
      unless ((← getEnv).getModuleIdxFor? decl).isNone do
        throwError "invalid attribute '[blueprint]', declaration is in an imported module"
      let cfg ← elabBlueprintConfig decl stx
      registerBlueprintDecl decl cfg stx
    descr := "Registers a compiled declaration as a Blueprint node, using its qualified declaration name as the default label; supports opt-in automatic dependency inference"
  }

end Informal
