"""Regressions for BPC-0001 on the `visual_inspection` test Blueprint."""

import json
import re

import pytest
from playwright.sync_api import Page, expect

from support import assert_no_runtime_errors, record_runtime_errors

LABEL_PIXELS = """() => {
  const label = document.querySelector('.bp_graph_canvas svg g.node text');
  return label ? label.getBoundingClientRect().height : 0;
}"""


def heading_status(page: Page, label: str) -> tuple[str, str]:
    link = page.locator(f'.bp_wrapper[title="{label}"] .bp_extra_slot_code .bp_code_link').first
    symbol = link.locator(".bp_code_status_symbol").inner_text().strip()
    status = next(
        name.removeprefix("bp_code_link_status_")
        for name in link.get_attribute("class").split()
        if name.startswith("bp_code_link_status_")
    )
    return symbol, status


def test_heading_status_distinguishes_each_formalization_state(named_site, page: Page):
    errors = record_runtime_errors(page)
    page.goto(f"{named_site('visual_inspection')}/Status-Matrix/")
    expected = {
        "status_statement_only": ("○", "absent"),
        "status_definition_complete": ("✓", "proved"),
        "status_definition_body_sorry": ("⚠", "warning"),
        "status_sorry": ("⚠", "warning"),
        "status_local_complete_prerequisite_open": ("◐", "requirements_open"),
        "status_fully_closed": ("✓", "proved"),
        "status_axiom": ("A", "axiom"),
        "status_external_missing": ("!", "missing"),
    }
    observed = {label: heading_status(page, label) for label in expected}
    assert observed == expected
    assert_no_runtime_errors(errors)


def test_empty_relation_chips_are_hidden_but_keep_their_column(named_site, page: Page):
    errors = record_runtime_errors(page)
    page.goto(f"{named_site('visual_inspection')}/Block-Anatomy/Header-Slots/")
    isolated = page.locator('.bp_wrapper[title="anatomy_isolated"]').first
    empty = isolated.locator(".bp_relation_chip_empty")
    expect(empty.first).to_be_attached()
    for index in range(empty.count()):
        expect(empty.nth(index)).to_be_hidden()
    hub_uses = page.locator('.bp_wrapper[title="anatomy_hub"] .bp_extra_slot_uses').first
    user_uses = page.locator('.bp_wrapper[title="anatomy_hub_user_one"] .bp_extra_slot_uses').first
    assert abs(hub_uses.bounding_box()["x"] - user_uses.bounding_box()["x"]) < 1
    assert_no_runtime_errors(errors)


def test_large_graph_opens_with_readable_labels(named_site, page: Page):
    errors = record_runtime_errors(page)
    page.goto(f"{named_site('visual_inspection')}/Dependency-Graph/")
    toggle = page.locator(".bp_graph_controls .bp_graph_zoom_toggle")
    expect(toggle).to_have_text("Show whole graph", timeout=30000)
    assert page.evaluate(LABEL_PIXELS) >= 7.5

    toggle.click()
    expect(toggle).to_have_text("Zoom to readable size")
    page.wait_for_function(f"({LABEL_PIXELS})() < 7.5")

    toggle.click()
    expect(toggle).to_have_text("Show whole graph")
    page.wait_for_function(f"({LABEL_PIXELS})() >= 7.5")
    assert_no_runtime_errors(errors)


def test_graph_explains_when_its_libraries_fail_to_load(named_site, page: Page):
    page.route("**/cdn.jsdelivr.net/**", lambda route: route.abort())
    page.goto(f"{named_site('visual_inspection')}/Dependency-Graph/")
    message = page.locator(".bp_graph_canvas .bp_graph_load_error")
    expect(message).to_be_visible()
    expect(message).to_contain_text("could not be drawn")


VISIBLE_PANEL_RECT = """(selector) => {
  const panel = [...document.querySelectorAll(selector)].find((element) => {
    const rect = element.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0 && getComputedStyle(element).visibility !== "hidden";
  });
  if (!panel) return null;
  const rect = panel.getBoundingClientRect();
  return { left: rect.left, top: rect.top, right: rect.right, bottom: rect.bottom };
}"""


@pytest.mark.parametrize("width,height", [(1440, 900), (390, 844)])
def test_block_popups_stay_inside_the_viewport(named_site, page: Page, width: int, height: int):
    errors = record_runtime_errors(page)
    page.set_viewport_size({"width": width, "height": height})
    page.goto(f"{named_site('visual_inspection')}/Block-Anatomy/Kinds/")
    theorem = '.bp_wrapper[title="anatomy_theorem"]'
    # Code previews open on hover; relation popups open on click.
    popups = [
        (f"{theorem} .bp_extra_slot_code .bp_code_link", ".bp_code_summary_preview_panel", False),
        (f"{theorem} .bp_extra_slot_uses .bp_relation_chip", ".bp_relation_panel_placed", True),
        (f"{theorem} .bp_extra_slot_group .bp_relation_chip", ".bp_relation_panel_placed", True),
    ]
    for trigger_selector, panel_selector, click in popups:
        trigger = page.locator(trigger_selector).first
        trigger.scroll_into_view_if_needed()
        if click:
            trigger.click()
        else:
            trigger.hover()
        query = f"({VISIBLE_PANEL_RECT})({json.dumps(panel_selector)})"
        page.wait_for_function(f"{query} !== null")
        page.wait_for_timeout(200)
        rect = page.evaluate(query)
        assert rect["left"] >= 0 and rect["top"] >= 0, (trigger_selector, rect)
        assert rect["right"] <= width and rect["bottom"] <= height, (trigger_selector, rect)
        box = trigger.bounding_box()
        covers_trigger = (
            rect["left"] < box["x"] + box["width"] and box["x"] < rect["right"]
            and rect["top"] < box["y"] + box["height"] and box["y"] < rect["bottom"]
        )
        assert not covers_trigger, (trigger_selector, rect, box)
        if click:
            page.keyboard.press("Escape")
        page.mouse.move(1, 1)
        page.wait_for_function(f"{query} === null")
    assert_no_runtime_errors(errors)


def test_block_parts_join_into_one_card(named_site, page: Page):
    """A statement, its proof and its Lean code, placed together, read as one card."""
    errors = record_runtime_errors(page)
    page.goto(f"{named_site('visual_inspection')}/Block-Anatomy/Kinds/")
    statement = page.locator('.bp_kind_theorem_wrapper[data-bp-owner="anatomy_theorem"]').first
    proof = page.locator('.bp_kind_proof_wrapper[data-bp-owner="anatomy_theorem"]').first
    code = page.locator('.bp_code_panel_wrapper[data-bp-owner="anatomy_theorem"]').first
    expect(statement).to_have_class(re.compile(r"\bbp_part_continues\b"))
    expect(proof).to_have_class(re.compile(r"\bbp_part_joined\b"))
    expect(proof).to_have_class(re.compile(r"\bbp_part_continues\b"))
    expect(code).to_have_class(re.compile(r"\bbp_part_joined\b"))

    # Joined, the proof reads "Proof." and the code panel "Lean"; their own
    # titles name the theorem only when they stand apart from it.
    expect(proof.locator(".bp_heading .bp_caption")).to_have_text("Proof.", use_inner_text=True)
    expect(code.locator(".bp_code_summary_text")).to_have_text(
        re.compile(r"^lean$", re.IGNORECASE), use_inner_text=True
    )
    for upper, lower in ((statement, proof), (proof, code)):
        upper_box, lower_box = upper.bounding_box(), lower.bounding_box()
        assert abs(upper_box["y"] + upper_box["height"] - lower_box["y"]) < 1

    # The next node starts its own card.
    corollary = page.locator('.bp_kind_corollary_wrapper[data-bp-owner="anatomy_corollary"]').first
    expect(corollary).not_to_have_class(re.compile(r"\bbp_part_joined\b"))
    assert_no_runtime_errors(errors)
