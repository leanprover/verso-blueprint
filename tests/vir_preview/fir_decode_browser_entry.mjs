/* Frozen FIR codecs, using the existing retained FLT replay boundary. */
import { createRoot } from "react-dom/client";
import { flushSync } from "react-dom";
import * as sessionApi from "@fir-codec-bootstrap";
import * as providers from "@fir-codec-providers";
import { describeError, withCleanup } from "@vir-test-support";
import { createComponentPhaseProbe } from "./component_phase_probe.mjs";
import { createHostImportCensus } from "./host_import_census.mjs";
import { PreviewMath } from "./matched_math_component.mjs";

const check = (ok, message) => { if (!ok) throw Error(message); };
const sampled = process.env.VBP_REPLAY_PROFILE === "1";
const censusEnabled = process.env.VBP_REPLAY_HOST_IMPORT_CENSUS === "1";
const stringCensusEnabled = process.env.VBP_REPLAY_HOST_STRING_CENSUS === "1";
const direct = process.env.VBP_REPLAY_FIR_DIRECT === "1";
const directPackage = process.env.VBP_REPLAY_FIR_DIRECT_PACKAGE === "1";
globalThis.decodeAcceptance = run().then(value => ({ ok: true, value }),
  error => ({ ok: false, error: describeError(error) }));

async function run() {
  const census = censusEnabled ? createHostImportCensus(128, stringCensusEnabled) : undefined;
  if (census) globalThis.__vbpFirHostImportCensus = census;
  const source = await (await fetch("/response.json")).text();
  const json = async file => (await fetch(`/${file}`)).json();
  const bindings = { ...providers.createJsCollectionHostBindings(),
    ...providers.createJsValueHostBindings(), ...providers.createBrowserEventHostBindings(),
    ...providers.createBrowserReactHostBindings(), ...providers.createJsonValueHostBindings(),
    "previewDemo.now": () => performance.now(),
    "previewDemo.mathComponent": () => PreviewMath };
  // The bootstrap creates the configured factory, then its separate default view.
  // Brackets are enabled only in the diagnostic/profile run, never headline timing.
  // The direct bootstrap creates only its retained timed view.  The older
  // configured-codec bootstrap also creates a separate default view first.
  const measuredFactory = directPackage ? 0 : 1;
  const probe = sampled || census ? createComponentPhaseProbe(bindings, () => performance.now(),
    directPackage ? 1 : 2, false, census) : undefined;
  const createSession = sessionApi[directPackage
    ? "createDirectConstructionSession" : "createConfiguredCodecSession"];
  const apiVersion = sessionApi[directPackage ? "DIRECT_CONSTRUCTION_API" : "CODEC_SESSION_API"];
  const session = await createSession({ apiVersion,
    module: await WebAssembly.compile(await (await fetch("/component.wasm")).arrayBuffer()),
    manifest: await json("component.wasm.json"), hostBoundary: await json("host-boundary.json"),
    callbackBoundary: await json("callback-boundary.json"), entryBoundary: await json("entry-boundary.json"),
    ...(directPackage ? { constructorLayouts: await json("constructor-layouts.json") } : {}),
    bindings: probe?.bindings ?? bindings });
  probe?.finishFactory();
  const container = document.getElementById("app"), root = createRoot(container);
  const byId = id => document.getElementById(`vir-verso-${id}`);
  const settle = () => new Promise(resolve => setTimeout(resolve, 0));
  const settleMath = async () => {
    for (let attempt = 0; attempt < 200; attempt++) {
      await settle();
      const formulas = [...container.querySelectorAll("[data-verso-math-mode]")];
      if (formulas.length > 0 && formulas.every(node => node.querySelector(".katex, .katex-error"))) return;
    }
    throw Error("KaTeX passive effects did not settle");
  };
  const warnings = [], originalError = console.error;
  console.error = (...args) => { warnings.push(args.map(String).join(" ")); originalError(...args); };
  let nextVersion = 10, checkbox, paragraph, canonicalText;
  const one = async () => {
    const version = nextVersion++, marker = `Preview timing sample ${String(version).padStart(2, "0")}`;
    const input = source.replace(/"version":3/, `"version":${version}`).replace("Preview timing sample 03", marker);
    check(input.includes(marker), "missing captured edit marker");
    let observer;
    const committed = new Promise(resolve => {
      observer = new MutationObserver(() => {
        if (byId("preview")?.dataset.versoVersion === String(version)) resolve(performance.now());
      });
      observer.observe(container, { subtree: true, childList: true, attributes: true, characterData: true });
    });
    const start = performance.now(), parsed = JSON.parse(input), parsedAt = performance.now();
    const token = (direct ? session.directParsed : session.browserParsed)(parsed), decodedAt = performance.now();
    probe?.clear();
    census?.clear();
    root.render(process.env.VBP_REPLAY_TIMED_VIEW === "1"
      ? session.renderTimedDecoded(token, { decodedAt }) : session.renderDecoded(token));
    const committedAt = await committed;
    observer.disconnect();
    if (probe) {
      check(probe.records.filter(e => e.phase === "decoded-document-to-elements").length === 1,
        "expected exactly one document construction");
      check(probe.records.every(e => e.factory === measuredFactory && e.ok &&
        e.startMs >= decodedAt && e.endMs <= committedAt),
        "component bracket outside measured default-view update");
    }
    const sample = { totalMs: committedAt - start, parseMs: parsedAt - start,
      decodeMs: decodedAt - start, codecMs: decodedAt - parsedAt,
      renderToDomMs: committedAt - decodedAt, raw: { start, parsedAt, decodedAt, committedAt }, version,
      ...(probe ? { componentEvents: [...probe.records] } : {}) };
    if (census) sample.hostImportCensus = census.drain();
    // KaTeX renders in a passive effect.  Keep it outside the timing endpoint,
    // but let it settle before semantic DOM/text and retention checks.
    await settleMath();
    check(byId("preview").textContent.includes(marker), "new text missing");
    check(!byId("debug-panel") && !byId("highlight-changes").checked, "debug/highlighting enabled");
    const text = container.querySelector("article").textContent.replace(marker, "Preview timing sample XX");
    canonicalText ??= text;
    check(text === canonicalText, "rendered text changed unexpectedly");
    if (checkbox) check(checkbox === byId("follow-cursor") && !checkbox.checked, "control lost state/identity");
    if (paragraph) check(paragraph.isConnected, "unchanged paragraph replaced");
    sample.retention = session.stats();
    return sample;
  };
  return withCleanup(async () => {
    await one();
    checkbox = byId("follow-cursor");
    flushSync(() => checkbox.click());
    await settle();
    paragraph = [...container.querySelectorAll("article p")].find(p => !p.textContent.includes("Preview timing sample"));
    check(paragraph, "missing retained paragraph");
    const rows = [], updates = Number(process.env.VBP_REPLAY_UPDATES);
    for (let pair = -2; pair < updates; pair++) {
      if (pair === 0 && sampled) check((await fetch("/profile/start")).ok, "profile start failed");
      const sample = await one();
      if (pair >= 0) rows.push({ pair, order: ["browserParsed"], browserParsed: sample });
    }
    if (sampled) check((await fetch("/profile/stop")).ok, "profile stop failed");
    check(warnings.length === 0, `browser warnings: ${warnings.join("; ")}`);
    const digest = async value => [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)))].map(b => b.toString(16).padStart(2, "0")).join("");
    const normalize = text => text.replaceAll(/Preview timing sample \d\d/g, "Preview timing sample XX");
    const tree = node => node.nodeType === Node.TEXT_NODE ? normalize(node.textContent) : {
      tag: node.tagName, attributes: [...node.attributes].map(({ name, value }) => [name,
        name === "data-verso-version" ? "VERSION" : normalize(value)]).sort(([a], [b]) => a.localeCompare(b)),
      children: [...node.childNodes].map(tree) };
    const renderedDom = tree(container.querySelector("article"));
    return { rows, warmupUpdates: 2, elementCount: container.querySelectorAll("*").length, renderedDom,
      renderedTextSha256: await digest(canonicalText), renderedDomSha256: await digest(JSON.stringify(renderedDom)),
      retainedCheckbox: true, retainedParagraph: true, warnings,
      boundary: `parse + ${direct ? "direct typed FIR construction" : "checked JSON/FromJson"}; render-to-DOM includes identity, elements and React commit; excludes RPC/server/startup/paint/passive-effect wait`,
      instrumentation: sampled ? "CDP 1ms and two component-callback brackets" : "coarse phase timestamps only" };
  }, [["React", () => { flushSync(() => root.unmount()); console.error = originalError; }],
    ["FIR", () => session.dispose()],
    ["host-import census", () => { delete globalThis.__vbpFirHostImportCensus; }]]);
}
