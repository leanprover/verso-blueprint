/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoRosetta.Render
import VersoManual

namespace VersoRosetta
open Lean Lean.Elab Verso Verso.Doc Verso.Doc.Elab Verso.Genre.Manual Rosetta
open Verso.Genre (Manual)

/-- Each phase owns the request exactly once, including its source text. -/
inductive Payload where
  | pending (request : Request)
  | analyzed (snapshot : RequestSnapshot)
deriving ToJson, FromJson

def Payload.request : Payload → Request
  | .pending request => request
  | .analyzed snapshot => snapshot.request

def Payload.snapshot? : Payload → Option RequestSnapshot
  | .pending _ => none
  | .analyzed snapshot => some snapshot

def requestFromString! (serialized : String) : Request :=
  match Json.parse serialized >>= fromJson? with
  | .ok request => request
  | .error message => panic! s!"invalid compiled LSP request: {message}"

block_extension Block.lspContexts (contexts : Array ContextObservation) where
  data := toJson contexts
  traverse _ _ _ := pure none
  extraCss := [CSS.mk css]
  toHtml := some <| fun _ _ _ data _ => do
    match fromJson? (α := Array ContextObservation) data with
    | .error message => Verso.reportError message *> pure .empty
    | .ok contexts =>
      return Verso.Output.Html.tag "aside" #[("class", "lsp-contexts")] <| .seq <| contexts.map fun context =>
        Verso.Output.Html.tag "details" #[] <| .seq #[
          Verso.Output.Html.tag "summary" #[] (.text true s!"Analysis context: {context.key}"),
          Verso.Output.Html.tag "p" #[] (.text true context.diagnosticCoverage),
          Verso.Output.Html.tag "ul" #[] <| .seq <| context.generatedDiagnostics.map fun diagnostic =>
            Verso.Output.Html.tag "li" #[] (.text true s!"Context diagnostic: {diagnostic.message}")]
  toTeX := some <| fun _ go _ data _ => do
    match fromJson? (α := Array ContextObservation) data with
    | .error message => Verso.reportError message *> pure .empty
    | .ok contexts => go (.para #[.text <| String.intercalate "\n" <|
        contexts.toList.map (fun context => s!"{context.key}: {context.diagnosticCoverage}")])

block_extension Block.lspCode (request : Request) via withHighlighting where
  data := toJson (Payload.pending request)
  traverse _ _ _ := pure none
  extraCss := [CSS.mk css]
  extraJs := [JS.mk hoverJs]
  toHtml := some <| fun _ _ _ data _ => do
    match fromJson? (α := Payload) data with
    | .error message => Verso.reportError message *> pure .empty
    | .ok payload => liftM <| codeHtml (g := Manual) payload.request payload.snapshot?
  toTeX := some <| fun _ go _ data _ => do
    match fromJson? (α := Payload) data with
    | .error message => Verso.reportError message *> pure .empty
    | .ok payload =>
      let code ← go (.code payload.request.text)
      let diagnostics ← match payload.snapshot? with
        | none => pure Verso.Output.TeX.empty
        | some snapshot =>
          go (.para #[.text <| String.intercalate "\n" <|
            snapshot.diagnostics.toList.map (·.diagnostic.message)])
      return code ++ diagnostics

inline_extension Inline.lspReference (request : Request) via withHighlighting where
  data := toJson (Payload.pending request)
  traverse _ _ _ := pure none
  extraCss := [CSS.mk css]
  extraJs := [JS.mk hoverJs]
  toHtml := some <| fun _ _ data _ => do
    match fromJson? (α := Payload) data with
    | .error message => Verso.reportError message *> pure .empty
    | .ok payload => liftM <| referenceHtml (g := Manual) payload.request payload.snapshot?
  toTeX := some <| fun go _ data _ => do
    match fromJson? (α := Payload) data with
    | .error message => Verso.reportError message *> pure .empty
    | .ok payload => go (.code payload.request.text)

structure CodeConfig where
  key : String
  context : String

structure ReferenceConfig extends CodeConfig where
  written : Verso.ArgParse.WithSyntax String

section
variable [Monad m] [MonadInfoTree m] [MonadResolveName m] [MonadEnv m] [MonadError m]

instance : Verso.ArgParse.FromArgs CodeConfig m where
  fromArgs := CodeConfig.mk <$> .positional `key .string <*> .named' `context false

instance : Verso.ArgParse.FromArgs ReferenceConfig m where
  fromArgs := (fun key written context => { key, context, written }) <$>
    .positional `key .string <*> .positional `written (.withSyntax .string) <*> .named' `context false
end

private def codeOrigins (contents : StrLit) : DocElabM (Array LineOrigin) := do
  let some rawRange := contents.raw.getRange? | throwError "LSP code requires source positions"
  let fileMap ← getFileMap
  let uri := (System.Uri.pathToUri (← getFileName) : String)
  let raw := rawRange.start.extract fileMap.source rawRange.stop
  let rawLines := raw.splitOn "\n" |>.toArray
  let lines := contents.getString.splitOn "\n" |>.toArray
  unless rawLines.size == lines.size do throwError "code source projection has different line counts"
  let mut offset := rawRange.start.byteIdx
  let mut origins := #[]
  for index in [:lines.size] do
    let rawLine := rawLines[index]!
    let line := lines[index]!
    unless rawLine.endsWith line do throwError "code text is not an exact authored line suffix"
    let removedIndent := rawLine.dropEnd line.length |>.copy
    unless removedIndent.all Char.isWhitespace do throwError "code projection removed non-whitespace source"
    let position := fileMap.utf8PosToLspPos ⟨offset⟩
    origins := origins.push {
      uri, line := position.line, character := position.character + removedIndent.utf16Length }
    offset := offset + rawLine.utf8ByteSize + 1
  return origins

/-- Experimental syntax: compilation records intent and never starts a server. -/
@[code_block]
def lspCode : CodeBlockExpanderOf CodeConfig
  | config, contents => do
    let request : Request := {
      key := config.context ++ ":" ++ config.key, context := config.context
      kind := .code, text := contents.getString, origins := ← codeOrigins contents }
    let serialized := (toJson request).compress
    ``(Block.other (Block.lspCode (requestFromString! $(quote serialized))) #[])

/-- Named references are compiled as inert requests in an explicitly named scope. -/
@[role]
def lspRef : RoleExpanderOf ReferenceConfig
  | config, contents => do
    unless contents.isEmpty do throwError "lspRef displays its written name; its body must be empty"
    let text := config.written.val
    if text.isEmpty || text.contains '\n' then throwError "expected a nonempty single-line reference"
    let some range := config.written.syntax.getRange? | throwError "reference requires source positions"
    let fileMap ← getFileMap
    let raw := range.start.extract fileMap.source range.stop
    unless raw == "\"" ++ text ++ "\"" do
      throwError "escaped reference literals are not supported by this experimental source mapper"
    let position := fileMap.utf8PosToLspPos (range.start + '"')
    let request : Request := {
      key := config.context ++ ":" ++ config.key, context := config.context
      kind := .reference, text
      origins := #[{ uri := (System.Uri.pathToUri (← getFileName) : String),
                     line := position.line, character := position.character }] }
    let serialized := (toJson request).compress
    ``(Inline.other (Inline.lspReference (requestFromString! $(quote serialized))) #[])

/-- Transform extension children as well as ordinary blocks. Other extensions'
opaque JSON is left alone; nested document data requires its own explicit hook. -/
private partial def mapPartM [Monad m] [MonadExceptOf String m] (f : Payload → m Payload)
    (part : Part Manual) : m (Part Manual) := do
  let onInline := fun (recurse : Verso.Doc.Inline Manual → m (Verso.Doc.Inline Manual))
      (container : Verso.Genre.Manual.Inline) (children : Array (Verso.Doc.Inline Manual)) => do
    let container ← if container.name == ``Inline.lspReference then
        let payload ← match fromJson? (α := Payload) container.data with
          | .ok payload => pure payload
          | .error message => throw message
        let payload ← f payload
        pure { container with data := toJson payload }
      else pure container
    return Verso.Doc.Inline.other container (← children.mapM recurse)
  let onBlock := fun (_ : Verso.Doc.Inline Manual → m (Verso.Doc.Inline Manual))
      (recurse : Verso.Doc.Block Manual → m (Verso.Doc.Block Manual))
      (container : Verso.Genre.Manual.Block) (children : Array (Verso.Doc.Block Manual)) => do
    let container ← if container.name == ``Block.lspCode then
        let payload ← match fromJson? (α := Payload) container.data with
          | .ok payload => pure payload
          | .error message => throw message
        let payload ← f payload
        pure { container with data := toJson payload }
      else pure container
    return Verso.Doc.Block.other container (← children.mapM recurse)
  return { part with
    title := ← part.title.mapM (·.rewriteOtherM onInline)
    content := ← part.content.mapM (·.rewriteOtherM onInline onBlock)
    subParts := ← part.subParts.mapM (mapPartM f) }

def collect (part : Part Manual) : Except String (Array Request) := do
  let action := mapPartM (m := StateT (Array Request) (Except String)) (fun payload => do
    modify (·.push payload.request)
    return payload) part
  return (← action.run #[]).2

/-- Replay accepted snapshots against exactly matching compiled requests.
This is an explicit offline artifact operation, not an automatic cache lookup. -/
def enrich (bundle : Bundle) (part : Part Manual) : Except String (Part Manual) := do
  bundle.validate
  let requests ← collect part
  let part ← mapPartM (fun payload => do
    let snapshot ← bundle.find payload.request
    return Payload.analyzed snapshot) part
  let contexts := bundle.contexts.filter fun context => requests.any (·.context == context.key)
  let content := part.content.filter fun
    | .other container _ => container.name != ``Block.lspContexts
    | _ => true
  return { part with content := #[.other (Block.lspContexts contexts) #[]] ++ content }

end VersoRosetta
