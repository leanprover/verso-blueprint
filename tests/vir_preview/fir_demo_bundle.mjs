// Consume the portable immutable none-component package; no producer build paths.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';

export async function prepareFirDemo(packageRoot, prepared) {
  const sha = bytes => createHash('sha256').update(bytes).digest('hex');
  packageRoot = resolve(packageRoot);
  const { verifyBrowserPackage } = await import(pathToFileURL(resolve(packageRoot, 'verified-package.mjs')));
  const { componentPackagePolicy } = await import(pathToFileURL(resolve(packageRoot, 'component-package-policy.mjs')));
  const verified = verifyBrowserPackage(packageRoot, componentPackagePolicy);
  const sdkRoot = resolve(prepared, '.lake/build/vir/sdk');
  const sdkBytes = await readFile(resolve(sdkRoot, 'lean-vir-artifact.json'));
  const sdk = JSON.parse(sdkBytes);
  assert.equal(sdk.gitCommit, '36d26bc224f0c2a52cd586587b2c3e1b1ade70d6');
  assert.equal(sdk.gitDirty, false);
  assert.equal(sdk.leanToolchain, 'leanprover/lean4:v4.34.0-rc2');
  for (const f of sdk.files) assert.equal(sha(await readFile(resolve(sdkRoot, f.path))), f.sha256, f.path);
  const hostRoot = resolve(prepared, '.lake/packages/lean_vir/web/src');
  for (const f of verified.build.externalProviders.sources)
    assert.equal(sha(await readFile(resolve(prepared, '.lake/packages/lean_vir', f.path))), f.sha256, f.path);
  const lock = JSON.parse(await readFile(resolve(prepared, '.lake/packages/lean_vir/package-lock.json')));
  for (const p of verified.build.externalProviders.react) {
    assert.equal(lock.packages[`node_modules/${p.name}`].version, p.version);
    assert.equal(lock.packages[`node_modules/${p.name}`].integrity, p.integrity);
  }
  const wasm = await readFile(resolve(packageRoot, 'component.wasm'));
  const json = async name => JSON.parse(await readFile(resolve(packageRoot, name)));
  const source = `
import { createComponentSession, COMPONENT_SESSION_API } from ${JSON.stringify(resolve(packageRoot, 'component-session-bootstrap.mjs'))};
import { createBrowserReactHostBindings } from ${JSON.stringify(resolve(hostRoot, 'vir-react-host-bindings.js'))};
import { createJsCollectionHostBindings } from ${JSON.stringify(resolve(hostRoot, 'host/vir-js-collection-bindings.js'))};
import { createJsValueHostBindings } from ${JSON.stringify(resolve(hostRoot, 'host/vir-js-value-bindings.js'))};
import { createBrowserEventHostBindings } from ${JSON.stringify(resolve(hostRoot, 'host/vir-dom-host-bindings.js'))};
let compiledModule;
export async function openFirDemo() {
  compiledModule ??= WebAssembly.compile(Uint8Array.from(atob(${JSON.stringify(wasm.toString('base64'))}), c => c.charCodeAt(0)));
  return createComponentSession({ apiVersion: COMPONENT_SESSION_API, module: await compiledModule,
    manifest: ${JSON.stringify(await json('component.wasm.json'))},
    hostBoundary: ${JSON.stringify(await json('host-boundary.json'))},
    callbackBoundary: ${JSON.stringify(await json('callback-boundary.json'))},
    bindings: { ...createJsCollectionHostBindings(), ...createJsValueHostBindings(),
      ...createBrowserEventHostBindings(), ...createBrowserReactHostBindings() } });
}
`;
  return { source, identity: { packageRoot, buildSha256: sha(await readFile(resolve(packageRoot, 'BUILD.json'))),
    wasmSha256: sha(wasm), sourceIdentity: verified.build.frozenInputs.sourceIdentity,
    providerIdentity: verified.build.externalProviders.sourceIdentity,
    hostSdkSha256: sha(sdkBytes), hostVirCommit: sdk.gitCommit, sharedProviderModules: true,
    boundary: 'native React component; props.document is Document.encode String; math none' } };
}
