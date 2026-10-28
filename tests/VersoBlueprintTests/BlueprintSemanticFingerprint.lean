/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean
import VersoBlueprint.Validation.Semantic
import VersoBlueprint.Translations

/-! Structural Merkle fingerprint controls. These test deterministic structure,
sharing, and checked-environment dependency traversal; fingerprints are not
kernel checks and do not stand in for native proof observations. -/

open Lean Elab Command Informal.Validation.NativeLean

namespace VersoBlueprintTests.BlueprintSemanticFingerprint

private def ensure (condition : Bool) (message : String) : CoreM Unit :=
  unless condition do throwError message

private def sharedTree (depth : Nat) (leaf : Expr) : Expr :=
  match depth with
  | 0 => leaf
  | n + 1 =>
    let child := sharedTree n leaf
    .app (.app (.const `Nat.add []) child) child

private def rebuiltTree (depth : Nat) (leaf : Expr) : Expr :=
  match depth with
  | 0 => leaf
  | n + 1 =>
    .app (.app (.const `Nat.add []) (rebuiltTree n leaf)) (rebuiltTree n leaf)

namespace GraphFixture

def leaf (n : Nat) : Nat := Nat.succ n
def left (n : Nat) : Nat := leaf (Nat.succ n)
def right (n : Nat) : Nat := leaf (Nat.succ (Nat.succ n))
def diamond (n : Nat) : Nat := left n + right n

inductive Token where
  | first
  | wrap (value : Token)

end GraphFixture

run_cmd liftCoreM do
  let openFingerprint := Semantic.fingerprint (.bvar 0)
  let cases : Array (String × Expr × Expr) := #[
    ("bound variable index", .bvar 0, .bvar 1),
    ("free variable identity", .fvar ⟨`left⟩, .fvar ⟨`right⟩),
    ("metavariable identity", .mvar ⟨`left⟩, .mvar ⟨`right⟩),
    ("sort universe", .sort .zero, .sort (.succ .zero)),
    ("constant name", .const `Nat [], .const `Int []),
    ("constant universe level", .const `Nat [.zero], .const `Nat [Level.succ .zero]),
    ("application argument", .app (.const `Nat.succ []) (.bvar 0), .app (.const `Nat.succ []) (.bvar 1)),
    ("lambda binder name", .lam `x (.const `Nat []) (.bvar 0) .default,
      .lam `y (.const `Nat []) (.bvar 0) .default),
    ("lambda binder info", .lam `x (.const `Nat []) (.bvar 0) .default,
      .lam `x (.const `Nat []) (.bvar 0) .implicit),
    ("forall binder info", .forallE `x (.const `Nat []) (.const `True []) .default,
      .forallE `x (.const `Nat []) (.const `True []) .implicit),
    ("let value", .letE `x (.const `Nat []) (.lit (.natVal 1)) (.bvar 0) false,
      .letE `x (.const `Nat []) (.lit (.natVal 2)) (.bvar 0) false),
    ("let dependency flag", .letE `x (.const `Nat []) (.lit (.natVal 1)) (.bvar 0) false,
      .letE `x (.const `Nat []) (.lit (.natVal 1)) (.bvar 0) true),
    ("natural literal", .lit (.natVal 1), .lit (.natVal 2)),
    ("string literal", .lit (.strVal "left"), .lit (.strVal "right")),
    ("projection structure", .proj `Prod 0 (.const `pair []), .proj `Prod 1 (.const `pair [])),
    ("projection type", .proj `Prod 0 (.const `pair []), .proj `Sigma 0 (.const `pair [])),
    ("projection target", .proj `Prod 0 (.const `left []), .proj `Prod 0 (.const `right []))]
  for (label, lhs, rhs) in cases do
    ensure (Semantic.fingerprint lhs != Semantic.fingerprint rhs)
      s!"Fingerprint omitted an expression field: {label}"

  -- Display and Repr both collide for these distinct structured names.
  let nameA := Name.mkSimple "foo.bar»"
  let nameB := Name.str (Name.mkSimple "foo") "bar»"
  ensure (nameA != nameB && reprStr nameA == reprStr nameB) "Name collision control changed"
  ensure (Semantic.fingerprint (.const nameA []) != Semantic.fingerprint (.const nameB []))
    "Semantic fingerprints must preserve structured names"
  let context : Informal.Realizations.Context := ⟨`verso, `nameCollision⟩
  let key : Informal.Realizations.RealizationKey := ⟨`node, `prose⟩
  let document : Informal.Realizations.DocumentKey := ⟨context, "MOCK.md"⟩
  let requirement : Informal.Realizations.RequirementKey := ⟨.realization key, `review⟩
  let makeInput (facet : Name) : Informal.Translations.Input := {
    nodes := #[⟨⟨`node, `MOCK_NAME_TEST, ""⟩, { label := `node, title := "Mock name test" }⟩]
    documents := #[⟨⟨`doc, `MOCK_NAME_TEST, ""⟩, { key := document, text := "MOCK prose" }⟩]
    realizations := #[⟨⟨`realization, `MOCK_NAME_TEST, ""⟩, {
      key, context, facets := #[{ name := facet, documents := #[document] }], required := #[requirement] }⟩]
    requirements := #[⟨⟨`requirement, `MOCK_NAME_TEST, ""⟩, {
      key := requirement, expected := .review `MOCK_REVIEW }⟩] }
  let .ok firstRegistry := Informal.Translations.admit (makeInput nameA)
    | throwError "First name-collision model rejected"
  let .ok secondRegistry := Informal.Translations.admit (makeInput nameB)
    | throwError "Second name-collision model rejected"
  ensure (firstRegistry.bindingFor requirement != secondRegistry.bindingFor requirement)
    "Changed facet identity with the same display text must invalidate the binding"

  let metadataLeft := Expr.mdata (MData.empty.insert `fingerprintTest ("left" : String)) (.const `Nat [])
  let metadataRight := Expr.mdata (MData.empty.insert `fingerprintTest ("right" : String)) (.const `Nat [])
  ensure (Semantic.fingerprint metadataLeft == Semantic.fingerprint metadataRight &&
      Semantic.fingerprint metadataLeft == Semantic.fingerprint (.const `Nat []))
    "Expression metadata must be ignored by structural fingerprints"

  let shared := sharedTree 20 (.const `base [])
  let duplicate := rebuiltTree 8 (.const `base [])
  let sharedSmall := sharedTree 8 (.const `base [])
  ensure (Semantic.fingerprint shared != openFingerprint)
    "Nested application graph unexpectedly collapsed to an unrelated expression"
  ensure (Semantic.fingerprint sharedSmall == Semantic.fingerprint duplicate)
    "Fingerprint must depend on expression structure, not allocation sharing"

  let provider := "semantic-fingerprint-test-provider"
  let session ← Semantic.newSession provider
  let project := `semanticFingerprintProject
  let graphNamespace := Name.str (← getMainModule) "GraphFixture"
  let diamond := Name.str graphNamespace "diamond"
  let tokenType := Name.str graphNamespace "Token"
  let roots := #[
    diamond,
    tokenType,
    Name.str tokenType "first",
    Name.str tokenType "wrap",
    Name.str tokenType "rec"]
  let getContext (session : Semantic.Session) (project : Name) (roots : Array Name) : CoreM String := do
    match ← session.context project roots with
    | .ok digest => pure digest
    | .error diagnostic => throwError s!"Unexpected semantic context error: {repr diagnostic}"

  let first ← getContext session project roots
  ensure (first.utf8ByteSize == 64) "Semantic context must remain a fixed-size digest"
  let firstSizes ← session.sizes
  ensure (firstSizes.1 > 0 && firstSizes.2 >= roots.size)
    "Semantic context did not memoize expression and declaration nodes"
  let repeated ← getContext session project #[diamond]
  let repeatedSizes ← session.sizes
  ensure (repeatedSizes == firstSizes)
    "Repeated root lookup grew the capture-local semantic memo tables"
  let fresh ← Semantic.newSession provider
  ensure ((← getContext fresh project roots) == first)
    "A fresh session over the same checked environment changed the semantic digest"
  let reversedFresh ← Semantic.newSession provider
  ensure ((← getContext reversedFresh project roots.reverse) == first)
    "A fresh traversal with reversed roots changed the semantic digest"
  ensure ((← getContext session `anotherSemanticFingerprintProject roots) != first)
    "Project identity was omitted from the semantic context"
  let differentProvider ← Semantic.newSession "another-semantic-provider"
  ensure ((← getContext differentProvider project roots) != first)
    "Provider identity was omitted from the semantic context"

  let currentEnvironment ← getEnv
  try
    addDecl <| .defnDecl {
      name := `SemanticFingerprintUnrelated
      levelParams := []
      type := mkConst ``Nat
      value := mkNatLit 42
      hints := .abbrev
      safety := .safe }
    match ← session.context project roots with
    | .ok _ => throwError "A semantic session was reused across checked environments"
    | .error diagnostic =>
      ensure (diagnostic.code == "semantic-session-mismatch") "Wrong stale-session diagnostic"
    let newEnvironmentSession ← Semantic.newSession provider
    ensure ((← getContext newEnvironmentSession project roots) == first)
      "An unrelated declaration changed the selected semantic digest"
  finally
    setEnv currentEnvironment
  try
    addDocStringCore diamond "Extension-only test metadata"
    match ← session.context project roots with
    | .ok _ => throwError "A semantic session was reused after extension-only mutation"
    | .error diagnostic =>
      ensure (diagnostic.code == "semantic-session-mismatch") "Wrong extension-session diagnostic"
    let metadataSession ← Semantic.newSession provider
    ensure ((← getContext metadataSession project roots) == first)
      "Unrelated environment metadata changed the semantic digest"
  finally
    setEnv currentEnvironment
  let singletonSession ← Semantic.newSession provider
  ensure ((← getContext singletonSession project #[diamond]) == repeated)
    "Incremental known-terminal hashing differs from a fresh singleton closure"

  let failedSession ← Semantic.newSession provider
  let beforeFailure ← failedSession.sizes
  match ← failedSession.context project #[`Missing.SemanticFingerprintRoot, diamond] with
  | .ok _ => throwError "A missing checked semantic root was accepted"
  | .error diagnostic =>
    ensure (diagnostic.code == "semantic-context-unavailable")
      "Missing checked roots need the ordinary unavailable diagnostic"
  ensure ((← failedSession.sizes) == beforeFailure)
    "Failed semantic graph capture retained partially collected cache entries"
  match ← fresh.context project #[] with
  | .ok _ => throwError "An empty semantic root list was accepted"
  | .error diagnostic =>
    ensure (diagnostic.code == "invalid-semantic-context")
      "Empty root list needs the invalid semantic context diagnostic"

end VersoBlueprintTests.BlueprintSemanticFingerprint
