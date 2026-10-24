/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean

/-! Pure identities and authored realization data. No environment extension,
language-server transport, renderer, or completion checker is installed here. -/

namespace Informal.Realizations

open Lean

/-- Logical namespace, independent of checkout paths and compiler processes. -/
structure Context where
  language : Name
  project : Name
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

structure ObjectKey where
  context : Context
  native : String
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

structure DocumentKey where
  context : Context
  path : String
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

/-- Current canonical bytes supplied by the owning source provider. -/
structure Document where
  key : DocumentKey
  text : String
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

structure RealizationKey where
  node : Name
  name : Name
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

structure TranslationKey where
  project : Name
  name : Name
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

structure ClaimKey where
  translation : TranslationKey
  name : Name
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

/-- Statement/proof are named facets; declarations can have separate requirements. -/
inductive Subject where
  | realization (key : RealizationKey)
  | facet (key : RealizationKey) (name : Name)
  | declaration (key : RealizationKey) (object : ObjectKey)
  | translation (key : TranslationKey)
  | claim (key : ClaimKey)
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

def Subject.realization? : Subject → Option RealizationKey
  | .realization key | .facet key _ | .declaration key _ => some key
  | _ => none

def Subject.translation? : Subject → Option TranslationKey
  | .translation key => some key
  | .claim key => some key.translation
  | _ => none

structure RequirementKey where
  subject : Subject
  name : Name
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

structure Node where
  label : Name
  title : String
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

structure Facet where
  name : Name
  documents : Array DocumentKey := #[]
  /-- Source declarations selected by this facet, referencing the realization's
  existing associations. Sharing a declaration does not duplicate its validation. -/
  declarations : Array ObjectKey := #[]
  required : Array RequirementKey := #[]
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

/-- Every listed declaration is required; alternatives belong in another realization. -/
structure Declaration where
  object : ObjectKey
  required : Array RequirementKey := #[]
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

structure Realization where
  key : RealizationKey
  context : Context
  facets : Array Facet := #[]
  declarations : Array Declaration := #[]
  required : Array RequirementKey := #[]
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

def Realization.requirements (r : Realization) : Array RequirementKey :=
  (r.required ++ r.facets.flatMap (·.required) ++ r.declarations.flatMap (·.required)).toList.eraseDups.toArray

inductive Resolution where
  | resolved
  | missing
  | ambiguous
  | unsupported
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

/-- Source resolution is an observation, not proof/completeness evidence. -/
structure ObjectObservation where
  key : ObjectKey
  resolution : Resolution
  document : Option DocumentKey := none
  explanation : String := ""
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

/-- Immutable producer-site identity and diagnostic provenance, not a semantic key. -/
structure Origin where
  id : Name
  moduleName : Name
  source : String := ""
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

structure Contribution (α : Type) where
  origin : Origin
  value : α
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

structure Diagnostic where
  code : String
  subject : String
  message : String
  origins : Array Origin := #[]
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

/-- Current provider/build semantic inputs for a selected subject. These are
materialized with current source, never exported by source authoring or reports. -/
structure BindingInput where
  subject : Subject
  name : Name
  content : String
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

/-- Canonical ordering uses exact structured content, not a possibly colliding hash. -/
def canonical [BEq α] [ToJson α] (values : Array α) : Array α :=
  values.toList.eraseDups.toArray.qsort fun a b => (toJson a).compress < (toJson b).compress

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
