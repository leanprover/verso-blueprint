/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoManual
public import VersoBlueprint.Source.Data

public section

namespace Informal.Source.Metadata

open Lean Elab Term
open Verso Doc Elab
open Lean.Doc.Syntax

/-- Reconstruct the Lean structure-initializer term carried by a Verso metadata block. -/
def metadataTerm? (block : TSyntax `block) : DocElabM (Option (TSyntax `term)) := do
  match block with
  | `(block|%%%%$_ $fieldOrAbbrev* %%%%$_) =>
      return some (← `(term| { $fieldOrAbbrev* }))
  | _ =>
      return none

def isMetadataBlock (block : TSyntax `block) : DocElabM Bool := do
  return (← metadataTerm? block).isSome

structure LeadingMetadata where
  term? : Option (TSyntax `term) := none
  body : Array (TSyntax `block) := #[]

/--
Split off the optional leading metadata block used by Blueprint source syntax.
The remaining blocks stay in original order so callers can render or reject them.
-/
def splitLeadingMetadata (contents : Array (TSyntax `block)) : DocElabM LeadingMetadata := do
  match contents[0]? with
  | some first =>
      match ← metadataTerm? first with
      | some term => pure { term? := some term, body := contents[1:] }
      | none => pure { body := contents }
  | none =>
      pure {}

/-- Keep visible blocks while letting callers report metadata that appears too late. -/
def visibleBlocksWithoutMetadata
    (contents : Array (TSyntax `block))
    (onMetadataBlock : TSyntax `block → DocElabM Unit) :
    DocElabM (Array (TSyntax `block)) := do
  let mut body := #[]
  for block in contents do
    if ← isMetadataBlock block then
      onMetadataBlock block
    else
      body := body.push block
  pure body

/-
Verso section metadata stays as syntax until the generated `Part.mk` term is
elaborated. Source provenance needs a typed value during directive expansion so
it can be validated and stored in Blueprint block data; this is the one unsafe
evaluation boundary for that conversion.
-/
private unsafe def evalMetadataValueUnsafe
    (α : Type) (expectedType : Name) (stx : TSyntax `term) : TermElabM α := do
  let ty := Lean.mkConst expectedType
  let expr ← elabTermAndSynthesize stx (some ty)
  Meta.evalExpr α ty expr

@[implemented_by evalMetadataValueUnsafe]
private opaque evalMetadataValue
    (α : Type) (expectedType : Name) (stx : TSyntax `term) : TermElabM α

/-- Evaluate a `:::source_document` metadata block into typed source-document metadata. -/
def evalDocumentMetadata
    (stx : TSyntax `term) : TermElabM Informal.Source.DocumentMetadata :=
  evalMetadataValue Informal.Source.DocumentMetadata ``Informal.Source.DocumentMetadata stx

/-- Evaluate a Blueprint node metadata block into typed node-local source metadata. -/
def evalNodeMetadataInput
    (stx : TSyntax `term) : TermElabM Informal.Source.NodeMetadataInput := do
  evalMetadataValue Informal.Source.NodeMetadataInput ``Informal.Source.NodeMetadataInput stx

end Informal.Source.Metadata
