import assert from "node:assert/strict";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = fileURLToPath(new URL("../../", import.meta.url));
const manifest = JSON.parse(await readFile(resolve(root, "lake-manifest.json"), "utf8"));
const standalone = JSON.parse(await readFile(resolve(root,
  "packages/verso-react/lake-manifest.json"), "utf8"));
assert.ok(standalone.packages.every(p => p.name !== "VersoBlueprint"));
for (const name of ["verso", "lean_vir"]) {
  assert.equal(standalone.packages.find(p => p.name === name)?.rev,
    manifest.packages.find(p => p.name === name)?.rev, `mismatched ${name} checkpoints`);
}
assert.equal(await readFile(resolve(root, "packages/verso-react/lean-toolchain"), "utf8"),
  await readFile(resolve(root, "lean-toolchain"), "utf8"));
const vir = manifest.packages.find(p => p.name === "lean_vir");
const virRoot = resolve(root, manifest.packagesDir, "lean_vir");
const sdkRoot = resolve(root, ".lake/build/vir/sdk");
const sdk = JSON.parse(await readFile(resolve(sdkRoot, "lean-vir-artifact.json"), "utf8"));
assert.equal(sdk.gitCommit, vir.rev);
assert.equal(sdk.gitDirty, false);
assert.equal(sdk.leanToolchain, (await readFile(resolve(root, "lean-toolchain"), "utf8")).trim());

async function packages(path, independent = false) {
  const descriptor = JSON.parse(await readFile(path, "utf8"));
  assert.equal(descriptor.version, 2);
  if (independent) assert.ok(!JSON.stringify(descriptor).includes("VersoBlueprint"),
    "standalone renderer package set must not import Blueprint");
  return Promise.all(descriptor.packages.map(member => readFile(resolve(dirname(path), member.path))));
}
const output = resolve(process.env.VBP_RENDERER_REPORT_DIR);
await mkdir(output, { recursive: true });
const bundle = resolve(output, "renderer-acceptance.mjs");
const { build } = await import(pathToFileURL(resolve(virRoot, "node_modules/esbuild/lib/main.js")));
await build({
  entryPoints: [resolve(root, "tests/vir_preview/renderer_package_entry.mjs")],
  bundle: true, platform: "node", format: "esm", outfile: bundle,
  nodePaths: [resolve(virRoot, "node_modules")],
  banner: { js: 'import { createRequire } from "node:module"; const require = createRequire(import.meta.url);' },
  alias: {
    "lean-vir": resolve(sdkRoot, "js/vir-runtime.js"),
    "lean-vir/host-bindings": resolve(sdkRoot, "js/vir-host-bindings.js"),
    "lean-vir/react-host-bindings": resolve(sdkRoot, "js/vir-react-host-bindings.js"),
  },
});
const { run } = await import(pathToFileURL(bundle));
const report = await run({
  wasmBytes: await readFile(resolve(sdkRoot, "wasm/vir-upstream.wasm")),
  genericPackages: await packages(resolve(root,
    "packages/verso-react/.lake/build/vir/module-sets/VersoReactTests.irpkg-set.json"), true),
  blueprintPackages: await packages(resolve(root,
    ".lake/build/vir/module-sets/VersoBlueprintVirTests/Renderer.irpkg-set.json")),
});
await writeFile(resolve(output, "renderer-acceptance.json"), JSON.stringify(report, null, 2) + "\n");
console.log(JSON.stringify(report, null, 2));
