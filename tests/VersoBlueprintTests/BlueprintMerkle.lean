/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Util.Merkle

/-! Controls for deterministic graph hashing. Payloads and edges below are
synthetic strings; no proof or validation status is asserted.
-/

namespace VersoBlueprintTests.BlueprintMerkle

private abbrev Digests := Std.HashMap String String
private abbrev EdgeMap := Std.HashMap String (Array String)

private def mapOfList {β} (entries : List (String × β)) : Std.HashMap String β :=
  entries.foldl (fun map (key, value) => map.insert key value) {}

private def runGraph (vertices : Array String) (payloads : Digests) (edges : EdgeMap)
    (known : Digests := {}) : Except String Digests :=
  Informal.Merkle.graph vertices id (fun vertex => payloads.getD vertex "")
    (fun vertex => edges.getD vertex #[]) known

private def expect (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error message => throw <| IO.userError message

private def ensure (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def sameOn (left right : Digests) (vertices : Array String) : Bool :=
  vertices.all fun vertex => left[vertex]? == right[vertex]?

#eval show IO Unit from do
  let vertices := #["A", "B", "C", "D", "unrelated"]
  let payloads := mapOfList [
    ("A", "payload-A"), ("B", "payload-B"), ("C", "payload-C"),
    ("D", "payload-D"), ("unrelated", "payload-unrelated")]
  let edges := mapOfList [
    ("A", #["B", "C"]), ("B", #["D"]), ("C", #["D"]),
    ("D", #[]), ("unrelated", #[])]
  let first ← expect (runGraph vertices payloads edges)
  let reorderedEdges := mapOfList [
    ("unrelated", #[]), ("D", #[]), ("C", #["D", "D"]),
    ("B", #["D", "D"]), ("A", #["C", "B", "C"])]
  let reordered ← expect (runGraph #["unrelated", "D", "C", "B", "A", "A"]
    payloads reorderedEdges)
  ensure (sameOn first reordered vertices)
    "Vertex order, edge order and repeated edges must not change digests"

  let changedPayloads := payloads.insert "D" "changed payload-D"
  let changed ← expect (runGraph vertices changedPayloads edges)
  ensure (first["D"]? != changed["D"]? && first["B"]? != changed["B"]? &&
      first["C"]? != changed["C"]? && first["A"]? != changed["A"]?)
    "A prerequisite payload change must propagate to every dependent in the diamond"
  ensure (first["unrelated"]? == changed["unrelated"]?)
    "A prerequisite change must not affect unrelated components"

  let cyclicVertices := #["P", "Q", "self"]
  let cyclicPayloads := mapOfList [("P", "p"), ("Q", "q"), ("self", "s")]
  let cyclicEdges := mapOfList [("P", #["Q"]), ("Q", #["P"]), ("self", #["self"])]
  let cyclic ← expect (runGraph cyclicVertices cyclicPayloads cyclicEdges)
  let cyclicReordered ← expect (runGraph #["self", "Q", "P"] cyclicPayloads
    (mapOfList [("self", #["self", "self"]), ("Q", #["P", "P"]), ("P", #["Q"])]))
  ensure (sameOn cyclic cyclicReordered cyclicVertices)
    "Multi-node and self cycles must be deterministic under input reordering"
  ensure (cyclic["P"]? != cyclic["Q"]?)
    "Members of one cycle must retain their own identities in their final digests"
  let changedCycle ← expect (runGraph cyclicVertices (cyclicPayloads.insert "Q" "changed-q") cyclicEdges)
  ensure (cyclic["P"]? != changedCycle["P"]? && cyclic["Q"]? != changedCycle["Q"]? &&
      cyclic["self"]? == changedCycle["self"]?)
    "A cycle payload change must propagate within its component, not to another component"

  let terminalDigest := Informal.SHA256.text "known immutable snapshot"
  let withKnown ← expect (runGraph #["root"] (mapOfList [("root", "root payload")])
    (mapOfList [("root", #["terminal"] )]) (mapOfList [("terminal", terminalDigest)]))
  ensure (withKnown["terminal"]? == some terminalDigest && withKnown["root"]?.isSome)
    "Known terminal digests must be retained and linked"
  let otherTerminalDigest := Informal.SHA256.text "different immutable snapshot"
  let changedKnown ← expect (runGraph #["root"] (mapOfList [("root", "root payload")])
    (mapOfList [("root", #["terminal"] )]) (mapOfList [("terminal", otherTerminalDigest)]))
  ensure (withKnown["root"]? != changedKnown["root"]?)
    "A changed known terminal digest must change its dependent"

  match runGraph #["root"] (mapOfList [("root", "payload")])
      (mapOfList [("root", #["missing"])]) with
  | .error message =>
    ensure (message.contains "Missing Merkle graph successor")
      "Missing graph successors must return a specific error"
  | .ok _ => throw <| IO.userError "Missing graph successor was accepted"

  match Informal.Merkle.graph #["A", "B"] (fun _ => "same") (fun _ => "payload")
      (fun _ => #[]) with
  | .error message =>
    ensure (message.contains "Distinct Merkle vertices share identity")
      "Identity collisions must return a specific error"
  | .ok _ => throw <| IO.userError "Duplicate vertex identities were accepted"

  match runGraph #["terminal"] (mapOfList [("terminal", "new payload")])
      (mapOfList [("terminal", #[])]) (mapOfList [("terminal", "old digest")]) with
  | .error message =>
    ensure (message.contains "both unknown and already known")
      "A known terminal cannot be silently recomputed as unknown"
  | .ok _ => throw <| IO.userError "Known and unknown vertex overlap was accepted"

end VersoBlueprintTests.BlueprintMerkle
