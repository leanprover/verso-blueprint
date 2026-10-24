/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Data
import VersoBlueprint.SourceData

/-! Structural raw-input controls, not provider/checker success. Native snapshots
below are explicit synthetic metadata. No proof, test or review is certified by
these constructors or diagnostics; the complete registration/capture boundary
still owns producer collision/import/admission and current native checking. -/

open Lean Informal Realizations SourceData

-- Canonical concept metadata has no language source slots or completion setter.
#check_failure (fun (node : Realizations.Node) => node.statement)
#check_failure (fun (node : Realizations.Node) => node.externalRefs)
#check_failure (fun (node : Realizations.Node) => node.complete)

namespace VersoBlueprintTests.BlueprintCanonicalSources

private def ensure (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def has (issues : Array Diagnostic) (code : String) : Bool := issues.any (·.code == code)

private def node := `canonicalExample
private def context : Context := ⟨`lean, `canonicalProject⟩
private def key : RealizationKey := ⟨node, `implementation⟩
private def document : DocumentKey := ⟨context, "Canonical.lean"⟩
private def model : Realization := {
  key, context
  facets := #[{ name := `statement, documents := #[document] }, { name := `proof }] }

#eval show IO Unit from do
  let metadata : Data.NodeMetadata := {
    kind := .theorem, kindIsExplicit := true, count := 7
    parent := some `home, priority := some "high", owner := some `author
    tags := #["first", "second"], effort := some "small"
    prUrl := some "https://example.invalid/pr", issueUrl := some "https://example.invalid/issue" }
  let registered : Data.Node := { toNodeMetadata := metadata }
  let concept := registered.toConcept node "Canonical concept"
  ensure (concept.toNodeMetadata == metadata && concept.label == node && concept.title == "Canonical concept")
    "The pure node must retain the same accepted metadata projection, including every shared field"

#eval show IO Unit from do
  let source : FacetSource := {
    destination := ⟨key, `statement⟩, context, document
    source := Data.SourceLocationResult.unavailable "Structural fixture has no source lookup"
    payload := .prose { stx := .missing } }
  ensure ((source.issues node model).isEmpty) "An explicitly unavailable location is retained, not fabricated"
  ensure (has (({ source with context := ⟨`lean, `otherProject⟩ } : FacetSource).issues node model)
    "source-context-mismatch") "A same-spelled declaration from another project is not this source"
  ensure (has (({ source with document := { document with context := ⟨`rocq, `canonicalProject⟩ } } : FacetSource).issues node model)
    "source-document-context") "Document ownership cannot disagree with the source context"
  ensure (has (({ source with destination := ⟨⟨`otherNode, key.name⟩, `statement⟩ } : FacetSource).issues node model)
    "source-destination-mismatch") "Facet sources cannot leak across concept identity"
  ensure (has (({ source with destination := ⟨key, `missing⟩ } : FacetSource).issues node model)
    "unknown-source-facet") "Missing facets remain explicit"
  ensure (has (source.issues node { model with facets := #[{ name := `statement }] })
    "source-document-membership") "Composed definitions cannot discard a source document"
  ensure (has (({ source with source := { ok := true } } : FacetSource).issues node model)
    "invalid-source-location") "Source presence without a location is not a valid source result"
  let rocq : Context := ⟨`rocq, context.project⟩
  let rocqDocument : DocumentKey := ⟨rocq, "Flag.v"⟩
  let foreign : FacetSource := { source with
    context := rocq, document := rocqDocument
    payload := .text "Module::symbol.with-dot»name is original foreign text" }
  let foreignModel := { model with context := rocq, facets := #[{ name := `statement, documents := #[rocqDocument] }] }
  ensure ((foreign.issues node foreignModel).isEmpty) "Foreign spelling requires no Lean name interpretation"
  let .text raw := foreign.payload | throw <| IO.userError "Foreign payload changed kind"
  ensure (raw == "Module::symbol.with-dot»name is original foreign text") "Original foreign bytes must remain intact"
  ensure (has (({ foreign with payload := .leanInline default } : FacetSource).issues node foreignModel)
    "source-payload-context") "Compiled Lean payload cannot be relabeled as foreign code"

#eval show IO Unit from do
  let association : NativeAssociation := {
    realization := key, context, facets := #[`statement, `proof]
    reference := { Data.ExternalRef.ofName `SyntheticNative with present := false } }
  ensure ((association.issues node model).isEmpty && !association.reference.present)
    "Raw missing native associations remain discoverable; this is no successful declaration lookup"
  ensure (has (({ association with facets := #[] } : NativeAssociation).issues node model) "empty-native-facets")
    "Empty native selection has no implicit all-facet meaning"
  ensure (has (({ association with facets := #[`statement, `statement] } : NativeAssociation).issues node model)
    "duplicate-native-facet") "Duplicate destinations must reject explicitly"
  ensure (has (({ association with facets := #[`missing] } : NativeAssociation).issues node model) "unknown-native-facet")
    "Unknown native destinations cannot create facets"
  ensure (has (({ association with realization := ⟨`sibling, key.name⟩ } : NativeAssociation).issues node model)
    "source-destination-mismatch") "Native associations must retain their enclosing concept"
  let foreignContext : Context := ⟨`rust, context.project⟩
  ensure (has (({ association with context := foreignContext } : NativeAssociation).issues node
    { model with context := foreignContext }) "wrong-native-context") "Foreign identity never enters Lean association handling"
  -- Retain the original typed Name, including metadata requiring the later
  -- selected-name admission gate. These structural checks do not replace #499.
  let internal := Name.str `SyntheticNative "bad»name"
  let retained := { association with reference := { association.reference with canonical := internal } }
  ensure ((retained.issues node model).isEmpty && retained.reference.canonical == internal)
    "Raw native identity must not be normalized by source construction; name admission remains separate"

#eval show IO Unit from do
  let shared : UseDeclaration := {
    node, facet := `proof, reference := { label := `unfinishedTarget, origin := .manual, intent := .technical } }
  ensure ((shared.issues node #[]).isEmpty) "Shared constraints do not invent a realization selection"
  let inferred := { shared with realization := some key.name, reference := { shared.reference with origin := .automatic } }
  ensure ((inferred.issues node #[model]).isEmpty && inferred.reference.intent == .technical)
    "Realization scope is explicit and independent of manual/automatic metadata"
  let manualScoped := { inferred with reference := { inferred.reference with origin := .manual } }
  ensure ((manualScoped.issues node #[model, model]).isEmpty) "Exact model replay creates no selection ambiguity"
  ensure (has (inferred.issues node #[]) "missing-use-realization") "Missing source realization remains diagnostic"
  ensure (has (inferred.issues node #[model, { model with context := ⟨`lean, `otherProject⟩ }]) "ambiguous-use-realization")
    "Competing realization contexts cannot select a winner"
  ensure (has (({ inferred with facet := `missing } : UseDeclaration).issues node #[model]) "unknown-use-facet")
    "A scoped edge must name a real facet"
  ensure (has (({ shared with node := `sibling } : UseDeclaration).issues node #[model]) "use-destination-mismatch")
    "Use scope cannot leak across concepts"
  ensure (shared.reference.label == inferred.reference.label && shared.facet == inferred.facet)
    "Source validation preserves the original unresolved target and axis"

end VersoBlueprintTests.BlueprintCanonicalSources
