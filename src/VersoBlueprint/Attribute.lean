/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Lean.DocString.Extension
import VersoManual
import VersoBlueprint.DependencyAnalysis
import VersoBlueprint.Environment
import VersoBlueprint.ExternalRefSnapshot
import VersoBlueprint.LabelNameParsing
import VersoBlueprint.Math

namespace Informal

open Lean

syntax blueprintDepTerm := "-"? (ident <|> str)
syntax blueprintDepList := "[" blueprintDepTerm,* "]"
declare_syntax_cat blueprintAttrOption
syntax (name := blueprintAutoDepsAttrOption) "(" &"autoDeps" " := " ident ")" : blueprintAttrOption
syntax (name := blueprintUsesAttrOption) "(" &"uses" " := " blueprintDepList ")" : blueprintAttrOption
syntax (name := blueprintProofUsesAttrOption) "(" &"proofUses" " := " blueprintDepList ")" : blueprintAttrOption
syntax (name := blueprint) "blueprint" ppSpace str (ppSpace blueprintAttrOption)* : attr

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

private def classifyDeclKind (decl : Name) (info : ConstantInfo) : CoreM Data.NodeKind :=
  match Informal.Data.ConstantInfo.blueprintNodeKind? info with
  | some kind => pure kind
  | none =>
    throwError "invalid '[blueprint]' target '{decl}': expected a definition-like declaration or theorem, got {Informal.Data.ConstantInfo.blueprintKindText info}"

private def pushLabelUnique (labels : Array Data.Label) (label : Data.Label) : Array Data.Label :=
  if labels.contains label then labels else labels.push label

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

private def elabBlueprintConfig : Syntax → CoreM BlueprintAttrConfig
  | `(attr| blueprint $label:str $[$opts:blueprintAttrOption]*) => do
    let mut cfg : BlueprintAttrConfig := { label := parseLabel label.getString }
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
  | _ => throwError "invalid syntax for '[blueprint]' attribute"

mutual

private partial def inlineToManualStx (inl : Lean.Doc.Inline Lean.ElabInline) : CoreM (TSyntax `term) := do
  match inl with
  | .text s => `(Verso.Doc.Inline.text $(quote s))
  | .emph content =>
    let content ← content.mapM inlineToManualStx
    `(Verso.Doc.Inline.emph #[$content,*])
  | .bold content =>
    let content ← content.mapM inlineToManualStx
    `(Verso.Doc.Inline.bold #[$content,*])
  | .code s => `(Verso.Doc.Inline.code $(quote s))
  | .math .inline s => Informal.Math.mkBpMathInlineTerm .inline s
  | .math .display s => Informal.Math.mkBpMathInlineTerm .display s
  | .linebreak s => `(Verso.Doc.Inline.linebreak $(quote s))
  | .link content url =>
    let content ← content.mapM inlineToManualStx
    `(Verso.Doc.Inline.link #[$content,*] $(quote url))
  | .footnote name content =>
    let content ← content.mapM inlineToManualStx
    `(Verso.Doc.Inline.footnote $(quote name) #[$content,*])
  | .image alt url => `(Verso.Doc.Inline.image $(quote alt) $(quote url))
  | .concat content =>
    let content ← content.mapM inlineToManualStx
    `(Verso.Doc.Inline.concat #[$content,*])
  -- Fallback for docstring extensions not available in the Manual genre.
  | .other _ content =>
    let content ← content.mapM inlineToManualStx
    `(Verso.Doc.Inline.concat #[$content,*])

private partial def listItemToManualStx
    (item : Lean.Doc.ListItem (Lean.Doc.Block Lean.ElabInline Lean.ElabBlock)) : CoreM (TSyntax `term) := do
  let contents ← item.contents.mapM blockToManualStx
  `(Verso.Doc.ListItem.mk #[$contents,*])

private partial def descItemToManualStx
    (item : Lean.Doc.DescItem (Lean.Doc.Inline Lean.ElabInline) (Lean.Doc.Block Lean.ElabInline Lean.ElabBlock)) :
    CoreM (TSyntax `term) := do
  let term ← item.term.mapM inlineToManualStx
  let desc ← item.desc.mapM blockToManualStx
  `(Verso.Doc.DescItem.mk #[$term,*] #[$desc,*])

private partial def blockToManualStx (b : Lean.Doc.Block Lean.ElabInline Lean.ElabBlock) : CoreM (TSyntax `term) := do
  match b with
  | .para contents =>
    let contents ← contents.mapM inlineToManualStx
    `(Verso.Doc.Block.para #[$contents,*])
  | .code content => `(Verso.Doc.Block.code $(quote content))
  | .ul items =>
    let items ← items.mapM listItemToManualStx
    `(Verso.Doc.Block.ul #[$items,*])
  | .ol start items =>
    let items ← items.mapM listItemToManualStx
    `(Verso.Doc.Block.ol $(quote start) #[$items,*])
  | .dl items =>
    let items ← items.mapM descItemToManualStx
    `(Verso.Doc.Block.dl #[$items,*])
  | .blockquote items =>
    let items ← items.mapM blockToManualStx
    `(Verso.Doc.Block.blockquote #[$items,*])
  | .concat content =>
    let content ← content.mapM blockToManualStx
    `(Verso.Doc.Block.concat #[$content,*])
  -- Fallback for docstring extensions not available in the Manual genre.
  | .other _ content =>
    let content ← content.mapM blockToManualStx
    `(Verso.Doc.Block.concat #[$content,*])

end

private partial def partToManualBlocksStx
    (p : Lean.Doc.Part Lean.ElabInline Lean.ElabBlock Empty) : CoreM (Array (TSyntax `term)) := do
  let mut out : Array (TSyntax `term) := #[]
  if !p.title.isEmpty then
    let title ← p.title.mapM inlineToManualStx
    let titleBold ← `(Verso.Doc.Inline.bold #[$title,*])
    let titleBlock ← `(Verso.Doc.Block.para #[$titleBold])
    out := out.push titleBlock
  out := out ++ (← p.content.mapM blockToManualStx)
  for child in p.subParts do
    out := out ++ (← partToManualBlocksStx child)
  pure out

private def statementFromDocstring? (decl : Name) (ref : Syntax) : CoreM (Option Data.InformalData) := do
  let env ← getEnv
  let internalDoc? ← liftM <| findInternalDocString? env decl
  let elabStx ←
    match internalDoc? with
    | none => pure #[]
    | some (.inl doc) =>
      let doc := doc.trimAscii.toString
      if doc.isEmpty then
        pure #[]
      else
        match MD4Lean.parse doc with
        | some ast =>
          ast.blocks.mapM (fun b =>
            Verso.Genre.Manual.Markdown.blockFromMarkdown b
              (handleHeaders := Verso.Genre.Manual.Markdown.strongEmphHeaders))
        | none =>
          pure #[← `(Verso.Doc.Block.para #[Verso.Doc.Inline.text $(quote doc)])]
    | some (.inr d) =>
      let mut blocks ← d.text.mapM blockToManualStx
      for part in d.subsections do
        blocks := blocks ++ (← partToManualBlocksStx part)
      pure blocks
  if elabStx.isEmpty then
    pure none
  else
    pure <| some {
      stx := ref
      deps := #[]
      elabStx := elabStx.map (·.raw)
    }

private structure ResolvedAutoDeps where
  statement : Array Data.UseRef := #[]
  proof : Array Data.UseRef := #[]
deriving Inhabited, Repr

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
    return labels.foldl pushLabelUnique acc

private def mergeAxisDeps
    (currentDecl currentLabel : Name) (inferred : Array Data.Label) (manual : AutoDepEntries) :
    CoreM (Array Data.UseRef) := do
  let explicit ← resolveManualTargets currentDecl currentLabel manual.add
  let excluded ← resolveManualTargets currentDecl currentLabel manual.exclude
  let excluded := pushLabelUnique excluded currentLabel
  let mut out := #[]
  for label in DependencyAnalysis.sortLabels inferred do
    if !excluded.contains label then
      out := Data.UseRef.pushMergeByLabel out (DependencyAnalysis.automaticUseRef label)
  for label in explicit do
    if !excluded.contains label then
      out := Data.UseRef.pushMergeByLabel out (manualUseRef label)
  return out

private def resolveAutoDeps
    (decl : Name) (label : Data.Label) (info : ConstantInfo) (cfg : BlueprintAttrConfig) :
    CoreM ResolvedAutoDeps := do
  let inferred ←
    if DependencyAnalysis.enabled (← getOptions) cfg.autoDeps then
      DependencyAnalysis.infer decl info
    else
      pure {}
  let statement ← mergeAxisDeps decl label inferred.statement cfg.uses
  let statementLabels := Data.UseRef.labels statement
  let proofInferred := inferred.proof.filter fun label => !statementLabels.contains label
  let proof ← mergeAxisDeps decl label proofInferred cfg.proofUses
  return { statement, proof }

private def payloadWithDeps
    (ref : Syntax) (deps : Array Data.UseRef) (incoming? existing? : Option Data.InformalData) :
    Option Data.InformalData :=
  let mergeDeps (payload : Data.InformalData) : Data.InformalData :=
    { payload with deps := deps.foldl Data.UseRef.pushMergeByLabel payload.deps }
  match existing? with
  | some payload => some (mergeDeps payload)
  | none =>
    match incoming? with
    | some payload => some (mergeDeps payload)
    | none =>
      if deps.isEmpty then
        none
      else
        some { stx := ref, deps }

private def registerLeanOnlyDecl (decl : Name) (cfg : BlueprintAttrConfig) (ref : Syntax) : CoreM Unit := do
  let decl := decl.eraseMacroScopes
  let label := cfg.label.eraseMacroScopes
  let some info := (← getEnv).find? decl
    | throwError "unknown declaration '{decl}'"
  let declKind ← classifyDeclKind decl info
  let statement? ← statementFromDocstring? decl ref
  let deps ← resolveAutoDeps decl label info cfg
  let opts ← getOptions
  let extRef ←
    externalRefSnapshotAtCurrentDir opts (Data.ExternalRef.ofName decl .blueprintAttr)

  Environment.modifyDataForLabel label fun data => do
    let data ← data.registerCodeRef label (.external #[extRef])
    let data :=
      match data.get? label with
      | some node =>
        let node :=
          if node.statement.isNone then
            { node with kind := declKind }
          else
            node
        let statement := payloadWithDeps ref deps.statement statement? node.statement
        let proof := payloadWithDeps ref deps.proof none node.proof
        let node := { node with statement, proof }
        data.insert label node
      | none => data
    return data
  Environment.registerBlueprintAttributeLabel label

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
      let cfg ← elabBlueprintConfig stx
      registerLeanOnlyDecl decl cfg stx
    descr := "Registers a definition/theorem as a Lean-only blueprint node; supports opt-in automatic dependency inference"
  }

end Informal
