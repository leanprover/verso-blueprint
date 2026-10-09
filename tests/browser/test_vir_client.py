import subprocess

import pytest

from conftest import serve_site
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
