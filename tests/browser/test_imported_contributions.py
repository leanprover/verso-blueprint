import json
import subprocess
import sys
import urllib.request

import pytest
from playwright.sync_api import Page

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
    params=["imported-late-attachments", "imported-literate-attachments"],
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
    statement = entries["key_theorem--statement"]
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
    else:
        keys = statement["leanCodePreviewKeys"]
        assert len(keys) == len(set(keys)) == 2
        assert all(entries[key]["title"] == "Lean code for key_theorem" for key in keys)
        paths = {entries[key]["sourceLocation"]["location"]["path"] for key in keys}
        assert any("InlineAttachment.lean" in path for path in paths)
        assert any("LiterateSecond.lean" in path for path in paths)
        expected_text = ["inlineAttached", "inlineSecond"]

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
