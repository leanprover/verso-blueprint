/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean.Data.Lsp.Utf16

/-! Experimental source projection for external language analysis. -/
namespace Rosetta
open Lean

/-- Rejects positions beyond a line or inside a UTF-16 surrogate pair.
CRLF is one line terminator; neither terminator code unit is source content. -/
def byteOffset? (text : String) (pos : Lsp.Position) : Option Nat := Id.run do
  let lines := text.splitOn "\n" |>.toArray
  let some line := lines[pos.line]? | return none
  let content := if pos.line + 1 < lines.size then
      (line.dropSuffix "\r").copy else line
  let base := (lines.extract 0 pos.line).foldl (fun n s => n + s.utf8ByteSize + 1) 0
  let mut col := 0
  let mut offset := base
  for c in content.toList do
    if col == pos.character then return some offset
    col := col + c.utf16Size.toNat
    offset := offset + c.utf8Size
  return if col == pos.character then some offset else none

def byteRange? (text : String) (range : Lsp.Range) : Option (Nat × Nat) := do
  let start ← byteOffset? text range.start
  let stop ← byteOffset? text range.end
  guard (start ≤ stop)
  return (start, stop)

structure SourceRange where
  uri : String
  source : String
  range : Lsp.Range
deriving Inhabited

/-- Each mapped piece is an exact source slice. Deindentation can be represented
by one piece per line; wrappers are ordinary unmapped pieces. -/
inductive Piece where
  | generated (text : String)
  | source (location : SourceRange)

private structure Segment where
  start : Nat
  stop : Nat
  origin? : Option (SourceRange × Nat)

structure Projection where
  text : String
  private segments : Array Segment

def compose (pieces : Array Piece) : Except String Projection := do
  let mut text := ""
  let mut segments := #[]
  for piece in pieces do
    let (content, origin?) ← match piece with
      | .generated generated => pure (generated, none)
      | .source loc => do
        let some (start, stop) := byteRange? loc.source loc.range
          | throw s!"invalid source range in {loc.uri}"
        pure ((String.Pos.Raw.extract loc.source ⟨start⟩ ⟨stop⟩), some (loc, start))
    if content.isEmpty && origin?.isNone then continue
    segments := segments.push {
      start := text.utf8ByteSize
      stop := text.utf8ByteSize + content.utf8ByteSize
      origin? }
    text := text ++ content
  return { text, segments }

structure MappedRange where
  locations : Array SourceRange := #[]
  containsGenerated : Bool := false

/-- Split a range at projection boundaries instead of fabricating one source
location. Empty ranges belong to the following segment, or the last at EOF. -/
def Projection.mapRange (projection : Projection) (range : Lsp.Range) :
    Except String MappedRange := do
  let some (start, stop) := byteRange? projection.text range
    | throw "invalid analysis range"
  let pointIndex? := if start == stop then
      projection.segments.findIdx? (fun segment => segment.start ≤ start && start < segment.stop) <|>
        (if start == projection.text.utf8ByteSize && !projection.segments.isEmpty then
          some (projection.segments.size - 1) else none)
    else none
  let mut result : MappedRange := {}
  for (segment, index) in projection.segments.zipIdx do
    let ownsPoint := pointIndex? == some index
    let left := max start segment.start
    let right := min stop segment.stop
    if left < right || ownsPoint then
      match segment.origin? with
      | none => result := { result with containsGenerated := true }
      | some (origin, sourceStart) =>
        let fileMap := FileMap.ofString origin.source
        let range : Lsp.Range := {
          start := fileMap.utf8PosToLspPos ⟨sourceStart + left - segment.start⟩
          «end» := fileMap.utf8PosToLspPos ⟨sourceStart + right - segment.start⟩ }
        result := { result with locations := result.locations.push { origin with range } }
  return result

end Rosetta
