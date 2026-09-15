/- Copyright (c) 2026 Lean FRO LLC. Released under Apache 2.0 license.
Author: Emilio J. Gallego Arias -/
module
public import VersoReact.Fingerprint
meta import VersoReact.Fingerprint

public section
namespace VersoReactTests.Fingerprint
open Verso VersoReact.Fingerprint

private def paragraph (text : String) : Value := .inl (.para #[.text text])

/-- All hashes collide. Covers duplicate contents, reordering, insertion,
deletion, replacement without coexistence, retirement, and independent sessions. -/
def collisionChecks : Bool := Id.run do
  let collide := fun (_ : Value) => (0 : UInt64)
  let a := paragraph "A"
  let b := paragraph "B"
  let c := paragraph "C"
  let first := (default : State).advance #[a, b, a] collide
  let second := first.advance #[c, b, a, a] collide
  let third := second.advance #[b] collide
  let replacement := third.advance #[a] collide
  let empty := replacement.advance #[] collide
  let reinserted := empty.advance #[a] collide
  let key := fun state value => State.key? state value collide
  return first.size == 2 && second.size == 3 && third.size == 1 && empty.size == 0 &&
    key first a != key first b &&
    key first a == key second a && key first b == key second b &&
    key second c != key second a && key second c != key second b &&
    key third b == key second b && (key third a).isNone &&
    key replacement a != key third b && key replacement a != key first a &&
    key reinserted a != key replacement a &&
    key ((default : State).advance #[a] collide) a == some "token:0"

private def corpus : Array Value :=
  let p : Doc.Block Genre.Manual := .para #[.text "α", .linebreak "\n", .code "c",
    .emph #[.text "e"], .bold #[.text "b"], .math .inline "x", .math .display "y",
    .link #[.text "l"] "url", .footnote "n" #[.text "f"], .image "a" "src",
    .concat #[], .other { name := `Test.inline, data := Lean.Json.mkObj [("x", .bool true)] } #[]]
  #[.inl p, .inl (.code "α\"\n"), .inl (.ul #[.mk #[p]]), .inl (.ol 3 #[.mk #[p]]),
    .inl (.dl #[.mk #[.text "term"] #[p]]), .inl (.blockquote #[p]), .inl (.concat #[p]),
    .inl (.other { name := `Test.block, data := .arr #[.null, .str "data"] } #[p]),
    .inr #[.text "Section"], .inr #[]]

def structuralChecks : Bool := Id.run do
  let values := corpus
  -- Equal decoded copies must have the same structural fingerprint.
  for value in values do
    let copied : Except String Value := match value with
      | .inl b => Sum.inl <$> Lean.fromJson? (Lean.toJson b)
      | .inr t => Sum.inr <$> Lean.fromJson? (Lean.toJson t)
    match copied with
    | .error _ => return false
    | .ok copy =>
      if copy != value || contentHash copy != contentHash value then return false
  for mask in #[0, 1, 3, 255] do
    let tiny := fun value => contentHash value &&& mask
    let first := (default : State).advance values tiny
    let moved := first.advance values.reverse tiny
    if first.size != values.size || moved.size != values.size then return false
    for value in values do
      if first.key? value tiny != moved.key? value tiny then return false
    for value in values do
      for other in values do
        if (first.key? value tiny == first.key? other tiny) != (value == other) then
          return false
  -- Map insertion order is not content identity; use upstream extensional
  -- equality/hash instances rather than the map's internal tree shape.
  let extension := fun properties data => (Sum.inl (.other
    { name := `Test.properties, properties, data } #[]) : Value)
  let left := extension (({} : Verso.NameMap String).insert `a "A" |>.insert `b "B")
    (Lean.Json.mkObj [("a", .bool true), ("b", .null)])
  let right := extension (({} : Verso.NameMap String).insert `b "B" |>.insert `a "A")
    (Lean.Json.mkObj [("b", .null), ("a", .bool true)])
  if left != right || contentHash left != contentHash right then return false
  let retained := (default : State).advance #[left]
  if retained.key? left != (retained.advance #[right]).key? right then return false
  -- Typed equality intentionally distinguishes representations that the
  -- old JSON printer normalized to the same string.
  let integer := extension {} (.num ⟨1, 0⟩)
  let decimal := extension {} (.num ⟨10, 1⟩)
  if integer == decimal || canonicalKey integer != canonicalKey decimal then return false
  let collide := fun (_ : Value) => (0 : UInt64)
  let first := (default : State).advance #[integer] collide
  if first.key? integer collide == (first.advance #[decimal] collide).key? decimal collide then
    return false
  return true

#guard collisionChecks
#guard structuralChecks
end VersoReactTests.Fingerprint
