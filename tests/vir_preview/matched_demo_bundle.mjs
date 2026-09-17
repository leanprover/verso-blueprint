import assert from "node:assert/strict";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { createHash } from "node:crypto";

const sha = bytes => createHash("sha256").update(bytes).digest("hex");
const quote = JSON.stringify;
export async function prepareMatchedDemo(root, backend) {
  assert.ok(["vir", "fir"].includes(backend));
  const common = resolve(root, "tests/vir_preview/matched_document_component.mjs");
  const vir = resolve(root, ".lake/packages/lean_vir/web/src");
  const sdk = resolve(root, ".lake/build/vir/sdk");
  const prefix = `import { createMatchedDocumentComponent } from ${quote(common)};\n`;
  if (backend === "vir") {
    const direct = process.env.VBP_DEMO_DIRECT_TYPED === "1";
    const timedChecked = process.env.VBP_DEMO_TIMED_CHECKED === "1";
    assert.ok(!(direct && timedChecked), "choose direct or timed checked decoding");
    const currentView = direct || timedChecked;
    assert.ok(process.env.VBP_MATCHED_IR_SET, "set VBP_MATCHED_IR_SET to the selected codec package-set descriptor");
    const descriptorPath = resolve(process.env.VBP_MATCHED_IR_SET);
    const descriptorBytes = await readFile(descriptorPath);
    const descriptor = JSON.parse(descriptorBytes);
    assert.equal(descriptor.format, "lean-vir-ir-package-set");
    assert.equal(descriptor.version, 2);
    assert.equal(descriptor.packages.at(-1).role, "root");
    if (!currentView) assert.equal(descriptor.packages.at(-1).sha256,
      "81d366e20fb716f511f45623e018636f5e67e0bd49fce76f6b58e061106afa68",
      "matched demo requires the frozen paired DecodeProbe");
    const members = [];
    for (const part of descriptor.packages) {
      const bytes = await readFile(resolve(dirname(descriptorPath), part.path));
      assert.equal(bytes.length, part.byteLength);
      assert.equal(sha(bytes), part.sha256, part.module);
      members.push(bytes.toString("base64"));
    }
    const wasm = await readFile(resolve(sdk, "wasm/vir-upstream.wasm"));
    const sdkManifest = JSON.parse(await readFile(resolve(sdk, "lean-vir-artifact.json"), "utf8"));
    assert.equal(sha(wasm), sdkManifest.files.find(f => f.path === "wasm/vir-upstream.wasm").sha256);
    const layoutsBytes = direct ? await readFile(resolve(root, ".deps/direct-codec/layouts.json")) : null;
    if (currentView) assert.equal(descriptor.packages.at(-1).module,
      "VersoBlueprintVirTests.NativeSession.DirectCodecProbe");
    return { identity: { backend, descriptorSha256: sha(descriptorBytes), wasmSha256: sha(wasm),
      codec: direct ? "experimental-direct-typed" : "checked",
      timedView: currentView,
      layoutsSha256: layoutsBytes ? sha(layoutsBytes) : null,
      members: descriptor.packages.length, commonSha256: sha(await readFile(common)) }, source: prefix + (direct ? `
import { createDirectPreviewDecoder } from ${quote(resolve(root, "tests/vir_preview/direct_typed_decoder.mjs"))};
import { withScopedStringIntern } from ${quote(resolve(root, "tests/vir_preview/scoped_string_intern.mjs"))};
import { withUtf8Scratch } from ${quote(resolve(root, "tests/vir_preview/utf8_scratch.mjs"))};
import { withPointerScratch } from ${quote(resolve(root, "tests/vir_preview/pointer_scratch.mjs"))};
` : "") + `
import { createVirRuntime } from ${quote(resolve(vir, "vir-runtime.js"))};
import { createBrowserHostBindings } from ${quote(resolve(vir, "vir-host-bindings.js"))};
import { createBrowserReactHostBindings } from ${quote(resolve(vir, "vir-react-host-bindings.js"))};
import { createJsonValueHostBindings } from ${quote(resolve(root, "tests/vir_preview/upstream-json-value-bindings.mjs"))};
const bytes = value => Uint8Array.from(atob(value), c => c.charCodeAt(0));
export async function openMatchedDemo() {
  const jsonBindings = createJsonValueHostBindings();
  const runtime = await createVirRuntime({ wasmBytes: bytes(${quote(wasm.toString("base64"))}),
    irPackageSet: ${quote(members)}.map(bytes), defaultHostBindings: () => ({
      ...createBrowserHostBindings({ reactHostBindings: createBrowserReactHostBindings }),
      ...jsonBindings, "previewDemo.now": () => performance.now() }) });
  try {
    const entry = ${quote("VersoBlueprintVirTests.NativeSession." + (currentView ? "DirectCodecProbe" : "DecodeProbe"))};
    const view = runtime.call(entry + ${quote(currentView ? ".createTimedView" : ".createView")});
    ${direct ? `const decode = createDirectPreviewDecoder(runtime, ${layoutsBytes.toString("utf8")}, jsonBindings);` : ""}
    return { Component: createMatchedDocumentComponent(
      ${direct ? `value => withPointerScratch(runtime, () => withUtf8Scratch(runtime,
        () => withScopedStringIntern(runtime, () => decode(value))))` : `value => runtime.call(entry + ".browserParsed", value)`},
      ${currentView ? `(value, timing) => runtime.call(entry + ".renderTimedDecoded", view, value,
        timing.requestedMs, timing.receivedMs, timing.notifiedMs, timing.decodedMs)` : `value => runtime.call(entry + ".renderDecoded", view, value)`}, "vir"), dispose: () => runtime.dispose() };
  } catch (error) { runtime.dispose(); throw error; }
}
` };
  }
  assert.notEqual(process.env.VBP_DEMO_DIRECT_TYPED, "1", "direct typed converter is VIR-only");
  const timedChecked = process.env.VBP_DEMO_TIMED_CHECKED === "1";
  assert.ok(process.env.VBP_MATCHED_FIR_PACKAGE, "set VBP_MATCHED_FIR_PACKAGE to the immutable package");
  const input = resolve(process.env.VBP_MATCHED_FIR_PACKAGE);
  const copied = resolve(root, timedChecked ? ".deps/matched-fir-timed-package" : ".deps/matched-fir-package");
  await mkdir(copied, { recursive: true });
  const sums = await readFile(resolve(input, "SHA256SUMS"), "utf8");
  assert.equal(sha(sums), timedChecked
    ? "1ce76db7a0d7b356e2bd5b90a4ef546cefbf8e0e72f842f19ea927215c0a1a18"
    : "d6d33302cca5bd9aeba5bcbb19866d7f3bbe6f6648ec62c699833fce2a5aa122");
  for (const line of sums.trim().split("\n")) {
    const [, hash, name] = line.match(/^([a-f0-9]{64})  ([\w.-]+)$/) ?? [];
    assert.ok(name);
    const bytes = await readFile(resolve(input, name));
    assert.equal(sha(bytes), hash, name);
    await writeFile(resolve(copied, name), bytes);
  }
  await writeFile(resolve(copied, "SHA256SUMS"), sums);
  const build = JSON.parse(await readFile(resolve(copied, "BUILD.json"), "utf8"));
  if (timedChecked) {
    assert.equal(build.capability, "retained-timed-view/v1");
    assert.equal(build.frozenInputs.identity,
      "6c7b96d8afaed7798c9af86c72315f77a1f88a3ddcde4ea2ac11190044b40a94");
  }
  // A new interpreter checkpoint does not silently retarget the compiled FIR
  // closure: its author-side provider modules must still be byte-identical.
  for (const provider of build.externalProviders.sources) {
    assert.ok(provider.path.startsWith("source/"));
    const local = resolve(root, provider.path.slice("source/".length));
    assert.equal(sha(await readFile(local)), provider.sha256, provider.path);
  }
  const lock = JSON.parse(await readFile(resolve(root, ".lake/packages/lean_vir/package-lock.json"), "utf8"));
  for (const provider of build.externalProviders.react) {
    const installed = lock.packages[`node_modules/${provider.name}`];
    assert.equal(installed.version, provider.version);
    assert.equal(installed.integrity, provider.integrity);
  }
  const wasm = await readFile(resolve(copied, "component.wasm"));
  const json = async name => JSON.parse(await readFile(resolve(copied, name), "utf8"));
  return { identity: { backend, packageChecksumsSha256: sha(sums), wasmSha256: sha(wasm),
    frozenSourceIdentity: build.frozenInputs.identity, timedView: timedChecked, codec: "checked", providerSourcesVerified: true,
    commonSha256: sha(await readFile(common)) }, source: prefix + `
import { createConfiguredCodecSession, CODEC_SESSION_API } from ${quote(resolve(copied, "codec-session-bootstrap.mjs"))};
import * as providers from ${quote(resolve(copied, "providers.mjs"))};
let module;
export async function openMatchedDemo() {
  module ??= WebAssembly.compile(Uint8Array.from(atob(${quote(wasm.toString("base64"))}), c => c.charCodeAt(0)));
  const session = await createConfiguredCodecSession({ apiVersion: CODEC_SESSION_API, module: await module,
    manifest: ${quote(await json("component.wasm.json"))},
    hostBoundary: ${quote(await json("host-boundary.json"))},
    callbackBoundary: ${quote(await json("callback-boundary.json"))},
    entryBoundary: ${quote(await json("entry-boundary.json"))},
    bindings: { ...providers.createJsCollectionHostBindings(), ...providers.createJsValueHostBindings(),
      ...providers.createBrowserEventHostBindings(), ...providers.createBrowserReactHostBindings(),
      ...providers.createJsonValueHostBindings(), "previewDemo.now": () => performance.now() } });
  return { Component: createMatchedDocumentComponent(session.browserParsed,
    ${timedChecked ? `(value, timing) => session.renderTimedDecoded(value, {
      requested: timing.requestedMs, received: timing.receivedMs,
      notified: timing.notifiedMs, decodedAt: timing.decodedMs })` : "session.renderDecoded"}, "fir"),
    dispose: session.dispose };
}
` };
}
