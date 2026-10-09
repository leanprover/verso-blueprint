import json
import subprocess

import pytest

from conftest import serve_site
from support import PACKAGE_ROOT
from scripts.blueprint_harness_paths import detect_harness_layout


@pytest.fixture(scope="session")
def vir_manifest_resolver_site():
    output = detect_harness_layout(PACKAGE_ROOT).artifact_root / "manifest-resolver-client"
    wrapper = str(PACKAGE_ROOT / "scripts/lean-low-priority")
    subprocess.run(
        [wrapper, "lake", "build", "manifest-resolver-oracle", "manifest-resolver-client"],
        cwd=PACKAGE_ROOT, check=True,
    )
    subprocess.run(
        [wrapper, "lake", "exe", "manifest-resolver-client", str(output)],
        cwd=PACKAGE_ROOT, check=True,
    )
    native = subprocess.run(
        ["node", "tests/runtime_manifest_resolver_conformance.mjs",
         ".lake/build/bin/manifest-resolver-oracle", "--emit-campaign"],
        cwd=PACKAGE_ROOT, check=True, capture_output=True, text=True,
    )
    with serve_site(output) as url:
        yield url, json.loads(native.stdout)


def test_vir_manifest_resolver_matches_native_and_recovers(page, vir_manifest_resolver_site):
    url, campaign = vir_manifest_resolver_site
    page.goto(f"{url}/client.json")
    result = page.evaluate("""async campaign => {
        const client = await (await fetch(location.href)).json();
        const {createProgram} = await import(new URL(client.runtimeModule, location.href));
        const program = await createProgram({
            runtimeManifestUrl: new URL(client.runtimeManifest, location.href),
            programManifestUrl: new URL(client.programManifest, location.href),
        });
        const rejects = f => { try { f(); return false; } catch { return true; } };
        const result = {};
        try {
            result.actual = campaign.map(({input}) => JSON.parse(program.call(client.entry, input)));
            result.badArgument = rejects(() => program.call(client.entry, 17));
            result.missingExport = rejects(() => program.call('Missing.export', campaign[0].input));
            result.recovered = JSON.parse(program.call(client.entry, campaign[0].input));
        } finally {
            program.dispose();
        }
        result.disposed = rejects(() => program.call(client.entry, campaign[0].input));
        return result;
    }""", campaign)
    assert result["actual"] == [case["expected"] for case in campaign]
    assert result["badArgument"] and result["missingExport"] and result["disposed"]
    assert result["recovered"] == campaign[0]["expected"]


def test_vir_manifest_resolver_retains_index_and_checks_ownership(page, vir_manifest_resolver_site):
    url, campaign = vir_manifest_resolver_site
    page.goto(f"{url}/client.json")
    result = page.evaluate("""async campaign => {
        const client = await (await fetch(location.href)).json();
        const {createProgram} = await import(new URL(client.runtimeModule, location.href));
        const options = {
            runtimeManifestUrl: new URL(client.runtimeManifest, location.href),
            programManifestUrl: new URL(client.programManifest, location.href),
        };
        const program = await createProgram(options);
        let other = null, held;
        const rejects = f => { try { f(); return false; } catch { return true; } };
        const request = input => {
            const {abiVersion, requests} = JSON.parse(input);
            return JSON.stringify({abiVersion, requests});
        };
        const lookup = (value, text) => JSON.parse(program.call(client.lookupEntry, value, text));
        const baselineRequests = request(campaign[0].input);
        const result = {actual: [], prepareFailures: []};
        try {
            held = program.call(client.prepareEntry, campaign[0].input);
            for (const testCase of campaign) {
                if (!testCase.expected.ok) {
                    result.prepareFailures.push(rejects(() => program.call(client.prepareEntry, testCase.input)));
                } else {
                    const value = program.call(client.prepareEntry, testCase.input);
                    result.actual.push({id: testCase.id, output: lookup(value, request(testCase.input))});
                }
            }
            result.malformedRequest = lookup(held, 'not json');
            result.wrongVersion = lookup(held, JSON.stringify({abiVersion: 2, requests: []}));
            result.invalidHandle = rejects(() => lookup({}, baselineRequests));
            result.copiedHandle = rejects(() => lookup({...held}, baselineRequests));
            result.badArgument = rejects(() => program.call(client.lookupEntry, held, 17));
            result.recovered = lookup(held, baselineRequests);
            other = await createProgram(options);
            const foreign = other.call(client.prepareEntry, campaign[0].input);
            result.crossRuntime = rejects(() => lookup(foreign, baselineRequests));
        } finally {
            other?.dispose();
            program.dispose();
        }
        result.disposed = rejects(() => program.call(client.lookupEntry, held, baselineRequests));
        const replacement = await createProgram(options);
        try {
            result.staleHandle = rejects(() => replacement.call(client.lookupEntry, held, baselineRequests));
            const fresh = replacement.call(client.prepareEntry, campaign[0].input);
            result.replacement = JSON.parse(replacement.call(client.lookupEntry, fresh, baselineRequests));
        } finally {
            replacement.dispose();
        }
        return result;
    }""", campaign)
    assert result["actual"] == [
        {"id": case["id"], "output": case["expected"]}
        for case in campaign if case["expected"]["ok"]
    ]
    assert len(result["prepareFailures"]) == sum(not case["expected"]["ok"] for case in campaign)
    assert all(result["prepareFailures"])
    assert result["recovered"] == result["replacement"] == campaign[0]["expected"]
    for field in ("malformedRequest", "wrongVersion"):
        assert not result[field]["ok"]
        assert result[field]["error"]
        assert result[field]["results"] == []
    for field in ("invalidHandle", "copiedHandle", "badArgument", "crossRuntime", "disposed", "staleHandle"):
        assert result[field]
