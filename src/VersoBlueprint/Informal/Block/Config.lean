/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean.Elab.InfoTree.Types
import VersoManual
import VersoBlueprint.Data
import VersoBlueprint.DependencyAnalysis
import VersoBlueprint.DirectiveArgParsing
import VersoBlueprint.Environment
import VersoBlueprint.Informal.ExternalCode
import VersoBlueprint.Informal.LabelArg
import VersoBlueprint.Informal.UseConfig
import VersoBlueprint.LabelNameParsing

namespace Informal

open Verso Doc Elab
open Verso.ArgParse
open Lean Elab

/--
Raw configuration accepted by informal block directives.

This is the parser boundary for block options such as `(lean := ...)`,
`(tags := ...)`, and metadata-only dependency edges written as
`(uses := "label1, label2")`. The optional `(uses_origin := ...)` and
`(uses_intent := ...)` strings are parsed here with the same accepted values as
inline `{uses ...}` metadata. Invalid dependency metadata is retained so
`resolveForDirective` can report block-specific diagnostics at the user-written
label while still recovering with default metadata.
-/
structure Config where
  /-- The block label used for environment registration and diagnostics. -/
  label : Data.Label
  /-- Syntax node of the original label argument. -/
  labelSyntax : Syntax := Syntax.missing
  /-- Optional Lean/external-code references associated with statement blocks. -/
  lean : Option String := none
  /-- Optional local override for automatic dependency inference. -/
  autoDeps : Option Bool := none
  /-- Optional parent node label. -/
  parent : Option Data.Parent := none
  /-- Raw priority option, normalized during directive resolution. -/
  priority : Option String := none
  /-- Optional author id for statement metadata. -/
  owner : Option Data.AuthorId := none
  /-- Normalized tag names, deduplicated in source order. -/
  tags : Array String := #[]
  /-- Raw effort option, normalized during directive resolution. -/
  effort : Option String := none
  /-- Optional PR URL associated with this statement. -/
  prUrl : Option String := none
  /-- Optional tracking-issue URL associated with this statement. -/
  issueUrl : Option String := none
  /-- Metadata-only dependency edges declared with `(uses := ...)`. -/
  metadataUses : Array Data.UseRef := #[]
  /-- Invalid block-level dependency origin string, when present. -/
  invalidMetadataUseOrigin : Option String := none
  /-- Invalid block-level dependency intent string, when present. -/
  invalidMetadataUseIntent : Option String := none
  /-- Parsed external-code references from `(lean := ...)`. -/
  externalCode : Array Data.ExternalRef := #[]
  /-- Malformed external-code reference strings ignored during resolution. -/
  invalidExternalCode : Array String := #[]
--  hide : Bool := false

private def normalizePriority? (raw : String) : Option String :=
  match raw.trimAscii.toString.toLower with
  | "high" => some "high"
  | "medium" => some "medium"
  | "low" => some "low"
  | _ => none

private def normalizeEffort? (raw : String) : Option String :=
  match raw.trimAscii.toString.toLower with
  | "small" | "s" => some "small"
  | "medium" | "m" => some "medium"
  | "large" | "l" => some "large"
  | _ => none

private def normalizeTags (raw : String) : Array String :=
  DirectiveArgParsing.splitCommaSeparatedList raw
    |>.map (fun tag => tag.trimAscii.toString.toLower)
    |>.foldl (init := #[]) fun acc tag => if acc.contains tag then acc else acc.push tag

section
variable [Monad m] [MonadInfoTree m] [MonadResolveName m] [MonadLiftT CoreM m] [MonadEnv m]
    [MonadError m] [MonadFileMap m] [MonadLog m] [AddMessageContext m] [MonadOptions m]

def Config.parse : ArgParse m Config :=
  (fun (labelArg : Verso.ArgParse.WithSyntax String) lean autoDeps parent priority owner tags effort prUrl
      issueUrl uses usesOrigin usesIntent =>
    let (externalCode, invalidExternalCode) := ExternalCode.parseExternalCodeList lean
    let parsedLabel := LabelArg.parse labelArg
    let useMetadata := UseConfig.parseMetadata usesOrigin usesIntent
    {
      label := parsedLabel.label
      labelSyntax := parsedLabel.labelSyntax
      lean := lean
      autoDeps := autoDeps
      parent := parent.map LabelNameParsing.parse
      priority := priority
      owner := owner.map LabelNameParsing.parse
      tags := normalizeTags (tags.getD "")
      effort := effort
      prUrl := prUrl.map (·.trimAscii.toString)
      issueUrl := issueUrl.map (·.trimAscii.toString)
      metadataUses := UseConfig.refsForLabels (UseConfig.parseLabels uses) useMetadata
      invalidMetadataUseOrigin := useMetadata.invalidOrigin
      invalidMetadataUseIntent := useMetadata.invalidIntent
      externalCode := externalCode
      invalidExternalCode := invalidExternalCode
    }) <$> .positional `label (.withSyntax .string) <*> .named `lean .string true
        <*> .named' `autoDeps true
        <*> .named `parent .string true <*> .named `priority .string true <*> .named `owner .string true
        <*> .named `tags .string true <*> .named `effort .string true <*> .named `pr_url .string true
        <*> .named `issue_url .string true
        <*> .named `uses .string true <*> .named `uses_origin .string true <*> .named `uses_intent .string true

instance : FromArgs Config m where
  fromArgs := Config.parse

end

/-- Directive configuration after proof-vs-statement validation and name resolution. -/
structure ResolvedConfig where
  label : Data.Label
  labelSyntax : Syntax
  envKind : Data.InProgressKind
  codeHint : Option Data.CodeRef := none
  parent : Option Data.Parent := none
  priority : Option String := none
  owner : Option Data.AuthorId := none
  tags : Array String := #[]
  effort : Option String := none
  prUrl : Option String := none
  issueUrl : Option String := none
  statementUses : Array Data.UseRef := #[]
  proofUses : Array Data.UseRef := #[]

private def resolvePriority? {m}
    [Monad m] [MonadOptions m] [MonadLog m] [AddMessageContext m] [MonadFileMap m]
    (cfg : Config) (isProof : Bool) : m (Option String) := do
  match cfg.priority with
  | none => pure none
  | some raw =>
    match normalizePriority? raw with
    | some normalized =>
      if isProof then
        logErrorAt cfg.labelSyntax m!"Label {cfg.label} cannot use '(priority := ...)' in a proof block"
        pure none
      else
        pure (some normalized)
    | none =>
      logErrorAt cfg.labelSyntax m!"Label {cfg.label} has invalid '(priority := \"{raw}\")'; expected one of \"high\", \"medium\", \"low\""
      pure none

private def resolveOwner? {m}
    [Monad m] [MonadEnv m] [MonadOptions m] [MonadLog m] [AddMessageContext m]
    [MonadFileMap m]
    (cfg : Config) (isProof : Bool) : m (Option Data.AuthorId) := do
  match cfg.owner with
  | none => pure none
  | some owner =>
    if isProof then
      logErrorAt cfg.labelSyntax m!"Label {cfg.label} cannot use '(owner := ...)' in a proof block"
      pure none
    else if (← Environment.getAuthor? owner).isNone then
      logErrorAt cfg.labelSyntax m!"Label {cfg.label} references unknown owner '{owner}'; declare it first with ':::author'"
      pure none
    else
      pure (some owner)

private def resolveEffort? {m}
    [Monad m] [MonadOptions m] [MonadLog m] [AddMessageContext m] [MonadFileMap m]
    (cfg : Config) (isProof : Bool) : m (Option String) := do
  match cfg.effort with
  | none => pure none
  | some raw =>
    match normalizeEffort? raw with
    | some normalized =>
      if isProof then
        logErrorAt cfg.labelSyntax m!"Label {cfg.label} cannot use '(effort := ...)' in a proof block"
        pure none
      else
        pure (some normalized)
    | none =>
      logErrorAt cfg.labelSyntax m!"Label {cfg.label} has invalid '(effort := \"{raw}\")'; expected one of \"small\", \"medium\", \"large\""
      pure none

private def resolveTags {m}
    [Monad m] [MonadOptions m] [MonadLog m] [AddMessageContext m] [MonadFileMap m]
    (cfg : Config) (isProof : Bool) : m (Array String) := do
  if isProof && !cfg.tags.isEmpty then
    logErrorAt cfg.labelSyntax m!"Label {cfg.label} cannot use '(tags := ...)' in a proof block"
    pure #[]
  else
    pure cfg.tags

/--
Validate a URL-valued statement option such as `pr_url`. Proof blocks reject the
option; a blank value counts as absent; anything else must be an http(s) URL and
is kept as written after trimming.
-/
private def resolveHttpUrlOption? {m}
    [Monad m] [MonadOptions m] [MonadLog m] [AddMessageContext m] [MonadFileMap m]
    (cfg : Config) (isProof : Bool) (optionName : String) (value : Option String) :
    m (Option String) := do
  if isProof then
    if value.isSome then
      logErrorAt cfg.labelSyntax m!"Label {cfg.label} cannot use '({optionName} := ...)' in a proof block"
    pure none
  else
    match value with
    | some url =>
      let url := url.trimAscii.toString
      if url.isEmpty then
        pure none
      else if url.startsWith "http://" || url.startsWith "https://" then
        pure (some url)
      else
        logErrorAt cfg.labelSyntax m!"Label {cfg.label} has invalid '({optionName} := \"{url}\")'; expected an http(s) URL"
        pure none
    | none => pure none

/--
Resolve a directive config for environment registration.

This keeps argument normalization and proof-vs-statement validation out of the
block expander. Invalid metadata logs diagnostics; the surrounding directive
transaction rejects the registration if resolution logged any errors.
-/
def Config.resolveForDirective {m}
    [Monad m] [MonadResolveName m] [MonadOptions m] [MonadLiftT CoreM m] [MonadEnv m]
    [MonadLog m] [AddMessageContext m] [MonadFileMap m] [MonadError m]
    (cfg : Config) (kind : Data.NodeKind) (isProof : Bool) : m ResolvedConfig := do
  let envKind : Data.InProgressKind :=
    if isProof then .proof else .statement kind
  let resolvedExternalCode ←
    ExternalCode.resolveExternalCodeList cfg.label cfg.labelSyntax kind cfg.externalCode
  let hasExternalRaw := !resolvedExternalCode.isEmpty
  if !cfg.invalidExternalCode.isEmpty then
    logWarningAt cfg.labelSyntax m!"Label {cfg.label}: ignoring malformed names in '(lean := ...)' ({String.intercalate ", " cfg.invalidExternalCode.toList})"
  if let some raw := cfg.invalidMetadataUseOrigin then
    logErrorAt cfg.labelSyntax m!"Label {cfg.label} has invalid '(uses_origin := \"{raw}\")'; expected one of {UseConfig.allowedOriginValues}"
  if let some raw := cfg.invalidMetadataUseIntent then
    logErrorAt cfg.labelSyntax m!"Label {cfg.label} has invalid '(uses_intent := \"{raw}\")'; expected one of {UseConfig.allowedIntentValues}"
  if isProof && hasExternalRaw then
    logErrorAt cfg.labelSyntax m!"Label {cfg.label} cannot use '(lean := ...)' in a proof block"
  let priority ← resolvePriority? cfg isProof
  let owner ← resolveOwner? cfg isProof
  let effort ← resolveEffort? cfg isProof
  let tags ← resolveTags cfg isProof
  let prUrl ← resolveHttpUrlOption? cfg isProof "pr_url" cfg.prUrl
  let issueUrl ← resolveHttpUrlOption? cfg isProof "issue_url" cfg.issueUrl
  let hasExternal := hasExternalRaw && !isProof
  let inferredDeps ←
    if hasExternal && DependencyAnalysis.enabled (← getOptions) cfg.autoDeps then
      liftM <| DependencyAnalysis.inferExternalRefs resolvedExternalCode
    else
      pure {}
  let inferredUseRefs := inferredDeps.toUseRefs cfg.metadataUses (some cfg.label)
  let codeHint : Option Data.CodeRef :=
    if isProof then
      none
    else if hasExternal then
      some (.external resolvedExternalCode)
    else
      none
  pure {
    label := cfg.label
    labelSyntax := cfg.labelSyntax
    envKind
    codeHint
    parent := cfg.parent
    priority
    owner
    tags
    effort
    prUrl
    issueUrl
    statementUses := inferredUseRefs.statement
    proofUses := inferredUseRefs.proof
  }

end Informal
