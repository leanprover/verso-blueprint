/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Data
import VersoBlueprint.SourceData
import VersoBlueprint.Realizations.NativeSource
import VersoBlueprintTests.BlueprintRealizationAdapter.Provider

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
    payload := .text "Structural source fixture" }
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

-- Synthetic metadata only: these controls establish source membership, never
-- native resolution, proof completion or review acceptance.
#eval show IO Unit from do
  let a := `SyntheticNative.a
  let b := `SyntheticNative.b
  let missing := `SyntheticNative.missing
  let object (name : Name) : ObjectKey := ⟨context, name.toString⟩
  let association (name : Name) (facets : Array Name) : NativeAssociation := {
    realization := key, context, facets
    reference := { Data.ExternalRef.ofName name with present := false } }
  let associations := #[association a #[`statement], association b #[`proof],
    association missing #[`statement, `proof], association a #[`proof]]
  let inlineDef := `SyntheticNative.inlineDef
  let inlineTheorem := `SyntheticNative.inlineTheorem
  let source : FacetSource := {
    destination := ⟨key, `proof⟩, context, document
    source := Data.SourceLocationResult.unavailable "Synthetic inline metadata; no source lookup"
    payload := .leanInline {
      stx := .missing
      definedDefs := #[{ name := inlineDef }]
      definedTheorems := #[{ name := inlineTheorem }] } }
  let expected := #[a, b, missing, inlineDef, inlineTheorem]
  let complete : Realization := { model with
    declarations := expected.map (fun name => { object := object name })
    facets := #[
      { name := `statement, documents := #[document], declarations := #[object a, object missing] },
      { name := `proof, documents := #[document], declarations := expected.map object }] }
  ensure (nativeNames associations #[source] == expected)
    "Full native collection preserves registration order and unions external/inline identities once"
  ensure ((nativeMembershipIssues node complete associations #[source]).isEmpty)
    "Missing associations and inline definitions/theorems belong to the exact composed union"
  ensure ((nativeMembershipIssues node complete (associations ++ associations) #[source, source]).isEmpty)
    "Raw replay does not duplicate semantic membership"
  let reordered := { complete with
    declarations := complete.declarations.reverse
    facets := complete.facets.map fun facet => { facet with declarations := facet.declarations.reverse } }
  ensure ((nativeMembershipIssues node reordered associations #[source]).isEmpty)
    "Membership equality is independent of model declaration presentation order"
  let explicitContract := { complete with facets := complete.facets.map fun facet =>
    if facet.name == `statement then
      { facet with required := #[⟨.declaration key (object b), `selectedCheck⟩] }
    else facet }
  ensure ((nativeMembershipIssues node explicitContract associations #[source]).isEmpty)
    "Exact source membership does not restrict an independently explicit requirement on another subject"
  ensure (has (nativeMembershipIssues node
    { complete with declarations := complete.declarations.filter (·.object != object missing) }
    associations #[source]) "native-declaration-membership")
    "Unavailable native references cannot disappear from the realization union"
  ensure (has (nativeMembershipIssues node
    { complete with declarations := complete.declarations.filter (·.object != object inlineDef) }
    associations #[source]) "native-declaration-membership")
    "Inline definitions participate independently of inline theorems"
  ensure (has (nativeMembershipIssues node
    { complete with declarations := complete.declarations.push { object := object `uncollectedSibling } }
    associations #[source]) "native-declaration-membership")
    "An uncollected sibling cannot appear as an association"
  let wrongFacet := { complete with facets := complete.facets.map fun facet =>
    if facet.name == `statement then { facet with declarations := facet.declarations.push (object b) } else facet }
  ensure (has (nativeMembershipIssues node wrongFacet associations #[source]) "native-facet-membership")
    "Realization-wide membership cannot confer membership in another selected facet"
  let omittedInline := { complete with facets := complete.facets.map fun facet =>
    { facet with declarations := facet.declarations.filter (· != object inlineTheorem) } }
  ensure (has (nativeMembershipIssues node omittedInline associations #[source]) "native-facet-membership")
    "Inline theorem membership must survive at its exact destination facet"
  let otherProject := { associations[0]! with context := ⟨`lean, `anotherProject⟩ }
  ensure (has (nativeMembershipIssues node complete (associations.push otherProject) #[source])
    "source-context-mismatch") "A same-spelled native identity in another project cannot be silently accepted"
  let otherRealization := { source with destination := ⟨⟨node, `alternative⟩, `proof⟩ }
  ensure (has (nativeMembershipIssues node complete associations #[otherRealization])
    "source-destination-mismatch") "A source for an alternative cannot enter this collection"
  let unsupported := Name.str `SyntheticNative "bad»name"
  let raw := #[association unsupported #[`statement]]
  ensure (nativeNames raw #[] == #[unsupported]) "Collection retains the exact typed unsupported native name"
  ensure (has (nativeMembershipIssues node complete raw #[]) "unsupported-native-identity")
    "The ObjectKey boundary rejects lossy names rather than comparing an incorrectly parsed declaration"
  let escaped := Name.str `SyntheticNative "with.dot"
  let escapedModel : Realization := {
    key, context
    declarations := #[{ object := object escaped }]
    facets := #[{ name := `statement, declarations := #[object escaped] }] }
  ensure ((nativeMembershipIssues node escapedModel #[association escaped #[`statement]] #[]).isEmpty)
    "A losslessly escaped dot remains a supported native identity"
  ensure (has (nativeMembershipIssues node complete associations
    #[{ source with context := ⟨`rust, context.project⟩ }]) "source-context-mismatch")
    "Inline collection cannot relabel compiled Lean source as foreign content"
  ensure (has (nativeMembershipIssues `anotherConcept complete associations #[source])
    "source-destination-mismatch") "An enclosing concept mismatch remains explicit"
  ensure (has (nativeMembershipIssues node { model with context := ⟨`lean, .anonymous⟩ } #[] #[])
    "source-context-mismatch") "Empty input cannot conceal an invalid composed context"

-- Real owning-source preparation feeds the same membership boundary. It supplies
-- no proof/review observation; membership success cannot certify native validity.
run_cmd Lean.Elab.Command.liftTermElabM do
  let path := "tests/VersoBlueprintTests/BlueprintRealizationAdapter/Provider.lean"
  let prepared ← NativeSource.prepare {
    project := context.project, canonical := `RealizationAdapterFixture.flagInvolutive
    moduleName := `VersoBlueprintTests.BlueprintRealizationAdapter.Provider, sourcePath := path }
  let .ok prepared := prepared | throwError "Real native owning-source preparation failed"
  let .ok input := prepared.realizeNative {
    id := `canonicalMembershipFlag, moduleName := prepared.moduleName, source := path }
    { label := node, title := "Flag" } key.name
    | throwError "Real native source model preparation failed"
  let native := input.realizations[0]!.value
  let association : NativeAssociation := {
    realization := key, context, facets := #[`statement, `proof]
    reference := Data.ExternalRef.ofName prepared.canonical }
  unless (nativeMembershipIssues node native #[association] #[]).isEmpty && input.evidence.isEmpty do
    throwError "Real native source membership must preserve exact source identity without creating validation"
  let omitted := { native with facets := native.facets.map fun facet =>
    if facet.name == `proof then { facet with declarations := #[] } else facet }
  unless (nativeMembershipIssues node omitted #[association] #[]).any (·.code == "native-facet-membership") do
    throwError "Real native proof-facet source membership cannot be silently dropped"

end VersoBlueprintTests.BlueprintCanonicalSources
