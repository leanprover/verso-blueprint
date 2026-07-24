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


def require_contains(haystack: str, needle: str, description: str) -> None:
    if needle not in haystack:
        fail(f"Missing {description}: {needle!r}")


def find_issue_130_page(out_root: Path) -> tuple[Path, str]:
    matches: list[tuple[Path, str]] = []
    for path in out_root.rglob("index.html"):
        html = load(path)
        if "Issue #130 heading-outline reproduction" in html:
            matches.append((path, html))

    if not matches:
        fail("Could not find issue #130 external declaration heading reproduction page")

    if len(matches) > 1:
        locations = ", ".join(str(path.relative_to(out_root)) for path, _ in matches)
        fail(f"Expected one issue #130 reproduction page, found {len(matches)}: {locations}")

    return matches[0]


def check_external_decl_section_label(
    html: str,
    label: str,
    description: str,
) -> None:
    pattern = (
        r'<div class="bp_external_decl_section" role="group" aria-labelledby="([^"]+)">\s*'
        r'<p class="bp_external_decl_section_label" id="\1">\s*'
        + re.escape(label)
        + r"\s*</p>"
    )
    if not re.search(pattern, html, re.S):
        fail(f"Missing named external declaration subsection group for {description}: {label}")


def has_class_set(html: str, required_classes: tuple[str, ...]) -> bool:
    required = set(required_classes)
    return any(
        required.issubset(set(class_attr.split()))
        for class_attr in re.findall(r'class="([^"]+)"', html)
    )


def require_class_set(html: str, required_classes: tuple[str, ...], description: str) -> None:
    if not has_class_set(html, required_classes):
        fail(f"{description} missing classes: {' '.join(required_classes)}")


def check_issue_130_external_decl_headings(out_root: Path) -> tuple[Path, list[str]]:
    issue_page, issue_html = find_issue_130_page(out_root)
    expected_labels = ["Fields", "Methods", "Constructors", "Extends"]

    raw_heading_re = r"<h1>\s*(?:Fields|Methods|Constructors|Extends|Constructor|Instance Constructor)\s*</h1>"
    if re.search(raw_heading_re, issue_html):
        fail("Issue #130 reproduction still renders external declaration subsection labels as h1")

    for label in expected_labels:
        check_external_decl_section_label(issue_html, label, f"issue #130 {label}")

    for definition_name in [
        "h1_repro_structure",
        "h1_repro_class",
        "h1_repro_inductive",
        "h1_repro_extends",
    ]:
        require_contains(issue_html, definition_name, f"{definition_name} reproduction node")

    return issue_page, expected_labels


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
    if 'bp_external_status_badge_text">2 theorems<' not in code_panels:
        fail("missing multi-theorem external summary text")
    if 'bp_external_status_badge_text">2 theorems, 1 incomplete<' not in code_panels:
        fail("missing mixed multi-theorem external summary text")
    if 'bp_external_status_badge_text">2 declarations, 1 missing<' not in code_panels:
        fail("missing mixed missing external summary text")
    if 'bp_external_status_badge_text">1 definition<' not in code_panels:
        fail("missing definition-specific external summary text")
    if 'bp_external_status_badge_text">2 definitions<' not in code_panels:
        fail("missing multi-definition external summary text")
    if "bp-renderer-select" in code_panels:
        fail("stale external renderer switcher still present")
    if "bp_code_expand_hint" in code_panels:
        fail("stale expand hint markup still present")
    if "bp_external_decl_render_error" in code_panels or "Render failed:" in code_panels:
        fail("unexpected external declaration render failure remains in showcase")
    if "padding-left: 1.1rem" in code_panels or "margin: 0.12rem 0 0" in code_panels:
        fail("shared code hover list spacing should not indent rendered declarations")
    if ".bp_external_decl_list > .bp_external_decl_item_rendered + .bp_external_decl_item_rendered" in code_panels:
        fail("rendered external declaration separator CSS should be gone")
    if "border-top-color: var(--bp-color-border-strong)" in code_panels:
        fail("rendered external declaration separator bar should be gone")
    if "bp_external_decl_kicker" not in code_panels:
        fail("missing compact rendered declaration boundary row")
    if "bp_external_decl_kind" not in code_panels:
        fail("missing compact rendered declaration kind marker")
    if "bp_external_decl_header_meta" not in code_panels:
        fail("missing compact rendered declaration metadata chips")
    if 'bp_external_decl_header_meta">docstring</span>' in code_panels or 'bp_external_decl_header_meta">(docstring)</span>' in code_panels:
        fail("rendered declaration header still displays uninformative docstring metadata")
    if "bp_external_decl_header_status" not in code_panels:
        fail("missing compact rendered declaration status marker")
    require_class_set(code_panels, ("declaration", "decl"), "rendered external declarations")
    require_class_set(code_panels, ("bp_external_decl_kicker",), "rendered external declaration header")
    if has_class_set(code_panels, ("bp_box",)) or has_class_set(code_panels, ("bp_box_header",)):
        fail("generic box utility classes should not be part of rendered declaration markup")
    if has_class_set(code_panels, ("bp_external_decl_box",)):
        fail("rendered declaration markup should keep the original declaration class contract")
    if (
        ".bp_external_decl_rendered .declaration {" not in code_panels
        or "border: var(--bp-box-border-width, 1px) solid" not in code_panels
    ):
        fail("missing scoped rendered declaration box primitive")
    if "border-left: var(--bp-box-border-left-width, var(--bp-box-border-width, 1px)) solid" not in code_panels:
        fail("missing reusable box left-border override primitive")
    if (
        "width: var(--bp-box-width, auto)" not in code_panels
        or "min-width: var(--bp-box-min-width, 0)" not in code_panels
    ):
        fail("missing reusable box sizing primitive")
    if "overflow: var(--bp-box-overflow, hidden)" not in code_panels:
        fail("missing reusable box overflow primitive")
    if "--bp-box-width: 100%" not in code_panels:
        fail("rendered declaration boxes should opt into full-width layout")
    if "--bp-box-border-left-width: 0.15rem" not in code_panels:
        fail("rendered declaration box left rail no longer matches theorem-scale width")
    if "--bp-box-border-left-color: var(--bp-color-border-strong)" not in code_panels:
        fail("rendered declaration box left rail no longer uses theorem-scale color")
    if ".bp_external_decl_kicker {" not in code_panels or (
        "background: var(--bp-box-header-background, var(--bp-color-surface-muted))" not in code_panels
    ):
        fail("missing reusable rendered declaration header band styling")
    if (
        ".bp_code_panel .bp_external_decl_rendered .declaration" not in code_panels
        or "--bp-box-shadow: var(--bp-shadow-sm)" not in code_panels
    ):
        fail("missing code-panel-specific single-box treatment for external declarations")
    if ".bp_code_panel_wrapper .bp_code_block > summary::before" not in code_panels:
        fail("missing code-panel collapse indicator")
    if ".bp_code_panel_wrapper .bp_code_block[open] > summary::before" not in code_panels:
        fail("missing open-state code-panel collapse indicator")
    if ".bp_code_panel_wrapper .bp_code_block > summary::-webkit-details-marker" not in code_panels:
        fail("missing native marker suppression for code-panel collapse indicator")
    if "padding: 0.32rem 0.35rem" not in code_panels:
        fail("missing compact rendered declaration header padding")
    if "padding: 0.4rem 0.35rem" not in code_panels:
        fail("missing compact rendered declaration signature padding")
    if "bp_external_decl_kicker_status" not in code_panels:
        fail("missing right-aligned rendered declaration header status container")
    if "bp_external_decl_source_path" not in code_panels:
        fail("missing rendered declaration source path metadata")
    source_link_re = re.compile(
        r'<a class="bp_external_decl_source_path" href="https://github\.com/leanprover/verso-blueprint/blob/[0-9a-f]{40}/tests/test_blueprints/preview_runtime_showcase/PreviewRuntimeShowcase/Chapters/CodePanels\.lean#L\d+(?:-L\d+)?">PreviewRuntimeShowcase/Chapters/CodePanels\.lean</a>'
    )
    if source_link_re.search(code_panels) is None:
        fail("missing GitHub source links for in-module rendered declarations")
    source_range_link_re = re.compile(
        r'<a class="bp_external_decl_source_path" href="https://github\.com/leanprover/verso-blueprint/blob/[0-9a-f]{40}/tests/test_blueprints/preview_runtime_showcase/PreviewRuntimeShowcase/Chapters/CodePanels\.lean#L\d+-L\d+">PreviewRuntimeShowcase/Chapters/CodePanels\.lean</a>'
    )
    if source_range_link_re.search(code_panels) is None:
        fail("missing GitHub source links with line ranges for multi-line declarations")
    if re.search(
        r'defined in <span class="bp_external_decl_source_path">PreviewRuntimeShowcase/Chapters/CodePanels\.lean</span>',
        code_panels,
    ):
        fail("in-module rendered declaration source path is not linked")
    if re.search(r'<div class="bp_external_decl_kicker"[^>]*>(?:(?!</div>).)*<code>', code_panels, re.S):
        fail("rendered declaration boundary row still duplicates declaration names")
    if re.search(
        r'<pre class="bp_external_decl_signature signature hl lean block"><span class="keyword token">[^<]+</span> <div class="wide-only">',
        code_panels,
        re.S,
    ):
        fail("external declaration signature still nests wide-only markup inside <pre>")
    if re.search(
        r"<h1>\s*(?:Fields|Methods|Constructors|Extends|Constructor|Instance Constructor)\s*</h1>",
        code_panels,
    ):
        fail("external declaration subsection labels should not render as h1")

    panel_re = re.compile(r'<details class="bp_code_block bp_code_panel"[^>]*>.*?</details>', re.S)
    external_panels = [p for p in panel_re.findall(code_panels) if "bp_external_status_badge_summary" in p]
    if len(external_panels) < 19:
        fail("expected at least nineteen external code panels in local showcase")

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
    if "PreviewRuntimeShowcase.CodePanelDecls.previewExternalUnsafeDefinition" not in code_panels:
        fail("missing in-module external unsafe definition showcase declaration")
    if "PreviewRuntimeShowcase.CodePanelDecls.previewDocstringedDefinition" not in code_panels:
        fail("missing in-module documented external definition showcase declaration")
    if "PreviewRuntimeShowcase.CodePanelDecls.previewDocstringedFunction" not in code_panels:
        fail("missing in-module documented external function showcase declaration")
    if "PreviewRuntimeShowcase.CodePanelDecls.previewVersoDocstringedDefinition" not in code_panels:
        fail("missing in-module Verso-docstring external definition showcase declaration")
    if "PreviewRuntimeShowcase.CodePanelDecls.PreviewVersoDocstringedStructure" not in code_panels:
        fail("missing in-module Verso-docstring external structure showcase declaration")
    if "PreviewRuntimeShowcase.CodePanelDecls.previewExternalTheorem" not in code_panels:
        fail("missing in-module external theorem showcase declaration")
    if "PreviewRuntimeShowcase.CodePanelDecls.previewDocstringedTheorem" not in code_panels:
        fail("missing in-module documented external theorem showcase declaration")
    if "PreviewRuntimeShowcase.CodePanelDecls.previewExternalTheoremTwo" not in code_panels:
        fail("missing in-module external multi-theorem showcase declaration")
    if "PreviewRuntimeShowcase.CodePanelDecls.PreviewStage" not in code_panels:
        fail("missing in-module external inductive showcase declaration")
    if "PreviewRuntimeShowcase.CodePanelDecls.PreviewFold" not in code_panels:
        fail("missing in-module external class showcase declaration")
    if "PreviewRuntimeShowcase.CodePanelDecls.PreviewFreyPackage" not in code_panels:
        fail("missing in-module external structure showcase declaration")
    if "PreviewRuntimeShowcase.CodePanelDecls.PreviewFreyPackage.ofCounterexample" not in code_panels:
        fail("missing in-module external theorem docstring showcase declaration")
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
    require_class_set(abbrev_panel, ("declaration", "decl", "def", "abbrev"), "external abbrev panel")
    if 'data-kind="abbrev"' not in abbrev_panel:
        fail("external abbrev panel missing abbrev kind marker")
    if '<span class="keyword token">abbrev</span>' not in abbrev_panel:
        fail("external abbrev panel missing abbrev signature keyword")
    if 'data-kind="def"' in abbrev_panel:
        fail("external abbrev panel still exposes def kind")

    unsafe_panel = next(
        (
            p
            for p in external_panels
            if "PreviewRuntimeShowcase.CodePanelDecls.previewExternalUnsafeDefinition" in p
        ),
        None,
    )
    if unsafe_panel is None:
        fail("missing external unsafe definition code panel")
    if 'data-kind="def"' not in unsafe_panel:
        fail("external unsafe definition panel missing def kind marker")
    if '<span class="bp_external_decl_kind">def</span>' not in unsafe_panel:
        fail("external unsafe definition panel missing visible def kind marker")
    if '<span class="bp_external_decl_header_meta">(unsafe)</span>' not in unsafe_panel:
        fail("external unsafe definition panel missing unsafe metadata chip")
    if '<span class="keyword token">unsafe def</span>' not in unsafe_panel:
        fail("external unsafe definition panel missing unsafe signature keyword")
    if "defined in" not in unsafe_panel or "PreviewRuntimeShowcase/Chapters/CodePanels.lean" not in unsafe_panel:
        fail("external unsafe definition panel missing elegant source path metadata")

    docstringed_defs_panel = next(
        (
            p
            for p in external_panels
            if "PreviewRuntimeShowcase.CodePanelDecls.previewDocstringedDefinition" in p
            and "PreviewRuntimeShowcase.CodePanelDecls.previewDocstringedFunction" in p
        ),
        None,
    )
    if docstringed_defs_panel is None:
        fail("missing documented multi-definition external code panel")
    if docstringed_defs_panel.count("bp_external_decl_kicker") < 2:
        fail("documented multi-definition panel missing per-declaration boundary rows")
    if docstringed_defs_panel.count("bp_external_decl_header_status bp_external_decl_ok") < 2:
        fail("documented multi-definition panel missing per-declaration completion badges")
    if docstringed_defs_panel.count('bp_external_decl_kind">def</span>') < 2:
        fail("documented multi-definition panel missing visible def kind markers")
    if not re.search(
        r'<span class="bp_external_decl_kind">def</span>.*?<div class="bp_external_decl_kicker_status">\s*<span class="bp_external_status_badge bp_external_decl_header_status bp_external_decl_ok">complete</span>',
        docstringed_defs_panel,
        re.S,
    ):
        fail("documented multi-definition panel does not place kind metadata before right-aligned completion badge")
    if "The first documented preview definition" not in docstringed_defs_panel:
        fail("documented multi-definition panel missing first definition docstring")
    if "The second paragraph keeps paragraph spacing visible" not in docstringed_defs_panel:
        fail("documented multi-definition panel missing second definition docstring")
    if docstringed_defs_panel.count('data-kind="def"') < 2:
        fail("documented multi-definition panel missing def kind markers")

    verso_docstring_panel = next(
        (
            p
            for p in external_panels
            if 'data-decl="PreviewRuntimeShowcase.CodePanelDecls.previewVersoDocstringedDefinition"'
            in p
        ),
        None,
    )
    if verso_docstring_panel is None:
        fail("missing Verso-docstring external code panel")
    if "<strong>structural external-panel docstring</strong>" not in verso_docstring_panel:
        fail("Verso-docstring panel missing structural emphasis")
    if '<code class="bp_math inline">6 + 1 = 7</code>' not in verso_docstring_panel:
        fail("Verso-docstring panel missing structural inline mathematics")
    if verso_docstring_panel.count("structural panel item") < 2:
        fail("Verso-docstring panel missing structural list items")
    if '<pre class="docstring">' in verso_docstring_panel:
        fail("Verso-docstring panel was flattened to a plain docstring")

    verso_structure_panel = next(
        (
            p
            for p in external_panels
            if 'data-decl="PreviewRuntimeShowcase.CodePanelDecls.PreviewVersoDocstringedStructure"'
            in p
        ),
        None,
    )
    if verso_structure_panel is None:
        fail("missing Verso-docstring external structure panel")
    if "<strong>structural container docstring</strong>" not in verso_structure_panel:
        fail("Verso structure panel missing structural declaration emphasis")
    if "<strong>structural field docstring</strong>" not in verso_structure_panel:
        fail("Verso structure panel missing structural field emphasis")
    if '<code class="bp_math inline">8 + 1 = 9</code>' not in verso_structure_panel:
        fail("Verso structure panel missing structural field mathematics")

    theorem_docstring_panel = next(
        (
            p
            for p in external_panels
            if 'data-decl="PreviewRuntimeShowcase.CodePanelDecls.previewDocstringedTheorem"' in p
        ),
        None,
    )
    if theorem_docstring_panel is None:
        fail("missing documented theorem external code panel")
    if "A documented preview theorem whose statement is intentionally small." not in theorem_docstring_panel:
        fail("documented theorem panel missing declaration docstring")

    inductive_panel = next(
        (
            p
            for p in external_panels
            if 'data-decl="PreviewRuntimeShowcase.CodePanelDecls.PreviewStage"' in p
        ),
        None,
    )
    if inductive_panel is None:
        fail("missing external inductive code panel")
    require_class_set(inductive_panel, ("declaration", "decl", "inductive"), "external inductive panel")
    if 'data-kind="inductive"' not in inductive_panel:
        fail("external inductive panel missing inductive kind marker")
    if '<span class="bp_external_decl_kind">inductive</span>' not in inductive_panel:
        fail("external inductive panel missing visible inductive kind marker")
    if "Constructors" not in inductive_panel:
        fail("external inductive panel missing constructor section")
    check_external_decl_section_label(inductive_panel, "Constructors", "external inductive panel")
    if "2 constructors" not in inductive_panel:
        fail("external inductive panel missing constructor-count metadata chip")
    if "PreviewStage.initial" not in inductive_panel or "PreviewStage.step" not in inductive_panel:
        fail("external inductive panel missing constructor signatures")
    if "The initial stage of the preview workflow." not in inductive_panel:
        fail("external inductive panel missing constructor docstring")

    class_panel = next(
        (
            p
            for p in external_panels
            if 'data-decl="PreviewRuntimeShowcase.CodePanelDecls.PreviewFold"' in p
        ),
        None,
    )
    if class_panel is None:
        fail("missing external class code panel")
    require_class_set(class_panel, ("declaration", "decl", "class"), "external class panel")
    if 'data-kind="class"' not in class_panel:
        fail("external class panel missing class kind marker")
    if '<span class="bp_external_decl_kind">class</span>' not in class_panel:
        fail("external class panel missing visible class kind marker")
    if "Methods" not in class_panel:
        fail("external class panel missing methods section")
    check_external_decl_section_label(class_panel, "Methods", "external class panel")
    if "2 methods" not in class_panel:
        fail("external class panel missing method-count metadata chip")
    if "PreviewFold.neutral" not in class_panel or "PreviewFold.combine" not in class_panel:
        fail("external class panel missing method signatures")
    if "The neutral preview value." not in class_panel:
        fail("external class panel missing method docstring")

    structure_panel = next(
        (
            p
            for p in external_panels
            if 'data-decl="PreviewRuntimeShowcase.CodePanelDecls.PreviewFreyPackage"' in p
        ),
        None,
    )
    if structure_panel is None:
        fail("missing external structure code panel")
    require_class_set(structure_panel, ("declaration", "decl", "structure"), "external structure panel")
    if 'data-kind="structure"' not in structure_panel:
        fail("external structure panel missing structure kind marker")
    if '<span class="bp_external_decl_kind">structure</span>' not in structure_panel:
        fail("external structure panel missing visible structure kind marker")
    if "Fields" not in structure_panel:
        fail("external structure panel missing fields section")
    check_external_decl_section_label(structure_panel, "Fields", "external structure panel")
    if "6 fields" not in structure_panel:
        fail("external structure panel missing field-count metadata chip")
    if "PreviewFreyPackage.hFLT" not in structure_panel:
        fail("external structure panel missing dependent field signature")
    if "PreviewFreyPackage.mk" in structure_panel or "Constructor" in structure_panel:
        fail("external structure panel still emphasizes the generated constructor")
    if source_range_link_re.search(structure_panel) is None:
        fail("external structure panel missing GitHub source line-range link")

    structure_docstring_panel = next(
        (
            p
            for p in external_panels
            if 'data-decl="PreviewRuntimeShowcase.CodePanelDecls.PreviewFreyPackage.ofCounterexample"' in p
        ),
        None,
    )
    if structure_docstring_panel is None:
        fail("missing external theorem docstring code panel")
    if "Given a counterexample `a^p + b^p = c^p`" not in structure_docstring_panel:
        fail("external theorem docstring panel missing counterexample prose")
    if "there exists a preview Frey package." not in structure_docstring_panel:
        fail("external theorem docstring panel missing package prose")

    mixed_constructs_panel = next(
        (
            p
            for p in external_panels
            if "PreviewRuntimeShowcase.CodePanelDecls.previewDocstringedDefinition" in p
            and "PreviewRuntimeShowcase.CodePanelDecls.previewDocstringedTheorem" in p
            and "PreviewRuntimeShowcase.CodePanelDecls.PreviewStage" in p
            and "PreviewRuntimeShowcase.CodePanelDecls.PreviewFold" in p
            and "PreviewRuntimeShowcase.CodePanelDecls.PreviewFreyPackage" in p
        ),
        None,
    )
    if mixed_constructs_panel is None:
        fail("missing mixed external construction code panel")
    for kind in ["def", "theorem", "inductive", "class", "structure"]:
        if f'data-kind="{kind}"' not in mixed_constructs_panel:
            fail(f"mixed external construction panel missing {kind} kind marker")

    literate_panels = [p for p in panel_re.findall(code_panels) if "data-bp-proof-fold=" in p]
    if len(literate_panels) < 9:
        fail("expected at least nine literate code panels in local showcase")

    for i, panel in enumerate(literate_panels, start=1):
        if "bp_code_summary_indicator" not in panel:
            fail(f"literate panel #{i} missing summary indicator wrapper")
    if "panelInlineOnlyOk" not in code_panels:
        fail("missing inline proved showcase declaration")
    if "panelInlineOnlySorry" not in code_panels:
        fail("missing inline warning showcase declaration")
    if "panelInlineMultiTheoremOkLeft" not in code_panels or "panelInlineMultiTheoremOkRight" not in code_panels:
        fail("missing inline multi-theorem proved showcase declarations")
    if "panelInlineMultiTheoremWarningOk" not in code_panels or "panelInlineMultiTheoremWarningSorry" not in code_panels:
        fail("missing inline multi-theorem warning showcase declarations")
    if "panelInlineAxiom" not in code_panels:
        fail("missing inline axiom showcase declaration")
    if "panelInlineOk" not in code_panels or "panelInlineSorry" not in code_panels:
        fail("missing mixed inline progress showcase declarations")
    if "PanelInlineDocstringedStructure" not in code_panels:
        fail("missing inline documented structure showcase declaration")
    if "Inline package docstring used to compare literate Lean" not in code_panels:
        fail("missing inline documented structure docstring")
    if "dependent-looking field" not in code_panels:
        fail("missing inline documented structure field docstring")
    if "PanelInlineDocstringedStage" not in code_panels:
        fail("missing inline documented inductive showcase declaration")
    if "Inline workflow stage docstring used to compare" not in code_panels:
        fail("missing inline documented inductive docstring")
    if "A follow-up inline stage carrying a counter." not in code_panels:
        fail("missing inline documented inductive constructor docstring")
    for decl in ["PanelInlineMixedConfig", "PanelInlineMixedState", "PanelInlineMixedFold"]:
        if decl not in code_panels:
            fail(f"missing mixed inline documented construction {decl}")
    if "Inline mixed fold class docstring." not in code_panels:
        fail("missing mixed inline class docstring")

    issue_page, issue_labels = check_issue_130_external_decl_headings(out_root)

    print(
        "[blueprint-panel-regression] OK:",
        f"external_panels={len(external_panels)}",
        f"literate_panels={len(literate_panels)}",
        f"issue130_page={issue_page.relative_to(out_root)}",
        f"issue130_section_labels={','.join(issue_labels)}",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
