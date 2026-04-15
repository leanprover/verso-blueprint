/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias

Compatibility single-declaration renderer used by the blueprint external-code path.
This is intentionally outside `Vendor/` so vendor files can stay upstream-identical.
-/

import Lean
import VersoBlueprint.Vendor.DocGen4.ToHtmlFormat

open Lean

namespace Informal

structure DeclHtmlInput where
  moduleName : Name
  declName : Name
  kindDescription : String
  typeText : String
  docString? : Option String := none
  fields : Array String := #[]
  constructors : Array String := #[]
  deriving Inhabited, Repr

private def kindClass (kind : String) : String :=
  match kind with
  | "def" => "def"
  | "abbrev" => "def abbrev"
  | "theorem" => "theorem"
  | "axiom" => "axiom"
  | "opaque" => "opaque"
  | "class" => "class"
  | "structure" => "structure"
  | "inductive" | "constructor" | "recursor" => "inductive"
  | _ => "def"

private def codeSpan (code : String) : DocGen4.Html :=
  .element "code" true #[] #[.text code]

private def docStringHtml (doc? : Option String) : Array DocGen4.Html :=
  match doc? with
  | none => #[]
  | some txt => #[.element "pre" false #[("class", "docstring")] #[.text txt]]

private def sectionListHtml (cls title : String) (items : Array String) : Array DocGen4.Html :=
  if items.isEmpty then
    #[]
  else
    let children := items.map fun item => .element "li" true #[] #[.text item]
    #[.element "details" false #[("class", cls)]
        #[
          .element "summary" true #[] #[.text title],
          .element "ul" false #[] children
        ]]

/-- Minimal declaration HTML rendering entry point. -/
def docInfoToHtml (input : DeclHtmlInput) : DocGen4.Html :=
  let headerChildren :=
    #[
      .element "span" true #[("class", "decl_kind")] #[.text input.kindDescription],
      .text " ",
      .element "span" true #[("class", "decl_name")] #[.text input.declName.toString],
      .text " : ",
      .element "span" true #[("class", "decl_type")] #[codeSpan input.typeText]
    ]
  let children :=
    #[.element "div" false #[("class", "decl_header")] headerChildren] ++
    docStringHtml input.docString? ++
    sectionListHtml "fields" "Fields" input.fields ++
    sectionListHtml "constructors" "Constructors" input.constructors
  .element "div" false
    #[(
      "class", s!"declaration decl {kindClass input.kindDescription}"),
      ("data-module", input.moduleName.toString),
      ("data-decl", input.declName.toString)
    ]
    children

end Informal
