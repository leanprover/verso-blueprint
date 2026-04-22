/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Informal.Block.Model

namespace Informal

structure MetadataBadgeSpec where
  text : String
  warning : Bool := false
deriving Repr, Inhabited

structure MetadataActionLink where
  label : String
  href : String
deriving Repr, Inhabited

structure MetadataPresentation where
  ownerText : Option String := none
  effort : Option String := none
  priority : Option String := none
  prUrl : Option String := none
  tags : Array String := #[]
deriving Repr, Inhabited

def MetadataPresentation.hasAny (metadata : MetadataPresentation) : Bool :=
  metadata.ownerText.isSome || metadata.effort.isSome || metadata.priority.isSome ||
    metadata.prUrl.isSome || !metadata.tags.isEmpty

def MetadataPresentation.summaryBadgeSpecs (metadata : MetadataPresentation) : Array MetadataBadgeSpec :=
  let ownerBadges :=
    match metadata.ownerText with
    | some owner => #[{ text := s!"owner: {owner}" }]
    | none => #[]
  let effortBadges :=
    match metadata.effort with
    | some effort => #[{ text := s!"effort: {effort}" }]
    | none => #[]
  let priorityBadges :=
    match metadata.priority with
    | some priority => #[{ text := s!"priority: {priority}", warning := true }]
    | none => #[]
  let tagBadges :=
    metadata.tags.map fun tag => { text := s!"tag: {tag}" }
  ownerBadges ++ effortBadges ++ priorityBadges ++ tagBadges

def MetadataPresentation.summaryActionLinks (metadata : MetadataPresentation) : Array MetadataActionLink :=
  match metadata.prUrl with
  | some href => #[{ label := "PR", href }]
  | none => #[]

def BlockData.metadataPresentation (data : BlockData) : MetadataPresentation := {
  ownerText := data.ownerDisplayName <|> data.owner.map toString
  effort := data.effort
  priority := data.priority
  prUrl := data.prUrl
  tags := data.tags
}

end Informal
