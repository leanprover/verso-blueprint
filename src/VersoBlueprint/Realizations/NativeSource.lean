/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean.Parser.Module
import Lean.Elab.DeclarationRange
import VersoBlueprint.Docstring.Compiled
import VersoBlueprint.ExternalModuleSource
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

private structure ParserState where
  context : Parser.ParserModuleContext
  openDecls : List OpenDecl := []

private def openParserNamespaces (state : ParserState) (decl : Syntax) : ParserState :=
  let openNamespace (state : ParserState) (id : Syntax) (recordOpen : Bool)
      (except : List Name := []) : ParserState :=
    let resolved := ResolveName.resolveNamespace state.context.env state.context.currNamespace
      state.openDecls (Syntax.getId id)
    resolved.foldl (init := state) fun state ns => {
      context := { state.context with env := Parser.parserExtension.activateScoped state.context.env ns }
      openDecls := if recordOpen then OpenDecl.simple ns except :: state.openDecls else state.openDecls }
  match decl.getKind with
  | ``Parser.Command.openSimple =>
    decl[0].getArgs.foldl (init := state) fun state id => openNamespace state id true
  | ``Parser.Command.openScoped =>
    decl[1].getArgs.foldl (init := state) fun state id => openNamespace state id false
  | ``Parser.Command.openHiding =>
    let except := decl[2].getArgs.toList.map Syntax.getId
    openNamespace state decl[0] true except
  | _ => state

private def setParserOption (state : ParserState) (command : Syntax) : ParserState :=
  let value := command[3]
  let optionValue : Option DataValue :=
    if let some s := value.isStrLit? then some (.ofString s)
    else if let some n := value.isNatLit? then some (.ofNat n)
    else if value.getAtomVal == "true" then some (.ofBool true)
    else if value.getAtomVal == "false" then some (.ofBool false)
    else none
  optionValue.elim state fun v =>
    { state with context := { state.context with options := state.context.options.insert command[1].getId v } }

-- Each entry saves the parser state before entering one component of a
-- section or namespace. Leaving that scope restores its options, opens and scoped syntax.
private abbrev ParserScopes := List ParserState

private def enterParserScopes (state : ParserState) (scopes : ParserScopes)
    (name : Name) (namespaceScope : Bool) : ParserState × ParserScopes :=
  match name with
  | .anonymous => (state, scopes)
  | .str parent component =>
    let (state, scopes) := enterParserScopes state scopes parent namespaceScope
    let next := if namespaceScope then
      let ns := Name.str state.context.currNamespace component
      { state with
        context := { state.context with
          currNamespace := ns
          env := Parser.parserExtension.activateScoped state.context.env ns } }
    else state
    (next, state :: scopes)
  | .num .. => (state, scopes)

private def advanceParserContext (state : ParserState) (scopes : ParserScopes)
    (command : Syntax) : ParserState × ParserScopes :=
  match command.getKind with
  | ``Parser.Command.open => (openParserNamespaces state command[1], scopes)
  | ``Parser.Command.set_option => (setParserOption state command, scopes)
  | ``Parser.Command.namespace => enterParserScopes state scopes command[1].getId true
  | ``Parser.Command.section =>
    if command[2][0].isIdent then enterParserScopes state scopes command[2][0].getId false
    else (state, state :: scopes)
  | ``Parser.Command.end =>
    let count := max 1 command[1][0].getId.getNumParts
    (scopes[count - 1]?.getD state, scopes.drop count)
  | _ => (state, scopes)

private partial def hasInheritance (stx : Syntax) : Bool :=
  (match stx with
    | .atom _ "inherit_doc" => true
    | .ident _ _ name _ => name == `inherit_doc
    | _ => false) || stx.getArgs.any hasInheritance

structure ParsedSource where
  private mk ::
  private commands : Array Syntax
  private incrementalDocument? : Option Syntax := none
  private failure? : Option String := none

private def parserFailure (messages : MessageLog) : String :=
  let location := (messages.toList.find? (·.severity == .error)).map
    (fun message => s!" at {message.pos.line}:{message.pos.column}") |>.getD ""
  s!"Owning source could not be parsed{location} in the current syntax environment without elaboration"

/-- The command grammar changes during elaboration of an incremental `#doc`.
Use the corresponding term grammar at its original position instead. -/
private def parseIncrementalDocument (input : Parser.InputContext) (context : Parser.ParserModuleContext)
    (header : Syntax) : Except String Syntax := do
  let some start := header.getPos? | throw "Verso document header has no original source position"
  let state := (Parser.mkParserState input.fileMap.source).setPos start
  let state := (Parser.categoryParserFnImpl `term).run input context (Parser.getTokenTable context.env) state
  unless state.allErrors.isEmpty && input.atEnd state.pos do
    throw "Owning Verso document could not be parsed in the current syntax environment without elaboration"
  return state.stxStack.back

private def parseSourceWith (env : Environment) (path text : String) : CoreM ParsedSource := do
  try
    let input := Parser.mkInputContext text path
    let (_, state, messages) ← liftM <| Parser.parseHeader input
    if messages.hasErrors then return { commands := #[], failure? := some (parserFailure messages) }
    let rec loop (fuel : Nat) (state : Parser.ModuleParserState)
        (parserState : ParserState) (scopes : ParserScopes) (parsed : ParsedSource) : ParsedSource :=
      match fuel with
      | 0 => { parsed with failure? := parsed.failure?.or (some "Owning source parser exhausted its progress bound") }
      | fuel + 1 => Id.run do
        let (command, next, messages) := Parser.parseCommand input parserState.context state {}
        let parsed := if messages.hasErrors && parsed.failure?.isNone then
          { parsed with failure? := some (parserFailure messages) }
        else parsed
        if command.isOfKind ``Parser.Command.eoi then return parsed
        if Parser.isTerminalCommand command || next.pos <= state.pos then
          return { parsed with failure? := parsed.failure?.or (some "Owning source parser stopped before end of file") }
        -- Keep only independently parsed commands. The first syntax returned
        -- during recovery can start inside the damaged command.
        if state.recovering || next.recovering || messages.hasErrors then
          return loop fuel next parserState scopes parsed
        if command.isOfKind `Verso.Doc.Concrete.replaceDoc then
          let parsed := { parsed with commands := parsed.commands.push command }
          return match parseIncrementalDocument input parserState.context command with
          | .ok document => { parsed with incrementalDocument? := some document }
          | .error failure => { parsed with failure? := parsed.failure?.or (some failure) }
        let (parserState, scopes) := advanceParserContext parserState scopes command
        return loop fuel next parserState scopes { parsed with
          commands := parsed.commands.push command }
    return loop (text.utf8ByteSize + 1) state { context := { env, options := {} } } [] { commands := #[] }
  catch _ =>
    return { commands := #[], failure? := some "Owning source parser failed" }

abbrev SourceParser := String → String → CoreM ParsedSource

private def parseOwningSource : SourceParser := fun path text => do
  parseSourceWith (← getEnv) path text

/-- Parse original source without elaborating commands. Use the current syntax
environment and replay the parser effects of standalone openings, options and
scopes. Syntax that requires intervening elaboration can still be unsupported. -/
def parseSource (label : Name) (path text : String) : CoreM (Except Diagnostic (Array Syntax)) := do
  let parsed ← parseOwningSource path text
  return match parsed.failure? with
    | some failure => .error (issue "source-parse-failed" label failure)
    | none => .ok parsed.commands

/-- Share parsing for the same path and exact bytes within one observation.
The environment is fixed at creation; cached failures carry no request label. -/
def newSourceParser : CoreM SourceParser := do
  let env ← getEnv
  let cache ← liftM <| IO.mkRef ({} : Std.HashMap (String × String) ParsedSource)
  return fun path text => do
    let key := (path, text)
    if let some parsed := (← cache.get).get? key then return parsed
    let parsed ← parseSourceWith env path text
    cache.modify (·.insert key parsed)
    return parsed

private def isDeclarationScope (command : Syntax) : Bool :=
  command.isOfKind ``Parser.Command.set_option || command.isOfKind ``Parser.Command.open ||
    command.isOfKind ``Parser.Command.variable || command.isOfKind ``Parser.Command.attribute ||
    (match command with | `(command| seal $_ids*) => true | _ => false)

private partial def declarations (command : Syntax) : Array Syntax :=
  -- Mathlib's `lemma` parser has the same modifier and declaration ID slots
  -- as `theorem`. Keep the original syntax and never execute its macro.
  if command.isOfKind ``Parser.Command.declaration || command.isOfKind `lemma then #[command]
  else if command.isOfKind ``Parser.Command.«mutual» then
    command[1].getArgs.flatMap declarations
  -- Lean's parser handles the scoped syntax of these command wrappers. Only
  -- unwrap their enclosed command; do not search arbitrary syntax subtrees or
  -- replace the declaration/name ranges with the enclosing wrapper's range.
  else if command.isOfKind ``Parser.Command.«in» && isDeclarationScope command[0] then
    declarations command[2]
  else #[]

private def originalRange? (text : String) (stx : Syntax) : Option Syntax.Range := do
  -- canonicalOnly also admits some synthetic positions; require original input.
  let .original leading _ _ _ := stx.getHeadInfo | none
  let .original _ _ trailing _ := stx.getTailInfo | none
  if leading.str != text || trailing.str != text then none else
    let range ← stx.getRange?
    if range.stop.byteIdx > text.utf8ByteSize then none else some range

private def declarationInBuffer (label : Name) (map : FileMap) (range selection : DeclarationRange)
    (commands : Array Syntax) : Except Diagnostic Syntax := do
  let candidates := commands.flatMap declarations |>.filter fun declaration => Id.run do
    let some whole := originalRange? map.source declaration | return false
    let name := Elab.getDeclarationSelectionRef declaration[1]
    let some selected := originalRange? map.source name | return false
    return DeclarationRange.ofStringPositions map whole.start whole.stop == range &&
      DeclarationRange.ofStringPositions map selected.start selected.stop == selection
  if candidates.isEmpty then
    throw <| issue "source-association-unavailable" label "No original declaration matches both accepted source ranges"
  if candidates.size != 1 then
    throw <| issue "ambiguous-docstring" label "Multiple source declarations match the accepted ranges"
  return candidates[0]!

/-- Select one original declaration at both owning native ranges. Lean's parser
uses LF-normalized buffers. The owning text may retain its original line endings. -/
def declarationAtRanges (label : Name) (text : String) (range selection : DeclarationRange)
    (commands : Array Syntax) : Except Diagnostic Syntax :=
  declarationInBuffer label (FileMap.ofString text.crlfToLf) range selection commands

private def docCommentSyntaxAtRanges (label : Name) (map : FileMap) (range selection : DeclarationRange)
    (commands : Array Syntax) : Except Diagnostic (Syntax × TSyntax ``Parser.Command.docComment) := do
  let declaration ← declarationInBuffer label map range selection commands
  let modifiers := declaration[0]
  if hasInheritance modifiers then
    throw <| issue "inherited-docstring" label "Own comment and inherit_doc cannot establish a unique own association"
  let comment := modifiers[0][0]
  unless comment.isOfKind ``Parser.Command.docComment do
    throw <| issue "missing-own-comment" label "Selected declaration has no direct modifier doc comment"
  return (declaration, ⟨comment⟩)

private def matchesDeclarationName (canonical : Name) (decl : Syntax) : Bool :=
  let spelling := (Elab.getDeclarationSelectionRef decl[1]).getId
  let canonical := privateToUserName canonical
  if (`_root_ : Name).isPrefixOf spelling then
    spelling.replacePrefix `_root_ .anonymous == canonical
  else
    !spelling.isAnonymous && spelling.isSuffixOf canonical

/-- Map a position in the LF-normalized parser buffer to the equivalent boundary
in its exact owning bytes. The maps must describe the same text modulo CRLF. -/
def rawSourcePosition (raw normalized : FileMap) (position : String.Pos.Raw) : String.Pos.Raw :=
  raw.ofPosition (normalized.toPosition position)

private def rawDocComment (label : Name) (text : String) (map : FileMap)
    (comment : TSyntax ``Parser.Command.docComment) :
    Except Diagnostic String := do
  let some source := originalRange? map.source comment.raw
    | throw <| issue "source-association-unavailable" label "Doc comment has no original owning-source positions"
  let source := if text == map.source then source else
    let file := FileMap.ofString text
    { start := rawSourcePosition file map source.start, stop := rawSourcePosition file map source.stop }
  let raw := String.Pos.Raw.extract text source.start source.stop
  unless raw.startsWith "/--" && raw.endsWith "-/" do
    throw <| issue "source-association-unavailable" label "Selected syntax does not delimit an original doc comment"
  -- The delimiters are ASCII. These byte adjustments preserve every body byte,
  -- including initial/final whitespace and supplementary-plane characters.
  return String.Pos.Raw.extract text ⟨source.start.byteIdx + 3⟩ ⟨source.stop.byteIdx - 2⟩

/-- Extract the direct modifier comment at the two original ranges. This
syntax-only helper checks the selected declaration's modifiers. Use
`selectDocumented` to also check compiled docstring metadata in the environment. -/
def docCommentAtRanges (label : Name) (text : String) (range selection : DeclarationRange)
    (commands : Array Syntax) : Except Diagnostic String := do
  let map := FileMap.ofString text.crlfToLf
  rawDocComment label text map (← docCommentSyntaxAtRanges label map range selection commands).2

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
  roles : Array Name := #[]
  moduleName : Name
  ranges : DeclarationRanges
  semanticContext : Option String := none
  statementContext : Option String := none
  semanticDiagnostics : Array Diagnostic := #[]

/-- A declaration together with its own comment's raw bytes and the verified
parser input containing it. A Verso fence has a padded input at the file's path. -/
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
  if ExternalModuleSource.moduleNameForDecl? env name != some request.moduleName then
    return .error <| issue "source-association-unavailable" name "Source module disagrees with current declaration owner"
  return .ok ()

-- Read direct compiled metadata and verify via Lean's `findInternalDocString?`
-- (which consults private `inheritDocStringExt` first) that the effective
-- docstring is the declaration's own entry rather than an inherited one.
-- Pointer identity (`unsafe ptrEq`) distinguishes distinct `VersoDocString`
-- entries even when `Repr` elides `ElabInline.custom`/`ElabBlock.custom`
-- `Dynamic` payloads (such as `{name}` links to different constants). Identical
-- content deduplicated during `.olean` compaction still requires Lean to expose
-- `Lean.getInheritedDocStringTarget?` (see UPC-0022).
private def ownDocstringMetadata (name : Name) : CoreM (Except Diagnostic (Option String)) := do
  let env ← getEnv
  let direct ← match Docstring.directCompiled env name with
    | .ok direct => pure direct
    | .error .missing =>
      return .error <| issue "unsupported-docstring" name "No direct own native docstring metadata"
    | .error .ambiguous =>
      return .error <| issue "ambiguous-docstring" name "Conflicting own native docstring formats"
  let effective? ← liftM <| Lean.findInternalDocString? env name (includeBuiltin := false)
  match direct, effective? with
  | .inl markdown, some (.inl effective) =>
    if unsafe ptrEq markdown effective && markdown == effective then return .ok (some markdown)
    else
      return .error <| issue "inherited-docstring" name
        "Compiled docstring is inherited from another declaration"
  | .inr verso, some (.inr effective) =>
    if unsafe ptrEq verso effective then return .ok none
    else
      return .error <| issue "inherited-docstring" name
        "Compiled Verso docstring is inherited from another declaration"
  | _, _ =>
    return .error <| issue "inherited-docstring" name
      "Compiled docstring is inherited from another declaration"

private def preparedAt (request : Request) (ranges : DeclarationRanges)
    (semantics : NativeLean.SemanticContext) :
    CoreM (Except Diagnostic Prepared) := do
  let some info := (← getEnv).checked.get.find? request.canonical
    | return .error <| issue "missing-declaration" request.canonical "Declaration is not in the current checked environment"
  let context : Context := ⟨`lean, request.project⟩
  let roles ← NativeLean.declarationRoles info
  let statement ← semantics .statement request.project #[request.canonical]
  let semantics ← semantics .implementation request.project #[request.canonical]
  return .ok {
    canonical := request.canonical, declaration := ⟨context, request.canonical.toString⟩
    roles, moduleName := request.moduleName, ranges
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

/-- Confirm the path resolves to the current file or to the loaded module's
verified source input before using any source text for native metadata. -/
def owningSource (request : Request) (sourcePath : String)
    (readSource : System.FilePath → IO String) : CoreM (Except Diagnostic String) := do
  if let .error diagnostic ← checkOwner request then return .error diagnostic
  if let .error diagnostic := checkSourcePath request sourcePath then return .error diagnostic
  let env ← getEnv
  let name := request.canonical
  let wrongOwner := issue "source-association-unavailable" name
    "Source path does not resolve to the checked declaration's owning file"
  let sourceUnavailable := issue "source-unavailable" name "Cannot read the declaration's owning source"
  let owner? ← match env.getModuleIdxFor? name with
    | some idx =>
      let some owner ← ExternalModuleSource.find? env idx | return .error wrongOwner
      pure (some owner)
    | none => pure none
  let ownerPath := (owner?.map (·.path)).getD (System.FilePath.mk (← getFileName))
  let text? ← try
    let physical ← IO.FS.realPath sourcePath
    unless physical == (← IO.FS.realPath ownerPath) do return .error wrongOwner
    match owner? with
    | some owner => owner.readVerified? (fun _ => readSource physical)
    | none =>
      let text ← readSource physical
      pure (if text.crlfToLf == (← getFileMap).source then some text else none)
  catch _ => return .error sourceUnavailable
  let some text := text?
    | return .error <| issue "source-selection-unavailable" name
        "Owning source bytes disagree with the checked declaration's build input"
  return .ok text

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
  ownerPath : String
  buffer : String
  range : Syntax.Range
  registeredRange? : Option Lsp.Range
  contents : StrLit
  deriving Inhabited

instance : BEq InlineBlock where
  beq a b := a.declaration == b.declaration && a.ownerPath == b.ownerPath &&
    a.range == b.range && a.registeredRange? == b.registeredRange? &&
    a.contents.raw.getRange? == b.contents.raw.getRange? && a.buffer == b.buffer

def selectInline (name : Name) (code : Data.Code) (registeredRange? : Option Lsp.Range := none) :
    Except Diagnostic InlineBlock := do
  let declared := code.definedDefs.map (·.name) ++ code.definedTheorems.map (·.name)
  unless (declared.filter (· == name)).size == 1 do
    throw <| issue "source-association-unavailable" name "Inline source must select the exact declaration once"
  let some ownerPath := code.ownerPath?
    | throw <| issue "source-association-unavailable" name "Inline block has no registered physical owning file"
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
  return ⟨name, ownerPath, leading.str, block, registeredRange?, ⟨literal⟩⟩

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
  let text ← try
    let physical ← IO.FS.realPath sourcePath
    unless physical.toString == block.ownerPath do
      return .error <| issue "source-association-unavailable" name "Inline block selects a different physical file"
    (·.crlfToLf) <$> readSource physical
  catch _ =>
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

/-- Own docstring selection without computed native semantics. -/
structure DocumentSelection where
  document : Document
  format : Name
  rawDocstring : String
  ranges : DeclarationRanges

open Lean.Doc.Syntax in
/-- Recover only actual Lean command fences from the original document syntax. -/
private partial def leanFenceContents (stx : Syntax) : Array StrLit :=
  match (⟨stx⟩ : TSyntax `block) with
  | `(block|``` $name:ident $_args* | $contents:str ```) =>
    let leanExpanders := #[`lean, `Informal.lean, `Verso.Genre.Manual.InlineLean.lean,
      `internal, `Informal.internal]
    if leanExpanders.contains (name.getId.replacePrefix `_root_ .anonymous) then #[contents] else #[]
  | _ => stx.getArgs.flatMap leanFenceContents

private partial def documentFenceContents (stx : Syntax) : Array StrLit :=
  if stx[0].getAtomVal == "#docs" || stx[0].getAtomVal == "#doc" ||
      stx.isOfKind `Verso.Doc.Concrete.docTerm then
    leanFenceContents stx
  else if stx.isOfKind `Lean.Parser.Term.dynamicQuot then #[]
  else stx.getArgs.flatMap documentFenceContents

private def documentFences (parsed : ParsedSource) : Array StrLit :=
  parsed.commands.flatMap documentFenceContents ++
    parsed.incrementalDocument?.toArray.flatMap documentFenceContents

private def paddedFenceInput (map : FileMap) (contents : StrLit) : CoreM String :=
  withReader (fun ctx : Core.Context => { ctx with fileMap := map }) <|
    Verso.SyntaxUtils.parserInputString contents

private def selectDocumentedWith (request : Request) (sourcePath : String)
    (source : CoreM (Except Diagnostic String)) (parse : SourceParser) :
    CoreM (Except Diagnostic DocumentSelection) := do
  if let .error diagnostic ← checkOwner request then return .error diagnostic
  if let .error diagnostic := checkSourcePath request sourcePath then return .error diagnostic
  let name := request.canonical
  let markdown ← match ← ownDocstringMetadata name with
    | .ok markdown => pure markdown
    | .error diagnostic => return .error diagnostic
  let ranges ← match ← environmentRanges request with
    | .ok ranges => pure ranges
    | .error diagnostic => return .error diagnostic
  let text ← match ← source with
    | .ok text => pure text
    | .error diagnostic => return .error diagnostic
  if blank text then return .error <| issue "source-unavailable" name "Canonical source is empty"
  let parsed ← parse sourcePath text
  let map := FileMap.ofString text.crlfToLf
  let (declaration, comment) ← match docCommentSyntaxAtRanges name map ranges.range ranges.selectionRange parsed.commands with
    | .ok selected => pure selected
    | .error diagnostic =>
      if let some failure := parsed.failure? then
        if diagnostic.code == "source-association-unavailable" then
          return .error <| issue "source-parse-failed" name failure
      return .error diagnostic
  unless matchesDeclarationName name declaration do
    return .error <| issue "source-association-unavailable" name
      "Selected source identifier disagrees with the checked declaration name"
  let rawDocstring ← match rawDocComment name text map comment with
    | .ok raw => pure raw
    | .error diagnostic => return .error diagnostic
  if blank rawDocstring then return .error <| issue "missing-docstring" name "Empty raw docstring"
  if let some compiled := markdown then
    let normalized ← try pure (← Lean.getDocStringText comment).removeLeadingSpaces catch _ =>
      return .error <| issue "source-association-unavailable" name "Cannot normalize the selected Markdown comment"
    unless normalized == compiled do
      return .error <| issue "compiled-docstring-mismatch" name
        "The selected Markdown comment disagrees with the direct compiled docstring"
  return .ok {
    document := { key := ⟨⟨`lean, request.project⟩, sourcePath⟩, text }
    format := if markdown.isSome then `markdown else `verso
    rawDocstring, ranges }

/-- Select an own modifier comment in caller-supplied bytes at both checked
native ranges. For Markdown, compare Lean's normalized value to the direct
compiled metadata. Use `prepareDocumented` to verify the owning source input. -/
def selectDocumented (request : Request) (sourcePath : String)
    (readSource : System.FilePath → IO String := IO.FS.readFile)
    (parse : SourceParser := parseOwningSource) : CoreM (Except Diagnostic DocumentSelection) :=
  selectDocumentedWith request sourcePath (do
    try return .ok (← readSource sourcePath) catch _ =>
      return .error <| issue "source-unavailable" request.canonical "Cannot read canonical source at owning association path") parse

private def prepareDocumentedFrom (request : Request) (sourcePath : String)
    (source : CoreM (Except Diagnostic String)) (semantics : NativeLean.SemanticContext)
    (parse : SourceParser) : CoreM (Except Diagnostic Documented) := do
  let selection ← match ← selectDocumentedWith request sourcePath source parse with
    | .ok selection => pure selection
    | .error diagnostic => return .error diagnostic
  let ranges := selection.ranges
  let prepared ← match ← preparedAt request ranges semantics with
    | .ok prepared => pure prepared
    | .error diagnostic => return .error diagnostic
  return .ok {
    toPrepared := prepared, document := selection.document
    format := selection.format, rawDocstring := selection.rawDocstring }

/-- Prepare an own comment using the loaded module's verified build input. -/
def prepareDocumented (request : Request) (sourcePath : String)
    (readSource : System.FilePath → IO String := IO.FS.readFile)
    (semantics : NativeLean.SemanticContext := NativeLean.semanticContext)
    (parse : SourceParser := parseOwningSource) : CoreM (Except Diagnostic Documented) :=
  prepareDocumentedFrom request sourcePath (owningSource request sourcePath readSource) semantics parse

/-- Reproduce Verso's checked input from one actual Lean fence in the physical
source. The prefix is just parser padding. Preserve raw line endings in the
literal body, where the native comment can occur. -/
private def attributeFenceInput (request : Request) (path raw registered : String) (parse : SourceParser) :
    CoreM (Except Diagnostic String) := do
  let text := raw.crlfToLf
  let map := FileMap.ofString text
  let parsed ← parse path text
  if let some failure := parsed.failure? then
    return .error <| issue "source-parse-failed" request.canonical failure
  for contents in documentFences parsed do
    let some range := originalRange? text contents.raw | continue
    unless range.stop.byteIdx == registered.utf8ByteSize do continue
    let padded ← paddedFenceInput map contents
    unless padded == registered do continue
    let rawMap := FileMap.ofString raw
    let rawStart := rawSourcePosition rawMap map range.start
    let rawStop := rawSourcePosition rawMap map range.stop
    let rawContents := rawStart.extract raw rawStop
    return .ok ((0 : String.Pos.Raw).extract padded range.start ++ rawContents)
  return .error <| issue "source-selection-unavailable" request.canonical
    "The attribute's owning file has no input matching its compiled source buffer"

/-- An owning attribute registration retains its compiler input even when Lake
restores the module with a synthetic trace. Capture supplies the document from
that declaration's exact producer. A Verso fence must reproduce its actual
compiler input from the original literal in that file. -/
def prepareAttributeDocstring (request : Request) (registered : Document) (nativePath : String)
    (readSource : System.FilePath → IO String) (semantics : NativeLean.SemanticContext)
    (parse : SourceParser) : CoreM (Except Diagnostic Documented) :=
  prepareDocumentedFrom request registered.key.path (do
    try
      let physical ← IO.FS.realPath registered.key.path
      unless physical == (← IO.FS.realPath nativePath) do
        return .error <| issue "source-selection-unavailable" request.canonical
          "The attribute and native association select different physical files"
      let text ← readSource physical
      if text.crlfToLf == registered.text then return .ok text
      attributeFenceInput request registered.key.path text registered.text parse
    catch _ =>
      return .error <| issue "source-unavailable" request.canonical "Cannot read the attribute's owning source") semantics parse

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
  let proofRealization := p.leanKey.forRole `proof
  let key : RequirementKey := ⟨.declaration proofRealization p.witness, `expectedProof⟩
  let wrongWitness := issue "wrong-proof-witness" p.leanKey.node
    "Expected the exact native proof realization and selected witness before adding a proof requirement"
  let models := canonical ((p.input.realizations.filter (·.value.key == proofRealization)).map (·.value))
  let #[model] := models | return .error wrongWitness
  let some declaration := model.declaration? p.witness | return .error wrongWitness
  unless model.role == `proof && declaration.projection == .implementation do
    return .error wrongWitness
  let some updated := model.attachDeclarationRequirement? key | return .error wrongWitness
  let docs := goalDocuments.foldl pushUnique #[]
  let checked ← NativeLean.check p.witness.context.project p.witness expected docs semantics
  let .ok checked := checked | return checked.map (fun checked => (p.input, checked))
  let input := { p.input with
    realizations := p.input.realizations.map fun record =>
      if record.value.key == proofRealization then { record with value := updated } else record
    requirements := p.input.requirements ++ #[p.contribution `expectedProofRequirement {
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
  let key : RequirementKey := ⟨.declaration (p.leanKey.forRole `proof) p.witness, `expectedProof⟩
  let result := admitWithEvidence input fun bindingFor => do
    let some binding := bindingFor key
      | throw #[issue "missing-binding" p.leanKey.node "No binding for native proof requirement"]
    let slot := `proofEvidence ++ Name.mkSimple ((BindingEncoding.requirementKey key).compress)
    let origin := (p.contribution slot ()).origin
    return #[{ origin, value := {
      id := origin.id, requirement := key, binding, observation := .proof checked.observation } }]
  return result.map Registry.contributions |>.mapError fun diagnostics =>
    diagnostics[0]?.getD (issue "invalid-projection" p.leanKey.node "Projected input failed admission")


end Informal.Realizations.NativeSource
