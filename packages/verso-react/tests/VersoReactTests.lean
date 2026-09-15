/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoReact
public import VersoReactTests.Fingerprint
meta import VersoReact.Renderer
meta import Vir.Attributes

public section

namespace VersoReactTests

open Verso Verso.Doc VersoReact Lean.Vir Lean.Vir.React
open scoped Lean.Vir.Js Lean.Vir.ProofWidgets.Jsx

def paragraph (text : String) : Block Genre.Manual := .para #[.text text]

def document (content : Array (Block Genre.Manual)) : Part Genre.Manual :=
  .mk #[.text "Independent Verso renderer"] "Independent Verso renderer" none content #[]

private def before := document (#["A", "B", "C"].map paragraph)
private def inserted := document (#["A", "X", "B", "C"].map paragraph)
private def moved := document (#["C", "A", "B"].map paragraph)

#guard Renderer.changedBlockIds before before |>.isEmpty
#guard Renderer.changedBlockIds before inserted == #["part-root-block-1"]
#guard Renderer.changedBlockIdsAndCount (some before) inserted == (#["part-root-block-1"], 5)
#guard Renderer.changedBlockIds before moved |>.isEmpty

private def extension (name : Lean.Name) : Genre.Manual.Block := { name, data := .null }

private def applicationExtensions : Renderer.Extensions := {
  blockIdentity? := fun ext => if ext.name == `Test.notice then some "notice" else none
  renderBlock? := fun key attributes ext children => do
    if ext.name == `Test.hidden then
      let props ← js%{ "key" := (← JsValue.ofString key) }
      return some (← Node.fragment props (← Js.Array.empty))
    else if ext.name == `Test.notice then
      let props ← attributes "notice" (← Renderer.Style.unsupported)
      let childNodes ← children ()
      return some (← <aside @props={props}>{...childNodes.map pure}</aside>)
    else return none
}

private def notice (text : String) : Block Genre.Manual :=
  .other (extension `Test.notice) #[paragraph text]

#guard Renderer.changedBlockIds (document #[notice "old"]) (document #[notice "new"])
    applicationExtensions == #["part-root-block-0", "part-root-block-0-block-0"]

private def rich : Part Genre.Manual := document #[
  .para #[.text "Plain ", .emph #[.text "emphasis"], .bold #[.text "strong"],
    .code "<script>unsafe()</script>", .link #[.text "Lean"] "https://lean-lang.org/",
    .math .inline "x < y", .math .display "x^2",
    .other { name := `Test.inline, data := .null } #[.text "inline child"]],
  .code "#check Nat",
  .ul #[.mk #[paragraph "unordered"]],
  .ol 3 #[.mk #[paragraph "ordered"]],
  .dl #[.mk #[.text "Term"] #[paragraph "Definition"]],
  .blockquote #[paragraph "Quotation"],
  .other (extension `Test.unknown) #[paragraph "unknown child"],
  notice "notice child",
  .other (extension `Test.hidden) #[paragraph "hidden child"]
]

/-- Test export only: the library itself has no runtime or widget entry point. -/
@[vir_export]
def render (scenario : Nat) : ReactM (Js Node) :=
  Renderer.render (match scenario with
    | 0 => before | 1 => inserted | 2 => moved
    | 4 => document #[.concat #[.concat #[],
        .concat #[paragraph "first", paragraph "second"], paragraph "third"], paragraph "unrelated"]
    | 5 => { rich with content := #[paragraph "Inserted before retained parents"] ++ rich.content }
    | _ => rich)
    { focus := if scenario == 4 then some "part-root-block-0" else none } applicationExtensions

end VersoReactTests
