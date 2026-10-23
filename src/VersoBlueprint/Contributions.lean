/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Data

/-! Identified external-declaration and priority contributions. This pure core
retains complete evidence and is used by registration and import assembly.
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
  deriving DecidableEq, Hashable, Repr

/-- Complete evidence for the external-association/priority slice. Body, kind and
markup contributions remain in the existing assembly policy. -/
structure Record where
  id : ContributionId
  label : Label
  /-- Statement-facet associations, including attribute attachments. -/
  references : Array ExternalRef := #[]
  /-- Proof-facet associations; the facet survives collection and projection. -/
  proofReferences : Array ExternalRef := #[]
  priority : Option String
  source : Option SourceLocation
  deriving DecidableEq, Repr

/-- Both facets establish normal node membership; neither is descriptive-only. -/
def Record.allReferences (r : Record) : Array ExternalRef :=
  r.references ++ r.proofReferences

def EvidenceEq (xs ys : List Record) : Prop := ∀ r, r ∈ xs ↔ r ∈ ys

def Collision (rs : List Record) (id : ContributionId) : Prop :=
  ∃ a ∈ rs, ∃ b ∈ rs, a.id = id ∧ b.id = id ∧ a ≠ b

def RelevantCollision (rs : List Record) (label : Label) (id : ContributionId) : Prop :=
  Collision rs id ∧ ∃ r ∈ rs, r.id = id ∧ r.label = label

def NoCollision (rs : List Record) (label : Label) : Prop :=
  ∀ id, ¬ RelevantCollision rs label id

def Association (rs : List Record) (label : Label) (decl : Name) : Prop :=
  ∃ r ∈ rs, r.label = label ∧ ∃ ref ∈ r.allReferences.toList,
    ref.present = true ∧ ref.canonical.eraseMacroScopes = decl

/-- Every selected external observation has a stable one-pass erased declaration key.
Both facets and missing references are checked; this is not an assumption about
Lean's name-resolution APIs or arbitrary `Name` values. -/
def StableReferences (rs : List Record) (label : Label) : Prop :=
  ∀ record ∈ rs, record.label = label → ∀ ref ∈ record.allReferences,
    ref.canonical.eraseMacroScopes.eraseMacroScopes = ref.canonical.eraseMacroScopes

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

/-- A bucket conflicts exactly when some record differs from its first record.
Exact replay is harmless; compare full records, including both facets and provenance. -/
def bucketConflicts : List Record → Bool
  | [] => false
  | first :: rest => rest.any fun record => decide (record ≠ first)

/-- Index the complete evidence once, then inspect only this label's identities.
Buckets retain other labels' records so cross-label identity collisions remain visible.
Do not decide the existential `Collision` specification: that searches all record pairs. -/
def collisionIds (label : Label) (rs : List Record) : List ContributionId :=
  let buckets := rs.groupByKey (·.id)
  let ids := ((rs.filter fun r => decide (r.label = label)).map (·.id)).eraseDups
  ids.filter fun id => bucketConflicts (buckets.getD id [])

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
    (r.allReferences.toList.filterMap fun ref =>
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
