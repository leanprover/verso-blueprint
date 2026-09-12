/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoBlueprint.Commands.Common
import VersoBlueprint.Macros
import VersoBlueprint.StyleSwitcher

namespace Informal.Block.Assets

def css : String := r##"
.bp_wrapper {
  scroll-margin-top: 1rem;
  margin: 0.85rem 0;
}

/* Leave scroll room for relation panels opened near the end of a page. */
.content-wrapper > section:has(.bp_relation_panel) {
  padding-bottom: min(18rem, 42vh);
}

.bp_heading {
  display: flex;
  align-items: center;
  gap: 0.55rem;
  flex-wrap: wrap;
  font-style: normal;
  font-weight: bold;
}

.bp_heading_title_row {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
}

.bp_kind_proof_heading {
  align-items: baseline;
}

.bp_heading_title_row_statement {
  display: inline-grid;
  grid-template-columns: 11ch 3ch;
  align-items: baseline;
  column-gap: 0.45rem;
}

.bp_caption {
  display: inline;
}

.bp_label {
  margin-left: 0.5rem;
}

.bp_heading_title_row_statement .bp_label {
  margin-left: 0;
  min-width: 0;
  text-align: right;
  font-variant-numeric: tabular-nums;
}

.bp_label::after,
span[class$="_thmlabel"]::after {
  content: ".";
}

.bp_extras {
  --bp-extra-source-col: minmax(5.2rem, max-content);
  --bp-extra-group-col: minmax(5rem, max-content);
  --bp-extra-uses-col: minmax(5.2rem, max-content);
  --bp-extra-used-by-col: minmax(7.2rem, max-content);
  --bp-extra-markup-col: max-content;
  --bp-extra-code-col: max-content;
  --bp-extra-code-placeholder-col: minmax(3.35rem, max-content);
  display: inline-grid;
  align-items: baseline;
  justify-content: end;
  column-gap: 0.55rem;
  grid-template-columns: var(--bp-extra-used-by-col) var(--bp-extra-code-col);
  grid-template-areas: "used code";
  margin-left: auto;
}

.bp_extras_with_uses {
  grid-template-columns:
    var(--bp-extra-uses-col)
    var(--bp-extra-used-by-col)
    var(--bp-extra-code-col);
  grid-template-areas: "uses used code";
}

.bp_extras_with_uses:not(.bp_extras_with_group):not(.bp_extras_with_used_by):not(.bp_extras_with_code) {
  /* Keep proof-only uses aligned with the statement uses column. */
  grid-template-columns:
    var(--bp-extra-uses-col)
    var(--bp-extra-used-by-col)
    var(--bp-extra-code-placeholder-col);
  grid-template-areas: "uses . .";
}

.bp_extras_with_group {
  grid-template-columns:
    var(--bp-extra-group-col)
    var(--bp-extra-used-by-col)
    var(--bp-extra-code-col);
  grid-template-areas: "group used code";
}

.bp_extras_with_group.bp_extras_with_uses {
  grid-template-columns:
    var(--bp-extra-group-col)
    var(--bp-extra-uses-col)
    var(--bp-extra-used-by-col)
    var(--bp-extra-code-col);
  grid-template-areas: "group uses used code";
}

.bp_extras_with_markup {
  grid-template-columns:
    var(--bp-extra-used-by-col)
    var(--bp-extra-markup-col)
    var(--bp-extra-code-col);
  grid-template-areas: "used markup code";
}

.bp_extras_with_markup.bp_extras_with_uses {
  grid-template-columns:
    var(--bp-extra-uses-col)
    var(--bp-extra-used-by-col)
    var(--bp-extra-markup-col)
    var(--bp-extra-code-col);
  grid-template-areas: "uses used markup code";
}

.bp_extras_with_markup.bp_extras_with_group {
  grid-template-columns:
    var(--bp-extra-group-col)
    var(--bp-extra-used-by-col)
    var(--bp-extra-markup-col)
    var(--bp-extra-code-col);
  grid-template-areas: "group used markup code";
}

.bp_extras_with_markup.bp_extras_with_group.bp_extras_with_uses {
  grid-template-columns:
    var(--bp-extra-group-col)
    var(--bp-extra-uses-col)
    var(--bp-extra-used-by-col)
    var(--bp-extra-markup-col)
    var(--bp-extra-code-col);
  grid-template-areas: "group uses used markup code";
}

.bp_extras_with_source {
  grid-template-columns:
    var(--bp-extra-source-col)
    var(--bp-extra-used-by-col)
    var(--bp-extra-code-col);
  grid-template-areas: "source used code";
}

.bp_extras_with_source.bp_extras_with_uses {
  grid-template-columns:
    var(--bp-extra-source-col)
    var(--bp-extra-uses-col)
    var(--bp-extra-used-by-col)
    var(--bp-extra-code-col);
  grid-template-areas: "source uses used code";
}

.bp_extras_with_source.bp_extras_with_group {
  grid-template-columns:
    var(--bp-extra-source-col)
    var(--bp-extra-group-col)
    var(--bp-extra-used-by-col)
    var(--bp-extra-code-col);
  grid-template-areas: "source group used code";
}

.bp_extras_with_source.bp_extras_with_group.bp_extras_with_uses {
  grid-template-columns:
    var(--bp-extra-source-col)
    var(--bp-extra-group-col)
    var(--bp-extra-uses-col)
    var(--bp-extra-used-by-col)
    var(--bp-extra-code-col);
  grid-template-areas: "source group uses used code";
}

.bp_extras_with_source.bp_extras_with_markup {
  grid-template-columns:
    var(--bp-extra-source-col)
    var(--bp-extra-used-by-col)
    var(--bp-extra-markup-col)
    var(--bp-extra-code-col);
  grid-template-areas: "source used markup code";
}

.bp_extras_with_source.bp_extras_with_markup.bp_extras_with_uses {
  grid-template-columns:
    var(--bp-extra-source-col)
    var(--bp-extra-uses-col)
    var(--bp-extra-used-by-col)
    var(--bp-extra-markup-col)
    var(--bp-extra-code-col);
  grid-template-areas: "source uses used markup code";
}

.bp_extras_with_source.bp_extras_with_markup.bp_extras_with_group {
  grid-template-columns:
    var(--bp-extra-source-col)
    var(--bp-extra-group-col)
    var(--bp-extra-used-by-col)
    var(--bp-extra-markup-col)
    var(--bp-extra-code-col);
  grid-template-areas: "source group used markup code";
}

.bp_extras_with_source.bp_extras_with_markup.bp_extras_with_group.bp_extras_with_uses {
  grid-template-columns:
    var(--bp-extra-source-col)
    var(--bp-extra-group-col)
    var(--bp-extra-uses-col)
    var(--bp-extra-used-by-col)
    var(--bp-extra-markup-col)
    var(--bp-extra-code-col);
  grid-template-areas: "source group uses used markup code";
}

.bp_extra_slot {
  display: inline-flex;
  align-items: center;
  min-height: 1.1rem;
  min-width: 0;
}

.bp_extra_slot_code {
  grid-area: code;
  justify-content: flex-end;
}

.bp_extra_slot_source {
  grid-area: source;
  justify-content: flex-start;
}

.bp_extra_slot_group {
  grid-area: group;
  justify-content: flex-start;
}

.bp_extra_slot_uses {
  grid-area: uses;
  justify-content: flex-start;
}

.bp_extra_slot_used_by {
  grid-area: used;
  justify-content: flex-start;
}

.bp_extra_slot_markup {
  grid-area: markup;
  justify-content: flex-start;
}

@media (max-width: 700px) {
  .bp_extras {
    display: flex;
    flex: 1 1 100%;
    flex-wrap: wrap;
    justify-content: flex-start;
    width: 100%;
    margin-left: 0;
    gap: 0.2rem 0.5rem;
  }

  .bp_extra_slot {
    max-width: 100%;
  }

  .bp_extra_slot_code {
    margin-left: auto;
  }
}

.bp_external_markup_badges {
  display: inline-flex;
  align-items: center;
  gap: 0.22rem;
  min-width: 0;
}

.bp_external_markup_badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.18rem;
  min-height: 1.08rem;
  border: 1px solid var(--bp-color-border-panel);
  border-radius: var(--bp-radius-md);
  background: var(--bp-color-surface-muted);
  color: var(--bp-color-text-muted);
  padding: 0.06rem 0.36rem;
  font-size: 0.68rem;
  line-height: 1;
  white-space: nowrap;
}

.bp_external_markup_badge_prefix {
  color: var(--bp-color-text-faint);
  font-size: 0.56rem;
  font-weight: 800;
  text-transform: uppercase;
  letter-spacing: 0;
}

.bp_external_markup_badge_language {
  color: var(--bp-color-text-strong);
  font-size: 0.68rem;
  font-weight: 850;
}

.bp_external_markup_badge_markdown {
  border-color: color-mix(in srgb, #0f766e 35%, var(--bp-color-border-panel));
  background: color-mix(in srgb, #0f766e 8%, var(--bp-color-surface-muted));
}

.bp_external_markup_badge_tex {
  border-color: color-mix(in srgb, #7c2d12 34%, var(--bp-color-border-panel));
  background: color-mix(in srgb, #7c2d12 7%, var(--bp-color-surface-muted));
}

.bp_metadata_panel {
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem 0.5rem;
  align-items: center;
  margin: 0.45rem 0 0.7rem;
  padding: 0.45rem 0.55rem;
  border: 1px solid var(--bp-color-border-panel);
  border-radius: var(--bp-radius-xl);
  background: var(--bp-color-surface-muted);
  font-size: 0.78rem;
  font-style: normal;
  font-weight: 400;
}

.bp_metadata_item {
  display: inline-flex;
  align-items: center;
  gap: 0.28rem;
  min-width: 0;
  flex-wrap: wrap;
}

.bp_metadata_owner {
  gap: 0.4rem;
}

.bp_metadata_key {
  font-weight: 700;
  color: var(--bp-color-text-subtle);
}

.bp_metadata_value {
  color: var(--bp-color-text-strong);
}

.bp_metadata_tags {
  display: inline-flex;
  flex-wrap: wrap;
  gap: 0.24rem;
}

.bp_metadata_tag {
  display: inline-flex;
  align-items: center;
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-pill);
  background: var(--bp-color-surface);
  color: var(--bp-color-text-muted);
  padding: 0.06rem 0.38rem;
  font-size: 0.72rem;
  font-weight: 600;
}

.bp_metadata_link {
  color: inherit;
  text-decoration: none;
  font-weight: 600;
}

.bp_metadata_link:hover {
  text-decoration: underline;
}

.bp_metadata_avatar {
  width: 1.6rem;
  height: 1.6rem;
  border-radius: 999px;
  object-fit: cover;
  border: 1px solid var(--bp-color-border);
  background: var(--bp-color-surface);
}

.bp_code_link {
  display: inline-flex;
  align-items: center;
  gap: 0.28rem;
  font-size: 0.8rem;
  color: inherit;
  text-decoration: none;
}

.bp_code_link_label {
  display: inline-flex;
  align-items: center;
}

.bp_code_status_symbol {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 0.9rem;
  font-size: 0.78rem;
  font-weight: 700;
  line-height: 1;
}

.bp_code_link_status_proved .bp_code_status_symbol {
  color: inherit;
}

.bp_code_link_status_warning .bp_code_status_symbol {
  color: var(--bp-color-accent-warning);
}

.bp_code_link_status_missing .bp_code_status_symbol,
.bp_code_link_status_axiom .bp_code_status_symbol {
  color: var(--bp-color-accent-danger);
}

.bp_code_link_status_absent .bp_code_status_symbol {
  color: inherit;
}

.bp_render_warning_badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 1rem;
  height: 1rem;
  border-radius: 999px;
  padding: 0 0.22rem;
  background: rgba(185, 28, 28, 0.08);
  color: var(--bp-color-status-error-text);
  font-size: 0.68rem;
  font-weight: 800;
  line-height: 1;
  border: 1px solid rgba(185, 28, 28, 0.18);
}

.bp_code_render_warning_badge {
  margin-right: 0.32rem;
}

.bp_code_summary_preview_root {
  position: relative;
  display: inline-flex;
  align-items: center;
  min-width: 0;
}

.bp_code_summary_preview_wrap {
  display: inline-flex;
  align-items: center;
  min-width: 0;
}

.bp_code_summary_preview_wrap_active {
  border-radius: var(--bp-radius-sm);
  cursor: help;
}

.bp_code_summary_preview_wrap_active[tabindex="0"] {
  outline: none;
}

.bp_code_summary_preview_wrap_active:focus-visible {
  background: var(--bp-color-focus-surface);
  box-shadow: 0 0 0 0.16rem var(--bp-color-focus-ring);
}

.bp_code_summary_preview_panel {
  position: fixed;
  z-index: 36;
  width: min(32rem, calc(100vw - 1.25rem));
  max-height: min(24rem, 78vh);
  overflow: hidden;
}

.bp_code_summary_preview_header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.6rem;
  padding: 0.42rem 0.55rem;
  border-bottom: 1px solid var(--bp-color-border-soft);
  background: linear-gradient(180deg, var(--bp-color-surface-muted), var(--bp-color-surface));
}

.bp_code_summary_preview_title {
  min-width: 0;
  color: var(--bp-color-text-strong);
  font-size: 0.82rem;
  font-weight: 700;
  line-height: 1.35;
  white-space: normal;
  overflow-wrap: anywhere;
}

.bp_code_summary_preview_body {
  padding: 0.55rem 0.6rem 0.6rem;
  max-height: min(20rem, 68vh);
  overflow: auto;
}

.bp_code_summary_preview_content {
  display: grid;
  gap: 0.5rem;
}

.bp_code_summary_preview_panel .bp_code_hover_section {
  margin-top: 0;
}

.bp_code_summary_preview_panel .bp_code_hover_section + .bp_code_hover_section {
  margin-top: 0;
  padding-top: 0.5rem;
  border-top: 1px solid var(--bp-color-border-soft);
}

.bp_code_summary_preview_panel .bp_code_hover_label {
  display: inline-flex;
  align-items: center;
  font-size: 0.7rem;
  font-weight: 700;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: var(--bp-color-text-faint);
}

.bp_code_summary_preview_panel .bp_code_hover_list {
  list-style: none;
}

.bp_code_decl_item {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  align-items: start;
  gap: 0.35rem 0.6rem;
}

.bp_code_decl_item + .bp_code_decl_item {
  margin-top: 0.3rem;
  padding-top: 0.3rem;
  border-top: 1px solid var(--bp-color-border-soft);
}

.bp_code_decl_name {
  min-width: 0;
  overflow-wrap: anywhere;
}

.bp_code_decl_name code {
  font-size: 0.76rem;
}

.bp_code_decl_status {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  white-space: nowrap;
  padding: 0.08rem 0.42rem;
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-pill);
  background: var(--bp-color-surface-muted);
  color: var(--bp-color-text-muted);
  font-size: 0.7rem;
  font-weight: 700;
  line-height: 1.2;
}

.bp_code_decl_status_ok {
  border-color: rgba(22, 101, 52, 0.18);
  background: rgba(22, 101, 52, 0.08);
  color: var(--bp-color-status-success-text);
}

.bp_code_decl_status_warning,
.bp_code_decl_status_axiom {
  border-color: rgba(161, 98, 7, 0.2);
  background: rgba(161, 98, 7, 0.09);
  color: var(--bp-color-status-warning-text);
}

.bp_code_decl_status_missing {
  border-color: rgba(185, 28, 28, 0.18);
  background: rgba(185, 28, 28, 0.08);
  color: var(--bp-color-status-error-text);
}

.bp_code_hover {
  position: absolute;
  left: 50%;
  top: 100%;
  transform: translateX(-50%);
  min-width: 20rem;
  max-width: min(34rem, 75vw);
  z-index: 20;
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-md);
  padding: 0.45rem 0.55rem;
  background: var(--bp-color-surface);
  box-shadow: 0 8px 20px rgba(15, 23, 42, 0.15);
  display: none;
  font-size: 0.78rem;
  font-style: normal;
  font-weight: 400;
}

.bp_code_hover_wrap:is(:hover, :focus-within) > .bp_code_hover,
.bp_code_link_wrap:is(:hover, :focus-within) > .bp_code_hover {
  display: block;
}

.bp_code_hover_title {
  font-weight: 700;
  margin-bottom: 0.3rem;
}

.bp_code_block summary {
  display: flex;
  align-items: center;
  gap: 0.55rem;
}

.bp_code_summary_text {
  white-space: nowrap;
}

.bp_code_summary_indicator {
  margin-left: auto;
  display: inline-flex;
  align-items: center;
}

.bp_code_progress {
  display: inline-flex;
  min-width: 9rem;
  max-width: 24rem;
  width: min(24rem, 40vw);
  height: 0.64rem;
  border-radius: 999px;
  overflow: hidden;
  border: 1px solid var(--bp-color-border-strong);
  background: linear-gradient(180deg, var(--bp-color-surface-muted), var(--bp-color-border-soft));
  box-shadow: inset 0 1px 1px rgba(15, 23, 42, 0.08);
}

.bp_code_progress_segment {
  min-width: 0.22rem;
}

.bp_code_progress_segment + .bp_code_progress_segment {
  border-left: 1px solid rgba(15, 23, 42, 0.35);
}

.bp_code_progress_segment_ok {
  background: var(--bp-color-accent-success);
}

.bp_code_progress_segment_sorry {
  background: var(--bp-color-accent-warning);
}

.bp_code_progress_segment_missing {
  background: var(--bp-color-accent-danger);
}

.bp_external_status_icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 1.08rem;
  height: 1.08rem;
  border-radius: 999px;
  font-size: 0.74rem;
  line-height: 1;
  color: var(--bp-color-surface);
  border: 1px solid rgba(15, 23, 42, 0.14);
  box-shadow: 0 1px 2px rgba(15, 23, 42, 0.18);
}

.bp_external_status_ok {
  background: var(--bp-color-accent-success);
}

.bp_external_status_sorry {
  background: var(--bp-color-accent-warning);
}

.bp_external_status_missing {
  background: var(--bp-color-accent-danger);
}

.bp_external_status_error {
  background: var(--bp-color-accent-info);
}

.bp_code_panel {
  margin: 0;
}

.bp_code_panel_wrapper {
  margin-top: 0.6rem;
}

.bp_code_panel_wrapper .bp_code_block > summary {
  cursor: pointer;
  color: var(--bp-color-text-strong);
}

.bp_code_panel_wrapper .bp_code_block > summary::marker {
  content: "";
}

.bp_code_panel_wrapper .bp_code_block > summary::-webkit-details-marker {
  display: none;
}

.bp_code_panel_wrapper .bp_code_block > summary::before {
  content: "";
  flex: 0 0 0.52rem;
  width: 0.52rem;
  height: 0.52rem;
  margin-top: 0.18rem;
  border-right: 0.12rem solid var(--bp-color-text-faint);
  border-bottom: 0.12rem solid var(--bp-color-text-faint);
  transform: rotate(-45deg);
  transition: transform 120ms ease;
}

.bp_code_panel_wrapper .bp_code_block[open] > summary::before {
  transform: rotate(45deg);
}

.bp_code_panel .bp_heading_title_row {
  min-width: 0;
}

.bp_code_panel .bp_code_summary_text {
  color: var(--bp-color-text-strong);
  white-space: normal;
  overflow-wrap: anywhere;
}

.bp_code_panel .bp_code_summary_label {
  flex: 0 0 auto;
}

.bp_code_panel .bp_code_summary_indicator {
  max-width: 100%;
}

.bp_code_panel .bp_external_decl_rendered .declaration {
  --bp-box-border-color: var(--bp-color-border-panel);
  --bp-box-background: var(--bp-color-surface);
  --bp-box-header-background: linear-gradient(180deg, var(--bp-color-surface-muted), var(--bp-color-surface));
  --bp-box-radius: var(--bp-radius-lg);
  --bp-box-shadow: var(--bp-shadow-sm);
  --bp-box-min-width: 0;
}

.bp_code_panel .bp_external_decl_kicker {
  padding: 0.38rem 0.5rem;
}

.bp_code_panel .bp_external_decl_rendered .bp_external_decl_signature {
  padding: 0.52rem 0.55rem;
}

.bp_code_panel .bp_external_decl_rendered .bp_external_decl_body:not(:empty) {
  padding: 0.5rem 0.55rem;
}

.bp_code_panel .bp_external_decl_head {
  min-width: 0;
}

.bp_code_panel .bp_external_decl_head .bp_inline_preview_ref,
.bp_code_panel .bp_external_decl_head a,
.bp_code_panel .bp_external_decl_head code {
  max-width: 100%;
  white-space: normal;
  overflow-wrap: anywhere;
  word-break: break-word;
}

.bp_decl_target {
  background: var(--bp-color-selection);
  border-radius: 0.18rem;
  box-shadow: 0 0 0 0.12rem var(--bp-color-selection-ring);
  animation: bp-decl-target-pulse 1.8s ease-out;
}

.bp_decl_target_block {
  border-radius: 0.3rem;
  box-shadow: 0 0 0 0.18rem var(--bp-color-selection-ring);
  background: linear-gradient(180deg, var(--bp-color-selection-surface-soft), rgba(59, 130, 246, 0.04));
  animation: bp-decl-block-pulse 2.2s ease-out;
}

@keyframes bp-decl-target-pulse {
  0% {
    background: var(--bp-color-selection-surface-strong);
    box-shadow: 0 0 0 0.2rem var(--bp-color-selection-shadow-strong);
  }
  100% {
    background: var(--bp-color-selection-surface-faint);
    box-shadow: 0 0 0 0.08rem var(--bp-color-selection-shadow-faint);
  }
}

@keyframes bp-decl-block-pulse {
  0% {
    background: var(--bp-color-selection-surface-soft);
    box-shadow: 0 0 0 0.28rem var(--bp-color-selection-shadow-soft);
  }
  100% {
    background: rgba(59, 130, 246, 0.04);
    box-shadow: 0 0 0 0.14rem var(--bp-color-selection-shadow-faint);
  }
}

.bp_code_link:hover {
  text-decoration: underline;
}

.bp_code_link_empty:hover {
  text-decoration: none;
}

.bp_relation_wrap {
  position: relative;
  display: inline-flex;
  align-items: center;
  padding-bottom: 0.45rem;
  margin-bottom: -0.45rem;
}

.bp_relation_wrap::after {
  content: "";
  position: absolute;
  left: -0.25rem;
  right: -0.25rem;
  top: 100%;
  height: 0.45rem;
}

.bp_relation_chip {
  display: inline-flex;
  align-items: center;
  appearance: none;
  border: 0;
  background: none;
  padding: 0;
  color: inherit;
  font: inherit;
  line-height: inherit;
  text-align: left;
  font-size: 0.78rem;
  font-weight: 600;
  color: var(--bp-color-text-muted);
  white-space: nowrap;
  cursor: default;
}

.bp_relation_chip_empty {
  color: var(--bp-color-text-faint);
  font-weight: 500;
}

.bp_relation_chip_warn {
  color: var(--bp-color-status-warning-text);
}

.bp_relation_panel {
  position: absolute;
  top: 100%;
  right: 0;
  min-width: 26rem;
  width: min(50rem, 92vw);
  z-index: 26;
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-xl);
  background: var(--bp-color-surface);
  box-shadow: var(--bp-shadow-lg);
  display: none;
  font-style: normal;
  font-weight: 400;
}

.bp_relation_wrap:is(:hover, :focus-within) > .bp_relation_panel {
  display: block;
}

.bp_relation_wrap.bp_relation_wrap_open > .bp_relation_panel {
  display: block;
}

.bp_source_ref_panel {
  min-width: 20rem;
  width: min(32rem, 92vw);
}

.bp_source_ref_panel_body {
  display: block;
  padding: 0.7rem;
}

.bp_source_ref_preview_surface {
  min-height: 0;
}

.bp_source_ref_preview_body {
  max-height: min(18rem, 58vh);
}

.bp_source_ref_panel_list {
  list-style: none;
  display: grid;
  gap: 0.55rem;
  margin: 0;
  padding: 0;
}

.bp_source_ref_panel_item {
  display: grid;
  gap: 0.32rem;
  padding: 0.56rem 0.62rem;
  border: 1px solid var(--bp-color-border-panel);
  border-radius: var(--bp-radius-md);
  background: var(--bp-color-surface-muted);
  color: var(--bp-color-text-muted);
  font-size: 0.76rem;
  line-height: 1.35;
}

.bp_source_ref_panel_document {
  display: flex;
  align-items: baseline;
  gap: 0.4rem;
  flex-wrap: wrap;
  color: var(--bp-color-text-strong);
}

.bp_source_ref_panel_key {
  color: var(--bp-color-text-faint);
  font-size: 0.66rem;
  font-weight: 700;
  text-transform: uppercase;
}

.bp_source_ref_panel_summary {
  color: var(--bp-color-text-strong);
  font-weight: 700;
}

.bp_source_ref_panel_spans {
  display: grid;
  gap: 0.22rem;
  margin: 0;
  padding-left: 1rem;
}

.bp_source_ref_panel_span {
  overflow-wrap: anywhere;
}

.bp_source_ref_panel_span_empty {
  color: var(--bp-color-text-faint);
}

.bp_relation_panel_header {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 0.55rem;
  padding: 0.55rem 0.7rem 0.45rem;
  border-bottom: 1px solid var(--bp-color-border-soft);
  background: linear-gradient(180deg, var(--bp-color-surface-muted), var(--bp-color-surface));
}

.bp_relation_panel_title {
  font-size: 0.82rem;
  font-weight: 700;
  color: var(--bp-color-text-strong);
}

.bp_relation_panel_meta {
  font-size: 0.72rem;
  color: var(--bp-color-text-faint);
}

.bp_relation_panel_body {
  display: grid;
  grid-template-columns: minmax(14rem, 18rem) minmax(18rem, 1fr);
  gap: 0.75rem;
  align-items: start;
  padding: 0.7rem;
}

.bp_relation_list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 0.45rem;
  max-height: min(20rem, 62vh);
  overflow: auto;
}

.bp_relation_item {
  border: 1px solid var(--bp-color-border-panel);
  border-radius: var(--bp-radius-md);
  background: var(--bp-color-surface-muted);
  transition: border-color 120ms ease, box-shadow 120ms ease, background 120ms ease;
}

.bp_relation_item:hover,
.bp_relation_item:focus-within,
.bp_relation_item.bp_relation_item_active {
  border-color: var(--bp-color-focus-border);
  background: var(--bp-color-focus-surface);
  box-shadow: inset 0 0 0 1px var(--bp-color-focus-ring);
}

.bp_relation_target {
  display: block;
  padding: 0.5rem 0.58rem;
  color: inherit;
  text-decoration: none;
}

.bp_relation_target:hover {
  text-decoration: none;
}

.bp_relation_target_title {
  display: block;
  font-size: 0.8rem;
  font-weight: 700;
  color: var(--bp-color-text-strong);
}

.bp_relation_target_meta {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  flex-wrap: wrap;
  margin-top: 0.26rem;
  color: var(--bp-color-text-subtle);
  font-size: 0.72rem;
}

.bp_relation_target_meta code {
  font-size: 0.72rem;
}

.bp_relation_axis_badge {
  --bp-relation-badge-bg: var(--bp-color-surface);
  --bp-relation-badge-border: var(--bp-color-border);
  --bp-relation-badge-text: var(--bp-color-text-muted);
  --bp-relation-badge-prefix: var(--bp-color-text-faint);
  display: inline-flex;
  align-items: center;
  border: 1px solid var(--bp-relation-badge-border);
  border-radius: var(--bp-radius-pill);
  background: var(--bp-relation-badge-bg);
  color: var(--bp-relation-badge-text);
  font-size: 0.66rem;
  font-weight: 700;
  letter-spacing: 0;
  line-height: 1.2;
  text-transform: none;
  padding: 0.1rem 0.36rem;
  box-shadow: inset 0 -1px 0 rgba(255, 255, 255, 0.35);
}

.bp_relation_badge_axis {
  font-weight: 700;
}

.bp_relation_badge_statement {
  --bp-relation-badge-bg: rgba(37, 99, 235, 0.1);
  --bp-relation-badge-border: rgba(37, 99, 235, 0.28);
  --bp-relation-badge-text: #1d4ed8;
}

.bp_relation_badge_proof {
  --bp-relation-badge-bg: rgba(5, 150, 105, 0.12);
  --bp-relation-badge-border: rgba(5, 150, 105, 0.28);
  --bp-relation-badge-text: #047857;
}

.bp_relation_badge_origin::before,
.bp_relation_badge_intent::before {
  color: var(--bp-relation-badge-prefix);
  font-weight: 600;
  margin-right: 0.22rem;
}

.bp_relation_badge_origin::before {
  content: "origin";
}

.bp_relation_badge_intent::before {
  content: "intent";
}

.bp_relation_badge_origin_automatic {
  --bp-relation-badge-bg: rgba(124, 58, 237, 0.1);
  --bp-relation-badge-border: rgba(124, 58, 237, 0.26);
  --bp-relation-badge-text: #6d28d9;
  --bp-relation-badge-prefix: #7c3aed;
}

.bp_relation_badge_intent_auxiliary {
  --bp-relation-badge-bg: rgba(245, 158, 11, 0.14);
  --bp-relation-badge-border: rgba(245, 158, 11, 0.32);
  --bp-relation-badge-text: #92400e;
  --bp-relation-badge-prefix: #b45309;
}

.bp_relation_badge_intent_technical {
  --bp-relation-badge-bg: rgba(79, 70, 229, 0.1);
  --bp-relation-badge-border: rgba(79, 70, 229, 0.26);
  --bp-relation-badge-text: #4338ca;
  --bp-relation-badge-prefix: #4f46e5;
}

.bp_relation_preview_surface {
  min-height: 14rem;
  border: 1px solid var(--bp-color-border-soft);
  border-radius: var(--bp-radius-lg);
  background: var(--bp-color-surface-muted);
  overflow: hidden;
}

.bp_relation_preview_header {
  padding: 0.5rem 0.62rem 0.44rem;
  border-bottom: 1px solid var(--bp-color-border-soft);
  background: linear-gradient(180deg, var(--bp-color-surface-muted), var(--bp-color-surface));
}

.bp_relation_preview_label {
  font-size: 0.66rem;
  font-weight: 700;
  letter-spacing: 0.05em;
  text-transform: uppercase;
  color: var(--bp-color-text-faint);
}

.bp_relation_preview_title {
  margin-top: 0.16rem;
  font-size: 0.8rem;
  font-weight: 700;
  color: var(--bp-color-text-strong);
}

.bp_relation_preview_body {
  max-height: min(20rem, 62vh);
  overflow: auto;
  padding: 0.62rem 0.68rem 0.72rem;
  background: var(--bp-color-surface);
}

.bp_relation_preview_message {
  display: grid;
  gap: 0.18rem;
  padding: 0.56rem 0.62rem;
  border: 1px solid var(--bp-color-border-soft);
  border-radius: 0.45rem;
  background: var(--bp-color-surface-muted);
  color: var(--bp-color-text-muted);
  font-size: 0.76rem;
  line-height: 1.38;
}

.bp_relation_preview_message[data-bp-preview-message="loading"] {
  color: var(--bp-color-text-faint);
}

.bp_relation_preview_message[data-bp-preview-message="error"] {
  border-color: var(--bp-color-status-error-border-soft);
  background: var(--bp-color-surface-warn);
  color: var(--bp-color-status-error-text);
}

.bp_relation_preview_message_title {
  font-weight: 700;
  color: inherit;
}

.bp_relation_preview_message_detail {
  color: inherit;
}

@media (max-width: 900px) {
  .bp_relation_panel {
    right: auto;
    left: 0;
    width: min(34rem, calc(100vw - 1.4rem));
  }

  .bp_relation_panel_body {
    grid-template-columns: 1fr;
  }

  .bp_relation_list,
  .bp_relation_preview_body {
    max-height: min(12rem, 36vh);
  }
}

.bp_status_mark {
  font-size: 0.78rem;
  font-weight: 600;
}

.bp_external_badge {
  font-size: 0.74rem;
  font-weight: 600;
  color: var(--bp-color-text-muted);
  border: 1px solid var(--bp-color-border-panel);
  border-radius: var(--bp-radius-pill);
  padding: 0.12rem 0.45rem;
  background: linear-gradient(180deg, var(--bp-color-surface), var(--bp-color-surface-muted));
}

.bp_external_badge_kind {
  text-transform: capitalize;
}

.bp_external_status_badge {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  border-radius: 999px;
  border: 1px solid currentColor;
  padding: 0.14rem 0.48rem;
  font-size: 0.75rem;
  font-weight: 700;
  line-height: 1.2;
  white-space: nowrap;
}

.bp_external_status_badge_summary {
  padding-right: 0.58rem;
}

.bp_external_status_badge_text {
  display: inline-block;
}

.bp_external_decl_ok {
  color: var(--bp-color-status-success-text);
}

.bp_external_decl_sorry {
  color: var(--bp-color-status-warning-text);
}

.bp_external_decl_missing {
  color: var(--bp-color-status-error-text);
}

.bp_external_decl_error {
  color: #7c3aed;
}

.bp_external_status_badge.bp_external_decl_ok,
.bp_external_status_badge.bp_external_status_ok {
  background: rgba(22, 101, 52, 0.08);
  border-color: rgba(22, 101, 52, 0.18);
}

.bp_external_status_badge.bp_external_decl_sorry,
.bp_external_status_badge.bp_external_status_sorry {
  background: rgba(161, 98, 7, 0.09);
  border-color: rgba(161, 98, 7, 0.2);
}

.bp_external_status_badge.bp_external_decl_missing,
.bp_external_status_badge.bp_external_status_missing {
  background: rgba(185, 28, 28, 0.08);
  border-color: rgba(185, 28, 28, 0.18);
}

.bp_external_status_badge.bp_external_decl_error,
.bp_external_status_badge.bp_external_status_error {
  background: rgba(124, 58, 237, 0.08);
  border-color: rgba(124, 58, 237, 0.18);
}

.bp_external_decl_meta {
  margin-top: 0.18rem;
  color: #475569;
  font-size: 0.75rem;
  line-height: 1.45;
}

.bp_external_decl_rendered_meta {
  display: flex;
  align-items: center;
  gap: 0.3rem 0.7rem;
  flex-wrap: wrap;
}

.bp_external_decl_footer_status {
  padding: 0.1rem 0.42rem;
  font-size: 0.7rem;
  font-weight: 700;
}

.bp_external_decl_list {
  list-style: none;
  margin: 0.45rem 0 0;
  padding-left: 0;
}

.bp_external_decl_item {
  margin: 0;
  padding: 0;
}

.bp_external_decl_item_rendered {
  padding: 0 0 0.1rem;
}

.bp_external_decl_list > .bp_external_decl_item + .bp_external_decl_item {
  margin-top: 0.8rem;
}

.bp_external_decl_head {
  display: flex;
  align-items: baseline;
  gap: 0.3rem 0.7rem;
  flex-wrap: wrap;
  line-height: 1.5;
}

.bp_external_decl_head_meta {
  color: #64748b;
  font-size: 0.76rem;
}

.bp_external_decl_rendered_source {
  margin-left: auto;
}

.bp_external_decl_details {
  margin-top: 0.12rem;
}

.bp_external_decl_details summary {
  cursor: pointer;
  font-size: 0.72rem;
  color: var(--bp-color-text-muted);
}

.bp_external_decl_preview {
  margin-top: 0.2rem;
  border-left: 2px solid var(--bp-color-border-soft);
  padding-left: 0.45rem;
}

.bp_external_decl_preview summary {
  cursor: pointer;
  font-size: 0.72rem;
  color: var(--bp-color-text-strong);
}

.bp_external_decl_preview pre {
  margin: 0.2rem 0 0;
  max-height: 8.5rem;
  overflow: auto;
  white-space: pre-wrap;
  font-size: 0.7rem;
  line-height: 1.35;
}

.bp_external_decl_stmt {
  margin: 0.32rem 0 0;
  padding: 0.1rem 0 0.1rem 0.7rem;
  border: 0;
  border-left: 0.18rem solid var(--bp-color-border-strong);
  border-radius: 0;
  background: transparent;
  white-space: pre-wrap;
  font-size: 0.8rem;
  line-height: 1.5;
  color: var(--bp-color-text-strong);
}

.bp_external_decl_rendered {
  margin: 0.35rem 0 0;
  border: 0;
  border-radius: 0;
  background: transparent;
  box-shadow: none;
  padding: 0;
  overflow-x: visible;
}

.bp_external_decl_rendered .declaration {
  --bp-box-width: 100%;
  --bp-box-border-left-width: 0.15rem;
  --bp-box-border-left-color: var(--bp-color-border-strong);
  --bp-box-radius: 6px;
  --bp-box-background: color-mix(in srgb, var(--bp-color-surface-muted) 54%, transparent);
  box-sizing: border-box;
  margin: var(--bp-box-margin, 0);
  padding: var(--bp-box-padding, 0);
  border: var(--bp-box-border-width, 1px) solid
    var(--bp-box-border-color, var(--bp-color-border-soft));
  border-left: var(--bp-box-border-left-width, var(--bp-box-border-width, 1px)) solid
    var(--bp-box-border-left-color, var(--bp-box-border-color, var(--bp-color-border-soft)));
  border-radius: var(--bp-box-radius, var(--bp-radius-md));
  background: var(--bp-box-background, var(--bp-color-surface));
  box-shadow: var(--bp-box-shadow, none);
  width: var(--bp-box-width, auto);
  min-width: var(--bp-box-min-width, 0);
  overflow: var(--bp-box-overflow, hidden);
}

.bp_external_decl_kicker {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 0.35rem 0.65rem;
  margin: 0;
  padding: 0.32rem 0.35rem;
  border-bottom: var(--bp-box-header-border-bottom-width, 1px) solid
    var(--bp-box-divider-color, var(--bp-color-border-soft));
  background: var(--bp-box-header-background, var(--bp-color-surface-muted));
  color: var(--bp-color-text-muted);
  font-size: 0.74rem;
  line-height: 1.35;
}

.bp_external_decl_kicker_main {
  display: flex;
  align-items: baseline;
  flex: 1 1 18rem;
  flex-wrap: wrap;
  gap: 0.12rem 0.32rem;
  min-width: 0;
}

.bp_external_decl_kicker_status {
  display: inline-flex;
  align-items: center;
  flex: 0 0 auto;
  margin-left: auto;
}

.bp_external_decl_header_status {
  padding: 0.05rem 0.42rem;
  font-size: 0.68rem;
  font-weight: 700;
  line-height: 1.25;
}

.bp_external_decl_kind {
  display: inline-flex;
  align-items: center;
  padding: 0;
  color: var(--bp-color-text-strong);
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
  font-size: 0.7rem;
  font-weight: 700;
  line-height: 1.25;
}

.bp_external_decl_header_meta {
  color: var(--bp-color-text-muted);
  font-size: 0.7rem;
  font-weight: 600;
  line-height: 1.25;
}

.bp_external_decl_source {
  display: inline-flex;
  align-items: baseline;
  gap: 0.22rem;
  min-width: 0;
  color: var(--bp-color-text-muted);
  font-size: 0.67rem;
  line-height: 1.25;
}

.bp_external_decl_source::before {
  content: "·";
  color: var(--bp-color-text-faint);
}

.bp_external_decl_source_path {
  min-width: 0;
  max-width: min(34rem, 72vw);
  overflow: hidden;
  color: var(--bp-color-text-strong);
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
  font-size: 0.66rem;
  overflow-wrap: anywhere;
  text-decoration: none;
}

a.bp_external_decl_source_path:hover {
  text-decoration: underline;
  text-underline-offset: 0.12rem;
}

.bp_external_decl_rendered .bp_external_decl_signature {
  margin: 0;
  padding: 0.4rem 0.35rem;
  max-width: 100%;
  overflow-x: auto;
  background: transparent;
  border: 0;
  font-size: 0.86rem;
  line-height: 1.45;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}

.bp_external_decl_rendered .bp_external_decl_signature.hl.lean,
.bp_external_decl_rendered .name-and-type.hl.lean {
  white-space: pre-wrap;
}

.bp_external_decl_rendered .bp_external_decl_signature .token,
.bp_external_decl_rendered .name-and-type .token {
  overflow-wrap: anywhere;
  word-break: break-word;
}

.bp_external_decl_rendered .bp_external_decl_body:empty {
  display: none;
}

.bp_external_decl_rendered .bp_external_decl_body:not(:empty) {
  margin-top: 0;
  padding: 0.4rem 0.35rem;
  border-top: 1px solid var(--bp-color-border-soft);
  background: var(--bp-color-surface);
}

.bp_external_decl_rendered .bp_external_decl_body > :first-child {
  margin-top: 0;
}

.bp_external_decl_rendered .bp_external_decl_body > :last-child {
  margin-bottom: 0;
}

.bp_external_decl_rendered .bp_external_decl_section + .bp_external_decl_section {
  margin-top: 0.75rem;
}

.bp_external_decl_rendered .bp_external_decl_section_label {
  margin: 0 0 0.4rem;
  padding-bottom: 0.18rem;
  border-bottom: 1px solid var(--bp-color-border-soft);
  color: var(--bp-color-text-muted);
  font-size: 0.78rem;
  font-weight: 600;
  letter-spacing: 0;
  text-transform: none;
}

.bp_external_decl_rendered pre {
  overflow-x: auto;
}

.bp_external_decl_rendered .constructor + .constructor,
.bp_external_decl_rendered .subdocs + .subdocs {
  margin-top: 0.45rem;
}

.bp_external_decl_rendered .constructor,
.bp_external_decl_rendered .subdocs {
  padding: 0.35rem 0 0.35rem 0.35rem;
  border-left: 0.1rem solid var(--bp-color-border-soft);
}

.bp_external_decl_rendered .name-and-type {
  margin: 0;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
  font-size: 0.82rem;
  line-height: 1.45;
}

.bp_external_decl_rendered .docs {
  margin: 0.28rem 0 0 0.35rem;
  color: var(--bp-color-text-muted);
}

.bp_external_decl_rendered .inheritance {
  margin-top: 0.25rem;
  color: #64748b;
  font-size: 0.82rem;
}

.bp_external_decl_rendered .inheritance ol {
  display: inline;
  margin: 0;
  padding: 0;
}

.bp_external_decl_rendered .inheritance li {
  display: inline;
  list-style: none;
}

.bp_external_decl_rendered .inheritance li + li::before {
  content: " > ";
}

.bp_external_decl_rendered .docstring {
  margin-top: 0;
  padding: 0;
  border: 0;
  background: transparent;
  color: inherit;
  font-family: var(--verso-text-font-family, inherit);
  font-size: 0.98em;
  line-height: 1.6;
  overflow: visible;
  max-height: none;
  max-width: none;
  width: auto;
}

.bp_external_decl_rendered pre.docstring {
  white-space: pre-wrap;
}

.bp_external_decl_rendered div.docstring {
  white-space: normal;
}

.bp_external_decl_rendered div.docstring > :first-child {
  margin-top: 0;
}

.bp_external_decl_rendered div.docstring > :last-child {
  margin-bottom: 0;
}

.bp_external_decl_rendered details {
  margin-top: 0.55rem;
}

.bp_external_decl_rendered details > summary {
  cursor: pointer;
  font-weight: 600;
}

.bp_external_decl_rendered details > ul {
  margin: 0.4rem 0 0;
  padding-left: 1rem;
}

.bp_external_decl_rendered details > ul > li {
  margin: 0.18rem 0;
  overflow-wrap: anywhere;
}

.bp_external_decl_rendered_source .bp_code_link {
  font-size: 0.76rem;
  white-space: nowrap;
}

@media (max-width: 700px) {
  .bp_code_block summary {
    align-items: flex-start;
    flex-wrap: wrap;
  }

  .bp_code_summary_text {
    white-space: normal;
  }

  .bp_code_summary_indicator {
    margin-left: 0;
  }

  .bp_external_decl_head_meta,
  .bp_external_decl_rendered_source {
    width: 100%;
    margin-left: 0;
  }

  .bp_external_decl_rendered .declaration {
    border-left-width: 0.12rem;
  }

  .bp_external_decl_list > .bp_external_decl_item + .bp_external_decl_item {
    margin-top: 0.7rem;
  }
}

.bp_content {
  padding-left: 0.65rem;
}

.bp_content > :first-child {
  margin-top: 0;
}

.bp_content > :last-child {
  margin-bottom: 0;
}

.bp-proof-tail-hidden {
  display: none;
}

.bp-proof-gap-hidden {
  display: none;
}

.bp-proof-by-toggle {
  cursor: pointer;
  text-decoration: underline dotted;
  text-decoration-thickness: 1px;
}

.bp-proof-by-toggle::after {
  content: " ...";
  color: var(--bp-color-text-faint);
}

.bp-proof-by-toggle.bp-proof-open::after {
  content: "";
}

details.bp_kind_proof_wrapper > summary.bp_heading {
  cursor: pointer;
}

details.bp_kind_proof_wrapper > summary.bp_heading::marker {
  color: var(--bp-color-text-faint);
}

.bp_wrapper.bp_style_plain .bp_heading,
div.theorem-style-plain div[class$="_thmheading"] {
  font-style: normal;
  font-weight: bold;
}

.bp_wrapper.bp_style_plain .bp_content,
div.theorem-style-plain div[class$="_thmcontent"] {
  font-style: italic;
  font-weight: normal;
}

.bp_wrapper.bp_style_definition .bp_heading,
div.theorem-style-definition div[class$="_thmheading"] {
  font-style: normal;
  font-weight: bold;
}

.bp_kind_theorem_content,
div.theorem_thmcontent {
  border-left: 0.15rem solid black;
}

.bp_kind_proposition_content,
div.proposition_thmcontent {
  border-left: 0.15rem solid black;
}

.bp_kind_lemma_content,
div.lemma_thmcontent {
  border-left: 0.1rem solid black;
}

.bp_kind_corollary_content,
div.corollary_thmcontent {
  border-left: 0.1rem solid black;
}

.bp_kind_proof_content,
div.proof_content {
  border-left: 0.08rem solid grey;
}

.bp_wrapper:target {
  animation: bp-target-pulse 1.6s ease-out;
  box-shadow: 0 0 0 0.18rem var(--bp-color-target-ring);
  border-radius: 0.35rem;
}

@keyframes bp-target-pulse {
  0% {
    background-color: var(--bp-color-target-surface);
    box-shadow: 0 0 0 0.28rem var(--bp-color-target-ring-strong);
  }
  100% {
    background-color: transparent;
    box-shadow: 0 0 0 0.18rem var(--bp-color-target-ring);
  }
}
"##

def codeAssetBundle : Informal.Commands.BlueprintAssetBundle :=
  Informal.Commands.blueprintCssAssetBundle [css, Verso.Genre.Manual.docstringStyle]

def blockAssetBundle : Informal.Commands.BlueprintAssetBundle :=
  Informal.Commands.previewPanelInlinePreviewAssetBundle
    (cssExtras := [css, Informal.StyleSwitcher.css, Verso.Genre.Manual.docstringStyle])
    (jsAfter := [Informal.Macros.blueprintMathJs, Informal.StyleSwitcher.jsInteractive])

def codeCssAssets : List String :=
  codeAssetBundle.css

def blockCssAssets : List String :=
  blockAssetBundle.css

def blockJsAssets : List String :=
  blockAssetBundle.js

end Informal.Block.Assets
