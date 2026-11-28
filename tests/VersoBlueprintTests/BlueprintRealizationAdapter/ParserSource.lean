/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean

namespace RealizationParserFixture

/-- Source docstring for compiled standalone inheritance tests. -/
theorem inheritSource : True := True.intro

/-- Direct comment overridden by standalone inherit_doc. -/
theorem standaloneInherited : True := True.intro

attribute [inherit_doc inheritSource] standaloneInherited

/-- Direct comment overridden through open renaming. -/
theorem renamedInherited : True := True.intro

open RealizationParserFixture renaming renamedInherited → renamedAlias in
attribute [inherit_doc inheritSource] renamedAlias

namespace ExportShadow
namespace Before
/-- Source sentinel. -/
theorem source : True := True.intro
/-- Original direct comment. -/
theorem target : True := True.intro
end Before
namespace Other
/-- Unrelated sibling target. -/
theorem target : True := True.intro
end Other
namespace Local
open Before
attribute [inherit_doc Before.source] target
export Other (target)
end Local
end ExportShadow

section
set_option doc.verso true

/-- {name (full := Nat.add)}`add` -/
theorem versoLinkNat : True := True.intro

/-- {name (full := Int.add)}`add` -/
theorem versoLinkDirect : True := True.intro

/-- {name (full := Int.add)}`add` -/
theorem versoLinkInherited : True := True.intro

attribute [inherit_doc versoLinkNat] versoLinkInherited
end

end RealizationParserFixture
