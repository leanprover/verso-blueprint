/- Copyright (c) 2026 Lean FRO LLC. Released under Apache 2.0 license. -/
module

public section

namespace VersoReact.RenderPath

/-- Positional addresses shared by rendering and source navigation, not React keys. -/
def root : String := "part-root"

def child (parent segment : String) (index : Nat) : String :=
  s!"{parent}-{segment}-{index}"

def heading (part : String) : String := s!"{part}-heading"

end VersoReact.RenderPath
