// Freeze consumer inputs; all builds belong to a fresh campaign directory.
import assert from 'node:assert/strict';
import { cp, readFile, writeFile, mkdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { createHash } from 'node:crypto';
const [snapshot, producerPackage, destination] = process.argv.slice(2).map(p => resolve(p));
const sha = b => createHash('sha256').update(b).digest('hex');
const identityBytes = await readFile(join(snapshot, 'identity.json'));
assert.equal(sha(identityBytes), '2c1ef0f6c7d78636af5f50384aafe6407282d1c4b06bece068d7ec49b1e4475b');
const identity = JSON.parse(identityBytes);
for (const f of identity.files) {
  assert.equal(f.kind, 'file');
  assert.equal(sha(await readFile(join(snapshot, f.path))), f.sha256, f.path);
}
assert.equal(sha(await readFile(join(producerPackage, 'BUILD.json'))),
  '33b3ad90c23864fc17bc8a50624de3e68aa43256ce1a1b7a40d20dbe2bef72f8');
await mkdir(destination, { recursive: false });
await cp(join(snapshot, 'source'), join(destination, 'source'), { recursive: true });
await cp(producerPackage, join(destination, 'fir'), { recursive: true });
const lake = JSON.parse(await readFile(join(destination, 'source/lake-manifest.json')));
const packages = lake.packages.map(p => ({ type: 'path', scope: p.scope, name: p.name,
  manifestFile: p.manifestFile, configFile: p.configFile, inherited: p.inherited,
  dir: p.type === 'path' ? join(destination, 'source', p.dir)
    : join(destination, 'source', lake.packagesDir, p.name.replaceAll('«','').replaceAll('»','')) }));
const mapBytes = Buffer.from(JSON.stringify({ version: lake.version, packages }, null, 2));
await writeFile(join(destination, 'packages.json'), mapBytes);
await writeFile(join(destination, 'identity.json'), JSON.stringify({
  sourceIdentity: sha(identityBytes), firBuildSha256: sha(await readFile(join(destination, 'fir/BUILD.json'))),
  packageMapSha256: sha(mapBytes), sourceFiles: identity.files,
  scope: 'matched frozen none-component consumer qualification; live pins unchanged',
}, null, 2));
console.log(destination);
