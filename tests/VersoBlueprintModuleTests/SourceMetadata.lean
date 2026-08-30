/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Source.Metadata
meta import VersoBlueprint.Source.Metadata

namespace VersoBlueprintModuleTests.SourceMetadata

open Lean
open Verso Doc Elab
open Lean.Doc.Syntax

example (block : TSyntax `block) : DocElabM (Option (TSyntax `term)) :=
  Informal.Source.Metadata.metadataTerm? block

example (contents : Array (TSyntax `block)) :
    DocElabM Informal.Source.Metadata.LeadingMetadata :=
  Informal.Source.Metadata.splitLeadingMetadata contents

meta example (stx : TSyntax `term) :
    TermElabM Informal.Source.NodeMetadataInput :=
  Informal.Source.Metadata.evalNodeMetadataInput stx

meta example (stx : TSyntax `term) :
    TermElabM Informal.Source.DocumentMetadata :=
  Informal.Source.Metadata.evalDocumentMetadata stx

end VersoBlueprintModuleTests.SourceMetadata
