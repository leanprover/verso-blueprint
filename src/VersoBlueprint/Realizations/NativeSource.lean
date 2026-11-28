/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean.Elab.DeclarationRange
import VersoBlueprint.Docstring.Canonical
import VersoBlueprint.ExternalModuleSource
import VersoBlueprint.Validation.Lean

/-! Native declaration and docstring preparation from the compiled environment. -/

namespace Informal.Realizations.NativeSource

open Lean Validation

private def issue (code : String) (label : Name) (message : String) : Diagnostic :=
  { code, subject := label.toString, message }

/-- Compare optional accepted snapshot ranges with the environment's current
native ranges for that same canonical declaration. This pure check does not fill
in or mutate any accepted record. -/
def checkedSourceRanges (label : Name) (snapshotRange snapshotSelection : Option DeclarationRange)
    (native : Option DeclarationRanges) : Except Diagnostic DeclarationRanges := do
  let some ranges := native
    | throw <| issue "source-association-unavailable" label "Accepted declaration has no native source ranges"
  if snapshotRange.any (· != ranges.range) || snapshotSelection.any (· != ranges.selectionRange) then
    throw <| issue "source-association-unavailable" label "Accepted snapshot and current native ranges disagree"
  return ranges

/-- Declaration metadata supplied by the owning producer, not a node or display
name. Snapshot ranges are compared with current native ranges, never filled in.
Package identity is recorded for imported docstring selections. -/
structure Request where
  project : Name
  canonical : Name
  moduleName : Name
  package? : Option String := none
  range? : Option DeclarationRange := none
  selectionRange? : Option DeclarationRange := none

/-- A declaration as the compiled environment establishes it. It carries no
source document: its content is the checked declaration, not the owning file. -/
structure Prepared where
  canonical : Name
  declaration : ObjectKey
  roles : Array Name := #[]
  moduleName : Name
  ranges : DeclarationRanges
  semanticContext : Option String := none
  statementContext : Option String := none
  semanticDiagnostics : Array Diagnostic := #[]

/-- An owned declaration and its compiled docstring content. -/
structure Documented extends Prepared where
  format : Name
  content : String

private def checkOwner (request : Request) : CoreM (Except Diagnostic ConstantInfo) := do
  let name := request.canonical
  if request.project.isAnonymous || name.isAnonymous || request.moduleName.isAnonymous then
    return .error <| issue "invalid-source-request" name "Expected explicit project, typed declaration and owning module"
  unless name.toString.toName == name do
    return .error <| issue "unsupported-identity" name "Canonical Lean name cannot be represented losslessly by this adapter"
  let env ← getEnv
  let some info := env.checked.get.find? name |
    return .error <| issue "missing-declaration" name "Declaration is not in the current checked environment"
  if ExternalModuleSource.moduleNameForDecl? env name != some request.moduleName then
    return .error <| issue "source-association-unavailable" name "Source module disagrees with current declaration owner"
  if let some package := request.package? then
    unless (env.getModuleIdxFor? name).bind env.getModulePackageByIdx? == some package do
      return .error <| issue "source-association-unavailable" name
        "Compiled declaration belongs to a different package"
  return .ok info

-- Read direct compiled metadata and verify via Lean's `findInternalDocString?`
-- (which consults private `inheritDocStringExt` first) that the effective
-- docstring is the declaration's own entry rather than an inherited one.
-- Pointer identity (`unsafe ptrEq`) distinguishes distinct `VersoDocString`
-- entries even when `Repr` elides `ElabInline.custom`/`ElabBlock.custom`
-- `Dynamic` payloads (such as `{name}` links to different constants). Identical
-- content deduplicated during `.olean` compaction still requires Lean to expose
-- `Lean.getInheritedDocStringTarget?` (see UPC-0022).
private def ownDocstringMetadata (name : Name) : CoreM (Except Diagnostic (String ⊕ Lean.VersoDocString)) := do
  let env ← getEnv
  let direct ← match Docstring.directCompiled env name with
    | .ok direct => pure direct
    | .error .missing =>
      return .error <| issue "unsupported-docstring" name "No direct own native docstring metadata"
    | .error .ambiguous =>
      return .error <| issue "ambiguous-docstring" name "Conflicting own native docstring formats"
  -- Note: `Lean.findInternalDocString?` is partial without fuel and loops on
  -- self-inheritance (`attribute [inherit_doc foo] foo`) or ≥3-cycles accepted
  -- by `addInheritedDocString`; see UPC-0022 for a direct, non-recursive query.
  let effective? ← liftM <| Lean.findInternalDocString? env name (includeBuiltin := false)
  match direct, effective? with
  | .inl markdown, some (.inl effective) =>
    if unsafe ptrEq markdown effective && markdown == effective then return .ok direct
    else
      return .error <| issue "inherited-docstring" name
        "Compiled docstring is inherited from another declaration"
  | .inr verso, some (.inr effective) =>
    if unsafe ptrEq verso effective then return .ok direct
    else
      return .error <| issue "inherited-docstring" name
        "Compiled Verso docstring is inherited from another declaration"
  | _, _ =>
    return .error <| issue "inherited-docstring" name
      "Compiled docstring is inherited from another declaration"

private def preparedAt (request : Request) (ranges : DeclarationRanges) (info : ConstantInfo)
    (semantics : NativeLean.SemanticContext) : CoreM Prepared := do
  let context : Context := ⟨`lean, request.project⟩
  let roles ← NativeLean.declarationRoles info
  let statement ← semantics .statement request.project #[request.canonical]
  let semantics ← semantics .implementation request.project #[request.canonical]
  return {
    canonical := request.canonical, declaration := ⟨context, request.canonical.toString⟩
    roles, moduleName := request.moduleName, ranges
    semanticContext := semantics.toOption, statementContext := statement.toOption
    semanticDiagnostics := canonical ((match semantics with | .ok _ => #[] | .error issue => #[issue]) ++
      (match statement with | .ok _ => #[] | .error issue => #[issue])) }

private def environmentRanges (request : Request) : CoreM (Except Diagnostic DeclarationRanges) := do
  return checkedSourceRanges request.canonical request.range? request.selectionRange?
    (← findDeclarationRanges? request.canonical)

/-- Prepare an owned declaration from compiled identity, ranges and semantics. -/
def prepare (request : Request)
    (semantics : NativeLean.SemanticContext := NativeLean.semanticContext) :
    CoreM (Except Diagnostic Prepared) := do
  let info ← match ← checkOwner request with
    | .ok info => pure info
    | .error diagnostic => return .error diagnostic
  let ranges ← match ← environmentRanges request with
    | .ok ranges => pure ranges
    | .error diagnostic => return .error diagnostic
  return .ok (← preparedAt request ranges info semantics)

/-- Prepare the direct docstring from the owning compiled declaration. -/
def prepareDocumented (request : Request)
    (semantics : NativeLean.SemanticContext := NativeLean.semanticContext) :
    CoreM (Except Diagnostic Documented) := do
  let info ← match ← checkOwner request with
    | .ok info => pure info
    | .error diagnostic => return .error diagnostic
  let ranges ← match ← environmentRanges request with
    | .ok ranges => pure ranges
    | .error diagnostic => return .error diagnostic
  let doc ← match ← ownDocstringMetadata request.canonical with
    | .ok doc => pure doc
    | .error diagnostic => return .error diagnostic
  let encoded : Except Diagnostic (Name × String) := match doc with
    | .inl markdown =>
      if blank markdown then .error (issue "missing-docstring" request.canonical "Empty compiled docstring")
      else .ok (`markdown, markdown)
    | .inr verso =>
      if verso.text.isEmpty && verso.subsections.isEmpty then
        .error (issue "missing-docstring" request.canonical "Empty compiled docstring")
      else (Docstring.canonicalVersoDocstring verso).map (`verso, ·)
  match encoded with
  | .error diagnostic => return .error { diagnostic with subject := request.canonical.toString }
  | .ok (format, content) =>
    return .ok { toPrepared := ← preparedAt request ranges info semantics, format, content }

end Informal.Realizations.NativeSource
