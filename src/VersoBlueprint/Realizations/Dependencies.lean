/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Environment
import VersoBlueprint.Translations

/-! Opt-in selection of complete-proof contracts for effective accepted theorem
uses. No completion, prerequisite rewriting, traversal or registration is done
here. Consumers evaluate selected keys with the existing Registry evaluator. -/

namespace Informal.Realizations.Dependencies

open Lean Validation Translations

/-- Keep the entire effective use, including metadata and unresolved selection. -/
abbrev SelectedUse := Data.UseRef × Except Diagnostic RequirementKey

/-- Statement then proof, preserving effective order independently on each axis. -/
abbrev SelectedUses := Array SelectedUse × Array SelectedUse

private def issue (code : String) (label : Name) (message : String) : Diagnostic :=
  { code, subject := label.toString, message }

private def canonicalTheorem (role : String) (label : Name) (node : Data.Node) :
    Except Diagnostic Name := do
  unless node.kind.isTheoremLike && node.blueprintAttributeAttachments &&
      node.externalRefs.size == 1 && node.proofExternalRefs.isEmpty &&
      node.literateCodes.isEmpty && node.rustCode.isNone && node.externalMarkup.isEmpty do
    throw <| issue ("unsupported-" ++ role) label "Expected one accepted attribute theorem"
  let ref := node.externalRefs[0]!
  unless ref.present && ref.origin == .blueprintAttr && ref.kind.isTheoremLike do
    throw <| issue ("unsupported-" ++ role) label "Expected a present canonical attribute theorem association"
  unless !ref.canonical.isAnonymous && ref.canonical.toString.toName == ref.canonical do
    throw <| issue "unsupported-identity" label "Canonical Lean name cannot be represented losslessly"
  return ref.canonical

private def selectTarget (registry : Registry) (context : Context) (label : Name) :
    CoreM (Except Diagnostic RequirementKey) := do
  let some node ← Environment.getNode? label
    | return .error <| issue "missing-target" label "No accepted dependency target"
  let canonical ← match canonicalTheorem "target" label node with
    | .ok name => pure name
    | .error diagnostic => return .error diagnostic
  let realizationKey : RealizationKey := ⟨label, `lean⟩
  if (registry.realization? realizationKey).any (·.context != context) then
    return .error <| issue "wrong-default-context" label "Default Lean realization belongs to a different project context"
  let key ← match registry.selectRequirement {
      node := label, context, realization := some `lean, requirement := `proof } with
    | .ok key => pure key
    | .error diagnostic => return .error diagnostic
  let witness : ObjectKey := ⟨context, canonical.toString⟩
  unless key.subject == .declaration realizationKey witness do
    return .error <| issue "wrong-default-subject" label "Selected proof must name this accepted canonical declaration"
  let some requirement := registry.requirement? key
    | return .error <| issue "missing-prerequisite" label "Selected contract is missing"
  match requirement.expected with
  | .proof goal actualWitness =>
    if actualWitness != witness then
      return .error <| issue "wrong-default-witness" label "Selected proof expects a different witness"
    if goal.context != context || actualWitness.context != context then
      return .error <| issue "wrong-default-context" label "Proof goal and witness must use the selected Lean context"
  | _ =>
    return .error <| issue "not-proof-requirement" label "A review or check named proof cannot supply complete-proof validation"
  if requirement.coverage != .dependencyClosure then
    return .error <| issue "insufficient-coverage" label "Default theorem policy requires dependency-closure coverage"
  let some realization := registry.realization? realizationKey
    | return .error <| issue "missing-prerequisite" label "Default Lean realization is missing"
  unless realization.declarations.size == 1 && realization.declarations[0]!.object == witness do
    return .error <| issue "unsupported-default-association" label "Default realization must contain exactly the accepted theorem"
  unless realization.declarations[0]!.required.contains key do
    return .error <| issue "unrequired-default-proof" label "Selected contract is not required by the default declaration"
  return .ok key

/-- Read accepted effective uses, without suppressing self/duplicate labels or
reinterpreting origin as producer scope. An outer error is source/view failure;
an empty pair is a supported source with no uses. Target failures remain edges.
This selects contracts, not the truth of caller-authored goal descriptions. -/
def selectUses (registry : Registry) (context : Context) (source : Name) :
    CoreM (Except Diagnostic SelectedUses) := do
  unless context.valid && context.language == `lean do
    return .error <| issue "unsupported-view" source "An explicit valid Lean project context is required"
  let some node ← Environment.getNode? source
    | return .error <| issue "missing-source" source "No accepted source node"
  if let .error diagnostic := canonicalTheorem "source" source node then return .error diagnostic
  let selectAxis (uses : Array Data.UseRef) : CoreM (Array SelectedUse) :=
    uses.mapM fun use => return (use, ← selectTarget registry context use.label)
  let statement ← selectAxis (node.statement.map (·.deps) |>.getD #[])
  let proof ← selectAxis (node.proof.map (·.deps) |>.getD #[])
  return .ok (statement, proof)

end Informal.Realizations.Dependencies
