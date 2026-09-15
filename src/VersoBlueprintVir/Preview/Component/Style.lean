/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Vir.ProofWidgets.Jsx

public section

namespace VersoBlueprint.Experimental.VirPreview.ComponentStyle

open Lean.Vir Lean.Vir.React
open scoped Lean.Vir.Js Lean.Vir.ProofWidgets.Jsx

private def vscodeColor (name fallback : String) : String :=
  "var(--vscode-" ++ name ++ ", " ++ fallback ++ ")"

private def border (color : String) : String :=
  "1px solid " ++ color

def foreground : String := vscodeColor "editor-foreground" "#24292f"
def muted : String := vscodeColor "descriptionForeground" "#57606a"
def background : String := vscodeColor "editor-background" "#ffffff"
def codeBackground : String := vscodeColor "textCodeBlock-background" "#f6f8fa"
def borderColor : String := vscodeColor "panel-border" "#d0d7de"
def debugForeground : String := vscodeColor "editorWarning-foreground" "#9a6700"

def shell : ReactM (Js Props) := do
  js%{
    "display" := (← JsValue.ofString ("grid")),
    "gap" := (← JsValue.ofString ("8px")),
    "minWidth" := (← JsValue.ofString ("0")),
    "padding" := (← JsValue.ofString ("8px 10px 12px")),
    "background" := (← JsValue.ofString (background)),
    "color" := (← JsValue.ofString (foreground))
  }

def label : ReactM (Js Props) := do
  js%{
    "margin" := (← JsValue.ofString ("0")),
    "color" := (← JsValue.ofString (muted)),
    "fontSize" := (← JsValue.ofString ("0.68rem")),
    "fontWeight" := (← JsValue.ofString ("700")),
    "letterSpacing" := (← JsValue.ofString ("0.04em")),
    "textTransform" := (← JsValue.ofString ("uppercase"))
  }

def configPanel : ReactM (Js Props) := do
  js%{
    "display" := (← JsValue.ofString ("flex")),
    "flexWrap" := (← JsValue.ofString ("wrap")),
    "gap" := (← JsValue.ofString ("6px 14px")),
    "margin" := (← JsValue.ofString ("0")),
    "padding" := (← JsValue.ofString ("5px 8px 7px")),
    "border" := (← JsValue.ofString (border borderColor)),
    "borderRadius" := (← JsValue.ofString ("5px")),
    "fontSize" := (← JsValue.ofString ("0.72rem"))
  }

def configLegend : ReactM (Js Props) := do
  js%{
    "padding" := (← JsValue.ofString ("0 4px")),
    "color" := (← JsValue.ofString (muted)),
    "fontWeight" := (← JsValue.ofString ("700"))
  }

def debugPanel : ReactM (Js Props) := do
  js%{
    "minWidth" := (← JsValue.ofString ("0")),
    "margin" := (← JsValue.ofString ("0")),
    "padding" := (← JsValue.ofString ("5px 8px")),
    "border" := (← JsValue.ofString (border borderColor)),
    "borderLeft" := (← JsValue.ofString ("3px solid " ++ debugForeground)),
    "borderRadius" := (← JsValue.ofString ("5px")),
    "background" := (← JsValue.ofString (codeBackground)),
    "fontFamily" := (← JsValue.ofString ("ui-monospace, SFMono-Regular, Menlo, Consolas, monospace")),
    "fontSize" := (← JsValue.ofString ("0.68rem")),
    "lineHeight" := (← JsValue.ofString ("1.35")),
    "overflowWrap" := (← JsValue.ofString ("anywhere"))
  }

def debugNote : ReactM (Js Props) := do
  js%{
    "margin" := (← JsValue.ofString ("0")),
    "color" := (← JsValue.ofString (muted)),
    "fontFamily" := (← JsValue.ofString ("ui-sans-serif, system-ui, sans-serif")),
    "fontSize" := (← JsValue.ofString ("0.62rem"))
  }

def debugDetails : ReactM (Js Props) := do
  js%{
    "margin" := (← JsValue.ofString ("0")),
    "color" := (← JsValue.ofString (muted))
  }

def status : ReactM (Js Props) := do
  js%{
    "padding" := (← JsValue.ofString ("10px")),
    "border" := (← JsValue.ofString (border borderColor)),
    "borderRadius" := (← JsValue.ofString ("5px")),
    "color" := (← JsValue.ofString (muted))
  }

end VersoBlueprint.Experimental.VirPreview.ComponentStyle
