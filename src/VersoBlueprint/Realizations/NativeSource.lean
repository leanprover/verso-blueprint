/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean.DocString.Extension
import Lean.Parser.Module
import Lean.Elab.DeclarationRange
import VersoBlueprint.Validation.Lean
import VersoBlueprint.Translations

/-! Native owning-source preparation. This module does not import the Blueprint
Environment or read accepted nodes. It prepares original source for a typed native
identity; callers separately establish the Blueprint association and admit their
complete model. Normal owning-module build is a precondition. -/

namespace Informal.Realizations.NativeSource

open Lean Validation Translations

private def issue (code : String) (label : Name) (message : String) : Diagnostic :=
  { code, subject := label.toString, message }

/-- Parse only in the current environment; do not elaborate commands or mutate
Blueprint state. Syntax requiring intervening elaboration, or made incompatible
by later imports reserving new keywords, is unsupported. Native declaration lookup can
stop after its checked range; whole-file parsing remains required for docstrings
so a later inheritance directive cannot be hidden. Original source is not sliced. -/
def parseSource (label : Name) (path text : String)
    (through? : Option DeclarationRange := none) : CoreM (Except Diagnostic (Array Syntax)) := do
  try
    let input := Parser.mkInputContext text path
    let (_, state, messages) ← liftM <| Parser.parseHeader input
    let env ← getEnv
    let stop? := through?.map fun range => input.fileMap.ofPosition range.endPos
    let rec loop (fuel : Nat) (state : Parser.ModuleParserState) (messages : MessageLog)
        (commands : Array Syntax) : Except Diagnostic (Array Syntax) := do
      match fuel with
      | 0 => throw <| issue "source-parse-failed" label "Owning source parser exhausted its progress bound"
      | fuel + 1 =>
        let (command, next, messages) := Parser.parseCommand input { env, options := {} } state messages
        if messages.hasErrors then
          let location := (messages.toList.find? (·.severity == .error)).map
            (fun message => s!" at {message.pos.line}:{message.pos.column}") |>.getD ""
          throw <| issue "source-parse-failed" label
            s!"Owning source could not be parsed{location} in the current syntax environment without elaboration"
        if command.isOfKind ``Parser.Command.eoi then return commands
        if Parser.isTerminalCommand command || next.pos <= state.pos then
          throw <| issue "source-parse-failed" label "Owning source parser stopped before end of file"
        let commands := commands.push command
        if stop?.any (next.pos >= ·) then return commands
        loop fuel next messages commands
    return loop (text.utf8ByteSize + 1) state messages #[]
  catch _ =>
    return .error <| issue "source-parse-failed" label "Owning source parser failed"

private partial def declarations (command : Syntax) : Array Syntax :=
  if command.isOfKind ``Parser.Command.declaration then #[command]
  -- Lean's parser handles the scoped syntax of these command wrappers. Only
  -- unwrap their enclosed command; do not search arbitrary syntax subtrees or
  -- replace the declaration/name ranges with the enclosing wrapper's range.
  else if command.isOfKind ``Parser.Command.«in» &&
      (command[0].isOfKind ``Parser.Command.set_option || command[0].isOfKind ``Parser.Command.«open») then
    declarations command[2]
  else #[]

private partial def hasInheritance (stx : Syntax) : Bool :=
  (match stx with
    | .atom _ "inherit_doc" => true
    | .ident _ _ name _ => name == `inherit_doc
    | _ => false) || stx.getArgs.any hasInheritance

private partial def hasStandaloneInheritance (stx : Syntax) : Bool :=
  (stx.isOfKind ``Parser.Command.attribute && hasInheritance stx) ||
    stx.getArgs.any hasStandaloneInheritance

private def originalRange? (text : String) (stx : Syntax) : Option Syntax.Range := do
  -- canonicalOnly also admits some synthetic positions; require original input.
  let .original leading _ _ _ := stx.getHeadInfo | none
  let .original _ _ trailing _ := stx.getTailInfo | none
  if leading.str != text || trailing.str != text then none else
    let range ← stx.getRange?
    if range.stop.byteIdx > text.utf8ByteSize then none else some range

/-- Select one original declaration at both owning native ranges. -/
def declarationAtRanges (label : Name) (text : String) (range selection : DeclarationRange)
    (commands : Array Syntax) : Except Diagnostic Syntax := do
  let map := FileMap.ofString text
  let candidates := commands.flatMap declarations |>.filter fun declaration => Id.run do
    let some whole := originalRange? text declaration | return false
    let name := Elab.getDeclarationSelectionRef declaration[1]
    let some selected := originalRange? text name | return false
    return DeclarationRange.ofStringPositions map whole.start whole.stop == range &&
      DeclarationRange.ofStringPositions map selected.start selected.stop == selection
  if candidates.isEmpty then
    throw <| issue "source-association-unavailable" label "No original declaration matches both accepted source ranges"
  if candidates.size != 1 then
    throw <| issue "ambiguous-docstring" label "Multiple source declarations match the accepted ranges"
  return candidates[0]!

/-- Exact own-comment association. Lean positions count codepoints;
`ofStringPositions` checks UTF-16 columns using the owning FileMap. -/
def docCommentAtRanges (label : Name) (text : String) (range selection : DeclarationRange)
    (commands : Array Syntax) : Except Diagnostic String := do
  if commands.any hasStandaloneInheritance then
    throw <| issue "inherited-docstring" label
      "Standalone inherit_doc applications prevent an unambiguous own-source association"
  let declaration ← declarationAtRanges label text range selection commands
  let modifiers := declaration[0]
  if hasInheritance modifiers then
    throw <| issue "inherited-docstring" label "Own comment and inherit_doc cannot establish a unique own association"
  let comment := modifiers[0][0]
  unless comment.isOfKind ``Parser.Command.docComment do
    throw <| issue "missing-own-comment" label "Selected declaration has no direct modifier doc comment"
  let some source := originalRange? text comment
    | throw <| issue "source-association-unavailable" label "Doc comment has no original owning-source positions"
  let raw := String.Pos.Raw.extract text source.start source.stop
  unless raw.startsWith "/--" && raw.endsWith "-/" do
    throw <| issue "source-association-unavailable" label "Selected syntax does not delimit an original doc comment"
  -- The delimiters are ASCII. These byte adjustments preserve every body byte,
  -- including initial/final whitespace and supplementary-plane characters.
  return String.Pos.Raw.extract text ⟨source.start.byteIdx + 3⟩ ⟨source.stop.byteIdx - 2⟩

/-- Compare optional accepted snapshot ranges with current owning native ranges.
The latter must be read for that same canonical declaration. This pure check
does not fill in or mutate any accepted record. -/
def checkedSourceRanges (label : Name) (snapshotRange snapshotSelection : Option DeclarationRange)
    (native : Option DeclarationRanges) : Except Diagnostic DeclarationRanges := do
  let some ranges := native
    | throw <| issue "source-association-unavailable" label "Accepted declaration has no native source ranges"
  if snapshotRange.any (· != ranges.range) || snapshotSelection.any (· != ranges.selectionRange) then
    throw <| issue "source-association-unavailable" label "Accepted snapshot and current native ranges disagree"
  return ranges

/-- Source metadata supplied by the owning producer, not a node or display name.
Snapshot ranges are compared with current native ranges, never filled in. -/
structure Request where
  project : Name
  canonical : Name
  moduleName : Name
  sourcePath : String
  range? : Option DeclarationRange := none
  selectionRange? : Option DeclarationRange := none

structure Prepared where
  canonical : Name
  declaration : ObjectKey
  kind : Data.NodeKind
  moduleName : Name
  document : Document
  ranges : DeclarationRanges
  semanticContext : Option String := none
  semanticDiagnostics : Array Diagnostic := #[]

structure Documented extends Prepared where
  format : Name
  rawDocstring : String

private def checkOwner (request : Request) : CoreM (Except Diagnostic Unit) := do
  let name := request.canonical
  if request.project.isAnonymous || name.isAnonymous || request.moduleName.isAnonymous || blank request.sourcePath then
    return .error <| issue "invalid-source-request" name "Expected explicit project, typed declaration and owning module/path"
  unless name.toString.toName == name do
    return .error <| issue "unsupported-identity" name "Canonical Lean name cannot be represented losslessly by this adapter"
  let env ← getEnv
  unless (env.checked.get.find? name).isSome do
    return .error <| issue "missing-declaration" name "Declaration is not in the current checked environment"
  let nativeModule := match env.getModuleIdxFor? name with
    | some index => env.header.moduleNames[index.toNat]?
    | none => some env.mainModule
  if nativeModule != some request.moduleName then
    return .error <| issue "source-association-unavailable" name "Source module disagrees with current declaration owner"
  return .ok ()

private def nativeDocstringFormat (name : Name) : CoreM (Except Diagnostic Name) := do
  let env ← getEnv
  return match Lean.docStringExt.find? (level := .server) env name,
      Lean.versoDocStringExt.find? (level := .server) env name with
    | some _, none => .ok `markdown
    | none, some _ => .ok `verso
    | none, none => .error <| issue "unsupported-docstring" name "No direct own native docstring metadata"
    | some _, some _ => .error <| issue "ambiguous-docstring" name "Conflicting own native docstring formats"

private def preparedAt (request : Request) (text : String) (ranges : DeclarationRanges)
    (semantics : NativeLean.SemanticContext) :
    CoreM (Except Diagnostic Prepared) := do
  let some info := (← getEnv).checked.get.find? request.canonical
    | return .error <| issue "missing-declaration" request.canonical "Declaration is not in the current checked environment"
  let context : Context := ⟨`lean, request.project⟩
  let kind : Data.NodeKind := match info with
    | .thmInfo _ => .theorem
    | _ => .definition
  let semantics ← semantics request.project #[request.canonical]
  return .ok {
    canonical := request.canonical, declaration := ⟨context, request.canonical.toString⟩
    kind, moduleName := request.moduleName
    document := { key := ⟨context, request.sourcePath⟩, text }, ranges
    semanticContext := semantics.toOption
    semanticDiagnostics := match semantics with | .ok _ => #[] | .error issue => #[issue] }

private def prepareSource (request : Request) (readSource : System.FilePath → IO String)
    (wholeFile : Bool := true)
    (semantics : NativeLean.SemanticContext := NativeLean.semanticContext) :
    CoreM (Except Diagnostic (Prepared × Array Syntax)) := do
  let name := request.canonical
  let ranges ← match checkedSourceRanges name request.range? request.selectionRange?
      (← findDeclarationRanges? name) with
    | .ok ranges => pure ranges
    | .error diagnostic => return .error diagnostic
  let text ← try liftM <| readSource request.sourcePath catch _ =>
    return .error <| issue "source-unavailable" name "Cannot read canonical source at owning association path"
  if blank text then return .error <| issue "source-unavailable" name "Canonical source is empty"
  let commands ← match ← parseSource name request.sourcePath text
      (if wholeFile then none else some ranges.range) with
    | .ok commands => pure commands
    | .error diagnostic => return .error diagnostic
  match declarationAtRanges name text ranges.range ranges.selectionRange commands with
  | .error diagnostic => return .error diagnostic
  | .ok _ => pure ()
  return (← preparedAt request text ranges semantics).map (·, commands)

/-- Prepare a canonical declaration, including an undocumented theorem or a
body-bearing definition. Source lookup neither checks proof validity nor asserts
a Blueprint association, expected goal or correspondence. Parsing stops after the
checked declaration; unrelated later document syntax does not invalidate its
association. Normal owning-module build remains a precondition, and both exact
native ranges are still required. Documentation uses the stricter whole-file path. -/
def prepare (request : Request) (readSource : System.FilePath → IO String := IO.FS.readFile)
    (semantics : NativeLean.SemanticContext := NativeLean.semanticContext) :
    CoreM (Except Diagnostic Prepared) := do
  if let .error diagnostic ← checkOwner request then return .error diagnostic
  return (← prepareSource request readSource (wholeFile := false) (semantics := semantics)).map (·.1)

/-- Prepare a declaration from an original Blueprint Lean block. Reparse the
original block contents with Verso's byte-preserving padding, then compare both
native ranges. Cached command syntax and rendered text cannot supply the source.
The owning source must still equal the producer's original syntax input; ordinary
source edits therefore require the normal owning-module rebuild. -/
def prepareInline (request : Request) (code : Data.Code)
    (readSource : System.FilePath → IO String := IO.FS.readFile)
    (semantics : NativeLean.SemanticContext := NativeLean.semanticContext) :
    CoreM (Except Diagnostic Prepared) := do
  if let .error diagnostic ← checkOwner request then return .error diagnostic
  let name := request.canonical
  let declared := code.definedDefs.map (·.name) ++ code.definedTheorems.map (·.name)
  unless (declared.filter (· == name)).size == 1 do
    return .error <| issue "source-association-unavailable" name "Inline source must select the exact declaration once"
  let text ← try liftM <| readSource request.sourcePath catch _ =>
    return .error <| issue "source-unavailable" name "Cannot read owning inline source"
  unless code.stx.isOfKind ``Lean.Doc.Syntax.codeblock && (originalRange? text code.stx).isSome do
    return .error <| issue "source-association-unavailable" name "Inline block is not original syntax from the current owning file"
  let strings := code.stx.getArgs.filter (·.isStrLit?.isSome)
  unless strings.size == 1 && (originalRange? text strings[0]!).isSome do
    return .error <| issue "source-association-unavailable" name "Inline block has no unique original contents"
  let padded ← withReader (fun ctx : Core.Context => { ctx with
      fileName := request.sourcePath, fileMap := FileMap.ofString text }) <|
    Verso.SyntaxUtils.parserInputString ⟨strings[0]!⟩
  let ranges ← match checkedSourceRanges name request.range? request.selectionRange?
      (← findDeclarationRanges? name) with
    | .ok ranges => pure ranges
    | .error diagnostic => return .error diagnostic
  let commands ← match ← parseSource name request.sourcePath padded with
    | .ok commands => pure commands
    | .error diagnostic => return .error diagnostic
  match declarationAtRanges name padded ranges.range ranges.selectionRange commands with
  | .error diagnostic => return .error diagnostic
  | .ok declaration =>
    -- Check the same byte ranges in the real owning FileMap too. Padding must
    -- never hide a Unicode/coordinate disagreement with the checked declaration.
    let some whole := declaration.getRange?
      | return .error <| issue "source-association-unavailable" name "Inline declaration has no original range"
    let some selected := (Elab.getDeclarationSelectionRef declaration[1]).getRange?
      | return .error <| issue "source-association-unavailable" name "Inline declaration has no original name range"
    let map := FileMap.ofString text
    unless DeclarationRange.ofStringPositions map whole.start whole.stop == ranges.range &&
        DeclarationRange.ofStringPositions map selected.start selected.stop == ranges.selectionRange do
      return .error <| issue "source-association-unavailable" name "Inline native ranges disagree with the owning FileMap"
  preparedAt request text ranges semantics

/-- Additionally require direct own native format metadata and one original
modifier comment at the declaration's exact full/name ranges. Return raw authored
bytes only; inherited/rendered text and nearby comments are not substitutes. -/
def prepareDocumented (request : Request) (readSource : System.FilePath → IO String := IO.FS.readFile)
    (semantics : NativeLean.SemanticContext := NativeLean.semanticContext) :
    CoreM (Except Diagnostic Documented) := do
  if let .error diagnostic ← checkOwner request then return .error diagnostic
  let format ← match ← nativeDocstringFormat request.canonical with
    | .ok format => pure format
    | .error diagnostic => return .error diagnostic
  let (source, commands) ← match ← prepareSource request readSource (semantics := semantics) with
    | .ok source => pure source
    | .error diagnostic => return .error diagnostic
  let rawDocstring ← match docCommentAtRanges request.canonical source.document.text
      source.ranges.range source.ranges.selectionRange commands with
    | .ok raw => pure raw
    | .error diagnostic => return .error diagnostic
  if blank rawDocstring then return .error <| issue "missing-docstring" request.canonical "Empty raw docstring"
  return .ok { toPrepared := source, format, rawDocstring }

/-- Evidence-free source model. No node lookup, admission or Blueprint
association is established by constructing it. The caller retains its producer
origin and separately admits the complete collected batch. -/
structure PreparedModel where
  input : Input
  origin : Origin
  witness : ObjectKey
  leanKey : RealizationKey
  informalKey : RealizationKey
  moduleName : Name
  sourcePath : String
  /-- Direct own native format; source text does not establish proofreading. -/
  docstringFormat : Name := `markdown

private def sourceContribution (origin : Origin) (slot : Name) (value : α) : Contribution α :=
  { origin := { origin with
      -- Structured typed boundaries preserve the producer site and child slot.
      id := Name.mkSimple (toJson (Vir.nameKey origin.id, Vir.nameKey slot)).compress }, value }

def PreparedModel.contribution (p : PreparedModel) (slot : Name) (value : α) : Contribution α :=
  sourceContribution p.origin slot value

/-- Source-only native representation, including declarations without prose.
The caller supplies concept metadata and producer origin. No native proof,
expected goal, prose realization or observation is synthesized. -/
def Prepared.realizeNative (source : Prepared) (origin : Origin) (node : Realizations.Node)
    (nativeName : Name) : Except Diagnostic Input := do
  unless !node.label.isAnonymous && !nativeName.isAnonymous do
    throw <| issue "invalid-source-destination" source.canonical "Expected an explicit concept and realization name"
  unless origin.moduleName == source.moduleName && !origin.id.isAnonymous && !blank origin.source do
    throw <| issue "invalid-source-origin" source.canonical "Expected an explicit owning producer origin"
  let key : RealizationKey := ⟨node.label, nativeName⟩
  let witness := source.declaration
  let document := source.document.key
  let bodyFacet := if source.kind.isTheoremLike then `proof else `body
  return {
    nodes := #[sourceContribution origin `node node]
    documents := #[sourceContribution origin `source source.document]
    objects := #[sourceContribution origin `object { key := witness, resolution := .resolved, document := some document }]
    realizations := #[sourceContribution origin `lean {
      key, context := witness.context
      facets := #[{ name := `statement, declarations := #[witness] },
        { name := bodyFacet, declarations := #[witness] }], declarations := #[{ object := witness }] }]
    bindingInputs := source.semanticContext.toArray.map fun content => sourceContribution origin `nativeSourceContext {
      subject := .declaration key witness, name := NativeLean.sourceContext, content } }

/-- Materialize two explicitly named source representations of the same concept,
without observations or fragment admission. The native source identity comes
from preparation, and own prose remains an independent unassessed realization. -/
def Documented.realize (source : Documented) (origin : Origin) (node : Realizations.Node)
    (nativeName informalName : Name) : Except Diagnostic PreparedModel := do
  unless !node.label.isAnonymous && !nativeName.isAnonymous && !informalName.isAnonymous && nativeName != informalName do
    throw <| issue "invalid-source-destination" source.canonical "Expected distinct named realizations of the same node"
  let native ← source.toPrepared.realizeNative origin node nativeName
  let leanKey : RealizationKey := ⟨node.label, nativeName⟩
  let informalKey : RealizationKey := ⟨node.label, informalName⟩
  let leanContext := source.declaration.context
  let proseContext : Context := ⟨source.format, leanContext.project⟩
  let witness := source.declaration
  let leanDoc := source.document.key
  let proseDoc : DocumentKey := ⟨proseContext, leanDoc.path ++ "#docstring:" ++ source.canonical.toString⟩
  let p : PreparedModel := {
    input := native, origin, witness, leanKey, informalKey
    moduleName := source.moduleName, sourcePath := leanDoc.path, docstringFormat := source.format }
  return { p with input := { native with
    documents := native.documents.push (p.contribution `docstring { key := proseDoc, text := source.rawDocstring })
    realizations := native.realizations.push (p.contribution `informal {
        key := informalKey, context := proseContext
        facets := #[{ name := `statement, documents := #[proseDoc] }] }) } }

/-- Prepare source/contracts plus a fresh observation without admission or binding.
The complete caller batch must supply any additional goal documents. The checked
result retains semantic-context diagnostics even when the native proof passes. -/
def PreparedModel.prepareValidation (p : PreparedModel) (expected : Syntax)
    (goalDocuments : Array DocumentKey := #[])
    (semantics : NativeLean.SemanticContext := NativeLean.semanticContext) :
    Elab.Term.TermElabM (Except Diagnostic (Input × NativeLean.Checked)) := do
  let docs := goalDocuments.foldl (fun docs key => if docs.contains key then docs else docs.push key)
    (p.input.objects.filterMap (·.value.document))
  let checked ← NativeLean.check p.witness.context.project p.witness expected docs semantics
  let .ok checked := checked | return checked.map (fun checked => (p.input, checked))
  let key : RequirementKey := ⟨.declaration p.leanKey p.witness, `proof⟩
  let input := { p.input with
    realizations := p.input.realizations.map fun record =>
      if record.value.key != p.leanKey then record else
        { record with value := { record.value with
          declarations := #[{ object := p.witness, required := #[key] }]
          facets := record.value.facets.map fun facet =>
            if facet.name == `proof || facet.name == `body then { facet with required := #[key] } else facet } }
    requirements := #[p.contribution `proofRequirement {
      key, expected := .proof checked.goal p.witness
      coverage := .dependencyClosure }]
    bindingInputs := p.input.bindingInputs ++ checked.semanticContext.toArray.map (fun content =>
      p.contribution `nativeExpectedContext { subject := key.subject, name := NativeLean.expectedContextFor key, content }) }
  return .ok (input, checked)

/-- Attach a freshly checked proof requirement/evidence to the returned input.
Does not register anything in the existing Blueprint environment. -/
def PreparedModel.validate (p : PreparedModel) (expected : Syntax) : Elab.Term.TermElabM (Except Diagnostic Input) := do
  let prepared ← p.prepareValidation expected
  let .ok (input, checked) := prepared | return prepared.map (·.1)
  let key : RequirementKey := ⟨.declaration p.leanKey p.witness, `proof⟩
  let .ok registry := admit input
    | return .error <| issue "invalid-projection" p.leanKey.node "Projected input failed pure structural admission"
  let some binding := registry.bindingFor key
    | return .error <| issue "missing-binding" p.leanKey.node "No binding for native proof requirement"
  return .ok { input with evidence := #[p.contribution `proofEvidence {
    id := p.leanKey.node ++ `nativeProof, requirement := key, binding
    observation := .proof checked.observation }] }


end Informal.Realizations.NativeSource
