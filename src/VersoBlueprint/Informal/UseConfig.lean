/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public meta import VersoBlueprint.Data
public meta import VersoBlueprint.DirectiveArgParsing
public meta import VersoBlueprint.LabelNameParsing

public meta section

namespace Informal.UseConfig

/-- Human-readable list of accepted dependency-origin values for diagnostics. -/
def allowedOriginValues : String := "\"manual\", \"automatic\""

/-- Human-readable list of accepted dependency-intent values for diagnostics. -/
def allowedIntentValues : String := "\"regular\", \"auxiliary\", \"technical\""

/--
Shared dependency-edge metadata accepted by block-level `(uses := ...)` options
and inline `{uses ...}` roles.

Omitted metadata is normalized to a manual, regular edge. Invalid strings are
kept separately so each caller can report a context-specific diagnostic while
still constructing a well-formed default edge.
-/
structure Metadata where
  /-- Whether the edge was written by the author or inserted by automation. -/
  origin : Data.UseOrigin := .manual
  /-- Invalid user-written origin value, when present. -/
  invalidOrigin : Option String := none
  /-- Semantic classification for the edge. -/
  intent : Data.UseIntent := .regular
  /-- Invalid user-written intent value, when present. -/
  invalidIntent : Option String := none

/-- Parse a comma-separated list of informal labels from an optional string argument. -/
def parseLabels (raw? : Option String) : Array Data.Label :=
  match raw? with
  | none => #[]
  | some raw => DirectiveArgParsing.splitCommaSeparatedList raw |>.map LabelNameParsing.parse

/-- Parse an optional dependency-origin argument, defaulting to `manual`. -/
def parseOrigin (raw? : Option String) : Data.UseOrigin × Option String :=
  match raw? with
  | none => (.manual, none)
  | some raw =>
    let raw := raw.trimAscii.toString
    match Data.UseOrigin.parse? raw with
    | some origin => (origin, none)
    | none => (.manual, some raw)

/-- Parse an optional dependency-intent argument, defaulting to `regular`. -/
def parseIntent (raw? : Option String) : Data.UseIntent × Option String :=
  match raw? with
  | none => (.regular, none)
  | some raw =>
    let raw := raw.trimAscii.toString
    match Data.UseIntent.parse? raw with
    | some intent => (intent, none)
    | none => (.regular, some raw)

/-- Parse the shared dependency metadata accepted by block and inline use syntax. -/
def parseMetadata (origin? intent? : Option String) : Metadata :=
  let (origin, invalidOrigin) := parseOrigin origin?
  let (intent, invalidIntent) := parseIntent intent?
  { origin, invalidOrigin, intent, invalidIntent }

/--
Construct metadata-only dependency refs for labels from a block-level
`(uses := "label1, label2")` option.
-/
def refsForLabels (labels : Array Data.Label) (metadata : Metadata) : Array Data.UseRef :=
  labels.map fun label => {
    label
    origin := metadata.origin
    intent := metadata.intent
  }

end Informal.UseConfig
