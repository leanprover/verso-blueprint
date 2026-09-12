/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Vir.React

public section

namespace VersoBlueprint.Experimental.VirPreview.ComponentStyle

open Lean.Vir.React

private def style (entries : Array (String × String)) : Props.Entry :=
  Props.stylePairs entries

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

def shell : Props.Entry := style #[
  ("display", "grid"),
  ("gap", "8px"),
  ("minWidth", "0"),
  ("padding", "8px 10px 12px"),
  ("background", background),
  ("color", foreground)
]

def label : Props.Entry := style #[
  ("margin", "0"),
  ("color", muted),
  ("fontSize", "0.68rem"),
  ("fontWeight", "700"),
  ("letterSpacing", "0.04em"),
  ("textTransform", "uppercase")
]

def configPanel : Props.Entry := style #[
  ("display", "flex"),
  ("flexWrap", "wrap"),
  ("gap", "6px 14px"),
  ("margin", "0"),
  ("padding", "5px 8px 7px"),
  ("border", border borderColor),
  ("borderRadius", "5px"),
  ("fontSize", "0.72rem")
]

def configLegend : Props.Entry := style #[
  ("padding", "0 4px"),
  ("color", muted),
  ("fontWeight", "700")
]

def debugPanel : Props.Entry := style #[
  ("margin", "0"),
  ("padding", "5px 8px"),
  ("border", border borderColor),
  ("borderLeft", "3px solid " ++ debugForeground),
  ("borderRadius", "5px"),
  ("background", codeBackground),
  ("fontFamily", "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"),
  ("fontSize", "0.68rem"),
  ("lineHeight", "1.35"),
  ("overflowWrap", "anywhere")
]

def debugBody : Props.Entry := style #[
  ("display", "grid"),
  ("gap", "6px")
]

def debugNote : Props.Entry := style #[
  ("margin", "0"),
  ("color", muted),
  ("fontFamily", "ui-sans-serif, system-ui, sans-serif"),
  ("fontSize", "0.62rem")
]

def debugDetails : Props.Entry := style #[
  ("margin", "0"),
  ("color", muted)
]

def status : Props.Entry := style #[
  ("padding", "10px"),
  ("border", border borderColor),
  ("borderRadius", "5px"),
  ("color", muted)
]

end VersoBlueprint.Experimental.VirPreview.ComponentStyle
