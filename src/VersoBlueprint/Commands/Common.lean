/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Lean.Data.Options

public section

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
  --bp-color-surface-modern: #f8fbff;
  --bp-color-surface-warn: #fff7ed;
  --bp-color-surface-warn-soft: #ffedd5;
  --bp-color-surface-note: #fffbeb;
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
  --bp-color-status-note-border: #fcd34d;
  --bp-color-status-note-text: #92400e;
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
  --bp-color-modern-border: #d6deea;
  --bp-color-modern-surface-alt: #f5f9ff;
  --bp-color-modern-caption: #e0ecff;
  --bp-color-bold-surface-glow-1: rgba(251, 191, 36, 0.2);
  --bp-color-bold-surface-glow-2: rgba(16, 185, 129, 0.2);
  --bp-color-bold-link: #7c2d12;
  --bp-color-bold-label: #f59e0b;
  --bp-color-biblio-border: #d6ccff;
  --bp-color-biblio-surface: #faf7ff;
  --bp-color-biblio-border-soft: #e9ddff;
  --bp-color-biblio-surface-soft: #fdfbff;
  --bp-color-biblio-link: #4c1d95;
  --bp-radius-sm: 0.35rem;
  --bp-radius-md: 0.45rem;
  --bp-radius-lg: 0.5rem;
  --bp-radius-xl: 0.55rem;
  --bp-radius-2xl: 0.7rem;
  --bp-radius-3xl: 0.85rem;
  --bp-radius-pill: 999px;
  --bp-shadow-sm: 0 4px 14px rgba(15, 23, 42, 0.1);
  --bp-shadow-md: 0 10px 24px rgba(15, 23, 42, 0.16);
  --bp-shadow-lg: 0 12px 28px rgba(15, 23, 42, 0.18);
  --bp-shadow-modern: 0 6px 18px rgba(15, 23, 42, 0.08);
  --bp-shadow-bold: 0 7px 0 var(--bp-color-text-strong);
  --bp-shadow-bold-lg: 0 9px 0 var(--bp-color-text-strong);
}
"##

def previewPanelCss : String := r##"
.bp_preview_panel {
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-lg);
  background: var(--bp-color-surface);
  box-shadow: var(--bp-shadow-md);
  padding: 0.65rem 0.75rem;
}

.bp_preview_panel[hidden] {
  display: none !important;
}

.bp_preview_panel[data-bp-preview-placement="anchored"]::before {
  content: "";
  position: absolute;
  left: 0;
  right: 0;
  top: -0.85rem;
  height: 0.85rem;
}

.bp_preview_panel[data-bp-preview-placement="anchored"]::after {
  content: "";
  position: absolute;
  left: 0;
  right: 0;
  bottom: -0.85rem;
  height: 0.85rem;
}

.bp_preview_panel_header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.5rem;
  margin-bottom: 0.4rem;
}

.bp_preview_panel_title {
  font-weight: 700;
  color: var(--bp-color-text);
  min-width: 0;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.bp_preview_panel_close {
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-sm);
  background: var(--bp-color-surface);
  color: var(--bp-color-text-strong);
  font-size: 0.72rem;
  font-weight: 600;
  line-height: 1;
  padding: 0.25rem 0.45rem;
  cursor: pointer;
}

.bp_preview_panel[data-bp-preview-mode="hover"] .bp_preview_panel_close {
  display: none;
}

.bp_preview_panel_body {
  border-left: 2px solid var(--bp-color-border-soft);
  overflow: auto;
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

.bp_inline_preview_panel {
  position: fixed;
  display: flex;
  flex-direction: column;
  z-index: 70;
  min-width: 18rem;
  max-width: min(34rem, 86vw);
  max-height: min(26rem, 80vh);
  overflow: hidden;
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-md);
  background: var(--bp-color-surface);
  box-shadow: var(--bp-shadow-lg);
}

.bp_inline_preview_panel[hidden] {
  display: none !important;
}

.bp_inline_preview_panel_child {
  z-index: 71;
}

.bp_inline_preview_panel[hidden] {
  display: none;
}

.bp_inline_preview_panel[data-bp-preview-placement="anchored"]::before {
  content: "";
  position: absolute;
  left: 0;
  right: 0;
  top: -0.85rem;
  height: 0.85rem;
}

.bp_inline_preview_panel[data-bp-preview-placement="docked"] {
  top: 0.9rem;
  right: 0.9rem;
  left: auto;
}

.bp_inline_preview_panel_header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.6rem;
  padding: 0.4rem 0.55rem;
  border-bottom: 1px solid var(--bp-color-border-soft);
  background: var(--bp-color-surface-muted);
}

.bp_inline_preview_panel_title {
  font-size: 0.82rem;
  font-weight: 700;
  color: var(--bp-color-text-strong);
}

.bp_inline_preview_panel_close {
  border: 1px solid var(--bp-color-border);
  border-radius: 0.3rem;
  background: var(--bp-color-surface);
  color: var(--bp-color-text-muted);
  font-size: 0.72rem;
  line-height: 1;
  padding: 0.2rem 0.35rem;
  cursor: pointer;
}

.bp_inline_preview_panel_body {
  padding: 0.5rem 0.6rem 0.55rem;
  min-height: 0;
  max-height: min(22rem, 70vh);
  overflow: auto;
  font-size: 0.8rem;
}

.bp_inline_preview_panel_footer {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 0.35rem;
  padding: 0.38rem 0.55rem 0.42rem;
  border-top: 1px solid var(--bp-color-border-soft);
  background: var(--bp-color-surface-muted);
  color: var(--bp-color-text-subtle);
  font-size: 0.72rem;
}

.bp_inline_preview_panel_footer[hidden] {
  display: none;
}

.bp_inline_preview_panel_footer code {
  font-size: 0.72rem;
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

.bp_inline_preview_panel[data-bp-preview-mode="hover"] .bp_inline_preview_panel_close {
  display: none;
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

def withJs (assets : BlueprintAssetBundle) (before after : List String) : BlueprintAssetBundle :=
  { assets with js := before ++ assets.js ++ after }

end BlueprintAssetBundle

def blueprintCssAssetBundle (extras : List String := []) : BlueprintAssetBundle :=
  ({ css := [blueprintTokensCss] } : BlueprintAssetBundle).withCss extras

def previewPanelCssAssetBundle (extras : List String := []) : BlueprintAssetBundle :=
  (blueprintCssAssetBundle [previewPanelCss]).withCss extras

def inlinePreviewCssAssetBundle (extras : List String := []) : BlueprintAssetBundle :=
  (blueprintCssAssetBundle extras).withCss [previewHeaderCss, inlinePreviewCss]

def previewPanelInlinePreviewCssAssetBundle (extras : List String := []) : BlueprintAssetBundle :=
  (previewPanelCssAssetBundle extras).withCss [previewHeaderCss, inlinePreviewCss]

def previewPanelAssetBundle
    (cssExtras : List String := [])
    (jsBefore : List String := [])
    (jsAfter : List String := []) : BlueprintAssetBundle :=
  (previewPanelCssAssetBundle cssExtras).append
    ({ js := jsBefore ++ jsAfter } : BlueprintAssetBundle)

def inlinePreviewAssetBundle
    (cssExtras : List String := [])
    (jsBefore : List String := [])
    (jsAfter : List String := []) : BlueprintAssetBundle :=
  (inlinePreviewCssAssetBundle cssExtras).append
    ({ js := jsBefore ++ jsAfter } : BlueprintAssetBundle)

def previewPanelInlinePreviewAssetBundle
    (cssExtras : List String := [])
    (jsBefore : List String := [])
    (jsAfter : List String := []) : BlueprintAssetBundle :=
  (previewPanelInlinePreviewCssAssetBundle cssExtras).append
    ({ js := jsBefore ++ jsAfter } : BlueprintAssetBundle)

end Informal.Commands
