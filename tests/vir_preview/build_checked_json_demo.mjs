/* Temporary demo bundle: upstream shell/lifecycle, benchmark JSON bindings.
 * Delete this seam once the pinned VIR ships the checked JSON codec. */
import assert from "node:assert/strict";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { prepareFirDemo } from "./fir_demo_bundle.mjs";
import { configureDemoShell, configureNativeComponentShell } from "./demo_shell.mjs";
import { prepareMatchedDemo } from "./matched_demo_bundle.mjs";

const root = fileURLToPath(new URL("../../", import.meta.url));
const vir = resolve(root, ".lake/packages/lean_vir");
const sdkRoot = resolve(root, ".lake/build/vir/sdk");
const read = path => readFile(path, "utf8");
const sha = value => createHash("sha256").update(value).digest("hex");
const sdk = JSON.parse(await read(resolve(sdkRoot, "lean-vir-artifact.json")));
const firPackage = process.env.VBP_DEMO_FIR_PACKAGE;
const matchedBackend = process.env.VBP_DEMO_MATCHED_BACKEND;
assert.ok(!firPackage || !matchedBackend, "choose the old FIR demo or a matched backend");
const matchedDemo = matchedBackend ? await prepareMatchedDemo(root, matchedBackend) : null;
const manifest = JSON.parse(await read(resolve(root, "lake-manifest.json")));
assert.equal(sdk.gitCommit, manifest.packages.find(p => p.name === "lean_vir").rev);
assert.equal(sdk.gitCommit, execFileSync("git", ["rev-parse", "HEAD"], { cwd: vir, encoding: "utf8" }).trim());
execFileSync("git", ["diff", "--quiet", "HEAD", "--", "web", "scripts/build-infoview-widget.mjs"], { cwd: vir });
assert.equal(sdk.leanToolchain, (await read(resolve(root, "lean-toolchain"))).trim());
assert.equal(sdk.gitDirty, false);
const { build } = await import(pathToFileURL(resolve(vir, "node_modules/esbuild/lib/main.js")));
const shell = resolve(vir, "web/app/vir-infoview-widget.js");
const objects = resolve(vir, "web/src/runtime/object-values.js");
const bridge = resolve(root, "tests/vir_preview/upstream-json-value-bindings.mjs");
const math = resolve(root, "packages/verso-react/web/katex.mjs");
const katex = resolve(root, ".lake/packages/verso/vendored-js/katex");
// One stylesheet per shell, with matching local WOFF2 assets. No CDN/font fetch.
let mathCss = firPackage || matchedDemo ? "" : await read(resolve(katex, "katex.min.css"));
const assetHashes = {};
for (const match of [...mathCss.matchAll(/src:url\((fonts\/[^)]+\.woff2)\)[^}]*/g)]) {
  const bytes = await readFile(resolve(katex, match[1]));
  assetHashes[match[1]] = sha(bytes);
  mathCss = mathCss.replace(match[0], `src:url(data:font/woff2;base64,${bytes.toString("base64")}) format("woff2")`);
}
assert.ok(firPackage || matchedDemo || (Object.keys(assetHashes).length > 0 && !mathCss.includes("url(fonts/")));
const liveOutput = resolve(root, ".lake/build/checked-json-demo.js");
const output = resolve(process.env.VBP_DEMO_OUTPUT ?? liveOutput);
const firDemo = firPackage ? await prepareFirDemo(firPackage, root) : null;
if (firDemo) assert.notEqual(output, liveOutput, "FIR must not overwrite the VIR demo");
if (matchedDemo) assert.notEqual(output, liveOutput, "matched demo must not overwrite the live demo");
const hostOverridePath = process.env.VBP_DEMO_HOST_STATE;
const hostOverride = hostOverridePath ? await read(hostOverridePath) : null;
if (hostOverride !== null) {
  assert.notEqual(output, liveOutput, "runtime qualification must not overwrite the live demo");
  assert.equal(sha(hostOverride), process.env.VBP_DEMO_HOST_STATE_SHA256, "reviewed host source mismatch");
}
const brandQuery = "\nexport function isLeanObjectHandle(value) { return leanObjectHandleStates.has(value); }\n";
const result = await build({
  absWorkingDir: vir, entryPoints: [shell], outfile: output,
  bundle: true, charset: "utf8", format: "esm", platform: "browser", target: "es2022",
  external: ["@leanprover/infoview", "react", "react-dom"],
  legalComments: "none", write: false, metafile: true,
  alias: { "@vir-object-values": objects },
  plugins: [{ name: "checked-json-demo-only", setup(builder) {
    if (matchedDemo) {
      builder.onResolve({ filter: /^@matched-demo$/ }, () => ({ path: "matched", namespace: "matched-demo" }));
      builder.onLoad({ filter: /.*/, namespace: "matched-demo" }, () => ({ contents: matchedDemo.source, loader: "js", resolveDir: root }));
    }
    if (firDemo) {
      builder.onResolve({ filter: /^@fir-demo$/ }, () => ({ path: "fir", namespace: "fir-demo" }));
      builder.onLoad({ filter: /.*/, namespace: "fir-demo" }, () => ({ contents: firDemo.source, loader: "js", resolveDir: root }));
    }
    if (hostOverride !== null) builder.onLoad({ filter: /runtime\/host-state\.js$/ }, ({ path }) => {
      assert.equal(path, resolve(vir, "web/src/runtime/host-state.js"));
      return { contents: hostOverride, loader: "js", resolveDir: dirname(path) };
    });
    builder.onLoad({ filter: /vir-infoview-widget\.js$/ }, async ({ path }) => {
      assert.equal(path, shell);
      const contents = matchedDemo ? configureNativeComponentShell(await read(path), {
        module: "@matched-demo", open: "openMatchedDemo", binding: "previewDemo.matchedComponent",
      }) : configureDemoShell(await read(path), Boolean(firDemo), {
        bridge, math, katex: resolve(katex, "katex.mjs"), mathCss,
      });
      return { contents, loader: "js", resolveDir: dirname(path) };
    });
    builder.onLoad({ filter: /runtime\/object-values\.js$/ }, async ({ path }) => {
      assert.equal(path, objects);
      const contents = await read(path);
      assert.ok(contents.includes("const leanObjectHandleStates = new WeakMap();"));
      assert.ok(!contents.includes("export function isLeanObjectHandle"));
      return { contents: contents + (firDemo ? "" : brandQuery), loader: "js", resolveDir: dirname(path) };
    });
    builder.onResolve({ filter: /vir-react-dom-client\.js$/ }, () => ({
      path: "react-dom-client", namespace: "infoview-client",
    }));
    builder.onLoad({ filter: /.*/, namespace: "infoview-client" }, () => ({
      contents: 'export { createRoot } from "react-dom";', loader: "js",
    }));
  } }],
});
// Verify the base sources against the full SDK; record any explicit one-file
// qualification override separately below.
const sourceHashes = {};
for (const input of Object.keys(result.metafile.inputs)) {
  const path = resolve(vir, input);
  if (path.startsWith(resolve(vir, "web/src") + "/")) {
    const relative = path.slice(resolve(vir, "web/src").length + 1);
    const bytes = await readFile(path);
    const expected = sdk.files.find(f => f.path === `js/${relative}`);
    if (expected) assert.equal(sha(bytes), expected.sha256, `SDK source mismatch: ${relative}`);
    else assert.equal(relative, "vir-widget-errors.js", "unexpected source outside SDK");
    sourceHashes[relative] = relative === "runtime/host-state.js" && hostOverride !== null
      ? sha(hostOverride) : sha(bytes);
  }
}
assert.equal(result.outputFiles.length, 1);
const bundle = result.outputFiles[0].contents;
await mkdir(dirname(output), { recursive: true });
if (await readFile(output).then(bytes => sha(bytes)).catch(() => null) !== sha(bundle))
  await writeFile(output, bundle);
await writeFile(output + ".identity.json", JSON.stringify({
  virCommit: sdk.gitCommit, toolchain: sdk.leanToolchain,
  sdkManifestSha256: sha(await readFile(resolve(sdkRoot, "lean-vir-artifact.json"))),
  shellSourceSha256: sha(await readFile(shell)), bridgeSha256: firDemo ? null : sha(await readFile(bridge)),
  scriptSha256: sha(await readFile(fileURLToPath(import.meta.url))),
  shellEditsSha256: sha(await readFile(new URL("./demo_shell.mjs", import.meta.url))),
  bundleSha256: sha(bundle), brandQuery: firDemo ? null : brandQuery, sourceHashes,
  firDemo: firDemo?.identity ?? null,
  matchedDemo: matchedDemo?.identity ?? null,
  hostOverride: hostOverride === null ? null : {
    sourcePath: resolve(hostOverridePath), sourceSha256: sha(hostOverride),
    baseSha256: sha(await readFile(resolve(sdkRoot, "js/runtime/host-state.js"))),
  },
  math: firDemo || matchedDemo ? "source display; no native math component" : { componentSha256: sha(await readFile(math)),
    katexSha256: sha(await readFile(resolve(katex, "katex.mjs"))),
    cssSha256: sha(mathCss), assetHashes },
}, null, 2) + "\n");
console.log(`Prepared ${output} (${bundle.length} bytes)`);
