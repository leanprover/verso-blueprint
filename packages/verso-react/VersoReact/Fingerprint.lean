/- Copyright (c) 2026 Lean FRO LLC. Released under Apache 2.0 license.
Author: Emilio J. Gallego Arias -/
module

public import VersoManual.Basic

public section

namespace VersoReact.Fingerprint

open Verso

/-- Existing document values, not a serialized document or a new wire format. -/
abbrev Value := Doc.Block Genre.Manual ⊕ Array (Doc.Inline Genre.Manual)

private partial def blockHash : Doc.Block Genre.Manual → UInt64
  | .para content => mixHash 101 (hash content)
  | .code text => mixHash 103 (hash text)
  | .ul items => mixHash 107 <| items.foldl (init := 7) fun acc item =>
      mixHash acc (blocksHash item.contents)
  | .ol start items => mixHash 109 <| mixHash (hash start) <|
      items.foldl (init := 7) fun acc item => mixHash acc (blocksHash item.contents)
  | .dl items => mixHash 113 <| items.foldl (init := 7) fun acc item =>
      mixHash acc (mixHash (hash item.term) (blocksHash item.desc))
  | .blockquote content => mixHash 127 (blocksHash content)
  | .concat content => mixHash 131 (blocksHash content)
  | .other extension content => mixHash 137 (mixHash (hash extension) (blocksHash content))
where
  blocksHash (content : Array (Doc.Block Genre.Manual)) : UInt64 :=
    content.foldl (init := 7) fun acc block => mixHash acc (blockHash block)

/-- Structural hash: constructors, ordered children and complete extension data.
Equal values must hash equally; equal hashes are never evidence of equality.
This is a session-local accelerator, not a persistent or cryptographic digest. -/
def contentHash : Value → UInt64
  | .inl block => mixHash 139 (blockHash block)
  | .inr title => mixHash 149 (hash title)

/-- Full serialized-content key for callers that do not retain identity state. -/
def canonicalKey : Value → String
  | .inl block => (Lean.toJson block).compress
  | .inr title => (Lean.toJson title).compress

/-- Only the current document's distinct fingerprinted values are retained.
The monotonically increasing counter prevents retired IDs from being reused.
Keep this state per mounted preview, and advance it as part of React state. -/
structure State where
  private buckets : Std.HashMap UInt64 (Array (Value × Nat)) := {}
  private nextId : Nat := 0
  deriving Inhabited

private def findId? (entries : Array (Value × Nat)) (value : Value) : Option Nat :=
  entries.findSome? fun (prior, id) => if prior == value then some id else none

/-- Pure transition. Hash collisions use exact typed equality, including when
the two colliding values only appear in different updates. Duplicate contents
share a token; the renderer separately disambiguates sibling occurrences.
The optional hasher is for collision tests; use one hasher consistently. -/
def State.advance (previous : State) (values : Array Value)
    (fingerprint : Value → UInt64 := contentHash) : State := Id.run do
  let mut current : State := { nextId := previous.nextId }
  for value in values do
    let bucket := fingerprint value
    let entries := current.buckets.getD bucket #[]
    if (findId? entries value).isSome then continue
    let id := (findId? (previous.buckets.getD bucket #[]) value).getD current.nextId
    current := {
      buckets := current.buckets.insert bucket (entries.push (value, id))
      nextId := max current.nextId (id + 1)
    }
  return current

/-- Look up a value in the state prepared for the current document. -/
def State.key? (state : State) (value : Value)
    (fingerprint : Value → UInt64 := contentHash) : Option String :=
  (findId? (state.buckets.getD (fingerprint value) #[]) value).map fun id => s!"token:{id}"

/-- Missing values indicate that the caller supplied another document's state. -/
def State.key (state : State) (value : Value) : String :=
  match state.key? value with
  | some key => key
  | none => panic! "VersoReact: fingerprint state does not contain this document value"

/-- Useful for bounded-retention tests; removed contents are not kept in history. -/
def State.size (state : State) : Nat :=
  state.buckets.fold (init := 0) fun count _ entries => count + entries.size

end VersoReact.Fingerprint
