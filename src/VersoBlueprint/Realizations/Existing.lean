/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean.DocString.Extension
import VersoBlueprint.Environment
import VersoBlueprint.Translations
import VersoBlueprint.Validation.Lean

/-! Read-only, opt-in projection of a single accepted attribute theorem. No
registration, admission mutation, source rendering or inferred correspondence. -/

namespace Informal.Realizations.Existing

open Lean Validation Translations

structure Projection where
  input : Input
  witness : ObjectKey
  leanKey : RealizationKey
  informalKey : RealizationKey
  moduleName : Name
  sourcePath : String
  /-- Raw Markdown from Lean's own docstring store, not rendered/proofread Verso. -/
  docstringFormat : Name := `markdown

private def issue (code : String) (label : Name) (message : String) : Diagnostic :=
  { code, subject := label.toString, message }

def Projection.contribution (p : Projection) (slot : Name) (value : α) : Contribution α :=
  { origin := {
      id := p.leanKey.node ++ `existingRealization ++ slot
      moduleName := p.moduleName, source := p.sourcePath }, value }

/-- Read canonical bytes at the accepted association's path. The injectable
reader permits explicit I/O-failure tests, not alternate successful provenance.
The caller must use a current ordinary build of the owning source. -/
def project (projectName label : Name)
    (readSource : System.FilePath → IO String := IO.FS.readFile) : CoreM (Except Diagnostic Projection) := do
  let some node ← Environment.getNode? label
    | return .error <| issue "missing-node" label "No accepted Blueprint node"
  unless !projectName.isAnonymous && node.blueprintAttributeAttachments &&
      node.externalRefs.size == 1 && node.proofExternalRefs.isEmpty &&
      node.literateCodes.isEmpty && node.rustCode.isNone && node.externalMarkup.isEmpty &&
      node.proof.isNone do
    return .error <| issue "unsupported-node" label "Expected one attribute-owned theorem and docstring only"
  let ref := node.externalRefs[0]!
  unless ref.origin == .blueprintAttr && ref.kind == .theorem && ref.present do
    return .error <| issue "unsupported-association" label "Expected one present attribute theorem association"
  let some body := node.statement
    | return .error <| issue "missing-docstring" label "No accepted statement body"
  unless body.stx.isOfKind `Informal.blueprint && body.hasBody do
    return .error <| issue "unsupported-statement" label "Statement is not the attribute-owned docstring"
  let some moduleName := ref.provenance.moduleName?
    | return .error <| issue "source-unavailable" label "Accepted association has no source module"
  let some sourcePath := ref.provenance.sourcePath?
    | return .error <| issue "source-unavailable" label "Accepted association has no source path"
  -- Query only the declaration's own raw Markdown, never inherited prose or HTML.
  let some doc := Lean.docStringExt.find? (level := .server) (← getEnv) ref.canonical
    | return .error <| issue "unsupported-docstring" label "This first adapter supports own Markdown docstrings only"
  if blank doc then return .error <| issue "missing-docstring" label "Empty raw docstring"
  let text ← try liftM <| readSource sourcePath catch _ =>
    return .error <| issue "source-unavailable" label "Cannot read canonical source at accepted association path"
  if blank text then return .error <| issue "source-unavailable" label "Canonical source is empty"
  let leanContext : Context := ⟨`lean, projectName⟩
  let proseContext : Context := ⟨`markdown, projectName⟩
  let witness : ObjectKey := ⟨leanContext, ref.canonical.toString⟩
  let leanKey : RealizationKey := ⟨label, `lean⟩
  let informalKey : RealizationKey := ⟨label, `docstring⟩
  let leanDoc : DocumentKey := ⟨leanContext, sourcePath⟩
  let proseDoc : DocumentKey := ⟨proseContext, sourcePath ++ "#docstring:" ++ ref.canonical.toString⟩
  let p : Projection := { input := {}, witness, leanKey, informalKey, moduleName, sourcePath }
  return .ok { p with input := {
    nodes := #[p.contribution `node { label, title := label.toString }]
    documents := #[p.contribution `source { key := leanDoc, text },
      p.contribution `docstring { key := proseDoc, text := doc }]
    objects := #[p.contribution `object { key := witness, resolution := .resolved, document := some leanDoc }]
    realizations := #[
      p.contribution `lean {
        key := leanKey, context := leanContext
        facets := #[{ name := `statement, declarations := #[witness] },
          { name := `proof, declarations := #[witness] }], declarations := #[{ object := witness }] },
      p.contribution `informal {
        key := informalKey, context := proseContext
        facets := #[{ name := `statement, documents := #[proseDoc] }] }] } }

/-- Attach a freshly checked proof requirement/evidence to the returned input.
Does not register anything in the existing Blueprint environment. -/
def Projection.validate (p : Projection) (expected : Syntax) : Elab.Term.TermElabM (Except Diagnostic Input) := do
  let docs := p.input.objects.filterMap (·.value.document)
  let checked ← NativeLean.check p.witness.context.project p.witness expected docs
  let .ok checked := checked | return checked.map (fun _ => p.input)
  let key : RequirementKey := ⟨.declaration p.leanKey p.witness, `proof⟩
  let input := { p.input with
    realizations := p.input.realizations.map fun record =>
      if record.value.key != p.leanKey then record else
        { record with value := { record.value with
          declarations := #[{ object := p.witness, required := #[key] }]
          facets := record.value.facets.map fun facet =>
            if facet.name == `proof then { facet with required := #[key] } else facet } }
    requirements := #[p.contribution `proofRequirement {
      key, expected := .proof checked.goal p.witness
      coverage := .dependencyClosure }] }
  let .ok registry := admit input
    | return .error <| issue "invalid-projection" p.leanKey.node "Projected input failed pure structural admission"
  let some binding := registry.bindingFor key
    | return .error <| issue "missing-binding" p.leanKey.node "No binding for native proof requirement"
  return .ok { input with evidence := #[p.contribution `proofEvidence {
    id := p.leanKey.node ++ `nativeProof, requirement := key, binding
    observation := .proof checked.observation }] }

end Informal.Realizations.Existing
