// FIR session-age diagnostic. Only the existing content callback is timed.
import * as React from 'react';
import { createRoot } from 'react-dom/client';
import { flushSync } from 'react-dom';
import { open } from './component_campaign_entry.mjs';

const check = (ok, message) => { if (!ok) throw Error(message); };
const median = values => {
  const sorted = [...values].sort((a,b) => a-b);
  return (sorted[Math.floor((sorted.length-1)/2)] + sorted[Math.floor(sorted.length/2)])/2;
};

// Retained sessions deliberately keep a block identity across prose edits;
// fresh sessions assign it from their own history. Compare all other markup.
function comparableHtml(container) {
  const clone = container.cloneNode(true);
  for (const node of clone.querySelectorAll('[data-verso-render-id]')) {
    node.removeAttribute('data-verso-render-id');
    const title = node.getAttribute('title');
    if (title !== null) {
      check(title.startsWith('render path:') && title.includes('\nidentity:'), 'unexpected render tooltip');
      node.setAttribute('title', title.slice(0,title.indexOf('\nidentity:')));
    }
  }
  return clone.innerHTML;
}

async function run() {
  const [bytes, manifest, hostBoundary, callbackBoundary, inputs] = await Promise.all([
    fetch('/component.wasm').then(r => r.arrayBuffer()),
    ...['component.wasm.json','host-boundary.json','callback-boundary.json','inputs.json'].map(
      path => fetch(`/${path}`).then(r => r.json())),
  ]);
  const assets = { measure: true, fir: {
    module: await WebAssembly.compile(bytes), manifest, hostBoundary, callbackBoundary,
  } };
  const documents = inputs.slice(-2), samples = [];
  const reverse = process.env.VBP_COMPONENT_RETENTION_REVERSE === '1';
  const lifetimes = new Set();
  const update = (lifetime, document) => flushSync(() => lifetime.root.render(
    React.createElement(lifetime.session.Component, { document })));
  const create = async target => {
    const session = await open('fir', assets);
    const container = document.createElement('div');
    document.getElementById('app').appendChild(container);
    const lifetime = { session, container, root: createRoot(container) };
    lifetimes.add(lifetime);
    // End both fresh and initial retained warmup at the opposite document,
    // so every measured edit must construct content, not hit an unchanged memo.
    update(lifetime, documents[target]);
    update(lifetime, documents[1-target]);
    check(container.querySelector('[data-verso-preview-status="ready"]'), 'warmup failed');
    return lifetime;
  };
  const dispose = lifetime => {
    lifetimes.delete(lifetime);
    try { flushSync(() => lifetime.root.unmount()); }
    finally {
      try { lifetime.session.dispose(); }
      finally { lifetime.container.remove(); }
    }
    check(lifetime.session.stats().disposed, 'session disposal failed');
  };
  try {
    const retained = await create(0);
    for (let round=0; round<4; round++) {
      const input = round % 2;
      const fresh = await create(input);
      // Each input sees both first/second positions; reverse in the second run.
      const freshFirst = (round === 0 || round === 3) !== reverse;
      const order = freshFirst ? ['fresh','retained'] : ['retained','fresh'];
      const pair = { fresh, retained };
      for (const mode of order) {
        const lifetime = pair[mode], probe = lifetime.session.probe;
        const before = lifetime.session.stats();
        const article = lifetime.container.querySelector('#vir-verso-document');
        probe.clear();
        update(lifetime, documents[input]);
        const content = probe.records.filter(row => row.phase === 'decoded-document-to-elements');
        check(content.length === 1 && content[0].ok, `${mode}: expected one content callback`);
        check(lifetime.container.querySelector('#vir-verso-document') === article, `${mode}: DOM replaced`);
        samples.push({ round, mode, input, order, contentMs: content[0].durationMs,
          before, after: lifetime.session.stats() });
      }
      const freshHtml = comparableHtml(fresh.container), retainedHtml = comparableHtml(retained.container);
      if (freshHtml !== retainedHtml) {
        let offset = 0;
        while (freshHtml[offset] === retainedHtml[offset]) offset++;
        const error = new Error(`round ${round}: DOM differs`);
        error.details = { samples, offset,
          fresh: freshHtml.slice(Math.max(0,offset-100),offset+300),
          retained: retainedHtml.slice(Math.max(0,offset-100),offset+300) };
        throw error;
      }
      dispose(fresh);
    }
    const summary = Object.fromEntries(['fresh','retained'].map(mode => {
      const values = samples.filter(row => row.mode === mode).map(row => row.contentMs);
      return [mode, { medianMs: median(values), minMs: Math.min(...values),
        maxMs: Math.max(...values), samples: values.length }];
    }));
    return { boundary: 'decoded Document and prepared identities to returned React elements; excludes decode/identity preparation/React commit',
      comparison: 'FIR fresh warmed session / FIR retained session',
      productionReact: true, cpuSampling: false, diagnostics: false, highlighting: false, optionalMath: false,
      forcedGc: false, statsOutsideTimedCallback: true, warmupUpdatesPerNewSession: 2,
      reverse, summary, samples, identityMetadataNormalizedDomEquality: true,
      excludedIdentityMetadata: ['data-verso-render-id', 'render tooltip identity line'],
      retainedDocument: true };
  } finally {
    for (const lifetime of lifetimes) dispose(lifetime);
  }
}
globalThis.componentCampaign = run().then(value => ({ok:true,value}),
  error => ({ok:false,error:String(error?.stack ?? error), details:error.details}));
