/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Init
public import Lean.Util.SCC
public import VersoBlueprint.Util.SHA256

/-! A deterministic Merkle digest for a finite directed graph.

Edges point from a vertex to its prerequisites. Strongly connected components
are hashed as units, in prerequisite-first order. Internal edges name their
target identity, avoiding recursive hashes; external edges include the target
identity and digest. The output is content-oriented: duplicate vertices/edges
and input ordering do not affect it.

The caller supplies the complete reachable unknown graph. `known` contains
terminal vertices already hashed from the same immutable snapshot; their
outgoing edges are intentionally not traversed. SHA-256 collision resistance is
an assumption here, not a proved security property.
-/

namespace Informal.Merkle

private def uniqueArray [BEq α] [Hashable α] (values : Array α) : Array α := Id.run do
  let mut seen : Std.HashMap α Unit := {}
  let mut result := #[]
  for value in values do
    unless seen.contains value do
      seen := seen.insert value ()
      result := result.push value
  return result

private def duplicateIdentityError (identity : String) : String :=
  s!"Distinct Merkle vertices share identity '{identity}'"

/-- Compute content digests for all supplied unknown vertices and retain the
known terminal digests in the result.

The graph must contain every reachable unknown successor; an edge may instead
end at a key in `known`. Identities must be unique across both maps and the
unknown vertex array. Supplying a known key again as an unknown vertex is an
error, so cached values cannot silently override newly supplied content.
-/
public def graph [BEq α] [Hashable α]
    (vertices : Array α)
    (identity : α → String)
    (payload : α → String)
    (edges : α → Array α)
    (known : Std.HashMap α String := {}) : Except String (Std.HashMap α String) := do
  let vertices := uniqueArray vertices
  let mut identityOwners : Std.HashMap String α := {}
  let knownEntries := known.toArray.qsort fun a b => identity a.1 < identity b.1
  for (vertex, _) in knownEntries do
    let key := identity vertex
    match identityOwners[key]? with
    | some previous =>
      if previous != vertex then throw (duplicateIdentityError key)
    | none => identityOwners := identityOwners.insert key vertex
  for vertex in vertices do
    if known.contains vertex then
      throw s!"Merkle vertex '{identity vertex}' is both unknown and already known"
    let key := identity vertex
    match identityOwners[key]? with
    | some previous =>
      if previous != vertex then throw (duplicateIdentityError key)
    | none => identityOwners := identityOwners.insert key vertex

  let mut vertexSet : Std.HashMap α Unit := {}
  for vertex in vertices do
    vertexSet := vertexSet.insert vertex ()

  let mut successors : Std.HashMap α (Array α) := {}
  for vertex in vertices do
    let targets := uniqueArray (edges vertex)
    for target in targets do
      unless vertexSet.contains target || known.contains target do
        throw s!"Missing Merkle graph successor '{identity target}' from '{identity vertex}'"
    successors := successors.insert vertex <|
      targets.filter vertexSet.contains

  -- Lean.SCC uses Tarjan's algorithm and returns SCCs in dependency-first
  -- order for this source-to-prerequisite edge orientation.
  let components := Lean.SCC.scc vertices.toList
    (fun vertex => (successors.getD vertex #[]).toList)
  let mut result := known
  for component in components do
    let componentVertices := uniqueArray component.toArray
    let mut componentSet : Std.HashMap α Unit := {}
    for vertex in componentVertices do
      componentSet := componentSet.insert vertex ()
    let componentVertices := componentVertices.qsort fun a b => identity a < identity b
    let mut records : Array (String × String) := #[]
    for vertex in componentVertices do
      let targets := (uniqueArray (edges vertex)).qsort fun a b => identity a < identity b
      let mut edgeDigests := #[]
      for target in targets do
        let edgeDigest ← if componentSet.contains target then
          pure <| SHA256.tagged "vbp-merkle-internal-edge-v1" #[identity target]
        else match result[target]? with
          | some targetDigest =>
            pure <| SHA256.tagged "vbp-merkle-external-edge-v1" #[identity target, targetDigest]
          | none =>
            throw s!"Merkle component order is not prerequisite-first at '{identity vertex}' → '{identity target}'"
        edgeDigests := edgeDigests.push edgeDigest
      let recordDigest := SHA256.tagged "vbp-merkle-node-record-v1"
        <| #[identity vertex, payload vertex] ++ edgeDigests
      records := records.push (identity vertex, recordDigest)
    let componentDigest := SHA256.tagged "vbp-merkle-component-v1"
      (records.flatMap fun (nodeIdentity, recordDigest) => #[nodeIdentity, recordDigest])
    for vertex in componentVertices do
      result := result.insert vertex <|
        SHA256.tagged "vbp-merkle-member-v1" #[identity vertex, componentDigest]
  return result

end Informal.Merkle
