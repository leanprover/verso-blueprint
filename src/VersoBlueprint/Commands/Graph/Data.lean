/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Lean
public import VersoBlueprint.Graph
public import VersoBlueprint.Lib.HoverRender

public section

namespace Informal.Commands

open Lean

/-- Serialized payload shared by graph authoring and runtime block rendering. -/
structure GraphBlockData where
  graphModel : Informal.Graph.GraphModel
  options : Informal.Graph.GraphOptions := {}
  previewMode : Informal.HoverRender.PreviewMode := .pinned
  previewPlacement : Informal.HoverRender.PreviewPlacement := .docked
deriving Inhabited, FromJson, ToJson

/-- Parse the user-facing graph preview behavior. -/
def parseGraphPreviewMode? (s : String) : Option Informal.HoverRender.PreviewMode :=
  match s.trimAscii.toString.toLower with
  | "hover" => some .hover
  | "pinned" => some .pinned
  | _ => none

/-- Parse the user-facing graph preview-panel placement. -/
def parseGraphPreviewPlacement? (s : String) : Option Informal.HoverRender.PreviewPlacement :=
  match s.trimAscii.toString.toLower with
  | "docked" => some .docked
  | "anchored" => some .anchored
  | _ => none

end Informal.Commands
