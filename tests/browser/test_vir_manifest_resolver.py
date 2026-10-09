import json
import subprocess
import hashlib
import os
import time

import pytest

from conftest import serve_site
from support import PACKAGE_ROOT
from scripts.blueprint_harness_paths import detect_harness_layout
from test_vir_client import vir_client_site


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


def test_data_api_uses_shared_lean_lookups_and_original_objects(page, vir_client_site, vir_manifest_resolver_site):
    _, campaign = vir_manifest_resolver_site
    page.goto(f"{vir_client_site}/client.json")
    result = page.evaluate("""async campaign => {
        const {createBlueprintDataApi} = await import('./-verso-data/Commands/preview-runtime-data.mjs');
        const shared = await import('./-verso-data/Commands/blueprint-vir-client.mjs');
        const ready = await shared.getBlueprintProgram();
        const originalProgram = ready.program;
        const calls = {prepare: 0, lookup: 0};
        // Acceptance counters only; the timing campaign does not install this wrapper.
        ready.program = {call(entry, ...args) {
            if (entry === ready.entries.manifestPrepare) calls.prepare++;
            if (entry === ready.entries.manifestLookup) calls.lookup++;
            return originalProgram.call(entry, ...args);
        }};
        const actual = [];
        let identity = true;
        try {
            for (const testCase of campaign) {
                if (!testCase.expected.ok) continue;
                const input = JSON.parse(testCase.input);
                const requests = input.requests.filter(request =>
                    request.kind === 'label' || request.kind === 'declaration');
                if (!requests.length) continue;
                const data = createBlueprintDataApi({fetchJson: async () => input.manifest});
                const map = await data.loadManifest();
                const before = calls.prepare;
                const outputs = await Promise.all(requests.map(request => request.kind === 'label'
                    ? data.resolveLabel(request.value, request.facet ? {facet: request.facet} : undefined)
                    : data.resolveDeclaration(request.value)));
                if (requests.some(request => typeof request.value === 'string' && request.value.trim())) {
                    if (calls.prepare !== before + 1) throw Error('Manifest was not prepared exactly once');
                }
                outputs.forEach(output => {
                    if (output.manifestEntry) {
                        const entry = map.get(output.manifestEntry.key.trim());
                        identity &&= output.manifestEntry === entry && output.sourceLocation === entry.sourceLocation;
                    }
                });
                actual.push({id: testCase.id, outputs});
            }
            const manifest = JSON.parse(campaign[0].input).manifest;
            const data = createBlueprintDataApi({fetchJson: async () => manifest});
            await data.resolveLabel('alpha');
            const beforeReset = calls.prepare;
            data.resetStores();
            await Promise.all([data.resolveLabel('alpha'), data.resolveDeclaration('Nat.add')]);
            const resetPreparedOnce = calls.prepare === beforeReset + 1;
            const replacementEntry = {...manifest.previews[0], key: 'beta--statement', label: 'beta',
                parent: null, parentTitle: null};
            const replacement = {previews: [replacementEntry], groups: [], sourceDocuments: []};
            let finishOld;
            const changing = createBlueprintDataApi({fetchJson: () => new Promise(resolve => {finishOld = resolve;})});
            const oldLookup = changing.resolveLabel('alpha');
            changing.setFetchJson(async () => replacement);
            const newLookup = await changing.resolveLabel('beta');
            finishOld(manifest);
            const oldResult = await oldLookup;
            const current = await changing.loadManifest();
            const staleLoadIgnored = newLookup.manifestEntry === replacementEntry && !oldResult.ok &&
                current.size === 1 && current.get('beta--statement') === replacementEntry;
            ready.program = originalProgram;
            shared.disposeBlueprintProgram();
            let disposed = false;
            try { await data.resolveLabel('alpha'); } catch (error) {disposed = /disposed/.test(error.message);}
            return {actual, identity, resetPreparedOnce, staleLoadIgnored, disposed, calls};
        } finally {
            ready.program = originalProgram;
            shared.disposeBlueprintProgram();
        }
    }""", campaign)
    expected = []
    for case in campaign:
        if not case["expected"]["ok"]:
            continue
        outputs = []
        for output in case["expected"]["results"]:
            if output["kind"] not in ("label", "declaration"):
                continue
            fields = ("ok", "reason", "key", "manifestEntry", "href", "sourceLocation")
            if output["kind"] == "label":
                fields += ("label", "facet")
            else:
                fields += ("declaration",)
            outputs.append({field: output[field] for field in fields})
        if outputs:
            expected.append({"id": case["id"], "outputs": outputs})
    assert result["actual"] == expected
    for field in ("identity", "resetPreparedOnce", "staleLoadIgnored", "disposed"):
        assert result[field]


def test_source_metadata_uses_lean_policy_and_original_references(page, vir_client_site, vir_manifest_resolver_site):
    _, campaign = vir_manifest_resolver_site
    page.goto(f"{vir_client_site}/client.json")
    result = page.evaluate("""async campaign => {
        const {createBlueprintDataApi} = await import('./-verso-data/Commands/preview-runtime-data.mjs');
        const shared = await import('./-verso-data/Commands/blueprint-vir-client.mjs');
        const ready = await shared.getBlueprintProgram();
        const originalProgram = ready.program;
        let fullManifestPrepares = 0;
        ready.program = {call(entry, ...args) {
            if (entry === ready.entries.manifestPrepare) fullManifestPrepares++;
            return originalProgram.call(entry, ...args);
        }};
        const actual = [];
        let identity = true, noUnnecessaryFetch = true;
        try {
            for (const testCase of campaign) {
                if (!testCase.expected.ok) continue;
                const input = JSON.parse(testCase.input);
                const requests = input.requests.filter(request => request.kind === 'sourceMetadata');
                if (!requests.length) continue;
                let fetches = 0;
                const data = createBlueprintDataApi({fetchJson: async () => {fetches++; return input.manifest;}});
                const outputs = [];
                for (const request of requests) {
                    const expected = testCase.expected.results.find(result => result.requestId === request.id);
                    const before = fetches;
                    const output = await data.resolveSourceMetadata(request.value);
                    const entry = expected.inputEntryIsNested === true ? request.value.manifestEntry :
                        expected.inputEntryIsNested === false ? request.value :
                        input.manifest.previews.find(entry => entry.key.trim() === output.key) || null;
                    identity &&= output.manifestEntry === entry;
                    output.sources.forEach((resolved, index) => {
                        const ref = entry.sources[index];
                        if (ref && typeof ref === 'object') identity &&= resolved.sourceRef === ref;
                        if (Array.isArray(ref?.spans)) identity &&= resolved.spans === ref.spans;
                        const document = (input.manifest.sourceDocuments || []).find(document =>
                            document.id.trim() === resolved.documentId) || null;
                        identity &&= resolved.document === document;
                    });
                    // Missing inputs and direct inputs without document IDs do not fetch the manifest.
                    if (output.reason === 'missing-key' || (expected.inputEntryIsNested !== null &&
                        output.sources.every(ref => !ref.documentId))) {
                        noUnnecessaryFetch &&= fetches === before;
                    }
                    outputs.push(output);
                }
                actual.push({id: testCase.id, outputs});
            }
            const manifest = JSON.parse(campaign[0].input).manifest;
            const direct = {key: 'detached', sources: [{document: 'paper', spans: []},
                {document: ' paper ', spans: []}]};
            let attempts = 0;
            const retrying = createBlueprintDataApi({fetchJson: async () => {
                if (++attempts === 1) throw Error('offline source fixture');
                return manifest;
            }});
            const failed = await retrying.resolveSourceMetadata(direct);
            const recovered = await retrying.resolveSourceMetadata(direct);
            const retryWorks = failed.ok && failed.sources.every(ref => ref.document === null) &&
                recovered.sources.every(ref => ref.document === manifest.sourceDocuments[0]) && attempts === 2;
            const cache = createBlueprintDataApi({fetchJson: async () => manifest});
            await cache.loadManifest();
            ready.program = originalProgram;
            shared.disposeBlueprintProgram();
            let disposed = false;
            try { await cache.resolveSourceMetadata(direct); } catch (error) {disposed = /disposed/.test(error.message);}
            return {actual, identity, noUnnecessaryFetch, fullManifestPrepares, retryWorks, disposed};
        } finally {
            ready.program = originalProgram;
            shared.disposeBlueprintProgram();
        }
    }""", campaign)
    expected = []
    for case in campaign:
        if not case["expected"]["ok"]:
            continue
        outputs = [
            {key: output[key] for key in ("ok", "key", "reason", "manifestEntry", "sources")}
            for output in case["expected"]["results"] if output["kind"] == "sourceMetadata"
        ]
        if outputs:
            expected.append({"id": case["id"], "outputs": outputs})
    assert result["actual"] == expected
    for field in ("identity", "noUnnecessaryFetch", "retryWorks", "disposed"):
        assert result[field]
    assert result["fullManifestPrepares"] == 0


@pytest.mark.skipif(not os.environ.get("VBP_RESOLVER_BENCH_INPUT"), reason="opt-in full manifest measurement")
def test_data_api_full_manifest_costs(page, browser, vir_client_site):
    input_path = os.environ["VBP_RESOLVER_BENCH_INPUT"]
    with open(input_path, "rb") as source:
        raw = source.read()
    manifest = json.loads(raw)
    blocks = [entry for entry in manifest["previews"] if entry.get("targetKind") == "block"]
    label = blocks[len(blocks) // 2]["label"]
    missing = "__manifest_measurement_missing__"
    assert all(entry.get("label") != missing for entry in blocks)
    requests = [{"id": "present", "kind": "label", "value": label},
                {"id": "missing", "kind": "label", "value": missing}]
    native = subprocess.run(
        [str(PACKAGE_ROOT / "scripts/lean-low-priority"), str(PACKAGE_ROOT / ".lake/build/bin/manifest-resolver-oracle")],
        cwd=PACKAGE_ROOT, input=json.dumps({"abiVersion": 1, "manifest": manifest, "requests": requests}) + "\n",
        capture_output=True, text=True, check=True, timeout=60,
    )
    native_output = json.loads(native.stdout)
    assert native_output["ok"], native_output["error"]
    fields = ("ok", "reason", "key", "label", "facet", "manifestEntry", "href", "sourceLocation")
    expected = [{key: result[key] for key in fields} for result in native_output["results"]]
    page.goto(f"{vir_client_site}/client.json")
    setup = page.evaluate("""async ({manifest, requests, expected}) => {
        const {createBlueprintDataApi} = await import('./-verso-data/Commands/preview-runtime-data.mjs');
        const {getBlueprintProgram} = await import('./-verso-data/Commands/blueprint-vir-client.mjs');
        const data = createBlueprintDataApi({fetchJson: async () => manifest});
        const normalize = value => Array.isArray(value) ? value.map(normalize) :
            value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map(key =>
                [key, normalize(value[key])])) : value;
        const check = outputs => {
            if (JSON.stringify(normalize(outputs)) !== JSON.stringify(normalize(expected))) {
                throw Error('Full native/public-API parity failed');
            }
            if (outputs[0].manifestEntry !== map.get(outputs[0].key.trim())) throw Error('Entry identity lost');
        };
        const mapStart = performance.now();
        const map = await data.loadManifest();
        const hostValidationMs = performance.now() - mapStart;
        const openStart = performance.now();
        const ready = await getBlueprintProgram();
        const runtimeOpenMs = performance.now() - openStart;
        const firstStart = performance.now();
        const first = await data.resolveLabel(requests[0].value);
        const prepareAndFirstLookupMs = performance.now() - firstStart;
        check([first, await data.resolveLabel(requests[1].value)]);
        const pair = async () => Promise.all(requests.map(request => data.resolveLabel(request.value)));
        for (let i = 0; i < 3; i++) check(await pair());
        window.resolverMeasurement = {pair, check};
        return {hostValidationMs, runtimeOpenMs, prepareAndFirstLookupMs,
            entries: manifest.previews.length, programEntries: ready.entries};
    }""", {"manifest": manifest, "requests": requests, "expected": expected})
    runs = []
    for block in range(6):
        row = page.evaluate("""async () => {
            const {pair, check} = window.resolverMeasurement;
            let output;
            const start = performance.now();
            for (let i = 0; i < 10; i++) output = await pair();
            const elapsedMs = performance.now() - start;
            check(output); // Validation is outside the measured interval.
            return {iterations: 10, elapsedMs, perPairMs: elapsedMs / 10};
        }""")
        runs.append({"block": block, **row})
    # Separate attribution capture, excluded from headline observations.
    cdp = page.context.new_cdp_session(page)
    cdp.send("Profiler.enable")
    cdp.send("Profiler.setSamplingInterval", {"interval": 1000})
    cdp.send("Profiler.start")
    page.evaluate("""async () => {
        for (let i = 0; i < 20; i++) {
            const result = await window.resolverMeasurement.pair();
            window.resolverMeasurement.check(result);
        }
    }""")
    profile = cdp.send("Profiler.stop")["profile"]
    cdp.detach()
    ordered = sorted(run["perPairMs"] for run in runs)
    median = (ordered[2] + ordered[3]) / 2
    bundle = detect_harness_layout(PACKAGE_ROOT).artifact_root / "manifest-data-api-perf" / str(time.time_ns())
    bundle.mkdir(parents=True)
    (bundle / "input-manifest.json").write_bytes(raw)
    (bundle / "warm.cpuprofile").write_text(json.dumps(profile))
    relative_sources = ["src/VersoBlueprint/Commands/preview-runtime-data.mjs",
                        "src/VersoBlueprint/Commands/manifest-resolver.mjs",
                        "src/VersoBlueprintVir/Program.lean",
                        "src/VersoBlueprintRuntime/ManifestResolver.lean",
                        "tests/browser/test_vir_manifest_resolver.py"]
    metadata = {
        "inputPath": input_path, "inputBytes": len(raw), "inputSha256": hashlib.sha256(raw).hexdigest(),
        "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=PACKAGE_ROOT, text=True).strip(),
        "trackedDiffSha256": hashlib.sha256(subprocess.check_output(["git", "diff", "HEAD"], cwd=PACKAGE_ROOT)).hexdigest(),
        "sources": {path: hashlib.sha256((PACKAGE_ROOT / path).read_bytes()).hexdigest() for path in relative_sources},
        "browser": browser.version, "toolchain": (PACKAGE_ROOT / "lean-toolchain").read_text().strip(),
        "setup": setup, "runs": runs, "medianWarmPairMs": median,
        "boundary": "two public resolveLabel calls, retained manifest/runtime, original complete entry result",
        "exclusions": "input JSON parsing, asset/module import, RPC/LSP, build, DOM/paint; runtime open is separate",
        "repeats": "3 warmup pairs; 6 blocks of 10 pairs; no candidate speedup comparison",
        "profile": "separate Chromium main-thread capture at requested 1000 us interval; unresolved Wasm symbols",
    }
    config = detect_harness_layout(PACKAGE_ROOT).artifact_root / "vir-client-example" / "-verso-data" / "Commands" / "blueprint-vir.mjs"
    metadata["programConfig"] = config.read_text()
    metadata["programConfigSha256"] = hashlib.sha256(config.read_bytes()).hexdigest()
    (bundle / "result.json").write_text(json.dumps(metadata, indent=2))
    print(f"manifest public API: setup={setup}; warm pair median={median:.3f} ms; evidence={bundle}")
