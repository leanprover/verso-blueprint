// Build only a consumer fixture against the frozen renderer; no producer/pin edits.
// Usage: node prepare_matched_renderer.mjs PREPARED_VBP NEW_CONSUMER_DIRECTORY
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { resolve } from "node:path";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";

assert.equal(process.argv.length, 4);
const [prepared, consumer] = process.argv.slice(2).map(p => resolve(p));
const revision = process.env.VBP_MATCHED_CURRENT === "1"
  ? "92db63257b33495f94495376ad9eb648b9365ce1" : "c4430bfe2c898c0312903ae46c45b410d253ebf4";
const sha = bytes => createHash("sha256").update(bytes).digest("hex");
const sourcePaths = ["packages/verso-react/VersoReact/Renderer.lean",
  "src/VersoBlueprintVir/Preview/Renderer.lean", "src/VersoBlueprintVir/Preview/Model.lean"];
const sources = {};
for (const path of sourcePaths) {
  const frozen = execFileSync("git", ["-C", prepared, "show", `${revision}:${path}`]);
  assert.deepEqual(await readFile(resolve(prepared, path)), frozen, `${path} source drift`);
  sources[path] = sha(frozen);
}
const fixture = execFileSync("git", ["-C", prepared, "show",
  `${revision}:tests/VersoBlueprintVirTests/Renderer.lean`], { encoding: "utf8" });
const extra = await readFile(fileURLToPath(new URL("./matched_renderer_entries.lean.inc", import.meta.url)), "utf8");
const end = "end VersoBlueprintVirTests.Renderer";
assert.equal(fixture.split(end).length, 2);
const source = fixture.replace(end, extra + "\n" + end);
await mkdir(consumer, { recursive: false });
await writeFile(resolve(consumer, "MatchedRenderer.lean"), source);
await writeFile(resolve(consumer, "lean-toolchain"), await readFile(resolve(prepared, "lean-toolchain")));
await writeFile(resolve(consumer, "lakefile.lean"), `import Lake
open Lake DSL
require VersoBlueprint from ${JSON.stringify(prepared)}
package matchedRenderer
lean_lib MatchedRenderer where
  requiresModuleSystem := true
`);
// Reuse the resolved dependency graph and existing checkouts read-only. All
// consumer module products stay in its own .lake; no dependency update needed.
const manifest = JSON.parse(await readFile(resolve(prepared, "lake-manifest.json"), "utf8"));
manifest.name = "matchedRenderer";
manifest.packagesDir = resolve(prepared, manifest.packagesDir);
for (const p of manifest.packages) {
  p.inherited = true;
  if (p.type === "path") p.dir = resolve(prepared, p.dir);
}
manifest.packages.unshift({ type: "path", name: "VersoBlueprint", scope: "", dir: prepared,
  inherited: false, manifestFile: "lake-manifest.json", configFile: "lakefile.lean" });
await writeFile(resolve(consumer, "lake-manifest.json"), JSON.stringify(manifest, null, 2));
await writeFile(resolve(consumer, "identity.json"), JSON.stringify({ revision, prepared,
  sourceHashes: sources, fixtureSha256: sha(fixture), entriesSha256: sha(extra),
  generatedSourceSha256: sha(source) }, null, 2));
console.log(consumer);
