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

/-! Native declaration preparation. This module does not import the Blueprint
Environment or read accepted nodes. It prepares a typed native identity from the
compiled environment, reading the owning source file only where its bytes are the
data: a declaration's own doc comment and an inline Blueprint block. Callers
separately establish the Blueprint association and admit their complete model.
Normal owning-module build is a precondition. -/

namespace Informal.Realizations.NativeSource

open Lean Validation Translations

private def issue (code : String) (label : Name) (message : String) : Diagnostic :=
  { code, subject := label.toString, message }

/-- Parse only in the current environment; do not elaborate commands or mutate
Blueprint state. Syntax requiring intervening elaboration, or made incompatible
by later imports reserving new keywords, is unsupported. The whole file is parsed
so a later inheritance directive cannot be hidden. Original source is not sliced. -/
def parseSource (label : Name) (path text : String) : CoreM (Except Diagnostic (Array Syntax)) := do
  try
    let input := Parser.mkInputContext text path
    let (_, state, messages) ← liftM <| Parser.parseHeader input
    let env ← getEnv
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
        loop fuel next messages (commands.push command)
    return loop (text.utf8ByteSize + 1) state messages #[]
  catch _ =>
    return .error <| issue "source-parse-failed" label "Owning source parser failed"

private partial def declarations (command : Syntax) : Array Syntax :=
  if command.isOfKind ``Parser.Command.declaration then #[command]
  else if command.isOfKind ``Parser.Command.«mutual» then
    command[1].getArgs.flatMap declarations
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
`ofStringPositions checks UTF-16 columns using the owning FileMap. -/
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

/-- Compare optional accepted snapshot ranges with the environment's current
native ranges for that same canonical declaration. This pure check does not fill
in or mutate any accepted record. -/
def checkedSourceRanges (label : Name) (snapshotRange snapshotSelection : Option DeclarationRange)
    (native : Option DeclarationRanges) : Except Diagnostic DeclarationRanges := do
  let some ranges := native
    | throw <| issue "source-association-unavailable" label "Accepted declaration has no native source ranges"
  if snapshotRange.any (· != ranges.range) || snapshotSelection.any (· != ranges.selectionRange) then
    throw <| issue "source-association-unavailable" label "Accepted snapshot and current native ranges disagree"
  return ranges

/-- Declaration metadata supplied by the owning producer, not a node or display
name. Snapshot ranges are compared with current native ranges, never filled in.
The owning source path is not part of it: only the providers that read the file
take one. -/
structure Request where
  project : Name
  canonical : Name
  moduleName : Name
  range? : Option DeclarationRange := none
  selectionRange? : Option DeclarationRange := none

/-- A declaration as the compiled environment establishes it. It carries no
source document: its content is the checked declaration, not the owning file. -/
structure Prepared where
  canonical : Name
  declaration : ObjectKey
  kind : Data.NodeKind
  roles : Array Name := #[]
  moduleName : Name
  ranges : DeclarationRanges
  semanticContext : Option String := none
  statementContext : Option String := none
  semanticDiagnostics : Array Diagnostic := #[]

/-- A declaration together with its own doc comment's raw bytes and the owning
source file they were read from. -/
structure Documented extends Prepared where
  document : Document
  format : Name
  rawDocstring : String

private def checkOwner (request : Request) : CoreM (Except Diagnostic Unit) := do
  let name := request.canonical
  if request.project.isAnonymous || name.isAnonymous || request.moduleName.isAnonymous then
    return .error <| issue "invalid-source-request" name "Expected explicit project, typed declaration and owning module"
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

private def preparedAt (request : Request) (ranges : DeclarationRanges)
    (semantics : NativeLean.SemanticContext) :
    CoreM (Except Diagnostic Prepared) := do
  let some info := (← getEnv).checked.get.find? request.canonical
    | return .error <| issue "missing-declaration" request.canonical "Declaration is not in the current checked environment"
  let context : Context := ⟨`lean, request.project⟩
  let roles ← NativeLean.declarationRoles info
  let kind : Data.NodeKind := if roles.contains `proof then .theorem else .definition
  let statement ← semantics .statement request.project #[request.canonical]
  let semantics ← semantics .implementation request.project #[request.canonical]
  return .ok {
    canonical := request.canonical, declaration := ⟨context, request.canonical.toString⟩
    kind, roles, moduleName := request.moduleName, ranges
    semanticContext := semantics.toOption, statementContext := statement.toOption
    semanticDiagnostics := canonical ((match semantics with | .ok _ => #[] | .error issue => #[issue]) ++
      (match statement with | .ok _ => #[] | .error issue => #[issue])) }

private def environmentRanges (request : Request) : CoreM (Except Diagnostic DeclarationRanges) := do
  return checkedSourceRanges request.canonical request.range? request.selectionRange?
    (← findDeclarationRanges? request.canonical)

private def checkSourcePath (request : Request) (sourcePath : String) : Except Diagnostic Unit :=
  if blank sourcePath then
    .error <| issue "invalid-source-request" request.canonical "Expected an explicit owning source path"
  else .ok ()

/-- Prepare a canonical declaration, including an undocumented theorem or a
body-bearing definition, from the compiled environment alone. No file is read:
the environment's declaration ranges, which must agree with any recorded snapshot
ranges, locate it, and an owning source file that is unreadable, edited or
deleted after the build does not change the result. Preparation neither checks
proof validity nor asserts a Blueprint association, expected goal or
correspondence. Normal owning-module build remains a precondition. -/
def prepare (request : Request)
    (semantics : NativeLean.SemanticContext := NativeLean.semanticContext) :
    CoreM (Except Diagnostic Prepared) := do
  if let .error diagnostic ← checkOwner request then return .error diagnostic
  let ranges ← match ← environmentRanges request with
    | .ok ranges => pure ranges
    | .error diagnostic => return .error diagnostic
  preparedAt request ranges semantics

/-- An original literal and its owning buffer, checked for this occurrence before
sharing any native answer. Verso reads the bytes between the literal's two
positions from this buffer when constructing its parser input. -/
structure InlineBlock where
  private mk ::
  declaration : Name
  buffer : String
  range : Syntax.Range
  registeredRange? : Option Lsp.Range
  contents : StrLit
  deriving Inhabited

instance : BEq InlineBlock where
  beq a b := a.declaration == b.declaration && a.range == b.range && a.registeredRange? == b.registeredRange? &&
    a.contents.raw.getRange? == b.contents.raw.getRange? && a.buffer == b.buffer

def selectInline (name : Name) (code : Data.Code) (registeredRange? : Option Lsp.Range := none) :
    Except Diagnostic InlineBlock := do
  let declared := code.definedDefs.map (·.name) ++ code.definedTheorems.map (·.name)
  unless (declared.filter (· == name)).size == 1 do
    throw <| issue "source-association-unavailable" name "Inline source must select the exact declaration once"
  let badBlock := issue "source-association-unavailable" name "Inline block has no original source range"
  let .original leading .. := code.stx.getHeadInfo | throw badBlock
  let some block := originalRange? leading.str code.stx | throw badBlock
  unless code.stx.isOfKind ``Lean.Doc.Syntax.codeblock do throw badBlock
  let strings := code.stx.getArgs.filter (·.isStrLit?.isSome)
  let #[literal] := strings
    | throw <| issue "source-association-unavailable" name "Inline block has no unique original contents"
  let some contents := originalRange? leading.str literal | throw badBlock
  unless block.start <= contents.start && contents.start <= contents.stop && contents.stop <= block.stop do
    throw <| issue "source-association-unavailable" name "Inline contents lie outside their original block"
  return ⟨name, leading.str, block, registeredRange?, ⟨literal⟩⟩

/-- Reparse the selected bytes with Verso's padding and verify the exact native
ranges. The current owning file must still match the original source buffer. -/
def prepareInlineBlock (request : Request) (sourcePath : String) (block : InlineBlock)
    (readSource : System.FilePath → IO String := IO.FS.readFile)
    (semantics : NativeLean.SemanticContext := NativeLean.semanticContext) :
    CoreM (Except Diagnostic Prepared) := do
  if let .error diagnostic ← checkOwner request then return .error diagnostic
  if let .error diagnostic := checkSourcePath request sourcePath then return .error diagnostic
  let name := request.canonical
  unless block.declaration == name do
    return .error <| issue "source-association-unavailable" name "Inline block was selected for another declaration"
  let text ← try liftM <| readSource sourcePath catch _ =>
    return .error <| issue "source-unavailable" name "Cannot read owning inline source"
  unless block.buffer == text do
    return .error <| issue "source-association-unavailable" name "Inline block is not from the current owning file"
  let map := FileMap.ofString text
  if let some registered := block.registeredRange? then
    unless map.utf8RangeToLspRange block.range == registered do
      return .error <| issue "source-association-unavailable" name "Inline block disagrees with its registered range"
  let padded ← withReader (fun ctx : Core.Context => { ctx with fileName := sourcePath, fileMap := map }) <|
    Verso.SyntaxUtils.parserInputString block.contents
  let ranges ← match ← environmentRanges request with
    | .ok ranges => pure ranges
    | .error diagnostic => return .error diagnostic
  let commands ← match ← parseSource name sourcePath padded with
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
    unless DeclarationRange.ofStringPositions map whole.start whole.stop == ranges.range &&
        DeclarationRange.ofStringPositions map selected.start selected.stop == ranges.selectionRange do
      return .error <| issue "source-association-unavailable" name "Inline native ranges disagree with the owning FileMap"
  preparedAt request ranges semantics

/-- Check one registered occurrence against its owning source and declaration. -/
def prepareInline (request : Request) (sourcePath : String) (code : Data.Code)
    (readSource : System.FilePath → IO String := IO.FS.readFile)
    (semantics : NativeLean.SemanticContext := NativeLean.semanticContext) :
    CoreM (Except Diagnostic Prepared) := do
  match selectInline request.canonical code with
  | .error diagnostic => return .error diagnostic
  | .ok block => prepareInlineBlock request sourcePath block readSource semantics

/-- Additionally require direct own native format metadata and one original
modifier comment at the declaration's exact full/name ranges. The environment
keeps only a normalized or parsed docstring, so the raw comment is read from the
whole owning source file, which must still contain one original declaration at
both native ranges. Return raw authored bytes only; inherited/rendered text and
nearby comments are not substitutes. -/
def prepareDocumented (request : Request) (sourcePath : String)
    (readSource : System.FilePath → IO String := IO.FS.readFile)
    (semantics : NativeLean.SemanticContext := NativeLean.semanticContext) :
    CoreM (Except Diagnostic Documented) := do
  if let .error diagnostic ← checkOwner request then return .error diagnostic
  if let .error diagnostic := checkSourcePath request sourcePath then return .error diagnostic
  let name := request.canonical
  let format ← match ← nativeDocstringFormat name with
    | .ok format => pure format
    | .error diagnostic => return .error diagnostic
  let ranges ← match ← environmentRanges request with
    | .ok ranges => pure ranges
    | .error diagnostic => return .error diagnostic
  let text ← try liftM <| readSource sourcePath catch _ =>
    return .error <| issue "source-unavailable" name "Cannot read canonical source at owning association path"
  if blank text then return .error <| issue "source-unavailable" name "Canonical source is empty"
  let commands ← match ← parseSource name sourcePath text with
    | .ok commands => pure commands
    | .error diagnostic => return .error diagnostic
  if let .error diagnostic := declarationAtRanges name text ranges.range ranges.selectionRange commands then
    return .error diagnostic
  let prepared ← match ← preparedAt request ranges semantics with
    | .ok prepared => pure prepared
    | .error diagnostic => return .error diagnostic
  let rawDocstring ← match docCommentAtRanges name text ranges.range ranges.selectionRange commands with
    | .ok raw => pure raw
    | .error diagnostic => return .error diagnostic
  if blank rawDocstring then return .error <| issue "missing-docstring" name "Empty raw docstring"
  return .ok {
    toPrepared := prepared, document := { key := ⟨⟨`lean, request.project⟩, sourcePath⟩, text }
    format, rawDocstring }

/-- Source contributions for the caller-supplied node. The caller merges them
into the complete batch for admission. Validation requirements and observations
are added separately. -/
structure PreparedModel where
  input : Input
  origin : Origin
  witness : ObjectKey
  /-- Base key for the role-qualified native realizations in `input`. -/
  leanKey : RealizationKey
  /-- Exact key of the separately owned prose statement realization. -/
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
The caller supplies concept metadata and producer origin. The resolved object
carries no source document; its content is the checked declaration. No native
proof, expected goal, prose realization or observation is synthesized. -/
def Prepared.realizeNative (source : Prepared) (origin : Origin) (node : Realizations.Node)
    (nativeName : Name) : Except Diagnostic Input := do
  unless !node.label.isAnonymous && !nativeName.isAnonymous do
    throw <| issue "invalid-source-destination" source.canonical "Expected an explicit concept and realization name"
  unless origin.moduleName == source.moduleName && !origin.id.isAnonymous && !blank origin.source do
    throw <| issue "invalid-source-origin" source.canonical "Expected an explicit owning producer origin"
  let key : RealizationKey := ⟨node.label, nativeName⟩
  let witness := source.declaration
  unless !source.roles.isEmpty do
    throw <| issue "unsupported-native-role" source.canonical "Checked declaration has no supported direct content role"
  let modelFor (role : Name) : Realization := {
    key := key.forRole role, context := witness.context, role
    declarations := #[{
      object := witness
      projection := if role == `statement then .statement else .implementation
      required := #[] }] }
  let roles := source.roles
  let models := roles.map modelFor
  return {
    nodes := #[sourceContribution origin `node node]
    objects := #[sourceContribution origin `object { key := witness, resolution := .resolved }]
    realizations := models.mapIdx fun index model =>
      sourceContribution origin (Name.mkSimple s!"native-role-{index}") model
    bindingInputs := roles.flatMap fun role =>
      if role == `statement then
        source.statementContext.toArray.map fun content => sourceContribution origin `nativeStatementContext {
          subject := .declaration (key.forRole role) witness, name := NativeLean.statementContext, content }
      else source.semanticContext.toArray.map fun content => sourceContribution origin `nativeSourceContext {
        subject := .declaration (key.forRole role) witness, name := NativeLean.sourceContext, content } }

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
  let proseDoc : DocumentKey := ⟨proseContext, leanDoc.path ++ "#docstring:" ++
    (toJson (Vir.nameKey source.canonical)).compress⟩
  let p : PreparedModel := {
    input := native, origin, witness, leanKey, informalKey
    moduleName := source.moduleName, sourcePath := leanDoc.path, docstringFormat := source.format }
  return { p with input := { native with
    documents := native.documents.push (p.contribution `docstring { key := proseDoc, text := source.rawDocstring })
    realizations := native.realizations ++ #[
      p.contribution `informal {
        key := informalKey, context := proseContext, role := `statement,
        documents := #[proseDoc] }] } }

/-- Prepare source/contracts plus a fresh observation without admission or binding.
The complete caller batch must supply any additional goal documents. The checked
result retains semantic-context diagnostics even when the native proof passes. -/
def PreparedModel.prepareValidation (p : PreparedModel) (expected : Syntax)
    (goalDocuments : Array DocumentKey := #[])
    (semantics : NativeLean.SemanticContext := NativeLean.semanticContext) :
    Elab.Term.TermElabM (Except Diagnostic (Input × NativeLean.Checked)) := do
  unless p.input.realizations.any (·.value.key == p.leanKey.forRole `proof) do
    return .error <| issue "wrong-proof-witness" p.leanKey.node
      "Expected a proof-valued native declaration before adding a proof requirement"
  let docs := goalDocuments.foldl (fun docs key => if docs.contains key then docs else docs.push key) #[]
  let checked ← NativeLean.check p.witness.context.project p.witness expected docs semantics
  let .ok checked := checked | return checked.map (fun checked => (p.input, checked))
  let proofRealization := p.leanKey.forRole `proof
  let key : RequirementKey := ⟨.declaration proofRealization p.witness, `expectedProof⟩
  let updateRealization (record : Contribution Realization) : Contribution Realization := Id.run do
    if record.value.key != proofRealization then return record
    let declaration : Declaration := {
      object := p.witness,
      projection := .implementation,
      required := canonical (record.value.declarations[0]!.required.push key) }
    return { record with value := { record.value with role := `proof, declarations := #[declaration] } }
  let input := { p.input with
    realizations := p.input.realizations.map updateRealization
    requirements := p.input.requirements ++ #[p.contribution `expectedProofRequirement {
      key, expected := .proof checked.goal p.witness
      coverage := .dependencyClosure }]
    bindingInputs := p.input.bindingInputs ++ checked.semanticContext.toArray.map (fun content =>
      p.contribution `nativeExpectedContext { subject := key.subject, name := NativeLean.expectedContextFor key, content }) ++
      checked.statementContext.toArray.map (fun content => p.contribution `nativeExpectedStatementContext {
        subject := key.subject, name := NativeLean.expectedStatementContextFor key, content }) }
  return .ok (input, checked)

/-- Attach a freshly checked proof requirement/evidence to the returned input.
Does not register anything in the existing Blueprint environment. -/
def PreparedModel.validate (p : PreparedModel) (expected : Syntax) : Elab.Term.TermElabM (Except Diagnostic Input) := do
  let prepared ← p.prepareValidation expected
  let .ok (input, checked) := prepared | return prepared.map (·.1)
  let key : RequirementKey := ⟨.declaration (p.leanKey.forRole `proof) p.witness, `expectedProof⟩
  let .ok registry := admit input
    | return .error <| issue "invalid-projection" p.leanKey.node "Projected input failed pure structural admission"
  let some binding := registry.bindingFor key
    | return .error <| issue "missing-binding" p.leanKey.node "No binding for native proof requirement"
  return .ok { input with evidence := #[p.contribution `proofEvidence {
    id := p.leanKey.node ++ `nativeProof, requirement := key, binding
    observation := .proof checked.observation }] }


end Informal.Realizations.NativeSource
