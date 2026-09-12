/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintAutoDeps.HelperProvider
import VersoBlueprintTests.BlueprintAutoDeps.Support
import VersoBlueprintTests.Blueprint.Support

open Lean Verso Verso.Genre.Manual Informal
open Verso.VersoBlueprintTests.BlueprintAutoDeps.Support
open Verso.VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintAutoDeps.ExpansionPolicy

-- HelperProvider enables .all, but settings must not leak through imports.
#eval show CoreM Unit from do
  unless (← DependencyAnalysis.getHelperExpansion) == .none do
    throwError "Imported helper expansion setting leaked"

/-- error: Invalid internal Blueprint helper expansion configuration -/
#guard_msgs in
#eval show CoreM Unit from
  withOptions (fun opts => opts.set `verso.blueprint.helperExpansion "not a policy") do
    let _ ← DependencyAnalysis.getHelperExpansion
    pure ()

def second : Nat := Provider.defSource
def first : Nat := second
def propSecond : Prop := Provider.typeSource
def propFirst : Prop := propSecond

set_blueprint_helper_expansion .some #[propFirst, propSecond] in
@[blueprint "policy.statement" (autoDeps := true)]
theorem statementTarget : propFirst := True.intro

set_blueprint_helper_expansion .some #[HelperProvider.behindBoundary, HelperProvider.boundary] in
@[blueprint "policy.boundary" (autoDeps := true)]
def boundaryTarget : Nat := HelperProvider.behindBoundary

@[blueprint "policy.default" (autoDeps := true)]
def defaultTarget : Nat := first
@[blueprint "policy.direct" (autoDeps := true)]
def directTarget : Nat := Provider.defSource

set_blueprint_helper_expansion .all in
@[blueprint "policy.once" (autoDeps := true)]
def onceTarget : Nat := first

@[blueprint "policy.after_once" (autoDeps := true)]
def afterOnceTarget : Nat := first

section
set_blueprint_helper_expansion .some #[first]
@[blueprint "policy.partial" (autoDeps := true)]
def partialTarget : Nat := first

section
set_blueprint_helper_expansion .some #[first, second, second]
@[blueprint "policy.selected" (autoDeps := true)]
def selectedTarget : Nat := first
end

@[blueprint "policy.after_nested" (autoDeps := true)]
def afterNestedTarget : Nat := first

-- A rejected list must not install its valid prefix or change the policy.
/-- error: Unknown constant `notAHelper` -/
#guard_msgs in
set_blueprint_helper_expansion .some #[second, notAHelper]

#eval show CoreM Unit from do
  unless (← DependencyAnalysis.getHelperExpansion) == .some #[``first] do
    throwError "Rejected symbol list changed the policy"
end

section
set_blueprint_helper_expansion .all
@[blueprint "policy.all" (autoDeps := true)]
def allTarget : Nat := first
@[blueprint "policy.disabled" (autoDeps := false)]
def disabledTarget : Nat := first

set_blueprint_helper_expansion .none
@[blueprint "policy.none" (autoDeps := true)]
def noneTarget : Nat := first
set_blueprint_helper_expansion .some #[]
@[blueprint "policy.empty" (autoDeps := true)]
def emptyTarget : Nat := first
end

section
set_blueprint_helper_expansion .some #[first, second]
namespace Shadow
def first : Nat := 99
@[blueprint "policy.resolved" (autoDeps := true)]
def resolvedTarget : Nat :=
  Verso.VersoBlueprintTests.BlueprintAutoDeps.ExpansionPolicy.first
end Shadow
end

-- Exercise the same policy in both document authoring adapters.
def externalTarget : Nat := first
set_option doc.verso true

set_blueprint_helper_expansion .none in
#docs (Genre.Manual) noneDoc "No helper expansion" :=
:::::::
:::definition "policy.none.external" (lean := "externalTarget") (autoDeps := true)
Direct-only external inference.
:::
:::definition "policy.none.inline"
Direct-only inline inference.
:::
```lean "policy.none.inline" (autoDeps := true)
def noneInline : Nat := first
```
:::::::

set_blueprint_helper_expansion .some #[first] in
#docs (Genre.Manual) partialDoc "Partial helper list" :=
:::::::
:::definition "policy.partial.external" (lean := "externalTarget") (autoDeps := true)
The second helper is not permitted.
:::
:::definition "policy.partial.inline"
The second helper is not permitted.
:::
```lean "policy.partial.inline" (autoDeps := true)
def partialInline : Nat := first
```
:::::::

set_blueprint_helper_expansion .some #[first, second] in
#docs (Genre.Manual) selectedDoc "Selected helpers" :=
:::::::
:::definition "policy.selected.external" (lean := "externalTarget") (autoDeps := true)
Both helpers are permitted.
:::
:::definition "policy.selected.inline"
Both helpers are permitted.
:::
```lean "policy.selected.inline" (autoDeps := true)
def selectedInline : Nat := first
```
:::::::

set_blueprint_helper_expansion .all in
#docs (Genre.Manual) allDoc "All helpers" :=
:::::::
:::definition "policy.all.external" (lean := "externalTarget") (autoDeps := true)
All helpers are permitted.
:::
:::definition "policy.all.inline"
All helpers are permitted.
:::
```lean "policy.all.inline" (autoDeps := true)
def allInline : Nat := first
```
:::::::

#eval show CoreM Unit from do
  unless (← DependencyAnalysis.getHelperExpansion) == .none do
    throwError "Document-local configuration leaked"
  let positive := #["policy.direct", "policy.once", "policy.selected", "policy.all",
    "policy.resolved", "policy.selected.external", "policy.selected.inline",
    "policy.all.external", "policy.all.inline"]
  let negative := #["policy.default", "policy.after_once", "policy.partial",
    "policy.after_nested", "policy.disabled", "policy.none", "policy.empty",
    "policy.none.external", "policy.none.inline",
    "policy.partial.external", "policy.partial.inline"]
  let expected := (positive.map fun labelText =>
      { labelText, proof := #[useRef "auto.def.source" .automatic] : ExpectedUses }) ++
    (negative.map fun labelText => { labelText : ExpectedUses }) ++ #[
      { labelText := "policy.statement", statement := #[useRef "auto.type.source" .automatic] },
      { labelText := "policy.boundary", proof := #[useRef "auto.frontier.boundary" .automatic] }]
  let failures ← expectedUsesFailures expected
  unless failures.isEmpty do throwError "{failures}"
  -- Direct-only inductive roots still inspect their own constructor types.
  let deps ← DependencyAnalysis.inferDecl? ``HelperProvider.HiddenBox
  unless deps.proof == #[label "auto.type.source"] do
    throwError "Direct-only inference lost an inductive root's body"

private def impls : ExtensionImpls := extension_impls%

#eval show IO Unit from do
  for (doc, policyName, expands) in #[(noneDoc, "none", false), (partialDoc, "partial", false),
      (selectedDoc, "selected", true), (allDoc, "all", true)] do
    let files ← buildManualPreviewDataFiles impls doc
    for suffix in #["external", "inline"] do
      let text := s!"policy.{policyName}.{suffix}"
      let some entry := files.manifest.previews.find? (fun entry =>
          entry.label == label text && entry.facet == .statement)
        | throw <| IO.userError s!"Missing policy preview: {text}"
      let expected := if expands then #[dataUseRef "auto.def.source" .automatic] else #[]
      unless entry.statementUses.isEmpty && entry.proofUses == expected do
        throw <| IO.userError s!"Expansion policy changed during export: {text}"

end Verso.VersoBlueprintTests.BlueprintAutoDeps.ExpansionPolicy
