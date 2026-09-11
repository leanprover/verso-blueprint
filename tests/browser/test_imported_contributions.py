import json
import subprocess
import sys
import urllib.request
from urllib.parse import urljoin

import pytest
from playwright.sync_api import Page, expect

from scripts.blueprint_harness_paths import canonical_test_blueprint_output_dir
from support import (
    PACKAGE_ROOT,
    assert_no_runtime_errors,
    find_free_port,
    record_runtime_errors,
    wait_for_server,
)


@pytest.fixture(
    scope="module",
    params=["imported-late-attachments", "imported-literate-attachments", "imported-filled-facets"],
)
def imported_site(request):
    slug = request.param
    output = canonical_test_blueprint_output_dir(slug, PACKAGE_ROOT)
    subprocess.run(
        [
            sys.executable, "-m", "scripts.blueprint_test_blueprints",
            "generate-all", slug,
        ],
        cwd=PACKAGE_ROOT,
        check=True,
    )
    port = find_free_port()
    proc = subprocess.Popen(
        [sys.executable, "-m", "http.server", str(port), "--bind", "127.0.0.1"],
        cwd=output / "html-multi",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    url = f"http://127.0.0.1:{port}"
    try:
        wait_for_server(url, proc)
        yield slug, url
    finally:
        proc.terminate()
        proc.wait()


def test_captured_imports_reach_generated_previews(imported_site, page: Page):
    slug, server = imported_site
    errors = record_runtime_errors(page)
    with urllib.request.urlopen(f"{server}/-verso-data/blueprint-manifest.json") as response:
        manifest = json.load(response)
    entries = {entry["key"]: entry for entry in manifest["previews"]}
    label = "filled_facet" if slug == "imported-filled-facets" else "key_theorem"
    statement = entries[f"{label}--statement"]
    page.goto(f"{server}/")

    if slug == "imported-late-attachments":
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
    elif slug == "imported-literate-attachments":
        keys = statement["leanCodePreviewKeys"]
        assert len(keys) == len(set(keys)) == 2
        assert all(entries[key]["title"] == "Lean code for key_theorem" for key in keys)
        paths = {entries[key]["sourceLocation"]["location"]["path"] for key in keys}
        assert any("InlineAttachment.lean" in path for path in paths)
        assert any("LiterateSecond.lean" in path for path in paths)
        expected_text = ["inlineAttached", "inlineSecond"]
    else:
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
    assert_no_runtime_errors(errors)
