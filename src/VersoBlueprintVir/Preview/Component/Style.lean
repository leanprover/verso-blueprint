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

/-- Constant presentation belongs to CSS rather than per-render native objects.
Selectors are scoped to the preview; VS Code theme variables remain live. -/
def css : String := "
#vir-verso-preview { display: grid; gap: 8px; min-width: 0; padding: 8px 10px 12px;
  background: var(--vscode-editor-background, #ffffff); color: var(--vscode-editor-foreground, #24292f); }
#vir-verso-preview #vir-verso-shell { position: sticky; top: 0; z-index: 10; align-self: start;
  display: grid; gap: 8px; min-width: 0; padding-bottom: 8px; background: var(--vscode-editor-background, #ffffff); }
#vir-verso-preview #vir-verso-label { margin: 0; color: var(--vscode-descriptionForeground, #57606a);
  font-size: 0.68rem; font-weight: 700; letter-spacing: 0.04em; text-transform: uppercase; }
#vir-verso-preview #vir-verso-config { display: flex; flex-wrap: wrap; gap: 6px 14px; margin: 0;
  padding: 5px 8px 7px; border: 1px solid var(--vscode-panel-border, #d0d7de); border-radius: 5px; font-size: 0.72rem; }
#vir-verso-preview #vir-verso-config legend { padding: 0 4px; color: var(--vscode-descriptionForeground, #57606a); font-weight: 700; }
#vir-verso-preview #vir-verso-debug-panel { min-width: 0; margin: 0; padding: 5px 8px;
  border: 1px solid var(--vscode-panel-border, #d0d7de); border-left: 3px solid var(--vscode-editorWarning-foreground, #9a6700);
  border-radius: 5px; background: var(--vscode-textCodeBlock-background, #f6f8fa);
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 0.68rem; line-height: 1.35; overflow-wrap: anywhere; }
#vir-verso-preview .vir-verso-debug-note { margin: 0; color: var(--vscode-descriptionForeground, #57606a);
  font-family: ui-sans-serif, system-ui, sans-serif; font-size: 0.62rem; }
#vir-verso-preview .vir-verso-debug-details { margin: 0; color: var(--vscode-descriptionForeground, #57606a); }
"

/-- Create once per runtime-owned component factory. React reuses this immutable
element across shell updates; no runtime-global native handles are retained. -/
def createStylesheet : RuntimeM (Js Node) := do
  return ← <style data-verso-shell-styles="true">{Node.text (← JsValue.ofString css)}</style>

/-- Initial RPC errors can precede the document shell. This small status style
is not on the document traversal or shell-update hot path. -/
def status : ReactM (Js Props) := do
  js%{
    "padding" := (← js#"10px"),
    "border" := (← js#"1px solid var(--vscode-panel-border, #d0d7de)"),
    "borderRadius" := (← js#"5px"),
    "color" := (← js#"var(--vscode-descriptionForeground, #57606a)")
  }

end VersoBlueprint.Experimental.VirPreview.ComponentStyle
