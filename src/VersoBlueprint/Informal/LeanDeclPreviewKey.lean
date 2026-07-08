/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean

namespace Informal.LeanDeclPreviewKey

open Lean

def domainName : Name := Name.mkSimple "Informal.LeanCodePreview"

private def namespaceRoot : Name :=
  Name.str (Name.str .anonymous "Informal") "LeanCodePreview"

private def inlineNamespaceRoot : Name :=
  Name.str namespaceRoot "Inline"

private partial def appendName (rootName : Name) (suffixName : Name) : Name :=
  match suffixName with
  | .anonymous => rootName
  | .str parent component => .str (appendName rootName parent) component
  | .num parent component => .num (appendName rootName parent) component

def targetName (decl : Name) : Name :=
  appendName namespaceRoot decl.eraseMacroScopes

def lookupKey (decl : Name) : String :=
  (targetName decl).toString

def inlineTargetName (label : Name) : Name :=
  appendName inlineNamespaceRoot label.eraseMacroScopes

def inlineLookupKey (label : Name) : String :=
  (inlineTargetName label).toString

end Informal.LeanDeclPreviewKey
