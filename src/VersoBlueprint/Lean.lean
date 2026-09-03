/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Lean.Elab.Command
public import Lean.Elab.InfoTree

public import SubVerso.Highlighting

public import Verso

public import VersoManual.Basic
public import VersoManual.HighlightedCode
public import VersoManual.InlineLean.Block
public import VersoManual.InlineLean.LongLines
public import VersoManual.InlineLean.Outputs
public import VersoManual.InlineLean.Scopes

public import VersoBlueprint.Data
public import VersoBlueprint.ProvedStatus
public import VersoBlueprint.Profiling

public section

open Verso Doc Elab Genre.Manual
open Lean Elab
open SubVerso.Highlighting

open Verso.SyntaxUtils (parserInputString)
open Verso.Genre.Manual (warnLongLines)
open Verso.Genre.Manual.InlineLean (saveOutputs)
open Verso.Genre.Manual.InlineLean.Scopes (getScopes setScopes)

namespace Informal.Lean

structure LeanBlockConfig where
  «show» : Bool
  name : Option Lean.Name

abbrev LiterateDef := Data.LiterateDef
abbrev LiterateThm := Data.LiterateThm

structure ElabCommandResult where
  block : Term
  definedDefs : Array LiterateDef := #[]
  definedTheorems : Array LiterateThm := #[]

private structure DeclSorryRefs where
  allRefs : Array Syntax := #[]
  typeRefs : Array Syntax := #[]
  proofRefs : Array Syntax := #[]

private structure CmdAnalysis where
  commandStx : Syntax := .missing
  commandIndex : Nat := 0
  commandRange? : Option Syntax.Range := none
  refs : DeclSorryRefs := {}

def LeanBlockConfig.outlineMeta (cfg : LeanBlockConfig) : String :=
  if cfg.show then " " else " (hidden)"

private def abbrevFirstLine (width : Nat) (str : String) : String :=
  let str := str.trimAsciiStart
  let short := str.take width |>.replace "\n" "⏎"
  if short.toSlice == str then short else short ++ "…"

private def firstToken? (stx : Syntax) : Option Syntax :=
  stx.find? fun
    | .ident info .. => usable info
    | .atom info .. => usable info
    | _ => false
where
  usable
    | .original .. => true
    | _ => false

private def reportMessages {m} [Monad m] [MonadLog m]
    (messages : MessageLog) : m Unit := do
  for msg in messages.toArray do
    logMessage {msg with
      isSilent := msg.isSilent || msg.severity != .error
    }

private def outputMessage (shouldHighlight : Bool) (msg : Message) : DocElabM Highlighted.Message := do
  let head := if msg.caption != "" then msg.caption ++ ":\n" else ""
  if shouldHighlight then
    let msg ← highlightMessage msg
    pure { msg with contents := .append #[.text head, msg.contents] }
  else
    let contents ← liftM <| msg.data.toString
    pure <| .ofSeverityString msg.severity (head ++ contents)

def reconstructHighlight (docReconst : DocReconstruction) (key : Export.Key) :=
  match docReconst.highlightDeduplication.toHighlighted key with
  | .error msg => panic! s!"Unable to export key {key}: {msg}"
  | .ok v => v

private def quoteHighlightViaSerialization (hls : Highlighted) : DocElabM Term := do
  match ((← readThe DocElabContext).docReconstructionPlaceholder, (← getThe DocElabM.State).highlightDeduplicationTable) with
  | (.some placeholder, .some exportTable) =>
    let (key, exportTable) := hls.export.run exportTable
    modifyThe DocElabM.State ({ · with highlightDeduplicationTable := exportTable })
    ``(reconstructHighlight $placeholder $(quote key))
  | _ =>
    let repr := hlToExport hls
    ``(hlFromExport! $(quote repr))

private def toHighlightedLeanBlock (shouldShow : Bool) (hls : Highlighted) (str: StrLit) : DocElabM Term := do
  if !shouldShow then
    return ← ``(Block.concat #[])

  let col? := (← getRef).getPos? |>.map (← getFileMap).utf8PosToLspPos |>.map (·.character)
  let hls := match col? with
  | .none => hls
  | .some col => hls.deIndent col

  let range := Syntax.getRange? str
  let range := range.map (← getFileMap).utf8RangeToLspRange
  ``(Block.other
      (Verso.Genre.Manual.InlineLean.Block.lean $(← quoteHighlightViaSerialization hls) (some $(quote (← getFileName))) $(quote range))
      #[Block.code $(quote str.getString)])

private def commandLineSpan (fileMap : FileMap) (stx : Syntax) : Nat :=
  match stx.getRange? with
  | none => 1
  | some range =>
    let endPos :=
      if range.start < range.stop then
        String.Pos.Raw.prev fileMap.source range.stop
      else
        range.stop
    let startLine := (fileMap.utf8PosToLspPos range.start).line
    let endLine := (fileMap.utf8PosToLspPos endPos).line
    endLine - startLine + 1

private def commandOwnsPos (cmd : CmdAnalysis) (pos : String.Pos.Raw) : Bool :=
  match cmd.commandRange? with
  | none => false
  | some range =>
    if range.start < range.stop then
      range.start <= pos && pos < range.stop
    else
      pos == range.start

private def findDeclCommand? (fileMap : FileMap) (cmdAnalyses : Array CmdAnalysis) (declName : Name) :
    DocElabM (Option CmdAnalysis) := do
  let some declRanges ← findDeclarationRanges? declName | return none
  let declPos := fileMap.ofPosition declRanges.selectionRange.pos
  return cmdAnalyses.findRev? (fun cmd => commandOwnsPos cmd declPos)

/- `sourceBackedDeclNames` comes from `Highlighted.definedNames`. SubVerso marks those tokens
using Lean's declaration ranges for source syntax, so generated constants that only inherit a
command range but have no definition token in the source are excluded here. -/
private def getDefinedDeclsImpl (fileMap : FileMap) (before after : Environment)
    (cmdAnalyses : Array CmdAnalysis) (sourceBackedDeclNames : NameSet) :
    DocElabM (Array LiterateDef × Array LiterateThm) := do
  let mut defs := #[]
  let mut theorems := #[]
  for name in sourceBackedDeclNames.toArray do
    if (before.find? name).isSome then
      continue
    if name.isInternalOrNum || name.hasMacroScopes then
      continue
    let some info := after.find? name
      | continue
    let baseStatus := Data.ConstantInfo.blueprintProvedStatus info (allowOpaque := true)
    let hasTypeGap := baseStatus.hasTypeGap
    let hasProofGap := baseStatus.hasProofGap
    let hasGap := baseStatus.isIncomplete
    let cmdInfo? ← findDeclCommand? fileMap cmdAnalyses name
    let refs := cmdInfo?.map (·.refs) |>.getD {}
    let commandStx := cmdInfo?.map (·.commandStx) |>.getD .missing
    let commandIndex := cmdInfo?.map (·.commandIndex) |>.getD 0
    let commandLines := commandLineSpan fileMap commandStx
    let fallbackRefs : Array Syntax :=
      if refs.allRefs.isEmpty then #[commandStx] else refs.allRefs
    let typeRefs :=
      if hasTypeGap then
        if refs.typeRefs.isEmpty then fallbackRefs else refs.typeRefs
      else
        #[]
    let proofRefs :=
      if hasProofGap then
        if refs.proofRefs.isEmpty then fallbackRefs else refs.proofRefs
      else
        #[]
    let typeSorryRefs :=
      if hasGap then typeRefs else #[]
    let proofSorryRefs :=
      if hasGap then proofRefs else #[]
    let provedStatus : Data.ProvedStatus :=
      if baseStatus.isAxiomLike then
        .axiomLike
      else
        Data.ProvedStatus.ofSorryFlags
          hasTypeGap
          hasProofGap
          (if hasTypeGap then some typeSorryRefs.size else none)
          (if hasProofGap then some proofSorryRefs.size else none)
    match info with
    | .thmInfo _ =>
      theorems := theorems.push ({
        name
        commandStx
        commandIndex
        commandLines
        provedStatus
        typeSorryRefs
        proofSorryRefs
      } : LiterateThm)
    | _ =>
      defs := defs.push ({
        name
        commandStx
        commandIndex
        commandLines
        provedStatus
        typeSorryRefs
      } : LiterateDef)
  let cmpDef (a b : LiterateDef) :=
    a.commandIndex < b.commandIndex ||
    (a.commandIndex == b.commandIndex && a.name.toString < b.name.toString)
  let cmpThm (a b : LiterateThm) :=
    a.commandIndex < b.commandIndex ||
    (a.commandIndex == b.commandIndex && a.name.toString < b.name.toString)
  pure (defs.qsort cmpDef, theorems.qsort cmpThm)

private def getDefinedDecls (fileMap : FileMap) (before after : Environment)
    (cmdAnalyses : Array CmdAnalysis) (sourceBackedDeclNames : NameSet) :=
  Profile.withDocElab "lean" "getDefinedDecls" <|
    getDefinedDeclsImpl fileMap before after cmdAnalyses sourceBackedDeclNames

-- Needs to improve
private partial def collectSorryRefs (stx : Syntax) : Array Syntax :=
  let fromChildren := stx.getArgs.foldl (init := #[]) fun acc arg =>
    acc ++ collectSorryRefs arg
  match stx with
  | .atom _ val =>
    if val == "sorry" then
      fromChildren.push stx
    else
      fromChildren
  | _ => fromChildren

private def getSorryRefs (cmds : Array Syntax) : Array Syntax :=
  Id.run <| do
    let mut out : Array Syntax := #[]
    for cmd in cmds do
      for sorryRef in collectSorryRefs cmd do
        out := out.push sorryRef
    out

private def getAssignPos? (cmd : Syntax) : Option String.Pos.Raw :=
  match cmd.find? fun
    | .atom info ":=" =>
      match info with
      | .original .. => true
      | _ => false
    | _ => false
  with
  | some (.atom info ":=") =>
    match info with
    | .original _ pos _ _ => some pos
    | _ => none
  | _ => none

private def splitRefsByAssignPos (cmd : Syntax) (refs : Array Syntax) : Array Syntax × Array Syntax :=
  match getAssignPos? cmd with
  | none => (#[], refs)
  | some pivot =>
    refs.foldl (init := (#[], #[])) fun (ty, pr) ref =>
      match ref.getPos? with
      | some p =>
        if p < pivot then (ty.push ref, pr) else (ty, pr.push ref)
      | none => (ty, pr.push ref)

private def cmdAnalysis (cmd : Syntax) (cmdIndex : Nat) : CmdAnalysis :=
  let cmdSorryRefs := getSorryRefs #[cmd]
  let refs : DeclSorryRefs :=
    if cmdSorryRefs.isEmpty then
      {}
    else
      let (typeRefs, proofRefs) := splitRefsByAssignPos cmd cmdSorryRefs
      {
        allRefs := cmdSorryRefs
        typeRefs
        proofRefs
      }
  {
    commandStx := cmd
    commandIndex := cmdIndex
    commandRange? := cmd.getRange?
    refs
  }

def elabCommands (config : LeanBlockConfig) (str : StrLit) : DocElabM ElabCommandResult :=
  withoutAsync <| do
    PointOfInterest.save (← getRef) ((config.name.map (·.toString)).getD (abbrevFirstLine 20 str.getString))
      (kind := Lsp.SymbolKind.file)
      (detail? := some ("Lean code" ++ config.outlineMeta))

    let inServer := Elab.inServer.get (← getOptions)
    let shouldAnalyze := !inServer
    let shouldHighlight := !inServer
    let envBefore ← getEnv
    let col? := (← getRef).getPos? |>.map (← getFileMap).utf8PosToLspPos |>.map (·.character)
    let origScopes := (← getScopes).modifyHead fun sc =>
      let opts := pp.tagAppFns.set (Elab.async.set sc.opts false) true
      -- Documented declarations must keep their written names and remain
      -- available to modules that import the containing Blueprint document.
      { sc with opts, isPublic := true }

    let altStr ← parserInputString str
    let ictx := Parser.mkInputContext altStr (← getFileName)
    let cctx : Command.Context := {
      fileName := ← getFileName
      fileMap := FileMap.ofString altStr
      snap? := none
      cancelTk? := none
    }

    let mut cmdState : Command.State := {
      env := envBefore
      maxRecDepth := ← MonadRecDepth.getMaxRecDepth
      scopes := origScopes
    }
    let mut pstate := {pos := 0, recovering := false}
    let mut cmds := #[]
    let mut cmdAnalyses : Array CmdAnalysis := #[]
    let mut cmdIndex := 0

    repeat
      let scope := cmdState.scopes.head!
      let pmctx := {
        env := cmdState.env
        options := scope.opts
        currNamespace := scope.currNamespace
        openDecls := scope.openDecls
      }
      let (cmd, ps', messages) := Parser.parseCommand ictx pmctx pstate cmdState.messages
      cmds := cmds.push cmd
      pstate := ps'
      cmdState := { cmdState with messages := messages }

      cmdState ← Profile.withDocElab "lean" "runCommand" <| runCommand (Command.elabCommand cmd) cmd cctx cmdState
      cmdIndex := cmdIndex + 1

      if shouldAnalyze then
        let analysis := cmdAnalysis cmd cmdIndex
        cmdAnalyses := cmdAnalyses.push analysis

      if Parser.isTerminalCommand cmd then break

    setEnv cmdState.env
    setScopes cmdState.scopes
    for t in cmdState.infoState.trees do
      pushInfoTree t

    let hls ←
      if shouldHighlight then
        let mut hls := Highlighted.empty
        let nonSilentMsgs := cmdState.messages.toArray.filter (!·.isSilent)
        let mut lastPos : String.Pos.Raw := cmds[0]? >>= (·.getRange?.map (·.start)) |>.getD 0
        for cmd in cmds do
          hls := hls ++ (← highlightIncludingUnparsed cmd nonSilentMsgs cmdState.infoState.trees (startPos? := lastPos))
          lastPos := (cmd.getTrailingTailPos?).getD lastPos
        pure hls
      else
        pure <| Highlighted.text str.getString

    if let some name := config.name then
      let nonSilentMsgs := cmdState.messages.toList.filter (!·.isSilent)
      let msgs ← nonSilentMsgs.mapM (outputMessage shouldHighlight)
      saveOutputs name msgs

    reportMessages cmdState.messages
    if config.show then
      warnLongLines col? str

    let block ← toHighlightedLeanBlock config.show hls str
    let (definedDefs, definedTheorems) ←
      if shouldAnalyze then
        getDefinedDecls cctx.fileMap envBefore cmdState.env cmdAnalyses hls.definedNames
      else
        pure (#[], #[])
    pure { block, definedDefs, definedTheorems }
where
  runCommand (act : Command.CommandElabM Unit) (stx : Syntax)
      (cctx : Command.Context) (cmdState : Command.State) :
      DocElabM Command.State := do
    let (output, cmdState) ←
      match (← liftM <| IO.FS.withIsolatedStreams <| EIO.toIO' <| (act.run cctx).run cmdState) with
      | (output, .error e) => Lean.logError e.toMessageData; pure (output, cmdState)
      | (output, .ok ((), cmdState)) => pure (output, cmdState)

    if output.trimAscii.isEmpty then return cmdState

    let log : MessageData → Command.CommandElabM Unit :=
      if let some tok := firstToken? stx then logInfoAt tok else logInfo

    match (← liftM <| EIO.toIO' <| ((log output).run cctx).run cmdState) with
    | .error _ => pure cmdState
    | .ok ((), cmdState) => pure cmdState

def lean : CodeBlockExpanderOf LeanBlockConfig
  | config, str => return (← elabCommands config str).block

def defaultConfig : LeanBlockConfig where
  «show» := true
  name := none

end Informal.Lean
