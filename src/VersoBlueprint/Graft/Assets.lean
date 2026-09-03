/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public section

namespace Informal.Graft

def css : String := r##"
.bp_graft_node {
  display: block;
  margin: 0.75rem 0;
}

.bp_graft_node_compact .bp_code_panel_wrapper {
  display: none;
}

.bp_graft_node_notice {
  margin: 0.75rem 0;
  padding: 0.6rem 0.75rem;
  border: 1px solid var(--bp-color-status-error-border-soft);
  border-radius: var(--bp-radius-md);
  background: var(--bp-color-surface-warn);
  color: var(--bp-color-status-error-strong);
  font-size: 0.9rem;
  line-height: 1.4;
}

.bp_graft_side_by_side {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(22rem, 100%), 1fr));
  gap: 0.9rem;
  align-items: start;
  margin: 0.9rem 0;
}

.bp_graft_side_by_side > * {
  min-width: 0;
}

.bp_graft_side_by_side_boxed > * {
  padding: 0.75rem;
  border: 1px solid var(--bp-color-border-soft, #d8dee8);
  border-radius: var(--bp-radius-md, 0.45rem);
  background: var(--bp-color-surface, #ffffff);
  box-shadow: 0 1px 2px rgba(15, 23, 42, 0.06);
}

.bp_graft_side_by_side .bp_wrapper,
.bp_graft_side_by_side .bp_graft_node {
  margin-top: 0;
  margin-bottom: 0;
}

.bp_graft_side_by_side .bp_heading {
  align-items: flex-start;
}

.bp_graft_side_by_side .bp_extras {
  margin-left: 0;
}

.bp_graft_side_by_side .bp_code_block summary {
  align-items: flex-start;
  flex-wrap: wrap;
}

.bp_graft_side_by_side .bp_code_summary_text {
  white-space: normal;
}

.bp_graft_side_by_side .bp_code_summary_indicator {
  margin-left: 0;
  width: 100%;
  max-width: 100%;
}

.bp_graft_side_by_side .bp_code_summary_indicator .bp_code_summary_preview_root,
.bp_graft_side_by_side .bp_code_summary_indicator .bp_code_summary_preview_wrap {
  display: block;
  width: 100%;
  max-width: 100%;
}

.bp_graft_side_by_side .bp_code_progress {
  width: 100%;
  min-width: 0;
  max-width: 100%;
}
"##

def cssAssets : List String := [css]

end Informal.Graft
