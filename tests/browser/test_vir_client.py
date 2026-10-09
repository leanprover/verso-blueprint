import subprocess
import json

import pytest
from playwright.sync_api import expect

from conftest import build_test_blueprint_site, serve_site
from support import PACKAGE_ROOT
from scripts.blueprint_harness_paths import detect_harness_layout


@pytest.fixture(scope="session")
def vir_client_site():
    output = detect_harness_layout(PACKAGE_ROOT).artifact_root / "vir-client-example"
    subprocess.run(
        [str(PACKAGE_ROOT / "scripts/lean-low-priority"), "lake", "exe",
         "vir-client-example", str(output)],
        cwd=PACKAGE_ROOT,
        check=True,
    )
    with serve_site(output) as url:
        yield url


@pytest.fixture(scope="session")
def external_markup_manifest():
    site = build_test_blueprint_site("preview_runtime_showcase")
    return site / "-verso-data" / "blueprint-manifest.json"


def test_vir_client_matches_native_and_disposes(page, vir_client_site):
    page.goto(vir_client_site)
    result = page.evaluate("""async () => {
        const client = await (await fetch(new URL('client.json', location.href))).json();
        const { createProgram } = await import(new URL(client.runtimeModule, location.href));
        const program = await createProgram({
            runtimeManifestUrl: new URL(client.runtimeManifest, location.href),
            programManifestUrl: new URL(client.programManifest, location.href),
        });
        const rejects = f => { try { f(); return false; } catch { return true; } };
        const result = {};
        try {
            result.actual = client.cases.map(({input}) => program.call(client.entry, input));
            result.expected = client.cases.map(({expected}) => expected);
            result.badArgument = rejects(() => program.call(client.entry, 17));
            result.missingExport = rejects(() => program.call('Missing.export', 'FLT'));
            result.recovered = program.call(client.entry, client.cases[1].input);
        } finally {
            program.dispose();
        }
        result.disposed = rejects(() => program.call(client.entry, 'FLT'));
        return result;
    }""")
    assert result["actual"] == result["expected"]
    assert len(result["actual"]) == 4
    assert result["badArgument"]
    assert result["missingExport"]
    assert result["recovered"] == result["expected"][1]
    assert result["disposed"]


def test_vir_external_markup_matches_native_and_js(page, vir_client_site):
    page.goto(vir_client_site)
    result = page.evaluate("""async () => {
        const client = await (await fetch('client.json')).json();
        const { createProgram } = await import(new URL(client.runtimeModule, location.href));
        const { createExternalMarkupSelector, selectionInput } = await import('./selector.mjs');
        const { selectExternalMarkup, renderExternalMarkupSelectionInto } =
            await import('./-verso-data/Commands/preview-runtime-render.mjs');
        const program = await createProgram({
            runtimeManifestUrl: new URL(client.runtimeManifest, location.href),
            programManifestUrl: new URL(client.programManifest, location.href),
        });
        const select = createExternalMarkupSelector(program, client.selectionEntry);
        const summarize = (result, entry, preferences) => ({
            ok: result.ok, reason: result.reason || '',
            markupIndex: result.markup === null ? null : entry.externalMarkup.indexOf(result.markup),
            preferenceIndex: result.preference === null ? null : preferences.indexOf(result.preference),
        });
        const compare = (entry, preferences) => {
            const actual = select(entry, preferences);
            const reference = selectExternalMarkup(entry, preferences);
            const summary = summarize(actual, entry, preferences);
            if (JSON.stringify(summary) !== JSON.stringify(summarize(reference, entry, preferences))) {
                throw new Error('VIR/JS selection differs: ' + JSON.stringify(summary));
            }
            if (actual.markup !== reference.markup || actual.preference !== reference.preference) {
                throw new Error('Selection did not preserve object/callback identity');
            }
            return summary;
        };
        const results = [];
        let malformed, callbackIdentity, descriptorSize, disposed, badResults, providerIdentity;
        try {
            for (const test of client.selectionCases) {
                const entry = {externalMarkup: test.input.markups.map((markup, i) => ({
                    language: markup.language, slot: markup.slot,
                    raw: markup.hasContent ? 'Body ' + i : '',
                }))};
                const preferences = test.input.preferences.map(preference => preference.enabled ? {
                    language: preference.language, slot: preference.slot,
                    ...(preference.canRender ? {display: 'source'} : {}),
                } : null);
                results.push({name: test.name, actual: compare(entry, preferences), expected: test.expected});
                const direct = JSON.parse(program.call(client.selectionEntry, JSON.stringify(test.input)));
                if (JSON.stringify(direct) !== JSON.stringify(test.expected)) {
                    // JSON object order is not part of the wire contract.
                    for (const key of Object.keys(test.expected)) {
                        if (direct[key] !== test.expected[key]) throw new Error('Native/VIR differs: ' + test.name);
                    }
                }
            }
            const callbackError = new Error('callback error identity');
            const callback = () => { throw callbackError; };
            const opaque = {}; opaque.self = opaque;
            const entry = {externalMarkup: [null, {
                language: '\\u00a0MARKDOWN\\ufeff', slot: ' δοκιμή 🦀 ',
                raw: '\\u0000' + 'x'.repeat(100000), opaque,
            }]};
            const preferences = [17, null, {
                language: ' markdown ', slot: 'δοκιμή 🦀', render: callback,
            }];
            const chosen = compare(entry, preferences);
            descriptorSize = JSON.stringify(selectionInput(entry, preferences)).length;
            const selection = select(entry, preferences);
            try {
                await renderExternalMarkupSelectionInto(document.createElement('div'), selection, {});
            } catch (error) { callbackIdentity = error === callbackError; }
            compare({externalMarkup: [{language: 'markdown', slot: 7, raw: ' '}]},
                    [{language: 'Markdown', slot: '7', display: ' SOURCE '}]);
            compare({externalMarkup: [{language: 'Σ', slot: '', raw: 'x'}]},
                    [{language: 'σ', display: 'source'}]);
            malformed = ['{', '{}', '{"markups":[],"preferences":17}'].every(input =>
                typeof JSON.parse(program.call(client.selectionEntry, input)).error === 'string');
            const invalid = [null, [],
                {ok: true, reason: '', markupIndex: null, preferenceIndex: null},
                {ok: true, reason: '', markupIndex: 99, preferenceIndex: 2},
                {ok: false, reason: 'external-markup-missing', markupIndex: 1, preferenceIndex: 2},
                {ok: false, reason: 'external-markup-renderer-missing', markupIndex: null, preferenceIndex: null},
                {ok: false, reason: 'unknown', markupIndex: null, preferenceIndex: null}];
            badResults = invalid.every(output => {
                const invalidSelect = createExternalMarkupSelector({call: () => JSON.stringify(output)}, 'test');
                try { invalidSelect(entry, preferences); return false; } catch { return true; }
            });
            const providerError = new Error('provider identity');
            try {
                createExternalMarkupSelector({call: () => {throw providerError;}}, 'test')(entry, preferences);
            } catch (error) { providerIdentity = error === providerError; }
            // Errors must not poison the retained program.
            compare(entry, preferences);
        } finally { program.dispose(); }
        try { select({externalMarkup: []}, []); disposed = false; }
        catch { disposed = true; }
        return {results, malformed, callbackIdentity, descriptorSize, disposed, badResults, providerIdentity};
    }""")
    assert len(result["results"]) == 18
    for case in result["results"]:
        assert case["actual"] == case["expected"], case["name"]
    assert result["malformed"]
    assert result["callbackIdentity"]
    assert result["descriptorSize"] < 1000
    assert result["disposed"]
    assert result["badResults"]
    assert result["providerIdentity"]


def test_vir_external_markup_live_example(page, vir_client_site):
    page.goto(vir_client_site)
    expect(page.locator("#status")).to_have_text("VIR selected markdown · statement")
    expect(page.locator("#preview code")).to_contain_text("For every natural number")
    page.select_option("#language", "tex")
    page.get_by_role("button", name="Preview", exact=True).click()
    expect(page.locator("#status")).to_have_text("VIR selected tex · statement")
    expect(page.locator("#preview code")).to_contain_text("\\mathbb")
    page.select_option("#display", "none")
    page.get_by_role("button", name="Preview", exact=True).click()
    expect(page.locator("#status")).to_have_text("external-markup-renderer-missing")
    expect(page.locator("#preview")).to_be_empty()
    page.select_option("#display", "callback")
    page.get_by_role("button", name="Preview", exact=True).click()
    expect(page.locator("#preview h2")).to_have_text("tex · statement")
    page.select_option("#language", "missing")
    page.get_by_role("button", name="Preview", exact=True).click()
    expect(page.locator("#status")).to_have_text("external-markup-missing")
    # Loading another manifest must use the same retained program and host path.
    manifest = {"previews": [{
        "key": "externalMarkup:uploaded", "authoredLabel": "uploaded",
        "title": "Uploaded Blueprint", "facet": "statement",
        "externalMarkup": [{"language": "markdown", "slot": "proof", "raw": "<b>Source, not HTML</b>"}],
    }]}
    page.select_option("#language", "markdown")
    page.select_option("#display", "source")
    page.set_input_files("#manifest", {
        "name": "blueprint-manifest.json", "mimeType": "application/json",
        "buffer": json.dumps(manifest).encode(),
    })
    expect(page.locator("#status")).to_have_text("VIR selected markdown · proof")
    expect(page.locator("#preview code")).to_have_text("<b>Source, not HTML</b>")
    expect(page.locator("#preview b")).to_have_count(0)
    page.evaluate("window.dispatchEvent(new PageTransitionEvent('pagehide', {persisted: true}))")
    page.get_by_role("button", name="Preview", exact=True).click()
    expect(page.locator("#status")).to_have_text("VIR selected markdown · proof")


def test_vir_external_markup_name_navigation(page, vir_client_site):
    page.goto(vir_client_site)
    expect(page.locator("#status")).to_have_text("VIR selected markdown · statement")
    expect(page.locator("#node")).to_have_attribute("size", "8")
    expect(page.locator("#node option")).to_have_count(3)
    expect(page.locator("#node option").nth(0)).to_contain_text("external_markup_example [statement]")
    expect(page.locator("#node option").nth(1)).to_contain_text("external_markup_example [proof]")
    expect(page.locator("#node option").nth(2)).to_contain_text("native_only_example [statement]")
    expect(page.locator("#node-count")).to_have_text("3 of 3 entries")
    expect(page.locator("#node-info")).to_contain_text("markdown / proof")
    expect(page.locator("#slots option")).to_have_count(2)

    page.select_option("#node", "1")
    expect(page.locator("#status")).to_have_text("VIR selected markdown · proof")
    expect(page.locator("#preview code")).to_contain_text("By the defining equation")
    page.get_by_label("Filter names", exact=True).fill("EXTERNAL_MARKUP")
    expect(page.locator("#node-count")).to_have_text("2 of 3 entries")
    # Filtering that retains the selected entry must preserve the selection.
    expect(page.locator("#node")).to_have_value("1")
    page.get_by_label("Filter names", exact=True).fill("native_only")
    expect(page.locator("#node-count")).to_have_text("1 of 3 entries")
    expect(page.locator("#node")).to_have_value("2")
    expect(page.locator("#status")).to_contain_text("No external markup attached to native_only_example")
    expect(page.locator("#preview")).to_be_empty()
    page.get_by_label("Filter names", exact=True).fill("not-a-name")
    expect(page.locator("#status")).to_have_text("No matching names")
    expect(page.get_by_role("button", name="Preview", exact=True)).to_be_disabled()
    expect(page.locator("#node-info")).to_be_empty()
    page.get_by_label("Filter names", exact=True).fill("")
    expect(page.locator("#status")).to_have_text("VIR selected markdown · statement")
    expect(page.get_by_role("button", name="Preview", exact=True)).to_be_enabled()

    # Bad uploads do not replace the last usable manifest or poison the runtime.
    page.set_input_files("#manifest", {
        "name": "bad.json", "mimeType": "application/json", "buffer": b'{"other":[]}',
    })
    expect(page.locator("#status")).to_have_text("Expected a Blueprint manifest previews array")
    expect(page.locator("#node option")).to_have_count(3)
    expect(page.locator("#preview")).to_be_empty()
    page.get_by_role("button", name="Preview", exact=True).click()
    expect(page.locator("#status")).to_have_text("VIR selected markdown · statement")
    page.set_viewport_size({"width": 390, "height": 844})
    assert page.evaluate("document.documentElement.scrollWidth <= window.innerWidth")


def test_vir_external_markup_generated_manifest(page, vir_client_site, external_markup_manifest):
    manifest = json.loads(external_markup_manifest.read_text())
    entries = manifest["previews"]
    selected = next(entry for entry in entries if any(
        markup["language"] == "markdown" for markup in entry["externalMarkup"]
    ))
    page.goto(vir_client_site)
    expect(page.locator("#status")).to_have_text("VIR selected markdown · statement")
    page.set_input_files("#manifest", str(external_markup_manifest))
    expect(page.locator("#node option")).to_have_count(len(entries))
    page.get_by_label("Filter names", exact=True).fill(selected["authoredLabel"])
    page.select_option("#node", str(entries.index(selected)))
    page.get_by_role("button", name="Preview", exact=True).click()
    expect(page.locator("#status")).to_contain_text("VIR selected markdown")
    expected_source = next(markup["raw"] for markup in selected["externalMarkup"]
                           if markup["language"] == "markdown" and markup["raw"])
    expect(page.locator("#preview code")).to_have_text(expected_source)
    expect(page.locator("#node-info")).to_contain_text(selected["key"])
