/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
module

public import VersoBlueprintVirTests.NativeSession.DecodeProbe
meta import Vir.GeneratePackage.Interface.Encode
meta import Vir.Attributes
meta import all MultiVerso.InternalId

public section

namespace VersoBlueprintVirTests.NativeSession.DirectCodecProbe

open Lean Lean.Vir VersoBlueprint.Experimental.VirPreview

-- Explicit transitional leaf operations. The tree itself is constructed by JS;
-- these preserve custom extension/metadata codecs rather than guessing them.
private def failure (message : String) : RuntimeM α := by
  unfold RuntimeM
  exact throw (IO.userError message)

private def leaf [FromJson α] (input : Js.Any) : RuntimeM (JSL α) := do
  match ← Lean.Vir.JsonValue.decodeJs input with
  | .ok value => LeanRef.toJSL value
  | .error message => failure message

@[vir_export]
def inlineContainer (input : Js.Any) : RuntimeM (JSL Verso.Genre.Manual.Inline) := leaf input

@[vir_export]
def blockContainer (input : Js.Any) : RuntimeM (JSL Verso.Genre.Manual.Block) := leaf input

@[vir_export]
def metadata (input : Js.Any) : RuntimeM (JSL (Option Verso.Genre.Manual.PartMetadata)) := leaf input

@[vir_export]
def serverTiming (input : Js.Any) : RuntimeM (JSL (Option ServerTiming)) := leaf input

@[vir_export]
def name (input : Js String) : RuntimeM (JSL Name) := do
  let text ← JsValue.toString input
  match (fromJson? (.str text) : Except String Name) with
  | .ok value => LeanRef.toJSL value
  | .error message => failure message

@[vir_export]
def properties (input : Js.Any) : RuntimeM (JSL (NameMap String)) := leaf input

@[vir_export]
def finish (input : JSL Preview) : RuntimeM (JSL (Except String Preview)) := do
  LeanRef.toJSL (.ok (← LeanRef.fromJSL input))

-- Keep baseline and real renderer in this same package for matched replay.
@[vir_export] def browserParsed := DecodeProbe.browserParsed
@[vir_export] def whole := DecodeProbe.whole
@[vir_export] def describe := DecodeProbe.describe
@[vir_export] def equivalent := DecodeProbe.equivalent
@[vir_export] def validateSource := DecodeProbe.validateSource
@[vir_export] def jsonEquivalent := DecodeProbe.jsonEquivalent
@[vir_export] def emptyIdentityState := DecodeProbe.emptyIdentityState
@[vir_export] def createView := DecodeProbe.createView
@[vir_export] def renderDecoded := DecodeProbe.renderDecoded

-- Generated artifact: constructor tags and field layouts come from the pinned
-- compiler, never a handwritten memory-layout table in the JS decoder.
meta section

run_elab do
  let mut rows : Array Json := #[]
  for name in #[``Lean.Doc.Inline, ``Lean.Doc.Block, ``Lean.Doc.Part,
      ``Lean.Doc.ListItem, ``Lean.Doc.DescItem, ``Lean.Doc.MathMode, ``Document, ``Preview,
      ``Verso.Genre.Manual.Inline, ``Verso.Genre.Manual.Block, ``Verso.Multi.InternalId,
      ``Lean.Json, ``Lean.JsonNumber, ``Std.TreeMap.Raw, ``Std.DTreeMap.Raw,
      ``Std.DTreeMap.Internal.Impl, ``Option] do
    let .inductInfo info ← getConstInfo name | throwError "expected inductive {name}"
    let trivial ← Lean.Compiler.LCNF.hasTrivialImpureStructure? name
    for ctor in info.ctors do
      let .ctorInfo ctorInfo ← getConstInfo ctor | throwError "expected constructor {ctor}"
      let layout ← Lean.Compiler.LCNF.getCtorLayout ctor
      let fields ← layout.fieldInfo.mapM fun field => do
        let some field := Vir.Interface.structureFieldLayout? field
          | throwError "unsupported erased field in {ctor}"
        match Json.parse field.toJson with
        | .ok json => pure json
        | .error error => throwError "invalid layout JSON: {error}"
      rows := rows.push (Json.mkObj [
        ("name", toJson ctor.toString), ("tag", toJson ctorInfo.cidx),
        ("objects", toJson layout.ctorInfo.size),
        ("usize", toJson layout.ctorInfo.usize),
        ("scalarBytes", toJson layout.ctorInfo.ssize),
        ("trivial", toJson (trivial.map (·.fieldIdx))),
        ("fields", .arr fields)])
  liftM <| IO.FS.createDirAll ".deps/direct-codec"
  liftM <| IO.FS.writeFile ".deps/direct-codec/layouts.json" (Json.arr rows).compress

end
end VersoBlueprintVirTests.NativeSession.DirectCodecProbe
