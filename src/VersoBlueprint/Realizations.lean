/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.ConceptMetadata
import Vir.Package.Name

/-! Pure identities and authored realization data. No environment extension,
language-server transport, renderer, or completion checker is installed here. -/

namespace Informal.Realizations

open Lean

/-- Logical namespace, independent of checkout paths and compiler processes. -/
structure Context where
  language : Name
  project : Name
  deriving Ord, Repr, Inhabited, BEq, Hashable, DecidableEq, ToJson

structure ObjectKey where
  context : Context
  native : String
  deriving Ord, Repr, Inhabited, BEq, Hashable, DecidableEq, ToJson

structure DocumentKey where
  context : Context
  path : String
  deriving Ord, Repr, Inhabited, BEq, Hashable, DecidableEq, ToJson

/-- Current canonical bytes supplied by the owning source provider. -/
structure Document where
  key : DocumentKey
  text : String
  deriving Ord, Repr, Inhabited, BEq, DecidableEq, ToJson

structure RealizationKey where
  node : Name
  name : Name
  deriving Ord, Repr, Inhabited, BEq, Hashable, DecidableEq, ToJson

structure TranslationKey where
  project : Name
  name : Name
  deriving Ord, Repr, Inhabited, BEq, Hashable, DecidableEq, ToJson

structure ClaimKey where
  translation : TranslationKey
  name : Name
  deriving Ord, Repr, Inhabited, BEq, Hashable, DecidableEq, ToJson

/-- Content interpretation belongs to an owned source selection, not a requirement. -/
inductive ContentScope where
  | statement
  | implementation
  deriving Ord, Repr, Inhabited, BEq, Hashable, DecidableEq, ToJson

/-- Ordinary producers split their source roles into separately addressable objects.
Role remains explicit data; consumers must not infer it from this key. -/
def RealizationKey.forRole (key : RealizationKey) (role : Name) : RealizationKey :=
  { key with name := Name.mkSimple (toJson (Vir.nameKey key.name, Vir.nameKey role)).compress }

/-- Exact independently addressable assessment subjects. -/
inductive Subject where
  | realization (key : RealizationKey)
  | declaration (key : RealizationKey) (object : ObjectKey)
  | translation (key : TranslationKey)
  | claim (key : ClaimKey)
  deriving Ord, Repr, Inhabited, BEq, Hashable, DecidableEq, ToJson

def Subject.realization? : Subject → Option RealizationKey
  | .realization key | .declaration key _ => some key
  | _ => none

def Subject.translation? : Subject → Option TranslationKey
  | .translation key => some key
  | .claim key => some key.translation
  | _ => none

structure RequirementKey where
  subject : Subject
  name : Name
  deriving Ord, Repr, Inhabited, BEq, Hashable, DecidableEq, ToJson

structure Node extends Data.NodeMetadata where
  label : Name
  title : String
  deriving Ord, Repr, Inhabited, BEq, DecidableEq, ToJson

/-- Immutable producer-site identity and diagnostic provenance, not a semantic key. -/
structure Origin where
  id : Name
  moduleName : Name
  source : String := ""
  deriving Ord, Repr, Inhabited, BEq, DecidableEq, ToJson

structure Diagnostic where
  code : String
  subject : String
  message : String
  origins : Array Origin := #[]
  deriving Ord, Repr, Inhabited, BEq, DecidableEq, ToJson

/-- Every listed declaration is required; alternatives belong in another realization. -/
structure Declaration where
  object : ObjectKey
  projection : ContentScope := .implementation
  required : Array RequirementKey := #[]
  /-- Failures of this owner's source association, even when another owner
  resolves the same canonical object. -/
  sourceIssues : Array Diagnostic := #[]
  deriving Ord, Repr, Inhabited, BEq, DecidableEq, ToJson

structure Realization where
  key : RealizationKey
  context : Context
  role : Name := `account
  documents : Array DocumentKey := #[]
  declarations : Array Declaration := #[]
  required : Array RequirementKey := #[]
  deriving Ord, Repr, Inhabited, BEq, DecidableEq, ToJson

def Realization.requirements (r : Realization) : Array RequirementKey :=
  (r.required ++ r.declarations.flatMap (·.required)).toList.eraseDups.toArray

inductive Resolution where
  | resolved
  | missing
  | ambiguous
  | unsupported
  deriving Ord, Repr, Inhabited, BEq, DecidableEq, ToJson

/-- Source resolution is an observation, not proof/completeness evidence. -/
structure ObjectObservation where
  key : ObjectKey
  resolution : Resolution
  document : Option DocumentKey := none
  explanation : String := ""
  deriving Ord, Repr, Inhabited, BEq, DecidableEq, ToJson

structure Contribution (α : Type) where
  origin : Origin
  value : α
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

/-- Current provider/build semantic inputs for a selected subject. These are
materialized with current source, never exported by source authoring or reports. -/
structure BindingInput where
  subject : Subject
  name : Name
  content : String
  deriving Ord, Repr, Inhabited, BEq, DecidableEq, ToJson

/-- Canonical set order uses structural `Ord`, never display JSON or `Repr`.
The supplied ordering must distinguish unequal values (as the derived instances
for these records do). Deduplication still uses typed equality. -/
def canonical [BEq α] [Ord α] (values : Array α) : Array α := Id.run do
  let sorted := values.qsort (fun a b => compare a b == .lt)
  let mut result := #[]
  for value in sorted do
    if result.back? != some value then result := result.push value
  return result

/-- Resolve an existing declaration by its exact object in this realization. -/
def Realization.declaration? (model : Realization) (object : ObjectKey) : Option Declaration := do
  guard (object.context == model.context)
  let #[declaration] := model.declarations.filter (·.object == object) | none
  return declaration

/-- Attach a requirement to its uniquely owned declaration, preserving the rest
of the realization, including any source issues on the selected declaration. -/
def Realization.attachDeclarationRequirement? (model : Realization) (key : RequirementKey) :
    Option Realization := do
  let .declaration owner object := key.subject | none
  guard (owner == model.key)
  let declaration ← model.declaration? object
  let updated := { declaration with required := canonical (declaration.required.push key) }
  return { model with declarations := model.declarations.map fun entry =>
    if entry.object == object then updated else entry }

def blank (s : String) : Bool := s.trimAscii.isEmpty

def Context.valid (context : Context) : Bool :=
  !context.language.isAnonymous && !context.project.isAnonymous

def ObjectKey.valid (key : ObjectKey) : Bool := key.context.valid && !blank key.native

def DocumentKey.valid (key : DocumentKey) : Bool := key.context.valid && !blank key.path

def RealizationKey.valid (key : RealizationKey) : Bool :=
  !key.node.isAnonymous && !key.name.isAnonymous

def TranslationKey.valid (key : TranslationKey) : Bool :=
  !key.project.isAnonymous && !key.name.isAnonymous

end Informal.Realizations
