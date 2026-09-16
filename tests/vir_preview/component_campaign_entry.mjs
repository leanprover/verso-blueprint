// Matched frozen none-factory replay. No runtime timing instrumentation.
import * as React from 'react';
import { createRoot } from 'react-dom/client';
import { renderToStaticMarkup } from 'react-dom/server';
import { createVirRuntime } from 'lean-vir';
import { createBrowserHostBindings } from 'lean-vir/host-bindings';
import { createBrowserReactHostBindings } from '@component-react';
import { createJsCollectionHostBindings } from '@component-collections';
import { createJsValueHostBindings } from '@component-values';
import { createBrowserEventHostBindings } from '@component-events';
import { createComponentSession, COMPONENT_SESSION_API } from '@component-bootstrap';
import { createComponentPhaseProbe } from './component_phase_probe.mjs';

const check = (ok, message) => { if (!ok) throw Error(message); };
const entry = 'VersoBlueprintVirTests.NativeSession.createEncodedDocumentComponent';
export async function open(backend, assets) {
  check(backend === 'vir' || backend === 'fir', `Unknown component backend: ${backend}`);
  let probe;
  const measured = bindings => {
    if (!assets.measure) return bindings;
    probe = createComponentPhaseProbe(bindings);
    return probe.bindings;
  };
  if (backend === 'vir') {
    const runtime = await createVirRuntime({ ...assets.vir,
      defaultHostBindings: () => measured(createBrowserHostBindings({ reactHostBindings: createBrowserReactHostBindings })) });
    try {
      const Component = runtime.call(entry);
      probe?.finishFactory();
      return { Component, probe, dispose: () => runtime.dispose() };
    } catch (error) { runtime.dispose(); throw error; }
  }
  const session = await createComponentSession({ apiVersion: COMPONENT_SESSION_API,
    ...assets.fir, bindings: measured({ ...createJsCollectionHostBindings(), ...createJsValueHostBindings(),
      ...createBrowserEventHostBindings(), ...createBrowserReactHostBindings() }) });
  probe?.finishFactory();
  return { ...session, probe };
}

export async function runSsr(assets, inputs) {
  const html = {};
  for (const backend of ['vir', 'fir']) {
    const session = await open(backend, assets);
    try {
      html[backend] = inputs.map(document => {
        const result = renderToStaticMarkup(React.createElement(session.Component, { document }));
        check(result.includes('data-verso-preview-status="ready"'), `${backend}: SSR not ready`);
        return result;
      });
      check(renderToStaticMarkup(React.createElement(session.Component,
        { document: '{malformed' })).includes('data-verso-preview-status="error"'), `${backend}: malformed SSR accepted`);
      check(renderToStaticMarkup(React.createElement(session.Component,
        { document: inputs[0] })) === html[backend][0], `${backend}: SSR recovery changed output`);
    } finally { session.dispose(); }
  }
  check(html.vir.every((value, i) => value === html.fir[i]), 'matched factory SSR differs');
  return { exactSsrEquality: true, readyDocumentsPerBackend: inputs.length, malformedRecovery: true, noTimings: true };
}

export async function runBrowser() {
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  const [bytes, manifest, hostBoundary, callbackBoundary, inputs] = await Promise.all([
    fetch('/component.wasm').then(r => r.arrayBuffer()),
    ...['component.wasm.json', 'host-boundary.json', 'callback-boundary.json', 'inputs.json'].map(
      file => fetch(`/${file}`).then(r => r.json())),
  ]);
  const assets = { fir: { module: await WebAssembly.compile(bytes), manifest, hostBoundary, callbackBoundary },
    vir: { wasmUrl: '/runtime.wasm', irPackageSet: '/control.irpkg-set.json' } };
  const warnings = [], original = console.error;
  console.error = (...args) => { warnings.push(args.map(String).join(' ')); original(...args); };
  const snapshots = {};
  try {
    for (const backend of ['vir', 'fir']) {
      const session = await open(backend, assets);
      const container = document.getElementById('app');
      const root = createRoot(container);
      const update = document => React.act(() => root.render(React.createElement(session.Component, { document })));
      const control = name => container.querySelector(`#vir-verso-${name}`);
      try {
        snapshots[backend] = [];
        update(inputs[0]);
        const shell = container.querySelector('#vir-verso-shell');
        const highlight = control('highlight-changes'), follow = control('follow-cursor');
        React.act(() => highlight.click());
        React.act(() => follow.click());
        check(highlight.checked && !follow.checked, `${backend}: native control events failed`);
        for (const document of [...inputs, inputs.at(-1)]) {
          const prior = container.querySelector('#vir-verso-document');
          update(document);
          check(container.querySelector('#vir-verso-document') === prior, `${backend}: document DOM replaced`);
          check(container.querySelector('#vir-verso-shell') === shell &&
            control('highlight-changes') === highlight && highlight.checked && !follow.checked,
            `${backend}: shell/control state changed`);
          check(!container.querySelector('.vir-verso-block-focused'), `${backend}: follow-cursor off ignored`);
          snapshots[backend].push(container.innerHTML);
        }
        if (process.env.VBP_COMPONENT_RICH === '1') {
          update(inputs.at(-2));
          const details = container.querySelector('details');
          check(details && !details.open, `${backend}: rich details absent or initially open`);
          React.act(() => details.querySelector('summary').click());
          check(details.open, `${backend}: rich details did not open`);
          for (const input of [inputs.at(-1), inputs.at(-2), inputs.at(-2)]) {
            update(input);
            check(container.querySelector('details') === details && details.open,
              `${backend}: rich update lost details identity/open state`);
          }
          for (const selector of ['[data-verso-informal-label="independent"]',
            '[data-verso-external-markup-display="summary"]',
            '[data-verso-external-markup-display="source"]'])
            check(container.querySelector(selector), `${backend}: missing rich output ${selector}`);
          check(!container.querySelector('script'), `${backend}: raw markup executed`);
          snapshots[backend].push(container.innerHTML);
        }
        update('{malformed');
        check(container.querySelector('[data-verso-preview-status="error"]'), `${backend}: decode error absent`);
        update(inputs[0]);
        check(highlight.checked && !follow.checked, `${backend}: recovery reset controls`);
        check(container.querySelector('#vir-verso-shell') === shell, `${backend}: recovery replaced shell`);
      } finally {
        React.act(() => root.unmount());
        session.dispose();
      }
      {
        let rejected = false;
        try { session.Component({ document: inputs[0] }); } catch { rejected = true; }
        check(rejected, `disposed ${backend} component accepted a callback`);
      }
    }
    check(JSON.stringify(snapshots.vir) === JSON.stringify(snapshots.fir), 'matched native factory DOM differs');
    check(warnings.length === 0, `React warnings: ${warnings.join('\n')}`);
    return { exactDomEquality: true, updatesPerBackend: inputs.length + 1,
      nativeControlEvents: true, retainedShellControlsDocument: true, malformedRecovery: true,
      unmountBeforeDispose: true, postDisposalRejectedBothBackends: true,
      ...(process.env.VBP_COMPONENT_RICH === '1' ? { retainedRichDetails: true,
        informalAndExternalMarkup: true, richUpdatesPerBackend: 3 } : {}),
      noReactWarnings: true, noTimings: true };
  } finally { console.error = original; }
}

if (typeof window !== 'undefined' && process.env.VBP_COMPONENT_MEASURE !== '1') globalThis.componentCampaign = runBrowser().then(
  value => ({ ok: true, value }), error => ({ ok: false, error: String(error?.stack ?? error) }));
