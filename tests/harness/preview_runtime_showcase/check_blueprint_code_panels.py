#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys

PACKAGE_ROOT = Path(__file__).resolve().parents[3]
if str(PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(PACKAGE_ROOT))

from scripts.blueprint_harness_paths import default_test_blueprint_site_dir, resolve_cli_path


def fail(msg: str) -> None:
    print(f"[blueprint-panel-regression] FAIL: {msg}", file=sys.stderr)
    raise SystemExit(1)


def load(path: Path) -> str:
    if not path.exists():
        fail(f"missing file: {path}")
    return path.read_text(encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Static regression checks for generated local code-panel showcase pages."
    )
    parser.add_argument(
        "--site-dir",
        default=None,
        help="Path to the generated preview_runtime_showcase html-multi directory.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    out_root = (
        resolve_cli_path(args.site_dir)
        if args.site_dir is not None
        else default_test_blueprint_site_dir("preview_runtime_showcase", Path(__file__))
    )
    code_panels = load(out_root / "Code-Panels" / "index.html")

    if "bp_external_status_badge_summary bp_external_status_ok" not in code_panels:
        fail("missing external summary badge for complete external declarations")
    if "bp_external_status_badge_summary bp_external_status_sorry" not in code_panels:
        fail("missing external warning summary badge for sorry-backed declarations")
    if "bp_external_status_badge_summary bp_external_status_missing" not in code_panels:
        fail("missing external summary badge for missing external declarations")
    if "External Lean for " in code_panels:
        fail("stale external panel caption still present")
    if "Lean code for Definition" not in code_panels:
        fail("definition code panel caption missing")
    if "Lean code for Theorem" not in code_panels:
        fail("theorem code panel caption missing")
    if "bp_code_link_status_proved" not in code_panels:
        fail("missing proved code-status chip")
    if "bp_code_link_status_warning" not in code_panels:
        fail("missing warning code-status chip")
    if "bp_code_link_status_axiom" not in code_panels:
        fail("missing axiom code-status chip")
    if "bp_code_link_status_missing" not in code_panels:
        fail("missing missing-declaration code-status chip")
    if "bp_code_link_status_absent" not in code_panels:
        fail("missing absent-code code-status chip")
    if 'bp_external_status_badge_text">1 theorem<' not in code_panels:
        fail("missing theorem-specific external summary text")
    if 'bp_external_status_badge_text">1 definition<' not in code_panels:
        fail("missing definition-specific external summary text")
    if "bp-renderer-select" in code_panels:
        fail("stale external renderer switcher still present")
    if "bp_code_expand_hint" in code_panels:
        fail("stale expand hint markup still present")
    if "bp_external_decl_render_error" in code_panels or "Render failed:" in code_panels:
        fail("unexpected external declaration render failure remains in showcase")
    if re.search(
        r'<pre class="bp_external_decl_signature signature hl lean block"><span class="keyword token">[^<]+</span> <div class="wide-only">',
        code_panels,
        re.S,
    ):
        fail("external declaration signature still nests wide-only markup inside <pre>")

    panel_re = re.compile(r'<details class="bp_code_block bp_code_panel"[^>]*>.*?</details>', re.S)
    external_panels = [p for p in panel_re.findall(code_panels) if "bp_external_status_badge_summary" in p]
    if len(external_panels) < 8:
        fail("expected at least eight external code panels in local showcase")

    for i, panel in enumerate(external_panels, start=1):
        if "bp_code_progress" in panel:
            fail(f"external panel #{i} still renders a progress bar")
        if 'class="namedocs"' in panel:
            fail(f"external panel #{i} still includes nested namedocs wrapper")
        if "bp_external_decl_renderer_variant" in panel:
            fail(f"external panel #{i} still includes renderer variants")
        if "data-bp-external-renderer" in panel:
            fail(f"external panel #{i} still includes renderer mode attributes")
        if "bp_external_decl_rendered" not in panel:
            if "bp_external_decl_missing" not in panel:
                fail(f"external panel #{i} missing rendered or missing-declaration body")
        if "bp_external_decl_stmt" not in panel and "bp_external_decl_rendered" not in panel:
            fail(f"external panel #{i} missing external declaration content")

    if "declaration not found" not in code_panels:
        fail("missing missing-declaration panel body")
    if "bp_external_decl_missing" not in code_panels:
        fail("missing missing-declaration row styling")
    if "PreviewRuntimeShowcase.CodePanelDecls.previewExternalDefinition" not in code_panels:
        fail("missing in-module external definition showcase declaration")
    if "PreviewRuntimeShowcase.CodePanelDecls.previewExternalAbbrev" not in code_panels:
        fail("missing in-module external abbrev showcase declaration")
    if "PreviewRuntimeShowcase.CodePanelDecls.previewExternalTheorem" not in code_panels:
        fail("missing in-module external theorem showcase declaration")
    if "Nat.add" not in code_panels:
        fail("missing out-of-module external definition showcase declaration")
    if "Nat.add_assoc" not in code_panels:
        fail("missing out-of-module external theorem showcase declaration")
    abbrev_panel = next(
        (p for p in external_panels if "PreviewRuntimeShowcase.CodePanelDecls.previewExternalAbbrev" in p),
        None,
    )
    if abbrev_panel is None:
        fail("missing external abbrev code panel")
    if 'class="declaration decl def abbrev"' not in abbrev_panel:
        fail("external abbrev panel missing definition-compatible abbrev styling classes")
    if 'data-kind="abbrev"' not in abbrev_panel:
        fail("external abbrev panel missing abbrev kind marker")
    if '<span class="keyword token">abbrev</span>' not in abbrev_panel:
        fail("external abbrev panel missing abbrev signature keyword")
    if 'data-kind="def"' in abbrev_panel:
        fail("external abbrev panel still exposes def kind")

    literate_panels = [p for p in panel_re.findall(code_panels) if "data-bp-proof-fold=" in p]
    if len(literate_panels) < 3:
        fail("expected at least three literate code panels in local showcase")

    for i, panel in enumerate(literate_panels, start=1):
        if "bp_code_summary_indicator" not in panel:
            fail(f"literate panel #{i} missing summary indicator wrapper")
    if "panelInlineOnlyOk" not in code_panels:
        fail("missing inline proved showcase declaration")
    if "panelInlineOnlySorry" not in code_panels:
        fail("missing inline warning showcase declaration")
    if "panelInlineAxiom" not in code_panels:
        fail("missing inline axiom showcase declaration")
    if "panelInlineOk" not in code_panels or "panelInlineSorry" not in code_panels:
        fail("missing mixed inline progress showcase declarations")

    print(
        "[blueprint-panel-regression] OK:",
        f"external_panels={len(external_panels)}",
        f"literate_panels={len(literate_panels)}",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
