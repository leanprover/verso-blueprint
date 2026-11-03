/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/


import Init
import Lean.Data.Json
import VersoBlueprint.Validation
import Vir.Package.Name

/-! Injective structural encodings for values that participate in validation
binding identities. Every Lean `Name` is encoded with `Vir.nameKey`; compound
`ToJson` and `Repr` output is deliberately not used because Name display text
is not an injective identity encoding.
-/

namespace Informal.Validation.BindingEncoding

open Lean Realizations

private def name (value : Name) : Json := Json.str (Vir.nameKey value)

private def tagged (tag : String) (parts : Array Json) : Json :=
  Json.arr (#[Json.str tag] ++ parts)

def context (value : Context) : Json :=
  tagged "context" #[name value.language, name value.project]

def objectKey (value : ObjectKey) : Json :=
  tagged "object-key" #[context value.context, Json.str value.native]

def documentKey (value : DocumentKey) : Json :=
  tagged "document-key" #[context value.context, Json.str value.path]

def realizationKey (value : RealizationKey) : Json :=
  tagged "realization-key" #[name value.node, name value.name]

def translationKey (value : TranslationKey) : Json :=
  tagged "translation-key" #[name value.project, name value.name]

def claimKey (value : ClaimKey) : Json :=
  tagged "claim-key" #[translationKey value.translation, name value.name]

def subject : Subject → Json
  | .realization key => tagged "realization-subject" #[realizationKey key]
  | .facet key facetName => tagged "facet-subject" #[realizationKey key, name facetName]
  | .declaration key object =>
    tagged "declaration-subject" #[realizationKey key, objectKey object]
  | .translation key => tagged "translation-subject" #[translationKey key]
  | .claim key => tagged "claim-subject" #[claimKey key]

def requirementKey (value : RequirementKey) : Json :=
  tagged "requirement-key" #[subject value.subject, name value.name]

def document (value : Document) : Json :=
  tagged "document" #[documentKey value.key, Json.str value.text]

def goal (value : Goal) : Json :=
  tagged "goal" #[context value.context, Json.str value.fingerprint,
    Json.arr (value.documents.map documentKey)]

def expectation : Expectation → Json
  | .proof expected witness => tagged "proof-expectation" #[goal expected, objectKey witness]
  | .review criterion => tagged "review-expectation" #[name criterion]
  | .check validator => tagged "check-expectation" #[name validator]

private def coverage : Coverage → Json
  | .subject => tagged "coverage" #[Json.str "subject"]
  | .dependencyClosure => tagged "coverage" #[Json.str "dependency-closure"]

def requirement (value : Requirement) : Json :=
  tagged "requirement" #[requirementKey value.key, expectation value.expected,
    coverage value.coverage, toJson value.scope, Json.arr (value.prerequisites.map requirementKey)]

def bindingInput (value : BindingInput) : Json :=
  tagged "binding-input" #[subject value.subject, name value.name, Json.str value.content]

end Informal.Validation.BindingEncoding
