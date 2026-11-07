/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean.Data.Options

namespace Informal.Commands

open Lean

register_option verso.blueprint.debug.commands : Bool := {
  defValue := false
  descr := "Emit debug info logs for blueprint graph, summary, and bibliography commands"
}

def blueprintTokensCss : String := r##"
:root {
  --bp-color-surface: #ffffff;
  --bp-color-surface-muted: #f8fafc;
  --bp-color-surface-subtle: #f9fafb;
  --bp-color-surface-warn: #fff7ed;
  --bp-color-surface-warn-soft: #ffedd5;
  --bp-color-border: #cbd5e1;
  --bp-color-border-soft: #e2e8f0;
  --bp-color-border-muted: #d1d5db;
  --bp-color-border-panel: #dbe4ee;
  --bp-color-border-strong: #94a3b8;
  --bp-color-text-strong: #0f172a;
  --bp-color-text: #111827;
  --bp-color-text-muted: #334155;
  --bp-color-text-subtle: #475569;
  --bp-color-text-faint: #64748b;
  --bp-color-accent-success: #16a34a;
  --bp-color-accent-warning: #ca8a04;
  --bp-color-accent-danger: #dc2626;
  --bp-color-accent-info: #7c3aed;
  --bp-color-status-success-text: #166534;
  --bp-color-status-warning-text: #a16207;
  --bp-color-status-warning-strong: #9a3412;
  --bp-color-status-warning-border: #fdba74;
  --bp-color-status-warning-border-soft: #fed7aa;
  --bp-color-status-error-text: #b91c1c;
  --bp-color-status-error-strong: #991b1b;
  --bp-color-status-error-border-soft: #fecaca;
  --bp-color-focus-border: #93c5fd;
  --bp-color-focus-surface: #eff6ff;
  --bp-color-focus-ring: rgba(59, 130, 246, 0.12);
  --bp-color-selection: rgba(59, 130, 246, 0.18);
  --bp-color-selection-ring: rgba(59, 130, 246, 0.22);
  --bp-color-selection-surface-strong: rgba(59, 130, 246, 0.28);
  --bp-color-selection-surface-soft: rgba(59, 130, 246, 0.14);
  --bp-color-selection-surface-faint: rgba(59, 130, 246, 0.1);
  --bp-color-selection-shadow-strong: rgba(59, 130, 246, 0.3);
  --bp-color-selection-shadow-soft: rgba(59, 130, 246, 0.24);
  --bp-color-selection-shadow-faint: rgba(59, 130, 246, 0.16);
  --bp-color-target-ring: rgba(37, 99, 235, 0.22);
  --bp-color-target-surface: rgba(37, 99, 235, 0.14);
  --bp-color-target-ring-strong: rgba(37, 99, 235, 0.28);
  --bp-color-biblio-border: #d6ccff;
  --bp-color-biblio-surface: #faf7ff;
  --bp-color-biblio-border-soft: #e9ddff;
  --bp-color-biblio-surface-soft: #fdfbff;
  --bp-color-biblio-link: #4c1d95;
  --bp-radius-sm: 0.35rem;
  --bp-radius-md: 0.45rem;
  --bp-radius-lg: 0.5rem;
  --bp-radius-xl: 0.55rem;
  --bp-radius-pill: 999px;
  --bp-shadow-sm: 0 4px 14px rgba(15, 23, 42, 0.1);
  --bp-shadow-md: 0 10px 24px rgba(15, 23, 42, 0.16);
  --bp-shadow-lg: 0 12px 28px rgba(15, 23, 42, 0.18);
}

/* Verso sets no body font, so Blueprint chrome would fall back to the browser default. */
body {
  font-family: var(--verso-structure-font-family, sans-serif);
}
"##

/--
The shared preview panel shell. Every Blueprint popup uses it: a header with an
eyebrow naming the kind of popup, a title and label link, and a close button; a
scrolling body; and an optional footer. Role classes add only size and placement.
-/
def previewPanelCss : String := r##"
.bp_preview_panel {
  --bp-preview-panel-radius: 0.625rem;
  box-sizing: border-box;
  display: flex;
  flex-direction: column;
  min-width: 0;
  border: 1px solid var(--bp-color-border-panel);
  border-radius: var(--bp-preview-panel-radius);
  background: var(--bp-color-surface);
  box-shadow: var(--bp-shadow-lg);
  color: var(--bp-color-text);
  font-style: normal;
  font-weight: 400;
  text-align: left;
}

.bp_preview_panel[hidden] {
  display: none !important;
}

/* Keep a hovered panel open while the pointer crosses the gap from its trigger. */
.bp_preview_panel[data-bp-preview-placement="anchored"]::before,
.bp_preview_panel[data-bp-preview-placement="anchored"]::after {
  content: "";
  position: absolute;
  left: 0;
  right: 0;
  height: 0.75rem;
}

.bp_preview_panel[data-bp-preview-placement="anchored"]::before {
  top: -0.75rem;
}

.bp_preview_panel[data-bp-preview-placement="anchored"]::after {
  bottom: -0.75rem;
}

.bp_preview_panel_header {
  flex: none;
  display: flex;
  align-items: flex-start;
  gap: 0.75rem;
  padding: 0.7rem 0.5rem 0.6rem 1rem;
  border-bottom: 1px solid var(--bp-color-border-soft);
}

.bp_preview_panel_heading {
  flex: 1 1 auto;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
}

.bp_preview_panel_eyebrow {
  color: var(--bp-color-text-faint);
  font-size: 0.6875rem;
  font-weight: 600;
  letter-spacing: 0.06em;
  line-height: 1.3;
  text-transform: uppercase;
}

.bp_preview_panel_titleline {
  display: flex;
  align-items: baseline;
  flex-wrap: wrap;
  gap: 0.15rem 0.5rem;
  min-width: 0;
}

.bp_preview_panel_title {
  min-width: 0;
  color: var(--bp-color-text-strong);
  font-size: 0.9375rem;
  font-weight: 700;
  line-height: 1.35;
  overflow-wrap: anywhere;
}

.bp_preview_panel_title a {
  color: inherit;
  text-decoration: none;
}

.bp_preview_panel_title a:hover,
.bp_preview_panel_label[href]:hover {
  color: var(--bp-color-link, #1d4ed8);
  text-decoration: underline;
}

.bp_preview_panel_label {
  color: var(--bp-color-text-faint);
  font-family: var(--bp-font-mono, ui-monospace, SFMono-Regular, Menlo, Consolas, monospace);
  font-size: 0.75rem;
  overflow-wrap: anywhere;
  text-decoration: none;
}

.bp_preview_panel_eyebrow[hidden],
.bp_preview_panel_label[hidden],
.bp_preview_panel_footer[hidden] {
  display: none;
}

.bp_preview_panel_close {
  flex: none;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 2.25rem;
  height: 2.25rem;
  margin: -0.45rem 0;
  padding: 0;
  border: 0;
  border-radius: 0.375rem;
  background: transparent;
  color: var(--bp-color-text-subtle);
  cursor: pointer;
}

.bp_preview_panel_close svg {
  fill: none;
  stroke: currentColor;
  stroke-width: 1.6;
  stroke-linecap: round;
}

.bp_preview_panel_close:hover {
  background: var(--bp-color-surface-muted);
  color: var(--bp-color-text-strong);
}

.bp_preview_panel_close:focus-visible {
  outline: 2px solid var(--bp-color-focus-border);
  outline-offset: -2px;
}

.bp_preview_panel[data-bp-preview-mode="hover"] .bp_preview_panel_close {
  display: none;
}

.bp_preview_panel_body {
  flex: 1 1 auto;
  min-height: 0;
  overflow: auto;
  padding: 0.75rem 1rem 0.9rem;
  font-size: 0.9rem;
  line-height: 1.5;
}

/* Previewed content keeps its own spacing, except at the body's edges. */
.bp_preview_panel_body > :first-child,
.bp_preview_panel_body > :first-child > :first-child {
  margin-top: 0;
}

.bp_preview_panel_body > :last-child,
.bp_preview_panel_body > :last-child > :last-child {
  margin-bottom: 0;
}

.bp_preview_panel_footer {
  flex: none;
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 0.35rem 0.75rem;
  padding: 0.55rem 1rem;
  border-top: 1px solid var(--bp-color-border-soft);
  border-radius: 0 0 var(--bp-preview-panel-radius) var(--bp-preview-panel-radius);
  background: var(--bp-color-surface-muted);
  color: var(--bp-color-text-subtle);
  font-size: 0.78rem;
}

.bp_preview_panel_footer code {
  font-size: 0.75rem;
}
"##

def previewHeaderCss : String := r##"
.bp_preview_header_heading {
  display: flex;
  align-items: baseline;
  flex-wrap: wrap;
  gap: 0.42rem;
  flex: 1 1 auto;
  min-width: 0;
}

.bp_preview_header_heading > *:first-child {
  min-width: 0;
}

.bp_preview_header_label {
  margin-left: auto;
  max-width: 100%;
  color: var(--bp-color-text-muted);
  font-family: var(--bp-font-mono, ui-monospace, SFMono-Regular, Menlo, Consolas, monospace);
  font-size: 0.72rem;
  font-weight: 600;
  overflow-wrap: anywhere;
  text-align: right;
  text-decoration: none;
}

.bp_preview_header_label[href]:hover {
  color: var(--bp-color-link);
  text-decoration: underline;
}

.bp_preview_header_label[hidden] {
  display: none;
}
"##

def inlinePreviewCss : String := r##"
.bp_inline_preview_ref {
  cursor: help;
}

.bp_preview_panel.bp_inline_preview_panel {
  position: fixed;
  z-index: 70;
  min-width: 18rem;
  max-width: min(34rem, calc(100vw - 1.5rem));
  max-height: min(26rem, 80vh);
}

.bp_preview_panel.bp_inline_preview_panel_child {
  z-index: 71;
}

.bp_preview_panel.bp_inline_preview_panel[data-bp-preview-placement="docked"] {
  top: 0.9rem;
  right: 0.9rem;
  left: auto;
}

.bp_bibliography_hover_entry {
  border: 1px solid var(--bp-color-border-soft);
  border-radius: 0.4rem;
  padding: 0.35rem 0.45rem;
  background: var(--bp-color-surface-muted);
}

.bp_bibliography_hover_entry .citation {
  display: block;
  line-height: 1.35;
}

.bp_bibliography_hover_meta {
  margin-top: 0.42rem;
  display: flex;
  align-items: baseline;
  gap: 0.42rem;
  flex-wrap: wrap;
}

.bp_bibliography_hover_meta_label {
  font-size: 0.68rem;
  font-weight: 700;
  letter-spacing: 0.05em;
  text-transform: uppercase;
  color: var(--bp-color-text-faint);
}

.bp_bibliography_hover_meta_value {
  font-size: 0.76rem;
  font-weight: 600;
  color: var(--bp-color-text-strong);
}

.bp_code_hover_section {
  margin-top: 0.28rem;
}

.bp_code_hover_label {
  font-weight: 600;
  color: var(--bp-color-text-muted);
}

.bp_code_hover_list code {
  font-size: 0.76rem;
}

.bp_code_hover_none {
  color: var(--bp-color-text-faint);
  font-style: italic;
}

"##

/--
Logical Blueprint browser assets before choosing a physical output mode.

Manual renderers currently inline these lists through Verso `HtmlAssets`.
JavaScript startup is supplied by the generated ESM page runtime instead of
these command-local bundles.
-/
structure BlueprintAssetBundle where
  css : List String := []
  js : List String := []
deriving Inhabited

namespace BlueprintAssetBundle

def append (left right : BlueprintAssetBundle) : BlueprintAssetBundle :=
  { css := left.css ++ right.css
    js := left.js ++ right.js }

def withCss (assets : BlueprintAssetBundle) (extras : List String) : BlueprintAssetBundle :=
  { assets with css := assets.css ++ extras }

end BlueprintAssetBundle

def blueprintCssAssetBundle (extras : List String := []) : BlueprintAssetBundle :=
  ({ css := [blueprintTokensCss] } : BlueprintAssetBundle).withCss extras

/-- Styles for pages with popups: the shared panel shell first, so `extras` can size
and place each popup role. -/
def previewPanelCssAssetBundle (extras : List String := []) : BlueprintAssetBundle :=
  blueprintCssAssetBundle ([previewPanelCss, previewHeaderCss, inlinePreviewCss] ++ extras)

def previewPanelAssetBundle
    (cssExtras : List String := [])
    (jsBefore : List String := [])
    (jsAfter : List String := []) : BlueprintAssetBundle :=
  (previewPanelCssAssetBundle cssExtras).append
    ({ js := jsBefore ++ jsAfter } : BlueprintAssetBundle)

end Informal.Commands
