/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import VersoManual

namespace Informal.Resolve

open Lean

def informalDomainName : Name := Name.mkSimple "Informal.Block.informal"
def informalCodeDomainName : Name := Name.mkSimple "Informal.Block.informalCode"
def informalRustCodeDomainName : Name := Name.mkSimple "Informal.Block.informalRustCode"
def informalPreviewDomainName : Name := Name.mkSimple "Informal.Block.informalPreview"
def informalGroupDomainName : Name := Name.mkSimple "Informal.Block.group"
/- 
Domain that stores anchors for rendered external declaration rows.

We intentionally keep this separate from `inlineLeanDeclDomainName`: inline Lean links are
declaration-centric (one destination per declaration), while rendered external rows are
reference-centric (one destination per `(informal label, canonical declaration)` pair). This
allows summary/graph UI to jump to the specific rendered instance, even when the same declaration
is referenced by many blueprint entries.
-/
def externalRenderedDeclDomainName : Name := Name.mkSimple "Informal.Block.externalRenderedDecl"
def bibliographyDomainName : Name := Name.mkSimple "Informal.Block.bpCitations"
def citationPreviewDomainName : Name := Name.mkSimple "Informal.Inline.bpCite.previews"
def citationUsageDomainName : Name := Name.mkSimple "Informal.Inline.bpCite.usages"
/--
Domain that stores declaration anchors for inline Lean code.

Blueprint code blocks currently elaborate via `Verso.Genre.Manual.InlineLean.Block.lean`,
which registers defined declarations in the Manual `example` domain through
`Verso.Genre.Manual.saveExampleDefs`. We intentionally reuse that index here.
-/
def inlineLeanDeclDomainName : Name := ``Verso.Genre.Manual.example

/--
Key for one rendered external declaration target.

The `decl` input should be canonicalized by callers (for example using `ExternalRef.canonical`).
-/
def externalRenderedDeclTargetKey (label decl : Name) : String :=
  let labelStr := label.toString
  let declStr := decl.toString
  s!"{labelStr.length}:{labelStr}|{declStr.length}:{declStr}"

def resolveDomainHref? (s : Verso.Genre.Manual.TraverseState) (domain : Name) (label : String) :
    Option String :=
  match s.resolveDomainObject domain label with
  | .ok dest => some dest.relativeLink
  | .error _ => none

def resolveDomainHrefs (s : Verso.Genre.Manual.TraverseState) (domain : Name) (label : String) :
    Array String :=
  match s.getDomainObject? domain label with
  | none => #[]
  | some obj =>
    let hrefs := obj.ids.toArray.filterMap fun id =>
      (s.externalTags[id]?).map (·.relativeLink)
    hrefs.qsort (fun a b => a < b)

def resolveInlineLeanDeclHref? (s : Verso.Genre.Manual.TraverseState) (decl : Name) : Option String :=
  match resolveDomainHref? s inlineLeanDeclDomainName decl.toString with
  | some href => some href
  | none =>
    match s.domains.get? inlineLeanDeclDomainName with
    | none => none
    | some dom =>
      let pref := decl.toString ++ " (in "
      let cands := dom.objects.foldl (init := #[]) fun acc key _obj =>
        if key == decl.toString || key.startsWith pref then
          acc.push key
        else
          acc
      if cands.size = 1 then
        resolveDomainHref? s inlineLeanDeclDomainName cands[0]!
      else
        none

def resolveRenderedExternalDeclHref? (s : Verso.Genre.Manual.TraverseState)
    (label decl : Name) : Option String :=
  resolveDomainHref? s externalRenderedDeclDomainName (externalRenderedDeclTargetKey label decl)

end Informal.Resolve
