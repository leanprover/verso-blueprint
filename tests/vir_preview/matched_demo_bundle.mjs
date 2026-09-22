import assert from "node:assert/strict";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { createHash } from "node:crypto";

const sha = bytes => createHash("sha256").update(bytes).digest("hex");
const quote = JSON.stringify;
const MATCHED_CODEC = "direct-typed/v1";
export async function prepareMatchedDemo(root, backend) {
  assert.ok(["vir", "fir"].includes(backend));
  const common = resolve(root, "tests/vir_preview/matched_document_component.mjs");
  const math = resolve(root, "tests/vir_preview/matched_math_component.mjs");
  const vir = resolve(root, ".lake/packages/lean_vir/web/src");
  const sdk = resolve(root, ".lake/build/vir/sdk");
  const prefix = `import { createMatchedDocumentComponent } from ${quote(common)};
import { PreviewMath } from ${quote(math)};\n`;
  if (backend === "vir") {
    assert.ok(process.env.VBP_MATCHED_IR_SET, "set VBP_MATCHED_IR_SET to the direct codec package-set descriptor");
    const descriptorPath = resolve(process.env.VBP_MATCHED_IR_SET);
    const descriptorBytes = await readFile(descriptorPath);
    const descriptor = JSON.parse(descriptorBytes);
    assert.equal(descriptor.format, "lean-vir-ir-package-set");
    assert.equal(descriptor.version, 2);
    assert.equal(descriptor.packages.at(-1).role, "root");
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
    const layoutsBytes = await readFile(resolve(root, ".deps/direct-codec/layouts.json"));
    assert.equal(descriptor.packages.at(-1).module,
      "VersoBlueprintVirTests.NativeSession.DirectCodecProbe");
    return { identity: { backend, descriptorSha256: sha(descriptorBytes), wasmSha256: sha(wasm),
      codec: MATCHED_CODEC, timedView: true, layoutsSha256: sha(layoutsBytes),
      members: descriptor.packages.length, commonSha256: sha(await readFile(common)),
      mathSha256: sha(await readFile(math)) }, source: prefix + `
import { createDirectPreviewDecoder } from ${quote(resolve(root, "tests/vir_preview/direct_typed_decoder.mjs"))};
import { withScopedStringIntern } from ${quote(resolve(root, "tests/vir_preview/scoped_string_intern.mjs"))};
import { withUtf8Scratch } from ${quote(resolve(root, "tests/vir_preview/utf8_scratch.mjs"))};
import { withPointerScratch } from ${quote(resolve(root, "tests/vir_preview/pointer_scratch.mjs"))};
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
      ...jsonBindings, "previewDemo.now": () => performance.now(),
      "previewDemo.mathComponent": () => PreviewMath }) });
  try {
    const entry = ${quote("VersoBlueprintVirTests.NativeSession.DirectCodecProbe")};
    const view = runtime.call(entry + ".createTimedView");
    const decode = createDirectPreviewDecoder(runtime, ${layoutsBytes.toString("utf8")}, jsonBindings);
    return { Component: createMatchedDocumentComponent(
      value => withPointerScratch(runtime, () => withUtf8Scratch(runtime,
        () => withScopedStringIntern(runtime, () => decode(value)))),
      (value, timing) => runtime.call(entry + ".renderTimedDecoded", view, value,
        timing.requestedMs, timing.receivedMs, timing.notifiedMs, timing.decodedMs), "vir"), dispose: () => runtime.dispose() };
  } catch (error) { runtime.dispose(); throw error; }
}
` };
  }
  assert.ok(process.env.VBP_MATCHED_FIR_PACKAGE, "set VBP_MATCHED_FIR_PACKAGE to the direct construction package");
  const input = resolve(process.env.VBP_MATCHED_FIR_PACKAGE);
  const copied = resolve(root, ".deps/matched-fir-direct-package");
  await mkdir(copied, { recursive: true });
  const sums = await readFile(resolve(input, "SHA256SUMS"), "utf8");
  assert.equal(sha(sums), "dfa13acc5d0f3ea7a8fc7cfb8e0ed8c3b02862f9be8cc4e49d17606ece166615");
  for (const line of sums.trim().split("\n")) {
    const [, hash, name] = line.match(/^([a-f0-9]{64})  ([\w.-]+)$/) ?? [];
    assert.ok(name);
    const bytes = await readFile(resolve(input, name));
    assert.equal(sha(bytes), hash, name);
    await writeFile(resolve(copied, name), bytes);
  }
  await writeFile(resolve(copied, "SHA256SUMS"), sums);
  const build = JSON.parse(await readFile(resolve(copied, "BUILD.json"), "utf8"));
  assert.equal(build.schemaVersion, "fir.vbp-direct-construction-package/v1");
  assert.equal(build.apiVersion, "fir.vbp.direct-construction-session/v1");
  assert.equal(build.noRawAddresses, true);
  assert.equal(build.frozenInputs.identity,
    "fbaa6efc8f44df0d94f902fd5b6aa43086231438ea8277efc0595a6e9b84c709");
  assert.equal(build.imports.filter(({ name }) => name.endsWith(".mathComponent")).length, 1,
    "matched FIR package must use the shared math component");
  // A new interpreter checkpoint does not silently retarget the compiled FIR
  // closure: its author-side provider modules must still be byte-identical.
  for (const provider of build.externalProviders?.sources ?? []) {
    assert.ok(provider.path.startsWith("source/"));
    const local = resolve(root, provider.path.slice("source/".length));
    assert.equal(sha(await readFile(local)), provider.sha256, provider.path);
  }
  const lock = JSON.parse(await readFile(resolve(root, ".lake/packages/lean_vir/package-lock.json"), "utf8"));
  for (const provider of build.externalProviders?.react ?? []) {
    const installed = lock.packages[`node_modules/${provider.name}`];
    assert.equal(installed.version, provider.version);
    assert.equal(installed.integrity, provider.integrity);
  }
  const wasm = await readFile(resolve(copied, "component.wasm"));
  const json = async name => JSON.parse(await readFile(resolve(copied, name), "utf8"));
  return { identity: { backend, packageChecksumsSha256: sha(sums), wasmSha256: sha(wasm),
    frozenSourceIdentity: build.frozenInputs.identity, timedView: true, codec: MATCHED_CODEC,
    providerSourcesVerified: false,
    commonSha256: sha(await readFile(common)), mathSha256: sha(await readFile(math)) }, source: prefix + `
import { createDirectConstructionSession as createSession, DIRECT_CONSTRUCTION_API as SESSION_API } from ${quote(resolve(copied,
      "direct-construction-session.mjs"))};
import * as providers from ${quote(resolve(copied, "providers.mjs"))};
let module;
export async function openMatchedDemo() {
  module ??= WebAssembly.compile(Uint8Array.from(atob(${quote(wasm.toString("base64"))}), c => c.charCodeAt(0)));
  const session = await createSession({ apiVersion: SESSION_API, module: await module,
    manifest: ${quote(await json("component.wasm.json"))},
    hostBoundary: ${quote(await json("host-boundary.json"))},
    callbackBoundary: ${quote(await json("callback-boundary.json"))},
    entryBoundary: ${quote(await json("entry-boundary.json"))},
    constructorLayouts: ${quote(await json("constructor-layouts.json"))},
    bindings: { ...providers.createJsCollectionHostBindings(), ...providers.createJsValueHostBindings(),
      ...providers.createBrowserEventHostBindings(), ...providers.createBrowserReactHostBindings(),
      ...providers.createJsonValueHostBindings(), "previewDemo.now": () => performance.now(),
      "previewDemo.mathComponent": () => PreviewMath } });
  return { Component: createMatchedDocumentComponent(session.directParsed,
    (value, timing) => session.renderTimedDecoded(value, {
      requested: timing.requestedMs, received: timing.receivedMs,
      notified: timing.notifiedMs, decodedAt: timing.decodedMs }), "fir"),
    dispose: session.dispose };
}
` };
}
