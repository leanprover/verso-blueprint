/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.TraversalIndex
meta import VersoBlueprint.TraversalIndex

namespace VersoBlueprintModuleTests.TraversalIndex

open Lean
open Informal
open Informal.TraversalIndex

local macro "quotedNodesDomain" : term => do
  return quote Nodes.domainName

/-- info: true -/
#guard_msgs in
#eval
  let names := allSpecs.map (·.name)
  let uniqueNames := names.foldl (init := ({} : NameSet)) fun seen name => seen.insert name
  allSpecs.size == 16 && uniqueNames.size == allSpecs.size &&
    (quotedNodesDomain : Name) == Resolve.informalDomainName &&
    Nodes.spec.kind == .semanticDomain &&
    Graphs.spec.kind == .runtimeCache &&
    RelatedPanelUsedByCache.spec.kind == .internalIndex &&
    CitationUsages.spec.kind == .accumulator &&
    TraversalPreviews.key `module_traversal .statement ==
      PreviewCache.key `module_traversal .statement &&
    LeanCodePreviews.lookupKey `Nat.add == LeanCodePreviewKey.lookupKey `Nat.add &&
    ExternalDeclAnchors.key `module_traversal `Nat.add ==
      Resolve.externalRenderedDeclTargetKey `module_traversal `Nat.add

end VersoBlueprintModuleTests.TraversalIndex
