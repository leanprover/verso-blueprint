/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Environment
import VersoBlueprint.Translations
import VersoBlueprint.Realizations.NativeSource

/-! Read-only, opt-in projection of a single accepted attribute theorem. No
registration, admission mutation, source rendering or inferred correspondence. -/

namespace Informal.Realizations.Existing

open Lean Validation Translations

private def issue (code : String) (label : Name) (message : String) : Diagnostic :=
  { code, subject := label.toString, message }

/-- Temporary old-node eligibility gate. It returns source metadata only; source
preparation and realization construction live at the direct native boundary.
Dependency-only proof syntax must be missing with no retained authored body. -/
def request (projectName label : Name) : CoreM (Except Diagnostic NativeSource.Request) := do
  let some node ← Environment.getNode? label
    | return .error <| issue "missing-node" label "No accepted Blueprint node"
  unless !projectName.isAnonymous && node.blueprintAttributeAttachments &&
      node.externalRefs.size == 1 && node.proofExternalRefs.isEmpty &&
      node.literateCodes.isEmpty && node.rustCode.isNone && node.externalMarkup.isEmpty &&
      (node.proof.all fun proof => proof.stx.isMissing && !proof.hasBody) do
    return .error <| issue "unsupported-node" label "Expected one attribute-owned theorem and docstring only"
  let ref := node.externalRefs[0]!
  unless ref.origin == .blueprintAttr && ref.kind == .theorem && ref.present do
    return .error <| issue "unsupported-association" label "Expected one present attribute theorem association"
  unless ref.canonical.toString.toName == ref.canonical do
    return .error <| issue "unsupported-identity" label
      "Canonical Lean name cannot be represented losslessly by this adapter"
  let some body := node.statement
    | return .error <| issue "missing-docstring" label "No accepted statement body"
  unless body.stx.isOfKind `Informal.blueprint && body.hasBody do
    return .error <| issue "unsupported-statement" label "Statement is not the attribute-owned docstring"
  let some moduleName := ref.provenance.moduleName?
    | return .error <| issue "source-unavailable" label "Accepted association has no source module"
  let some sourcePath := ref.provenance.sourcePath?
    | return .error <| issue "source-unavailable" label "Accepted association has no source path"
  return .ok {
    project := projectName, canonical := ref.canonical, moduleName, sourcePath
    range? := ref.range?, selectionRange? := ref.selectionRange? }

/-- Transitional consumer of the old shape gate; not the source-provider API.
It is removed with the old storage/consumer cutover. -/
def project (projectName label : Name)
    (readSource : System.FilePath → IO String := IO.FS.readFile) :
    CoreM (Except Diagnostic NativeSource.PreparedModel) := do
  let request ← match ← request projectName label with
    | .ok request => pure request
    | .error diagnostic => return .error diagnostic
  let source ← match ← NativeSource.prepareDocumented request readSource with
    | .ok source => pure source
    | .error diagnostic => return .error { diagnostic with subject := label.toString }
  let some accepted ← Environment.getNode? label
    | return .error <| issue "missing-node" label "No accepted Blueprint metadata"
  return source.realize {
    id := label ++ `existingRealization, moduleName := request.moduleName
    source := request.sourcePath } (accepted.toConcept label label.toString) `lean `docstring

end Informal.Realizations.Existing
