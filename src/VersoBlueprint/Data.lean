/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.SourcePayload
import VersoBlueprint.Realizations

namespace Informal.Data

open Lean
set_option doc.verso true

/-- An assembled body and the declarations needed to validate its dependencies. -/
structure InformalData extends InformalBody where
  /-- One declaration per label and authority; manual precedence never erases validation evidence. -/
  useDeclarations : Array UseRef := #[]
deriving Repr, Inhabited

def InformalData.hasBody (data : InformalData) : Bool := data.toInformalBody.hasBody

/-- Effective dependency edges, with manual metadata taking precedence. -/
def InformalData.deps (data : InformalData) : Array UseRef :=
  UseRef.mergeByLabel #[] data.useDeclarations

def InformalData.dependencyLabels (data : InformalData) : Array Label :=
  data.deps.map (·.label)

structure Node extends NodeMetadata where
  statement : Option InformalData := none -- Informal Object statement
  proof : Option InformalData := none -- Informal Object proof
  /-- Statement-facet external associations, in registration order. -/
  externalRefs : Array ExternalRef := #[]
  /-- Proof-facet external associations, in registration order. They also contribute to the node. -/
  proofExternalRefs : Array ExternalRef := #[]
  /-- Whether accepted selected evidence includes a Blueprint-attribute association.
  This capability is independent of the snapshot retained for each declaration. -/
  blueprintAttributeAttachments : Bool := false
  /-- Every associated literate block, in registration order. -/
  literateCodes : Array Code := #[]
  rustCode : Option RustInlineCode := none -- Informal object associated Rust code
  externalMarkup : ExternalMarkupSet := {} -- Raw external markup keyed by language and slot
deriving Repr, Inhabited

/-- The same accepted shared metadata, projected into the pure model. This is a
transitional metadata-only bridge; no source fields or completion flags survive
this projection. The old Node container is removed with its consumer migration. -/
def Node.toConcept (node : Node) (label : Name) (title : String) : Realizations.Node :=
  { toNodeMetadata := node.toNodeMetadata, label, title }


/--
Body, dependency, metadata, and literate-code inputs for one registration.
External associations and priority belong exclusively to identified contribution
records. Dependencies are independent of body
additions; adding code or dependencies cannot reclassify an authored statement.
-/
structure NodeContribution where
  /-- Explicit kind from a statement directive, including an empty placeholder. -/
  kind : Option NodeKind := none
  count : Nat := 0
  statementBody : Option InformalBody := none
  proofBody : Option InformalBody := none
  statementUses : Array UseRef := #[]
  proofUses : Array UseRef := #[]
  literateCodes : Array Code := #[]
  rustCode : Option RustInlineCode := none
  externalMarkup : ExternalMarkupSet := {}
  parent : Option Parent := none
  owner : Option AuthorId := none
  tags : Array String := #[]
  effort : Option String := none
  prUrl : Option String := none
  issueUrl : Option String := none
deriving Repr, Inhabited

/-- All captured external associations. Facet snapshots remain separate;
declaration membership and status projections consume both facets. -/
def Node.externalAssociationSnapshots (node : Node) : Array ExternalRef :=
  node.externalRefs ++ node.proofExternalRefs

/-- Canonical node associations from both facets. Rendering keeps each facet's
snapshot; node-level projections retain every observed status conservatively. -/
def Node.associatedExternalRefs (node : Node) : Array ExternalRef :=
  ExternalRef.mergeSnapshots #[] node.externalAssociationSnapshots

/-- External summary entries not already supplied by a compiled literate declaration. -/
def Node.summaryExternalRefs (node : Node) : Array ExternalRef :=
  let names := node.literateCodes.foldl (init := ({} : NameSet)) fun names code =>
    code.definedDeclNames.foldl (fun names name => names.insert name) names
  node.associatedExternalRefs.filter fun ref => !names.contains ref.canonical.eraseMacroScopes

/-- Prefer each inline declaration once for summaries, preserving status evidence
from every external and inline association of the same canonical declaration.
The authored code blocks remain unchanged for rendering and provenance. -/
def Node.summaryLiterateCodes (node : Node) : Array Code := Id.run do
  let observations := node.associatedExternalRefs.map
      (fun ref => (ref.canonical, if ref.present then ref.provedStatus else .missing)) ++
    node.literateCodes.flatMap fun code =>
      code.definedDefs.map (fun decl => (decl.name, decl.provedStatus)) ++
      code.definedTheorems.map (fun decl => (decl.name, decl.provedStatus))
  let statuses := ProvedStatus.indexByName observations
  let mut seen : NameSet := {}
  let mut codes := #[]
  for code in node.literateCodes do
    let mut definitions := #[]
    let mut theorems := #[]
    for decl in code.definedDefs do
      let name := decl.name.eraseMacroScopes
      unless seen.contains name do
        seen := seen.insert name
        definitions := definitions.push { decl with provedStatus := statuses.getD name decl.provedStatus }
    for decl in code.definedTheorems do
      let name := decl.name.eraseMacroScopes
      unless seen.contains name do
        seen := seen.insert name
        theorems := theorems.push { decl with provedStatus := statuses.getD name decl.provedStatus }
    codes := codes.push { code with definedDefs := definitions, definedTheorems := theorems }
  return codes

def Node.leanDecls (node : Node) : Array Name :=
  let external := node.externalAssociationSnapshots.foldl (init := #[]) fun acc ref =>
    if ref.present then pushUniqueNativeName acc ref.canonical else acc
  node.literateCodes.foldl (init := external) fun acc code =>
    code.definedDeclNames.foldl pushUniqueNativeName acc

def Node.hasAssociatedCode (node : Node) : Bool :=
  !node.externalRefs.isEmpty || !node.proofExternalRefs.isEmpty || !node.literateCodes.isEmpty

def Node.hasStatementBody (node : Node) : Bool := node.statement.any (·.hasBody)

def Node.hasProofBody (node : Node) : Bool := node.proof.any (·.hasBody)

end Informal.Data
