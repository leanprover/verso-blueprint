import json
import urllib.request
from urllib.parse import urljoin

from playwright.sync_api import Page, expect

from support import assert_no_runtime_errors, record_runtime_errors


def manifest_entries(server):
    with urllib.request.urlopen(f"{server}/-verso-data/blueprint-manifest.json") as response:
        manifest = json.load(response)
    return manifest, {entry["key"]: entry for entry in manifest["previews"]}


def assert_rendered_previews(page, keys, expected_text):
    rendered = page.evaluate(
        """async (keys) => {
          const { createPreview } = await import("/-verso-data/api/preview.mjs");
          const api = createPreview();
          const results = [];
          for (const key of keys) {
            const host = document.createElement("div");
            document.body.appendChild(host);
            const result = await api.renderPreviewInto(host, key);
            results.push({ ok: result.ok, text: host.textContent });
          }
          return results;
        }""",
        keys,
    )
    assert all(result["ok"] for result in rendered)
    text = "\n".join(result["text"] for result in rendered)
    assert all(expected in text for expected in expected_text)


def test_late_attachments_reach_generated_previews(named_site, page: Page):
    server = named_site("imported-late-attachments")
    errors = record_runtime_errors(page)
    manifest, entries = manifest_entries(server)
    label = "key_theorem"
    statement = entries[f"{label}--statement"]
    page.goto(f"{server}/")
    proof = entries["key_theorem--proof"]
    assert [ref["label"] for ref in proof["proofUses"]] == ["proof_dep", "statement_dep"]
    assert proof["proofUses"] == statement["proofUses"]
    assert "late" in statement["tags"]
    assert proof["effort"] == "small"
    graph_node = next(
        node for graph in manifest["graphs"] for node in graph["nodes"]
        if node["label"] == "key_theorem"
    )
    assert graph_node["proofUses"] == proof["proofUses"]
    keys = [statement["key"], proof["key"]]
    expected_text = ["A statement declared in this module", "A proof declared in a different module"]
    assert_rendered_previews(page, keys, expected_text)
    assert_no_runtime_errors(errors)


def test_literate_attachments_reach_generated_previews(named_site, page: Page):
    server = named_site("imported-literate-attachments")
    errors = record_runtime_errors(page)
    manifest, entries = manifest_entries(server)
    label = "key_theorem"
    statement = entries[f"{label}--statement"]
    page.goto(f"{server}/")
    keys = statement["leanCodePreviewKeys"]
    assert len(keys) == len(set(keys)) == 2
    assert all(entries[key]["title"] == "Lean code for key_theorem" for key in keys)
    paths = {entries[key]["sourceLocation"]["location"]["path"] for key in keys}
    assert any("InlineAttachment.lean" in path for path in paths)
    assert any("LiterateSecond.lean" in path for path in paths)
    expected_text = ["inlineAttached", "inlineSecond"]
    assert_rendered_previews(page, keys, expected_text)
    assert_no_runtime_errors(errors)


def test_filled_facets_reach_generated_previews(named_site, page: Page):
    server = named_site("imported-filled-facets")
    errors = record_runtime_errors(page)
    manifest, entries = manifest_entries(server)
    label = "filled_facet"
    statement = entries[f"{label}--statement"]
    page.goto(f"{server}/")
    page.locator("body[data-bp-inline-preview-bound='1']").wait_for()
    references = page.locator('.bp_inline_preview_ref[data-bp-preview-key="filled_facet--statement"]')
    expect(references).to_have_count(2)
    expect(references.nth(1)).to_have_text("the completed result")
    references.first.hover()
    panel = page.locator("#bp-inline-preview-panel")
    expect(panel).to_be_visible()
    expect(panel).to_contain_text("A completed statement from page one.")
    proof = entries["filled_facet--proof"]
    keys = [statement["key"], proof["key"]]
    expected_text = [
        "A completed statement from page one.",
        "A completed proof from page two.",
    ]
    for entry, source_page, source_module, source_document in [
        (statement, "1", "FacetStatement.lean", "facet-paper"),
        (proof, "2", "FacetProof.lean", "facet-proof-paper"),
    ]:
        assert [span["page"] for source in entry["sources"] for span in source["spans"]] == [source_page]
        assert [source["document"] for source in entry["sources"]] == [source_document]
        assert source_module in entry["sourceLocation"]["location"]["path"]
        assert len(entry["leanCodePreviewKeys"]) == 1
        code = entries[entry["leanCodePreviewKeys"][0]]
        assert {source["document"] for source in code["sources"]} == {"facet-paper", "facet-proof-paper"}
        page.goto(urljoin(f"{server}/", entry["href"]))
        source_slot = page.locator(":target .bp_extra_slot_source")
        source_slot.locator(".bp_source_ref_chip").hover()
        source_preview = source_slot.locator(".bp_source_ref_preview_body")
        expect(source_preview).to_be_visible()
        expect(source_preview).to_contain_text(f"{source_document} p. {source_page}")
    graph_node = next(
        node for graph in manifest["graphs"] for node in graph["nodes"]
        if node["label"] == label
    )
    assert graph_node["href"] == statement["href"]
    page.goto(urljoin(f"{server}/", statement["href"]))
    expect(page.locator(":target")).to_contain_text(expected_text[0])

    assert_rendered_previews(page, keys, expected_text)
    assert_no_runtime_errors(errors)
