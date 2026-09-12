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

-- HelperProvider disables expansion at EOF; importers still get the true default.
#eval show CoreM Unit from do
  unless DependencyAnalysis.verso.blueprint.expandHelpers.get (← getOptions) do
    throwError "Imported helper expansion setting leaked"

def second : Nat := Provider.defSource
def first : Nat := second
def propSecond : Prop := Provider.typeSource
def propFirst : Prop := propSecond

@[blueprint "policy.statement" (autoDeps := true)]
theorem statementTarget : propFirst := True.intro

@[blueprint "policy.boundary" (autoDeps := true)]
def boundaryTarget : Nat := HelperProvider.behindBoundary

@[blueprint "policy.default" (autoDeps := true)]
def defaultTarget : Nat := first

-- Expansion does not independently enable inference.
@[blueprint "policy.disabled" (autoDeps := false)]
def disabledTarget : Nat := first
@[blueprint "policy.not_enabled"]
def notEnabledTarget : Nat := first

set_option verso.blueprint.expandHelpers false in
@[blueprint "policy.once" (autoDeps := true)]
def onceTarget : Nat := first

@[blueprint "policy.after_once" (autoDeps := true)]
def afterOnceTarget : Nat := first

section
set_option verso.blueprint.expandHelpers false
@[blueprint "policy.none" (autoDeps := true)]
def noneTarget : Nat := first
@[blueprint "policy.direct" (autoDeps := true)]
def directTarget : Nat := Provider.defSource
@[blueprint "policy.statement.none" (autoDeps := true)]
theorem directStatementTarget : propFirst := True.intro

namespace Nested
set_option verso.blueprint.expandHelpers true
@[blueprint "policy.all" (autoDeps := true)]
def allTarget : Nat := first
end Nested

@[blueprint "policy.after_nested" (autoDeps := true)]
def afterNestedTarget : Nat := first

-- Direct-only inductive roots still inspect their own constructor types.
#eval show CoreM Unit from do
  let deps ← DependencyAnalysis.inferDecl? ``HelperProvider.HiddenBox
  unless deps.proof == #[label "auto.type.source"] do
    throwError "Direct-only inference lost an inductive root's body"
end

-- Exercise default and scoped settings in both document authoring adapters.
def externalTarget : Nat := first
set_option doc.verso true

#docs (Genre.Manual) defaultDoc "Default helper expansion" :=
:::::::
:::definition "policy.default.external" (lean := "externalTarget") (autoDeps := true)
Default external inference follows helpers.
:::
:::definition "policy.default.inline"
Default inline inference follows helpers.
:::
```lean "policy.default.inline" (autoDeps := true)
def defaultInline : Nat := first
```
:::::::

set_option verso.blueprint.expandHelpers false in
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

section
set_option verso.blueprint.expandHelpers false
set_option verso.blueprint.expandHelpers true in
#docs (Genre.Manual) allDoc "All helpers" :=
:::::::
:::definition "policy.all.external" (lean := "externalTarget") (autoDeps := true)
Helper expansion can be re-enabled for one document.
:::
:::definition "policy.all.inline"
Helper expansion can be re-enabled for one document.
:::
```lean "policy.all.inline" (autoDeps := true)
def allInline : Nat := first
```
:::::::

#eval show CoreM Unit from do
  if DependencyAnalysis.verso.blueprint.expandHelpers.get (← getOptions) then
    throwError "Document-local configuration leaked into outer section"
end

#eval show CoreM Unit from do
  unless DependencyAnalysis.verso.blueprint.expandHelpers.get (← getOptions) do
    throwError "Section-local configuration leaked"
  let positive := #["policy.default", "policy.direct", "policy.after_once", "policy.all",
    "policy.default.external", "policy.default.inline", "policy.all.external", "policy.all.inline"]
  let negative := #["policy.once", "policy.after_nested", "policy.disabled", "policy.not_enabled",
    "policy.none", "policy.statement.none", "policy.none.external", "policy.none.inline"]
  let expected := (positive.map fun labelText =>
      { labelText, proof := #[useRef "auto.def.source" .automatic] : ExpectedUses }) ++
    (negative.map fun labelText => { labelText : ExpectedUses }) ++ #[
      { labelText := "policy.statement", statement := #[useRef "auto.type.source" .automatic] },
      { labelText := "policy.boundary", proof := #[useRef "auto.frontier.boundary" .automatic] }]
  let failures ← expectedUsesFailures expected
  unless failures.isEmpty do throwError "{failures}"

private def impls : ExtensionImpls := extension_impls%

#eval show IO Unit from do
  for (doc, policyName, expands) in #[(defaultDoc, "default", true), (noneDoc, "none", false),
      (allDoc, "all", true)] do
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
