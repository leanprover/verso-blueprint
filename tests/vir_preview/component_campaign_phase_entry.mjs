// Diagnostic rendering boundary; decoding/session and React commit stay outside.
import * as React from 'react';
import { createRoot } from 'react-dom/client';
import { flushSync } from 'react-dom';
import { open } from './component_campaign_entry.mjs';
import { createComponentSession as baselineFactory } from '@component-baseline-bootstrap';

const check = (ok, message) => { if (!ok) throw Error(message); };
async function run() {
  const adapter = process.env.VBP_COMPONENT_ADAPTER === '1';
  const backends = adapter ? ['fir-baseline','fir'] : ['vir','fir'];
  const [bytes, manifest, hostBoundary, callbackBoundary, inputs] = await Promise.all([
    fetch('/component.wasm').then(r => r.arrayBuffer()),
    ...['component.wasm.json','host-boundary.json','callback-boundary.json','inputs.json'].map(
      path => fetch(`/${path}`).then(r => r.json())),
  ]);
  const assets = { measure: true, fir: { module: await WebAssembly.compile(bytes), manifest, hostBoundary, callbackBoundary },
    vir: { wasmUrl: '/runtime.wasm', irPackageSet: '/control.irpkg-set.json' } };
  const baselineAssets = adapter ? { ...assets, fir: { module: assets.fir.module,
    ...Object.fromEntries(await Promise.all(['manifest','hostBoundary','callbackBoundary'].map(async (key,i) =>
      [key, await fetch(`/baseline/${['component.wasm.json','host-boundary.json','callback-boundary.json'][i]}`).then(r=>r.json())]))) } } : null;
  const sessions = {}, roots = {}, containers = {}, samples = [];
  const documents = inputs.slice(-2);
  const update = (backend, document) => flushSync(() => roots[backend].render(
    React.createElement(sessions[backend].Component, { document })));
  try {
    for (const backend of backends) {
      sessions[backend] = backend === 'fir-baseline' ? await open('fir', baselineAssets, baselineFactory) : await open(backend, assets);
      const container = document.createElement('div');
      document.getElementById('app').appendChild(container);
      containers[backend] = container;
      roots[backend] = createRoot(container);
      for (const input of documents) update(backend,input);
      check(container.querySelector('[data-verso-preview-status="ready"]'), `${backend}: warmup failed`);
    }
    const profile = process.env.VBP_COMPONENT_PROFILE === '1';
    const rounds = profile ? 2 : 4;
    if (profile) check((await fetch('/profile/start', {method:'POST'})).ok, 'CPU profiler failed to start');
    // Paired AB/BA rounds; both see the same edit each round.
    for (let round=0; round<rounds; round++) {
      const input = documents[round % 2];
      for (const backend of round % 2 ? [...backends].reverse() : backends) {
        const probe = sessions[backend].probe;
        probe.clear();
        const article = containers[backend].querySelector('#vir-verso-document');
        update(backend,input);
        const content = probe.records.filter(row => row.phase === 'decoded-document-to-elements');
        check(content.length === 1 && content[0].ok, `${backend}: expected one successful content callback`);
        check(containers[backend].querySelector('#vir-verso-document') === article, `${backend}: replaced document DOM`);
        samples.push({ round, backend, input: round % 2, contentMs: content[0].durationMs,
          contentStartMs: content[0].startMs, contentEndMs: content[0].endMs,
          callbacks: probe.records.map(row => ({ phase: row.phase, durationMs: row.durationMs, ok: row.ok })) });
      }
      check(containers[backends[0]].innerHTML === containers[backends[1]].innerHTML, `round${round}: DOM differs`);
    }
    if (profile) check((await fetch('/profile/stop', {method:'POST'})).ok, 'CPU profiler failed to stop');
    const summary = Object.fromEntries(backends.map(backend => {
      const values = samples.filter(row => row.backend === backend).map(row => row.contentMs).sort((a,b)=>a-b);
      return [backend, { medianMs: (values[Math.floor((values.length-1)/2)]+values[Math.floor(values.length/2)])/2,
        minMs: values[0], maxMs: values.at(-1), samples: values.length }];
    }));
    return { boundary: 'decoded Document and prepared identities to returned React elements, including host calls/props access/effect registration; excludes decode/identity preparation/React commit',
      productionReact: true, diagnostics: false, highlighting: false, optionalMath: false,
      cpuSampling: profile ? 'CDP 1ms; attribution only' : false,
      comparison: adapter ? 'FIR baseline / FIR adapter candidate' : 'VIR / FIR',
      warmupUpdatesPerBackend: 2, pairedRounds: rounds, runOrder: profile ? 'AB/BA' : 'AB/BA/AB/BA', sessionRetention: 'until disposal',
      summary, samples, exactDomEquality: true, retainedDocument: true };
  } finally {
    for (const backend of backends) {
      if (roots[backend]) flushSync(() => roots[backend].unmount());
      sessions[backend]?.dispose();
    }
  }
}
globalThis.componentCampaign = run().then(value => ({ok:true,value}), error => ({ok:false,error:String(error?.stack ?? error)}));
