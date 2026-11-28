/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint

open Informal

namespace Verso.VersoBlueprintTests.BlueprintAttribute.DocstringProvider

set_option doc.verso true

/--
The premise is {uses "attr.doc.target" (intent := "technical")}[].
See {bpref "attr.doc.link"}[*the comparison* $`x + 1`] and
{bpref "attr.doc.link"}[].

* A repeated {uses "attr.doc.target" (intent := "technical")}[premise].
* An excluded {uses "attr.doc.excluded"}[dependency].
* A self-reference {uses "attr.doc.source"}[here].

# Supporting material

{uses "attr.doc.automatic" (origin := "automatic") (intent := "auxiliary")}[Support].
-/
@[blueprint "attr.doc.source" (autoDeps := true)
  (uses := [-"attr.doc.excluded"])
  (proofUses := ["attr.doc.proof"])]
def source : Nat := 0

@[blueprint "attr.doc.target"]
def target : Nat := 1

@[blueprint "attr.doc.link"]
def linkOnly : Nat := 2

@[blueprint "attr.doc.automatic"]
def automatic : Nat := 3

@[blueprint "attr.doc.excluded"]
def excluded : Nat := 4

@[blueprint "attr.doc.proof"]
def proofDependency : Nat := 5

/-- A later body with {uses "attr.doc.ignored"}[] must not replace the first. -/
@[blueprint "attr.doc.source"]
def laterBody : Nat := 6

@[blueprint "attr.doc.late" (uses := ["attr.doc.target"])]
def bodyless : Nat := 7

/-- A late body referencing {uses "attr.doc.automatic"}[support]. -/
@[blueprint "attr.doc.late"]
def lateBody : Nat := 8

/-- Untagged documentation uses {uses "attr.doc.target" (intent := "technical")}[] and links to {bpref "attr.doc.link"}[]. -/
def untagged : Nat := 9

@[inherit_doc source]
def inherited : Nat := 10

attribute [blueprint "attr.doc.inherited"] inherited

set_option doc.verso false in
/--
Before the Markdown separator.

---

After the Markdown separator.
-/
@[blueprint "attr.doc.markdownFallback"]
def markdownFallback : Nat := 11

end Verso.VersoBlueprintTests.BlueprintAttribute.DocstringProvider
