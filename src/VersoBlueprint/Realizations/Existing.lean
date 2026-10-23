/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean.DocString.Extension
import Lean.Parser.Module
import Lean.Elab.DeclarationRange
import VersoBlueprint.Environment
import VersoBlueprint.Translations
import VersoBlueprint.Validation.Lean

/-! Read-only, opt-in projection of a single accepted attribute theorem. No
registration, admission mutation, source rendering or inferred correspondence. -/

namespace Informal.Realizations.Existing

open Lean Validation Translations

structure Projection where
  input : Input
  witness : ObjectKey
  leanKey : RealizationKey
  informalKey : RealizationKey
  moduleName : Name
  sourcePath : String
  /-- Direct own native format; source text does not establish proofreading. -/
  docstringFormat : Name := `markdown

private def issue (code : String) (label : Name) (message : String) : Diagnostic :=
  { code, subject := label.toString, message }

/-- Parse only; do not elaborate commands or mutate Blueprint state. Files that
need intervening syntax elaboration are explicitly unsupported by this adapter. -/
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
          throw <| issue "source-parse-failed" label "Owning source could not be parsed without elaboration"
        if command.isOfKind ``Parser.Command.eoi then return commands
        if Parser.isTerminalCommand command || next.pos <= state.pos then
          throw <| issue "source-parse-failed" label "Owning source parser stopped before end of file"
        loop fuel next messages (commands.push command)
    return loop (text.utf8ByteSize + 1) state messages #[]
  catch _ =>
    return .error <| issue "source-parse-failed" label "Owning source parser failed"

private partial def declarations (command : Syntax) : Array Syntax :=
  if command.isOfKind ``Parser.Command.declaration then #[command]
  else if command.isOfKind ``Parser.Command.«in» && command[0].isOfKind ``Parser.Command.set_option then
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

/-- Exact association check, exposed for negative structural-injection tests.
Production calls use commands parsed from these same canonical source bytes.
Lean positions count codepoints; `ofStringPositions` also checks stored UTF-16
columns using the owning FileMap. Neither is treated as a raw byte column. -/
def docCommentAtRanges (label : Name) (text : String) (range selection : DeclarationRange)
    (commands : Array Syntax) : Except Diagnostic String := do
  if commands.any hasStandaloneInheritance then
    throw <| issue "inherited-docstring" label
      "Standalone inherit_doc applications prevent an unambiguous own-source association"
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
  let modifiers := candidates[0]![0]
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

def Projection.contribution (p : Projection) (slot : Name) (value : α) : Contribution α :=
  { origin := {
      id := p.leanKey.node ++ `existingRealization ++ slot
      moduleName := p.moduleName, source := p.sourcePath }, value }

/-- Read canonical bytes at the accepted association's path. The injectable
reader permits explicit I/O-failure tests, not alternate successful provenance.
The caller must use a current ordinary build of the owning source. -/
def project (projectName label : Name)
    (readSource : System.FilePath → IO String := IO.FS.readFile) : CoreM (Except Diagnostic Projection) := do
  let some node ← Environment.getNode? label
    | return .error <| issue "missing-node" label "No accepted Blueprint node"
  unless !projectName.isAnonymous && node.blueprintAttributeAttachments &&
      node.externalRefs.size == 1 && node.proofExternalRefs.isEmpty &&
      node.literateCodes.isEmpty && node.rustCode.isNone && node.externalMarkup.isEmpty &&
      node.proof.isNone do
    return .error <| issue "unsupported-node" label "Expected one attribute-owned theorem and docstring only"
  let ref := node.externalRefs[0]!
  unless ref.origin == .blueprintAttr && ref.kind == .theorem && ref.present do
    return .error <| issue "unsupported-association" label "Expected one present attribute theorem association"
  unless ref.canonical.toString.toName == ref.canonical do
    return .error <| issue "unsupported-identity" label
      "Canonical Lean name cannot be represented losslessly by this adapter"
  let some body := node.statement
    | return .error <| issue "missing-docstring" label "No accepted statement body"
  unless body.stx.isOfKind `Informal.blueprint && body.hasBody do
    return .error <| issue "unsupported-statement" label "Statement is not the attribute-owned docstring"
  let some moduleName := ref.provenance.moduleName?
    | return .error <| issue "source-unavailable" label "Accepted association has no source module"
  let some sourcePath := ref.provenance.sourcePath?
    | return .error <| issue "source-unavailable" label "Accepted association has no source path"
  let env ← getEnv
  let nativeModule := match env.getModuleIdxFor? ref.canonical with
    | some index => env.header.moduleNames[index.toNat]?
    | none => some env.mainModule
  if nativeModule != some moduleName then
    return .error <| issue "source-association-unavailable" label "Accepted source module disagrees with current declaration owner"
  let format ← match Lean.docStringExt.find? (level := .server) env ref.canonical,
      Lean.versoDocStringExt.find? (level := .server) env ref.canonical with
    | some _, none => pure `markdown
    | none, some _ => pure `verso
    | none, none => return .error <| issue "unsupported-docstring" label "No direct own native docstring metadata"
    | some _, some _ => return .error <| issue "ambiguous-docstring" label "Conflicting own native docstring formats"
  -- Attribute application can precede range registration. Resolve current owning
  -- metadata by the accepted canonical declaration, never by source spelling.
  let some ranges ← findDeclarationRanges? ref.canonical
    | return .error <| issue "source-association-unavailable" label "Accepted declaration has no native source ranges"
  if ref.range?.any (· != ranges.range) || ref.selectionRange?.any (· != ranges.selectionRange) then
    return .error <| issue "source-association-unavailable" label "Accepted snapshot and current native ranges disagree"
  let text ← try liftM <| readSource sourcePath catch _ =>
    return .error <| issue "source-unavailable" label "Cannot read canonical source at accepted association path"
  if blank text then return .error <| issue "source-unavailable" label "Canonical source is empty"
  let commands ← match ← parseSource label sourcePath text with
    | .ok commands => pure commands
    | .error diagnostic => return .error diagnostic
  let doc ← match docCommentAtRanges label text ranges.range ranges.selectionRange commands with
    | .ok doc => pure doc
    | .error diagnostic => return .error diagnostic
  if blank doc then return .error <| issue "missing-docstring" label "Empty raw docstring"
  let leanContext : Context := ⟨`lean, projectName⟩
  let proseContext : Context := ⟨format, projectName⟩
  let witness : ObjectKey := ⟨leanContext, ref.canonical.toString⟩
  let leanKey : RealizationKey := ⟨label, `lean⟩
  let informalKey : RealizationKey := ⟨label, `docstring⟩
  let leanDoc : DocumentKey := ⟨leanContext, sourcePath⟩
  let proseDoc : DocumentKey := ⟨proseContext, sourcePath ++ "#docstring:" ++ ref.canonical.toString⟩
  let p : Projection := { input := {}, witness, leanKey, informalKey, moduleName, sourcePath, docstringFormat := format }
  return .ok { p with input := {
    nodes := #[p.contribution `node { label, title := label.toString }]
    documents := #[p.contribution `source { key := leanDoc, text },
      p.contribution `docstring { key := proseDoc, text := doc }]
    objects := #[p.contribution `object { key := witness, resolution := .resolved, document := some leanDoc }]
    realizations := #[
      p.contribution `lean {
        key := leanKey, context := leanContext
        facets := #[{ name := `statement, declarations := #[witness] },
          { name := `proof, declarations := #[witness] }], declarations := #[{ object := witness }] },
      p.contribution `informal {
        key := informalKey, context := proseContext
        facets := #[{ name := `statement, documents := #[proseDoc] }] }] } }

/-- Attach a freshly checked proof requirement/evidence to the returned input.
Does not register anything in the existing Blueprint environment. -/
def Projection.validate (p : Projection) (expected : Syntax) : Elab.Term.TermElabM (Except Diagnostic Input) := do
  let docs := p.input.objects.filterMap (·.value.document)
  let checked ← NativeLean.check p.witness.context.project p.witness expected docs
  let .ok checked := checked | return checked.map (fun _ => p.input)
  let key : RequirementKey := ⟨.declaration p.leanKey p.witness, `proof⟩
  let input := { p.input with
    realizations := p.input.realizations.map fun record =>
      if record.value.key != p.leanKey then record else
        { record with value := { record.value with
          declarations := #[{ object := p.witness, required := #[key] }]
          facets := record.value.facets.map fun facet =>
            if facet.name == `proof then { facet with required := #[key] } else facet } }
    requirements := #[p.contribution `proofRequirement {
      key, expected := .proof checked.goal p.witness
      coverage := .dependencyClosure }] }
  let .ok registry := admit input
    | return .error <| issue "invalid-projection" p.leanKey.node "Projected input failed pure structural admission"
  let some binding := registry.bindingFor key
    | return .error <| issue "missing-binding" p.leanKey.node "No binding for native proof requirement"
  return .ok { input with evidence := #[p.contribution `proofEvidence {
    id := p.leanKey.node ++ `nativeProof, requirement := key, binding
    observation := .proof checked.observation }] }

end Informal.Realizations.Existing
