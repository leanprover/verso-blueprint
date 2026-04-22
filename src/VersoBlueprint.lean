/-
Copyright (c) 2025 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias, David Thrane Christiansen
-/

-- XXX VersoManual is not module yet
-- module

-- Blueprint library extending the Verso `Manual` genre.

import Lean.Elab.InfoTree.Types

import VersoManual

import VersoBlueprint.Data
import VersoBlueprint.ProvedStatus
import VersoBlueprint.ExternalRefSnapshot
import VersoBlueprint.Macros
import VersoBlueprint.Math
import VersoBlueprint.Rust
import VersoBlueprint.Environment
import VersoBlueprint.Attribute
import VersoBlueprint.Cite
import VersoBlueprint.Commands.Graph
import VersoBlueprint.Commands.Summary
import VersoBlueprint.Commands.Bibliography
import VersoBlueprint.Informal.Block.Assets
import VersoBlueprint.Informal.Code
import VersoBlueprint.Informal.RustBlock
import VersoBlueprint.Informal.Block
import VersoBlueprint.Informal.Block.Store
import VersoBlueprint.Informal.MetadataView
import VersoBlueprint.Informal.LeanDeclPreviewKey
import VersoBlueprint.Informal.LeanCodePreview
import VersoBlueprint.Informal.GroupData
import VersoBlueprint.Informal.Group
import VersoBlueprint.Informal.Author
import VersoBlueprint.Informal.Uses
import VersoBlueprint.DocGenNameRender
import VersoBlueprint.Lean
import VersoBlueprint.LabelNameParsing
import VersoBlueprint.LeanNameParsing
import VersoBlueprint.PreviewCache
import VersoBlueprint.PreviewManifest
import VersoBlueprint.Resolve
import VersoBlueprint.TraversalIndex
import VersoBlueprint.StyleSwitcher
import VersoBlueprint.Profiling

set_option doc.verso true
