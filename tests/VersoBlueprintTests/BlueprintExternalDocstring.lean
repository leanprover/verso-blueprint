/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintExternalDocstring.Consumer
import VersoBlueprintTests.BlueprintExternalDocstring.ConflictOwner
import VersoBlueprintTests.Blueprint.Support
import VersoBlueprint.Realizations.Capture

open Lean Elab Command Term Verso Verso.Genre Informal Realizations
open Verso.VersoBlueprintTests.Blueprint.Support

namespace VersoBlueprintTests.BlueprintExternalDocstring

set_option verso.blueprint.project "externalDocstringQuery"

private def one : Name := Name.mkSimple "external.docstring.one"
private def two : Name := Name.mkSimple "external.docstring.two"
private def verso : Name := Name.mkSimple "external.docstring.verso"
private def project : Name := `externalDocstringFixture
private def upstreamBody : String := " The **upstream statement marker** retains λ and 😀. "

private def ensure (condition : Bool) (failure : String) : TermElabM Unit :=
  unless condition do throwError failure

private def obtain [Repr ε] (result : Except ε α) : TermElabM α :=
  match result with
  | .ok value => pure value
  | .error issues => throwError "Unexpected capture rejection: {repr issues}"

private def statementDocuments (snapshot : Capture.Snapshot) (label : Name) (language : Name) :
    Array Document :=
  snapshot.registry.realizations.flatMap fun model =>
    if model.key.node == label && model.role == `statement && model.context == ⟨language, project⟩ then
      model.documents.filterMap snapshot.registry.document?
    else #[]

private def hasStatement (snapshot : Capture.Snapshot) (label : Name)
    (language : Name := `markdown) (body : String := upstreamBody) : Bool :=
  (statementDocuments snapshot label language).any (·.text == body)

private def hasNoMarkdown (snapshot : Capture.Snapshot) (label : Name) : Bool :=
  (statementDocuments snapshot label `markdown).all (·.text.trimAscii.isEmpty)

private def hasNativeProof (snapshot : Capture.Snapshot) (label : Name) (declaration : Name) : Bool :=
  (snapshot.nativeRealizationsFor label).any fun model =>
    model.context == ⟨`lean, project⟩ && model.role == `proof &&
      model.declarations.any (·.object.native == declaration.toString) &&
      (snapshot.registry.resultFor (.realization model.key)).complete

run_cmd liftTermElabM do
  let env ← getEnv
  let state := Environment.informalExt.getState env
  let raw := Capture.Raw.ofState state
  let plan := Capture.plan raw
  let capture (plan : Capture.Plan) (readFile : System.FilePath → IO String := IO.FS.readFile) := do
    let observations ← obtain (← Capture.observe plan readFile)
    obtain (Capture.evaluate plan observations)
  let valid ← capture plan
  let canonical := ``ExternalDocstringFixture.selected
  let ownerModule := `VersoBlueprintTests.BlueprintExternalDocstring.Owner
  let consumerModule := `VersoBlueprintTests.BlueprintExternalDocstring.Consumer
  let some ownerIdx := env.getModuleIdxFor? canonical | throwError "Missing imported native owner"
  let some ownerPackage := env.getModulePackageByIdx? ownerIdx | throwError "Missing loaded package identity"
  let isOwnerFile (path : System.FilePath) := path.toString.endsWith "/BlueprintExternalDocstring/Owner.lean"
  for label in #[one, two] do
    let some node := state.inventory.get? label | throwError "Missing re-exported consumer node"
    let #[source] := node.sources.filter (·.adoption.isSome) | throwError "Missing exact adoption record"
    let some adoption := source.adoption | throwError "Missing typed adoption"
    let (path, _) ← obtain adoption.owner
    ensure (adoption.canonical == canonical && adoption.moduleName == ownerModule &&
      adoption.package == some ownerPackage && adoption.consumerModule == consumerModule &&
      source.context == ⟨`markdown, project⟩ && source.document.path.endsWith "/BlueprintExternalDocstring/Consumer.lean" &&
      isOwnerFile path)
      "Re-export lost the independent producer, source owner, package, or project"
    ensure (hasStatement valid label && hasNativeProof valid label canonical)
      "Two labels must be able to adopt the same exact comment independently of native proof coverage"
  ensure (hasNativeProof valid one ``ExternalDocstringFixture.alternative)
    "Adopting one docstring removed another attached native declaration"
  ensure (hasStatement valid verso `verso " The *upstream Verso marker* names {name}`True`. " &&
    hasNativeProof valid verso ``ExternalDocstringFixture.versoSelected)
    "A direct Verso docstring must keep its format, exact own bytes and native proof"
  ensure (valid.registry.realizations.any fun model =>
    model.key.node == one && model.context == ⟨`verso, project⟩ && model.role == `proof &&
      !model.documents.isEmpty)
    "The consumer proof did not retain its independently addressable realization"
  for (label, name, code) in #[
      ("external.docstring.undocumented", ``ExternalDocstringFixture.undocumented, "unsupported-docstring"),
      ("external.docstring.empty", ``ExternalDocstringFixture.emptyComment, "missing-docstring"),
      ("external.docstring.inherited", ``ExternalDocstringFixture.inherited, "unsupported-docstring")] do
    let label := Name.mkSimple label
    let scopedIssues := valid.sourceDiagnostics.nodes.filter (·.1 == label)
    ensure (hasNoMarkdown valid label && hasNativeProof valid label name && scopedIssues.any (·.2.code == code))
      s!"Unavailable own Markdown for {label} must retain native completion and issue {code}; got {repr scopedIssues}"
  ensure (!(valid.sourceDiagnostics.nodes.any (fun (label, _) => label == one || label == two)))
    "A valid sibling selection acquired the missing declaration's source diagnostic"

  -- The source reader only changes the owning file. Native results must still
  -- come from the ordinary checked environment for every consumer label.
  for (edit, allowed) in #[
      ((fun text : String => text.replace "upstream statement" "upstream statemant"),
        #["compiled-docstring-mismatch"]),
      ((fun text : String => text.replace "Copyright (c) 2026" "Copyright (c) 2027"),
        #["source-selection-unavailable"]),
      ((fun text : String => text.replace "\n" "\r\n"),
        #["source-association-unavailable", "source-selection-unavailable"])] do
    let stale ← capture plan fun path => do
      let bytes ← IO.FS.readFile path
      if isOwnerFile path then pure (edit bytes) else pure bytes
    for label in #[one, two] do
      let scopedIssues := stale.sourceDiagnostics.nodes.filter (·.1 == label)
      ensure (hasNoMarkdown stale label && hasNativeProof stale label canonical &&
        scopedIssues.any (fun (_, issue) => allowed.contains issue.code && issue.subject == canonical.toString))
        s!"Edited owner bytes for {label} must fail with one of {allowed} while keeping native proof coverage; got {repr scopedIssues}"
  let unreadable ← capture plan fun path =>
    if isOwnerFile path then throw (IO.userError "Injected unreadable owner") else IO.FS.readFile path
  ensure (hasNoMarkdown unreadable one && hasNativeProof unreadable one canonical &&
    unreadable.sourceDiagnostics.nodes.any (fun (label, _) => label == one))
    "An unreadable upstream document must retain native availability"

  -- Isolate one registration before replanning. The sibling shares the same
  -- declaration and source bytes but must not authorize a forged owner.
  let wrongOwner (alter : SourceData.AdoptedDocstring → SourceData.AdoptedDocstring) : Capture.Plan :=
    Capture.plan { raw with nodes := raw.nodes.map fun (label, node) =>
      (label, if label != one then node else
        { node with sources := node.sources.map fun source => { source with adoption := source.adoption.map alter } }) }
  for alter in #[(fun adoption : SourceData.AdoptedDocstring => { adoption with moduleName := `WrongModule }),
      fun adoption : SourceData.AdoptedDocstring => { adoption with package := some "WrongPackage" }] do
    let wrong ← capture (wrongOwner alter)
    ensure (hasNoMarkdown wrong one && hasNativeProof wrong one canonical && hasStatement wrong two &&
      wrong.sourceDiagnostics.nodes.any (fun (label, _) => label == one) &&
      !(wrong.sourceDiagnostics.nodes.any (fun (label, _) => label == two)))
      "Matching comment bytes or a valid sibling bypassed exact package/module ownership"

private def impls : Manual.ExtensionImpls := extension_impls%
private def model : RenderModel := blueprint_render_model%

/-- info: true -/
#guard_msgs in
#eval show IO Bool from do
  let html ← renderManualDocHtmlString impls ExternalDocstringFixture.chapter (model := model)
  let files ← buildManualPreviewDataFiles impls ExternalDocstringFixture.chapter (model := model)
  let body := "<strong>upstream statement marker</strong>"
  let versoBody := "<strong>upstream Verso marker</strong>"
  let proof := "<strong>consumer proof marker</strong>"
  let preview (label : Name) := files.htmlCache.findHtml? (PreviewCache.statementKey label)
  let selectedPreview (html : String) := hasSubstr html body &&
    !hasSubstr html "A different source marker for the other attached declaration"
  pure <| hasSubstr html body && hasSubstr html proof && hasSubstr html versoBody &&
    (preview one).any selectedPreview && (preview two).any selectedPreview &&
    (preview verso).any (fun html => hasSubstr html versoBody)

/-- error: An adopted docstring and an explicit Verso body compete for the default statement -/
#guard_msgs in
#docs (Manual) competingBody "Competing statement bodies" :=
:::::::
:::theorem "external.docstring.competing" (lean := "ExternalDocstringFixture.selected") (leanDocstring := "ExternalDocstringFixture.selected")
An independently authored statement.
:::
:::::::

/-- error: 'leanDocstring' must select the canonical name of one present declaration in 'lean' -/
#guard_msgs in
#docs (Manual) nonmember "Unattached selected declaration" :=
:::::::
:::theorem "external.docstring.nonmember" (lean := "ExternalDocstringFixture.alternative") (leanDocstring := "ExternalDocstringFixture.selected")
:::
:::::::

/-- error: Label «external.docstring.one» already defined -/
#guard_msgs in
#docs (Manual) explicitAfterAdoption "Competing imported default" :=
:::::::
:::theorem "external.docstring.one"
A later explicit consumer body.
:::
:::::::

/-- error: Label «external.docstring.attribute» already defined -/
#guard_msgs in
#docs (Manual) adoptionAfterAttribute "Competing attribute default" :=
:::::::
:::theorem "external.docstring.attribute" (lean := "ExternalDocstringFixture.selected") (leanDocstring := "ExternalDocstringFixture.selected")
:::
:::::::

end VersoBlueprintTests.BlueprintExternalDocstring
