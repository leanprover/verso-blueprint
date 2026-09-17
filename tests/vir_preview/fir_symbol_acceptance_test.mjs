// Integration guardrails for offline symbols, using explicitly synthetic names.
// Usage: node --test fir_symbol_acceptance_test.mjs (VBP_FIR_PROFILE_CAPTURE required).
import test from "node:test";
import assert from "node:assert/strict";
import { readFile, writeFile, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const capture = process.env.VBP_FIR_PROFILE_CAPTURE;
const script = fileURLToPath(new URL("./summarize_replay_profile.mjs", import.meta.url));
function uleb(value) {
  const bytes = [];
  do { const byte = value & 127; value = Math.floor(value / 128); bytes.push(byte | (value ? 128 : 0)); } while (value);
  return Buffer.from(bytes);
}
function string(value) { const bytes = Buffer.from(value); return Buffer.concat([uleb(bytes.length), bytes]); }

test("exact executable match accepts synthetic names; wrong module and empty names reject", {
  skip: !capture && "set VBP_FIR_PROFILE_CAPTURE to a retained FIR CPU capture",
}, async () => {
  const temporary = await mkdtemp(resolve(tmpdir(), "vbp-fir-symbol-test-"));
  try {
    const raw = await readFile(resolve(capture, "fir/component.wasm"));
    const profile = JSON.parse(await readFile(resolve(capture, "browser.cpuprofile")));
    const first = profile.nodes.find(node => /^wasm-function\[\d+\]$/.test(node.callFrame.functionName));
    const index = Number(/\[(\d+)\]/.exec(first.callFrame.functionName)[1]);
    const names = Buffer.concat([uleb(1), uleb(index), string("TEST_ONLY_SYNTHETIC_SYMBOL")]);
    const payload = Buffer.concat([string("name"), Buffer.from([1]), uleb(names.length), names]);
    const named = resolve(temporary, "synthetic.wasm");
    await writeFile(named, Buffer.concat([raw, Buffer.from([0]), uleb(payload.length), payload]));
    const invoke = (file, output) => spawnSync(process.execPath,
      [script, capture, `--out=${output}`, `--fir-named-wasm=${file}`],
      { encoding: "utf8", maxBuffer: 16 * 1024 * 1024, timeout: 30_000 });
    const output = resolve(temporary, "accepted");
    const accepted = invoke(named, output);
    assert.equal(accepted.status, 0, accepted.stderr);
    const evidence = JSON.parse(await readFile(resolve(output, "wasm-symbols.json")));
    assert.equal(evidence.names[index], "TEST_ONLY_SYNTHETIC_SYMBOL");
    assert.ok(evidence.resolvedFrames > 0);
    assert.ok(evidence.unresolvedFrames > 0, "partial names must not hide unresolved frames");
    const identity = JSON.parse(await readFile(resolve(capture, "identity.json")));
    const foreign = resolve(identity.root, ".lake/build/vir/sdk/wasm/vir-upstream.dev.wasm");
    const mismatch = invoke(foreign, resolve(temporary, "mismatch"));
    assert.notEqual(mismatch.status, 0);
    assert.match(mismatch.stderr, /does not match all captured non-custom sections/);
    const stripped = invoke(resolve(capture, "fir/component.wasm"), resolve(temporary, "stripped"));
    assert.notEqual(stripped.status, 0);
    assert.match(stripped.stderr, /missing FIR function names/);
    const overwrite = invoke(named, output);
    assert.notEqual(overwrite.status, 0);
    assert.match(overwrite.stderr, /EEXIST/);
  } finally { await rm(temporary, { recursive: true, force: true }); }
});
