/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
module

public import VersoBlueprint.Data

public section

/-! Identified external-declaration and priority contributions. This pure core
retains complete evidence; producer/import adoption is a separate integration.
Body, kind, other metadata and rendered-resource policies remain outside it. -/

open Lean Informal.Data
namespace Informal.Contributions

/-- Immutable producer-site identity, preserved through import replay. -/
structure ContributionId where
  moduleName : Name
  producer : Name
  subject : Name
  site : Nat -- UTF-8 source offset, or caller-supplied stable synthetic site
  slot : Nat -- stable ordinal within this producer-site expansion
  deriving DecidableEq, Repr

/-- Complete evidence for the external-association/priority slice. Body, kind and
markup contributions remain in the existing assembly policy. -/
structure Record where
  id : ContributionId
  label : Label
  references : Array ExternalRef
  priority : Option String
  source : Option SourceLocation
  deriving DecidableEq, Repr

-- Native source order remains observable even though evidence is extensional.
def Record.sourceOrder (r : Record) : Name × Nat × Nat :=
  (r.id.moduleName, r.id.site, r.id.slot)

@[expose] def Record.toNodeContribution (r : Record) : NodeContribution := {
  leanCode := #[.external r.references]
  priority := r.priority
}

def EvidenceEq (xs ys : List Record) : Prop := ∀ r, r ∈ xs ↔ r ∈ ys

@[expose] def Collision (rs : List Record) (id : ContributionId) : Prop :=
  ∃ a ∈ rs, ∃ b ∈ rs, a.id = id ∧ b.id = id ∧ a ≠ b

@[expose] def RelevantCollision (rs : List Record) (label : Label) (id : ContributionId) : Prop :=
  Collision rs id ∧ ∃ r ∈ rs, r.id = id ∧ r.label = label

def NoCollision (rs : List Record) (label : Label) : Prop :=
  ∀ id, ¬ RelevantCollision rs label id

def Association (rs : List Record) (label : Label) (decl : Name) : Prop :=
  ∃ r ∈ rs, r.label = label ∧ ∃ ref ∈ r.references.toList,
    ref.present = true ∧ ref.canonical.eraseMacroScopes = decl

def Priority (rs : List Record) (label : Label) (value : String) : Prop :=
  ∃ r ∈ rs, r.label = label ∧ r.priority = some value

def PriorityDisagreement (rs : List Record) (label : Label) : Prop :=
  ∃ a b, Priority rs label a ∧ Priority rs label b ∧ a ≠ b

-- A map or another concrete collector can implement this interface. No assumed laws.
structure Collector (σ : Type) where
  empty : σ
  insert : Record → σ → σ
  records : σ → List Record

def Collector.extend (c : Collector σ) (state : σ) (rs : List Record) : σ :=
  rs.foldl (fun s r => c.insert r s) state

def Collector.collect (c : Collector σ) (rs : List Record) : σ := c.extend c.empty rs

def Collector.batches (c : Collector σ) (state : σ) (bs : List (List Record)) : σ :=
  bs.foldl (fun s rs => c.extend s rs) state

structure View where
  declarations : List Name
  priority : Option String
  supports : List Record
  deriving DecidableEq, Repr

-- Bucket membership is extensional; all distinct variants/supports are retained.
structure Diagnostics where
  collisions : List (ContributionId × List Record)
  priorityConflict : List (String × List Record)
  deriving DecidableEq, Repr

def Diagnostics.hasCollision (d : Diagnostics) (id : ContributionId) : Prop :=
  ∃ bucket, (id, bucket) ∈ d.collisions

def Diagnostics.collisionSupport (d : Diagnostics) (id : ContributionId) (r : Record) : Prop :=
  ∃ bucket, (id, bucket) ∈ d.collisions ∧ r ∈ bucket

def Diagnostics.hasPriority (d : Diagnostics) (v : String) : Prop :=
  ∃ bucket, (v, bucket) ∈ d.priorityConflict

def Diagnostics.prioritySupport (d : Diagnostics) (v : String) (r : Record) : Prop :=
  ∃ bucket, (v, bucket) ∈ d.priorityConflict ∧ r ∈ bucket

def View.Equivalent (v w : View) : Prop :=
  (∀ d, d ∈ v.declarations ↔ d ∈ w.declarations) ∧
  v.priority = w.priority ∧ EvidenceEq v.supports w.supports

def Diagnostics.Equivalent (d e : Diagnostics) : Prop :=
  (∀ i, d.hasCollision i ↔ e.hasCollision i) ∧
  (∀ i r, d.collisionSupport i r ↔ e.collisionSupport i r) ∧
  (∀ v, d.hasPriority v ↔ e.hasPriority v) ∧
  (∀ v r, d.prioritySupport v r ↔ e.prioritySupport v r)

def OutcomeEq : Except Diagnostics View → Except Diagnostics View → Prop
  | .ok v, .ok w => v.Equivalent w
  | .error d, .error e => d.Equivalent e
  | _, _ => False

abbrev Resolver := Label → List Record → Except Diagnostics View

/-- Full-record union: replay is ignored, identity collisions retain all variants. -/
def insert (record : Record) (records : List Record) : List Record :=
  if record ∈ records then records else record :: records

def collector : Collector (List Record) := ⟨[], insert, id⟩

instance (rs : List Record) (id : ContributionId) : Decidable (Collision rs id) := by
  unfold Collision
  infer_instance

instance (rs : List Record) (label : Label) (id : ContributionId) :
    Decidable (RelevantCollision rs label id) := by
  unfold RelevantCollision
  infer_instance

/-- Source records are preserved; list ordering is not semantic ordering. -/
def recordsFor (label : Label) (rs : List Record) : List Record :=
  (rs.filter fun r => decide (r.label = label)).eraseDups

def variants (rs : List Record) (id : ContributionId) : List Record :=
  (rs.filter fun r => decide (r.id = id)).eraseDups

def priorityValues (label : Label) (rs : List Record) : List String :=
  ((recordsFor label rs).filterMap (·.priority)).eraseDups

def priorityDisagrees (label : Label) (rs : List Record) : Bool :=
  let values := priorityValues label rs
  values.any fun a => values.any fun b => decide (a ≠ b)

def collisionIds (label : Label) (rs : List Record) : List ContributionId :=
  (rs.map (·.id)).eraseDups.filter fun id => decide (RelevantCollision rs label id)

def diagnostics (label : Label) (rs : List Record) : Diagnostics := {
  collisions := (collisionIds label rs).map fun id => (id, variants rs id)
  priorityConflict := if priorityDisagrees label rs then
    (priorityValues label rs).map fun v =>
      (v, (recordsFor label rs).filter fun r => decide (r.priority = some v))
    else []
}

/-- Candidate projection. Only `resolve` validates identity and priority agreement
before admitting this data as an accepted result. -/
def view (label : Label) (rs : List Record) : View := {
  declarations := ((recordsFor label rs).flatMap fun r =>
    (r.references.toList.filterMap fun ref =>
      if ref.present then some ref.canonical.eraseMacroScopes else none)).eraseDups
  priority := (priorityValues label rs).head?
  supports := recordsFor label rs
}

/-- Resolve only when both identity and scalar evidence agree. Diagnostics report
both kinds of conflict together; a rejected label has no partially accepted view. -/
def resolve (label : Label) (rs : List Record) : Except Diagnostics View :=
  if (collisionIds label rs).isEmpty && !priorityDisagrees label rs then
    .ok (view label rs)
  else .error (diagnostics label rs)

end Informal.Contributions
