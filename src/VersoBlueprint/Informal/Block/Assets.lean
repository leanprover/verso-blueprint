/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoBlueprint.Commands.Common
import VersoBlueprint.StyleSwitcher

namespace Informal.Block.Assets

def css : String := r##"
.bp_wrapper {
  scroll-margin-top: 1rem;
  margin: 0.85rem 0;
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
  display: inline-grid;
  align-items: baseline;
  justify-content: end;
  column-gap: 0.55rem;
  grid-template-columns: minmax(7.2rem, max-content) max-content;
  grid-template-areas: "used code";
  margin-left: auto;
}

.bp_extras_with_group {
  grid-template-columns: minmax(5rem, max-content) minmax(7.2rem, max-content) max-content;
  grid-template-areas: "group used code";
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

.bp_extra_slot_group {
  grid-area: group;
  justify-content: flex-start;
}

.bp_extra_slot_used_by {
  grid-area: used;
  justify-content: flex-start;
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
  margin: 0.24rem 0 0;
  padding-left: 0;
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

.bp_used_by_wrap {
  position: relative;
  display: inline-flex;
  align-items: center;
  padding-bottom: 0.45rem;
  margin-bottom: -0.45rem;
}

.bp_used_by_wrap::after {
  content: "";
  position: absolute;
  left: -0.25rem;
  right: -0.25rem;
  top: 100%;
  height: 0.45rem;
}

.bp_used_by_chip {
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

.bp_used_by_chip_empty {
  color: var(--bp-color-text-faint);
  font-weight: 500;
}

.bp_used_by_chip_warn {
  color: var(--bp-color-status-warning-text);
}

.bp_used_by_panel {
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

.bp_used_by_wrap:is(:hover, :focus-within) > .bp_used_by_panel {
  display: block;
}

.bp_used_by_wrap.bp_used_by_wrap_open > .bp_used_by_panel {
  display: block;
}

.bp_used_by_panel_header {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 0.55rem;
  padding: 0.55rem 0.7rem 0.45rem;
  border-bottom: 1px solid var(--bp-color-border-soft);
  background: linear-gradient(180deg, var(--bp-color-surface-muted), var(--bp-color-surface));
}

.bp_used_by_panel_title {
  font-size: 0.82rem;
  font-weight: 700;
  color: var(--bp-color-text-strong);
}

.bp_used_by_panel_meta {
  font-size: 0.72rem;
  color: var(--bp-color-text-faint);
}

.bp_used_by_panel_body {
  display: grid;
  grid-template-columns: minmax(14rem, 18rem) minmax(18rem, 1fr);
  gap: 0.75rem;
  align-items: start;
  padding: 0.7rem;
}

.bp_used_by_list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 0.45rem;
  max-height: min(20rem, 62vh);
  overflow: auto;
}

.bp_used_by_item {
  border: 1px solid var(--bp-color-border-panel);
  border-radius: var(--bp-radius-md);
  background: var(--bp-color-surface-muted);
  transition: border-color 120ms ease, box-shadow 120ms ease, background 120ms ease;
}

.bp_used_by_item:hover,
.bp_used_by_item:focus-within,
.bp_used_by_item.bp_used_by_item_active {
  border-color: var(--bp-color-focus-border);
  background: var(--bp-color-focus-surface);
  box-shadow: inset 0 0 0 1px var(--bp-color-focus-ring);
}

.bp_used_by_target {
  display: block;
  padding: 0.5rem 0.58rem;
  color: inherit;
  text-decoration: none;
}

.bp_used_by_target:hover {
  text-decoration: none;
}

.bp_used_by_target_title {
  display: block;
  font-size: 0.8rem;
  font-weight: 700;
  color: var(--bp-color-text-strong);
}

.bp_used_by_target_meta {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  flex-wrap: wrap;
  margin-top: 0.26rem;
  color: var(--bp-color-text-subtle);
  font-size: 0.72rem;
}

.bp_used_by_target_meta code {
  font-size: 0.72rem;
}

.bp_used_by_axis_badge {
  display: inline-flex;
  align-items: center;
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-pill);
  background: var(--bp-color-surface);
  color: var(--bp-color-text-muted);
  font-size: 0.66rem;
  font-weight: 700;
  letter-spacing: 0.03em;
  text-transform: uppercase;
  padding: 0.08rem 0.34rem;
}

.bp_used_by_preview_surface {
  min-height: 14rem;
  border: 1px solid var(--bp-color-border-soft);
  border-radius: var(--bp-radius-lg);
  background: var(--bp-color-surface-muted);
  overflow: hidden;
}

.bp_used_by_preview_header {
  padding: 0.5rem 0.62rem 0.44rem;
  border-bottom: 1px solid var(--bp-color-border-soft);
  background: linear-gradient(180deg, var(--bp-color-surface-muted), var(--bp-color-surface));
}

.bp_used_by_preview_label {
  font-size: 0.66rem;
  font-weight: 700;
  letter-spacing: 0.05em;
  text-transform: uppercase;
  color: var(--bp-color-text-faint);
}

.bp_used_by_preview_title {
  margin-top: 0.16rem;
  font-size: 0.8rem;
  font-weight: 700;
  color: var(--bp-color-text-strong);
}

.bp_used_by_preview_body {
  max-height: min(20rem, 62vh);
  overflow: auto;
  padding: 0.62rem 0.68rem 0.72rem;
  background: var(--bp-color-surface);
}

.bp_used_by_preview_message {
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

.bp_used_by_preview_message[data-bp-preview-message="loading"] {
  color: var(--bp-color-text-faint);
}

.bp_used_by_preview_message[data-bp-preview-message="error"] {
  border-color: var(--bp-color-status-error-border-soft);
  background: var(--bp-color-surface-warn);
  color: var(--bp-color-status-error-text);
}

.bp_used_by_preview_message_title {
  font-weight: 700;
  color: inherit;
}

.bp_used_by_preview_message_detail {
  color: inherit;
}

@media (max-width: 900px) {
  .bp_used_by_panel {
    right: auto;
    left: 0;
    width: min(34rem, calc(100vw - 1.4rem));
  }

  .bp_used_by_panel_body {
    grid-template-columns: 1fr;
  }

  .bp_used_by_list,
  .bp_used_by_preview_body {
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
  padding: 0;
}

.bp_external_decl_list > .bp_external_decl_item + .bp_external_decl_item {
  margin-top: 0.85rem;
  padding-top: 0.85rem;
  border-top: 1px solid var(--bp-color-border-soft);
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
  overflow-x: auto;
}

.bp_external_decl_rendered .declaration {
  margin: 0;
  padding: 0;
  min-width: 100%;
}

.bp_external_decl_rendered .bp_external_decl_body {
  margin-top: 0.6rem;
}

.bp_external_decl_rendered .bp_external_decl_body > :first-child {
  margin-top: 0;
}

.bp_external_decl_rendered .bp_external_decl_body > :last-child {
  margin-bottom: 0;
}

.bp_external_decl_rendered .bp_external_decl_body h1 {
  margin: 0.85rem 0 0.35rem;
  color: inherit;
  font-size: 0.82rem;
  font-weight: 600;
  letter-spacing: 0;
  text-transform: none;
}

.bp_external_decl_rendered pre {
  overflow-x: auto;
}

.bp_external_decl_rendered .constructor + .constructor,
.bp_external_decl_rendered .subdocs + .subdocs {
  margin-top: 0.6rem;
}

.bp_external_decl_rendered .name-and-type {
  margin: 0;
}

.bp_external_decl_rendered .docs {
  margin-top: 0.35rem;
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
  margin-top: 0.6rem;
  padding: 0;
  border: 0;
  background: transparent;
  color: inherit;
  font-family: var(--verso-text-font-family, inherit);
  font-size: 0.98em;
  line-height: 1.6;
  white-space: pre-wrap;
  overflow: visible;
  max-height: none;
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

  .bp_external_decl_list > .bp_external_decl_item + .bp_external_decl_item {
    margin-top: 0.7rem;
    padding-top: 0.7rem;
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

def codeCssAssets : List String :=
  Informal.Commands.withBlueprintCssAssets [css, Verso.Genre.Manual.docstringStyle]

def blockCssAssets : List String :=
  Informal.Commands.withPreviewPanelInlinePreviewCssAssets
    [css, Informal.StyleSwitcher.css, Verso.Genre.Manual.docstringStyle]

def codeSummaryPreviewJs : String := r##"(function () {
  function bindCodeSummaryPreview(root) {
    if (!(root instanceof Element)) return;
    if (root.getAttribute("data-bp-code-summary-preview-bound") === "1") return;
    root.setAttribute("data-bp-code-summary-preview-bound", "1");

    const previewUtils = window.bpPreviewUtils;
    const panel = root.querySelector(".bp_code_summary_preview_panel");
    if (!panel || !previewUtils || typeof previewUtils.bindTemplatePreview !== "function") return;
    previewUtils.bindTemplatePreview({
      root: root,
      previewRoot: root,
      triggerRoot: root,
      panel: panel,
      templateSelector: "template.bp_code_summary_preview_tpl[data-bp-preview-id]",
      triggerSelector: ".bp_code_summary_preview_wrap_active[data-bp-preview-id]",
      keyAttr: "data-bp-preview-id",
      titleAttr: "data-bp-preview-title",
      titleSelector: ".bp_code_summary_preview_title",
      bodySelector: ".bp_code_summary_preview_body",
      closeSelector: ".bp_code_summary_preview_close",
      triggerBoundAttr: "data-bp-code-summary-trigger-bound",
      defaults: { mode: "hover", placement: "anchored" }
    });
  }

  function init() {
    document.querySelectorAll(".bp_code_summary_preview_root").forEach(bindCodeSummaryPreview);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init, { once: true });
  } else {
    init();
  }
})();"##

def usedByPanelJs : String := r##"(function () {
  function escapeHtml(text) {
    return String(text || "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }

  function previewMessageHtml(kind, title, detail) {
    const safeKind = String(kind || "info").trim() || "info";
    let html =
      '<div class="bp_used_by_preview_message" data-bp-preview-message="' +
      escapeHtml(safeKind) +
      '">';
    html +=
      '<div class="bp_used_by_preview_message_title">' +
      escapeHtml(title || "Preview unavailable") +
      "</div>";
    if (detail) {
      html +=
        '<div class="bp_used_by_preview_message_detail">' +
        escapeHtml(detail) +
        "</div>";
    }
    html += "</div>";
    return html;
  }

  function loadingPreviewHtml() {
    return previewMessageHtml(
      "loading",
      "Loading preview",
      "Reading this preview from the shared Blueprint manifest."
    );
  }

  function readManifestStatus(previewUtils) {
    if (previewUtils && typeof previewUtils.readSharedPreviewManifestStatus === "function") {
      return previewUtils.readSharedPreviewManifestStatus();
    }
    return null;
  }

  function previewUnavailableHtml(previewUtils, previewKey, fallbackDetail) {
    const status = readManifestStatus(previewUtils);
    if (!previewKey) {
      return previewMessageHtml(
        "error",
        "Preview unavailable",
        "This entry did not provide a shared preview key."
      );
    }
    if (
      !previewUtils ||
      typeof previewUtils.loadSharedPreviewEntry !== "function" ||
      typeof previewUtils.readPreviewTemplate !== "function"
    ) {
      return previewMessageHtml(
        "error",
        "Preview unavailable",
        "The page preview runtime is not available. Rebuild this page with the Blueprint JavaScript assets enabled."
      );
    }
    if (status && status.state === "error") {
      return previewMessageHtml(
        "error",
        "Preview manifest unavailable",
        "Rebuild the site or refresh after the current build finishes."
      );
    }
    if (status && status.state === "ready") {
      return previewMessageHtml(
        "error",
        "Preview entry not found",
        "The shared preview manifest loaded, but it does not contain this entry yet. Rebuild the Blueprint output to resync generated data."
      );
    }
    return previewMessageHtml(
      "error",
      "Preview unavailable",
      fallbackDetail || "The shared preview content could not be loaded."
    );
  }

  function bindUsedByPanel(panel) {
    if (!(panel instanceof Element)) return;
    if (panel.getAttribute("data-bp-bound") === "1") return;
    panel.setAttribute("data-bp-bound", "1");

    const previewUtils = window.bpPreviewUtils;
    const wrap = panel.closest(".bp_used_by_wrap");
    const chip = wrap instanceof Element ? wrap.querySelector(".bp_used_by_chip") : null;
    const title = panel.querySelector(".bp_used_by_preview_title");
    const body = panel.querySelector(".bp_used_by_preview_body");
    if (!(title instanceof Element) || !(body instanceof Element)) return;

    const defaultTitle = (title.textContent || "").trim() || "Hover a use site";
    const items = Array.from(panel.querySelectorAll(".bp_used_by_item[data-bp-used-preview-id]"));
    let closeTimer = null;
    let activateRequestToken = 0;

    function setExpanded(expanded) {
      if (chip instanceof Element) {
        chip.setAttribute("aria-expanded", expanded ? "true" : "false");
      }
    }

    function cancelClose() {
      if (closeTimer !== null) {
        clearTimeout(closeTimer);
        closeTimer = null;
      }
    }

    function activeItem() {
      return items.find(function (item) {
        return item instanceof Element && item.classList.contains("bp_used_by_item_active");
      }) || items[0] || null;
    }

    function selectItem(item) {
      if (!(item instanceof Element)) return;
      const itemTitle = (item.getAttribute("data-bp-used-preview-title") || "").trim() || defaultTitle;
      items.forEach(function (other) {
        if (other instanceof Element) {
          other.classList.toggle("bp_used_by_item_active", other === item);
        }
      });
      title.textContent = itemTitle;
      body.innerHTML = "";
    }

    function loadActivePreview() {
      const item = activeItem();
      if (item instanceof Element) {
        activate(item, { openWrap: false });
      }
    }

    function openWrap(options) {
      const opts = options && typeof options === "object" ? options : {};
      cancelClose();
      if (wrap instanceof Element) {
        wrap.classList.add("bp_used_by_wrap_open");
      }
      setExpanded(true);
      if (opts.loadPreview !== false) {
        loadActivePreview();
      }
    }

    function closeWrap() {
      cancelClose();
      if (wrap instanceof Element) {
        wrap.classList.remove("bp_used_by_wrap_open");
      }
      setExpanded(false);
    }

    function scheduleClose() {
      cancelClose();
      closeTimer = window.setTimeout(function () {
        closeTimer = null;
        if (wrap instanceof Element) {
          wrap.classList.remove("bp_used_by_wrap_open");
        }
        setExpanded(false);
      }, 180);
    }

    async function activate(item, options) {
      if (!(item instanceof Element)) return;
      const opts = options && typeof options === "object" ? options : {};
      const previewKey = (item.getAttribute("data-bp-used-preview-key") || "").trim();
      const itemTitle = (item.getAttribute("data-bp-used-preview-title") || "").trim() || defaultTitle;
      const requestToken = ++activateRequestToken;
      selectItem(item);
      body.innerHTML = loadingPreviewHtml();
      if (opts.openWrap !== false) {
        openWrap({ loadPreview: false });
      }
      if (
        !previewKey ||
        !previewUtils ||
        typeof previewUtils.loadSharedPreviewEntry !== "function" ||
        typeof previewUtils.readPreviewTemplate !== "function"
      ) {
        body.innerHTML = previewUnavailableHtml(previewUtils, previewKey, "");
        return;
      }
      try {
        const sharedEntry = await previewUtils.loadSharedPreviewEntry(previewKey);
        if (requestToken !== activateRequestToken) return;
        const html = previewUtils.readPreviewTemplate(sharedEntry);
        if (!html) {
          body.innerHTML = previewUnavailableHtml(previewUtils, previewKey, "");
          return;
        }
        body.innerHTML = html;
        if (previewUtils && typeof previewUtils.hydratePreviewSubtree === "function") {
          previewUtils.hydratePreviewSubtree(body);
        }
        if (previewUtils && typeof previewUtils.renderMath === "function") {
          previewUtils.renderMath(body);
        }
      } catch (_err) {
        if (requestToken !== activateRequestToken) return;
        body.innerHTML = previewUnavailableHtml(
          previewUtils,
          previewKey,
          "The shared preview content could not be loaded. Refresh the page, or rebuild the site if this persists."
        );
      }
    }

    items.forEach(function (item) {
      if (!(item instanceof Element)) return;
      item.addEventListener("mouseenter", function () {
        activate(item);
      });
      item.addEventListener("focusin", function () {
        activate(item);
      });
    });
    const initialItem = items.find(function (item) {
      return item instanceof Element && item.classList.contains("bp_used_by_item_active");
    }) || items[0];
    if (initialItem instanceof Element) {
      selectItem(initialItem);
    }

    if (wrap instanceof Element && chip instanceof Element) {
      setExpanded(wrap.classList.contains("bp_used_by_wrap_open"));
      const previewAwareClose = function (ev) {
        if (!previewUtils || typeof previewUtils.shouldKeepOpen !== "function") {
          scheduleClose();
          return;
        }
        if (previewUtils.shouldKeepOpen(ev.relatedTarget, wrap, panel)) return;
        scheduleClose();
      };
      chip.addEventListener("mouseenter", openWrap);
      chip.addEventListener("focusin", openWrap);
      chip.addEventListener("mouseleave", previewAwareClose);
      chip.addEventListener("focusout", previewAwareClose);
      panel.addEventListener("mouseenter", openWrap);
      panel.addEventListener("focusin", openWrap);
      panel.addEventListener("mouseleave", previewAwareClose);
      panel.addEventListener("focusout", previewAwareClose);
      chip.addEventListener("click", function (ev) {
        ev.preventDefault();
        ev.stopPropagation();
        cancelClose();
        wrap.classList.toggle("bp_used_by_wrap_open");
        const expanded = wrap.classList.contains("bp_used_by_wrap_open");
        setExpanded(expanded);
        if (expanded) {
          loadActivePreview();
        }
      });
      panel.addEventListener("click", function (ev) {
        ev.stopPropagation();
      });
      document.addEventListener("click", function (ev) {
        if (!(ev.target instanceof Element)) {
          closeWrap();
          return;
        }
        if (!wrap.contains(ev.target)) {
          closeWrap();
        }
      });
      document.addEventListener("keydown", function (ev) {
        if (ev.key === "Escape") {
          closeWrap();
        }
      });
    }
  }

  function bindAllUsedByPanels(root) {
    if (!(root instanceof Element || root instanceof Document)) return;
    root.querySelectorAll(".bp_used_by_panel").forEach(bindUsedByPanel);
  }

  if (window.bpPreviewUtils && typeof window.bpPreviewUtils.registerPreviewHydrator === "function") {
    window.bpPreviewUtils.registerPreviewHydrator("usedBy", bindAllUsedByPanels);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      bindAllUsedByPanels(document);
    });
  } else {
    bindAllUsedByPanels(document);
  }
})();"##

def blockJsAssets : List String :=
  Informal.Commands.withInlinePreviewJsAssets
    []
    [codeSummaryPreviewJs, usedByPanelJs, Informal.StyleSwitcher.jsInteractive]

end Informal.Block.Assets
