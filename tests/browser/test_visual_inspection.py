"""Regressions for BPC-0001 on the `visual_inspection` test Blueprint."""

from playwright.sync_api import Page, expect

from support import assert_no_runtime_errors, record_runtime_errors

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

