/* Replay one validated FLT response; optional real retained-renderer timing. */
import { createRoot } from "react-dom/client";
import { flushSync } from "react-dom";
import { createVirRuntime } from "lean-vir";
import { createBrowserHostBindings } from "lean-vir/host-bindings";
import { createBrowserReactHostBindings } from "lean-vir/react-host-bindings";
import { describeError, withCleanup } from "@vir-test-support";
import { measureHostCalls } from "./response_phase_probe.mjs";
import { createJsonValueHostBindings } from "./upstream-json-value-bindings.mjs";
import { createIdentityPhaseProbe } from "./identity_phase_probe.mjs";
import { identityBrowserCases } from "./identity_browser_cases.mjs";

const entry = "VersoBlueprintVirTests.NativeSession.DecodeProbe";
const check = (value, message) => { if (!value) throw Error(message); };
globalThis.decodeAcceptance = run().then(
  value => ({ ok: true, value }), error => ({ ok: false, error: describeError(error) }));

async function run() {
  let runtime;
  let marker;
  let observeMarker = false;
  let identityProbe;
  return withCleanup(async () => {
    const source = await (await fetch("/response.json")).text();
    const expectedVersion = JSON.parse(source).ready.document.version;
    runtime = await createVirRuntime({
      wasmUrl: "/runtime.wasm", irPackageSet: "/widget.irpkg-set.json",
      defaultHostBindings: () => {
        const defaults = createBrowserHostBindings({ reactHostBindings: createBrowserReactHostBindings });
        const bool = defaults["js.bool"];
        if (process.env.VBP_REPLAY_IDENTITY_PHASES === "1") identityProbe = createIdentityPhaseProbe(defaults);
        return { ...defaults, ...identityProbe?.bindings, ...createJsonValueHostBindings(), "js.bool": (...args) => {
          if (observeMarker) marker = performance.now();
          return bool(...args);
        } };
      },
    });
    if (process.env.VBP_REPLAY_FINGERPRINT_CHECK === "1") {
      check(runtime.call(`${entry}.checkFingerprint`), "structural fingerprint/collision checks failed");
      return { structuralFingerprint: true, forcedCollisions: true, boundedRetention: true };
    }
    if (process.env.VBP_REPLAY_IDENTITY_TEST === "retained") {
      let state;
      return identityBrowserCases(scenario => {
        state = runtime.call(`${entry}.advanceIdentityScenario`, state, scenario);
        return runtime.call(`${entry}.renderIdentityScenarioRetained`, state, scenario);
      }, "content-local", () => { state = runtime.call(`${entry}.emptyIdentityState`); });
    }
    if (process.env.VBP_REPLAY_IDENTITY_TEST !== "") return identityBrowserCases(
      scenario => runtime.call(`${entry}.renderIdentityScenario`, scenario), process.env.VBP_REPLAY_IDENTITY_TEST);
    if (process.env.VBP_REPLAY_COMPRESSION_CHECK === "1") return compressionCheck(runtime, source);
    if (process.env.VBP_REPLAY_RENDER === "1") return renderExperiment(runtime, source, identityProbe);
    if (process.env.VBP_DECODE_BROWSER_JSON === "1") {
      return browserJsonExperiment(runtime, source, expectedVersion,
        active => { observeMarker = active; marker = undefined; }, () => marker);
    }
    const rows = [];
    const call = (mode, input) => {
      const raw = {};
      const value = measureHostCalls(runtime.hostState, () => runtime.call(`${entry}.${mode}`, input), raw);
      const targets = raw.hosts.map(h => h.target);
      const expected = mode === "split" ? ["js.string.value", "js.bool", "js.leanRef"] : ["js.string.value", "js.leanRef"];
      check(JSON.stringify(targets) === JSON.stringify(expected), `host sequence: ${targets}`);
      const [string, next] = raw.hosts, last = raw.hosts.at(-1);
      const timing = { totalMs: raw.end - raw.start, decodeMs: last.start - string.end,
        stringMs: string.end - string.start,
        ...(mode === "split" ? { parseMs: next.start - string.end,
          markerMs: next.end - next.start, reconstructMs: last.start - next.end } : {}), raw };
      return { value, timing };
    };
    // Adjacent pairs reverse order. Equality/description checks are outside
    // timing; handles are local to each pair and released by runtime disposal.
    for (let pair = -1; pair < 16; pair++) {
      const order = pair % 2 === 0 ? ["whole", "split"] : ["split", "whole"];
      const results = {};
      for (const mode of order) results[mode] = call(mode, source);
      check(runtime.call(`${entry}.equivalent`, results.whole.value, results.split.value), "decoder results differ");
      check(runtime.call(`${entry}.describe`, results.whole.value) === `ready:${expectedVersion}`, "wrong document version");
      if (pair >= 0) rows.push({ pair, order, whole: results.whole.timing, split: results.split.timing });
    }
    const invalid = [];
    for (const source of ["{", "{}", '{"ready":{}}']) {
      const whole = call("whole", source), split = call("split", source);
      check(runtime.call(`${entry}.equivalent`, whole.value, split.value), "error results differ");
      const description = runtime.call(`${entry}.describe`, whole.value);
      check(description.startsWith("error:"), "malformed response accepted");
      invalid.push({ source, description });
    }
    return { sourceChars: source.length, expectedVersion, warmupPairs: 1, rows, invalid,
      boundary: "browser replay of the captured response; no RPC, React render, or DOM included" };
  }, [["runtime", () => runtime?.dispose()]]);
}

function compressionCheck(runtime, source) {
  const cases = ["null", "true", "false", "[]", "{}", "0", "-0", "1.2300",
    "1e100", "-1e-100", "123456789012345678901234567890", "9007199254740993",
    '{"2":null,"10":false,"01":true,"a":[],"A":{}}', '{"a":1,"a":2}',
    JSON.stringify(String.fromCharCode(...Array.from({ length: 128 }, (_, i) => i)) +
      "α数学𝄞😀\u2028\u2029\\\"/"), source];
  let seed = 0x31415926;
  const next = () => { seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5; return seed >>> 0; };
  const generate = depth => {
    if (!depth) return [null, true, false, next() % 10000, `text:${next()}\\\"\nα`][next() % 5];
    return next() % 2 ? Array.from({ length: next() % 5 }, () => generate(depth - 1)) :
      Object.fromEntries(Array.from({ length: next() % 5 }, (_, i) => [`key:${i}:${next()}`, generate(depth - 1)]));
  };
  for (let i = 0; i < 64; ++i) cases.push(JSON.stringify(generate(4)));
  for (const [index, input] of cases.entries())
    check(runtime.call(`${entry}.checkCompression`, input), `serializer bytes differ in case ${index}`);
  check(runtime.call(`${entry}.checkCompressionStress`), "deep/wide serializer bytes differ");
  return { exactByteCases: cases.length, capturedFltResponse: true, deepArrayLevels: 5000,
    wideArrayEntries: 5000, seed: "0x31415926", scope: "byte equivalence against Lean.Json.compress in the matched VIR runtime; not a timing run" };
}

async function renderExperiment(runtime, source, identityProbe) {
  const invoke = (name, ...args) => runtime.call(`${entry}.${name}`, ...args);
  check(invoke("validateSource", source), "unsafe producer number domain");
  check(invoke("jsonEquivalent", source, JSON.parse(source)), "full JSON differs");
  const component = invoke("createView");
  const container = document.getElementById("app");
  const root = createRoot(container);
  const byId = id => document.getElementById(`vir-verso-${id}`);
  const warnings = [];
  const originalError = console.error, originalWarn = console.warn;
  console.error = (...args) => { warnings.push(args.map(String).join(" ")); originalError(...args); };
  console.warn = (...args) => { warnings.push(args.map(String).join(" ")); originalWarn(...args); };
  let nextVersion = 10;
  let checkbox, paragraph, canonicalText;
  const settle = () => new Promise(resolve => setTimeout(resolve, 0));
  const one = async mode => {
    // Input construction and domain validation are not browser reply processing.
    const version = nextVersion++;
    const marker = `Preview timing sample ${String(version).padStart(2, "0")}`;
    const input = source.replace(/"version":3/, `"version":${version}`)
      .replace("Preview timing sample 03", marker);
    check(input.includes(marker), "captured edit marker missing");
    let observer;
    const committed = new Promise(resolve => {
      observer = new MutationObserver(() => {
        if (byId("preview")?.dataset.versoVersion === String(version)) resolve(performance.now());
      });
      observer.observe(container, { subtree: true, childList: true, attributes: true, characterData: true });
    });
    const start = performance.now();
    const decoded = invoke(mode, mode === "browserParsed" ? JSON.parse(input) : input);
    const decodedAt = performance.now();
    identityProbe?.begin();
    const node = invoke("renderDecoded", component, decoded);
    root.render(node);
    const committedAt = await committed;
    const identityEvents = identityProbe?.finish();
    observer.disconnect();
    const sample = { totalMs: committedAt - start, decodeMs: decodedAt - start,
      renderToDomMs: committedAt - decodedAt, raw: { start, decodedAt, committedAt }, version };
    if (identityEvents) {
      check(identityEvents.filter(e => e.kind === "calibration").length === 1, "expected one instrumented render");
      check(identityEvents.filter(e => e.kind === "render").length === 1, "expected one renderer interval");
      check(identityEvents.every(e => e.start >= decodedAt && (e.end ?? e.allocationEnd) <= committedAt), "phase outside render");
      sample.identityEvents = identityEvents;
    }
    // Commit/DOM assertions and effect settling are deliberately outside timing.
    check(invoke("describe", decoded) === `ready:${version}`, "wrong decoded version");
    check(byId("preview").textContent.includes(marker), "new FLT text did not commit");
    check(!byId("debug-panel") && !byId("highlight-changes").checked, "debug/highlighting enabled");
    // Exclude the instrumentation <style>, whose animation name includes version.
    const text = container.querySelector("article").textContent.replace(marker, "Preview timing sample XX");
    if (canonicalText === undefined) canonicalText = text;
    check(text === canonicalText, "decoder paths changed rendered document text");
    if (checkbox) check(checkbox === byId("follow-cursor") && !checkbox.checked, "control lost state/identity");
    if (paragraph) check(paragraph.isConnected, "unchanged document node was replaced");
    await settle();
    return sample;
  };
  return withCleanup(async () => {
    const rows = [];
    await one("whole");
    checkbox = byId("follow-cursor");
    flushSync(() => checkbox.click());
    await settle();
    paragraph = [...container.querySelectorAll("article p")].find(p => !p.textContent.includes("Preview timing sample"));
    check(paragraph, "FLT paragraph missing");
    // Two complete warmup pairs; sixteen measured pairs, alternating order.
    for (let pair = -2; pair < 16; pair++) {
      if (pair === 0 && process.env.VBP_REPLAY_PROFILE === "1") {
        check((await fetch("/profile/start")).ok, "profile start failed");
      }
      const order = pair % 2 === 0 ? ["whole", "browserParsed"] : ["browserParsed", "whole"];
      const results = {};
      for (const mode of order) results[mode] = await one(mode);
      if (pair >= 0) rows.push({ pair, order, ...results });
    }
    if (process.env.VBP_REPLAY_PROFILE === "1") {
      check((await fetch("/profile/stop")).ok, "profile stop failed");
    }
    check(warnings.length === 0, `browser warnings: ${warnings.join("; ")}`);
    const digest = async value => [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)))].map(b => b.toString(16).padStart(2, "0")).join("");
    const renderedTextSha256 = await digest(canonicalText);
    // Stronger cross-check than text alone: preserve tags, attributes and styles.
    // Sort attributes and normalize only our edited marker/version metadata.
    const normalize = text => text.replaceAll(/Preview timing sample \d\d/g, "Preview timing sample XX");
    const tree = node => node.nodeType === Node.TEXT_NODE ? normalize(node.textContent) : {
      tag: node.tagName,
      attributes: [...node.attributes].map(({ name, value }) => [name,
        name === "data-verso-version" ? "VERSION" : normalize(value)]).sort(([a], [b]) => a.localeCompare(b)),
      children: [...node.childNodes].map(tree),
    };
    const renderedDom = tree(container.querySelector("article"));
    const renderedDomSha256 = await digest(JSON.stringify(renderedDom));
    return { rows, warmupPairs: 2, sourceChars: source.length, renderedTextSha256,
      renderedDomSha256, renderedDom,
      elementCount: container.querySelectorAll("*").length, warnings,
      retainedCheckbox: true, retainedParagraph: true,
      boundary: "captured FLT response decode to MutationObserver after React DOM commit; real retained preview, debug/highlighting off, no RPC/LSP, no paint or passive-effect wait included",
      instrumentation: identityProbe ? "diagnostic identity boundaries; no CPU sampler; not headline timings" : process.env.VBP_REPLAY_PROFILE === "1"
        ? "Chrome CPU sampling at 1000 us; diagnostic timings, no host timers"
        : "three coarse timestamps per update; no host timers or profiler" };
  }, [["React root", () => { flushSync(() => root.unmount()); }],
    ["console", () => { console.error = originalError; console.warn = originalWarn; }]]);
}

async function browserJsonExperiment(runtime, source, expectedVersion, setMarker, getMarker) {
  const invoke = (name, ...args) => runtime.call(`${entry}.${name}`, ...args);
  // Untimed producer-domain gate: JS parsing must not silently round exact Lean numbers.
  check(invoke("validateSource", source), "captured response is outside the upstream bridge's numeric domain");
  check(invoke("jsonEquivalent", source, JSON.parse(source)), "full captured JSON differs");
  const validJson = ['null', 'true', '-9007199254740991', '9007199254740991',
    '"λ😀"', '[]', '[null,false,42,"x"]',
    '{"__proto__":{"x":1},"10":true,"2":false,"nested":[{}]}'];
  for (const text of validJson) {
    check(invoke("validateSource", text), `valid source rejected: ${text}`);
    check(invoke("jsonEquivalent", text, JSON.parse(text)), `JSON mismatch: ${text}`);
  }
  const rejectedSources = ['9007199254740992', '9007199254740991.4', '0.5', '{'];
  for (const text of rejectedSources) check(!invoke("validateSource", text), `unsafe source accepted: ${text}`);

  const call = (mode, input) => {
    setMarker(mode === "browserParsed");
    try {
      const start = performance.now();
      const parsed = mode === "browserParsed" ? JSON.parse(input) : input;
      const parsedAt = performance.now();
      const value = invoke(mode, parsed);
      const end = performance.now();
      const convertedAt = getMarker();
      if (mode === "browserParsed") check(Number.isFinite(convertedAt), "conversion marker missing");
      return { value, timing: { totalMs: end - start,
        ...(mode === "browserParsed" ? { parseMs: parsedAt - start,
          conversionMs: convertedAt - parsedAt, reconstructMs: end - convertedAt } : {}),
        raw: { start, parsedAt, convertedAt, end } } };
    } finally { setMarker(false); }
  };
  const rows = [];
  for (let pair = -1; pair < 16; pair++) {
    const order = pair % 2 === 0 ? ["whole", "browserParsed"] : ["browserParsed", "whole"];
    const results = {};
    for (const mode of order) results[mode] = call(mode, source);
    check(invoke("equivalent", results.whole.value, results.browserParsed.value), "Preview decoder results differ");
    check(invoke("describe", results.whole.value) === `ready:${expectedVersion}`, "wrong document version");
    if (pair >= 0) rows.push({ pair, order, whole: results.whole.timing, browserParsed: results.browserParsed.timing });
  }
  const invalid = [];
  for (const text of ['{}', '{"ready":{}}']) {
    const whole = call("whole", text), candidate = call("browserParsed", text);
    check(invoke("equivalent", whole.value, candidate.value), "typed error results differ");
    const description = invoke("describe", candidate.value);
    check(description.startsWith("error:"), "malformed response accepted");
    invalid.push({ source: text, description });
  }
  let syntaxRejected = false;
  try { call("browserParsed", "{"); } catch (error) { syntaxRejected = error instanceof SyntaxError; }
  check(syntaxRejected, "malformed JSON accepted");
  const cycle = {}; cycle.self = cycle;
  const getter = Object.defineProperty({}, "x", { enumerable: true, get() { throw Error("getter executed"); } });
  const rejectedValues = [undefined, 0.5, -0, 9007199254740992, "\ud800", [ , ], cycle, getter,
    new Date(), invoke("whole", source)];
  for (const value of rejectedValues) {
    const description = invoke("describe", invoke("browserParsed", value));
    check(description.startsWith("error:$"), "invalid JS value or Lean handle accepted");
  }
  return { sourceChars: source.length, expectedVersion, warmupPairs: 1, rows, invalid,
    validJsonCases: validJson.length, rejectedSourceCases: rejectedSources.length,
    rejectedJsCases: rejectedValues.length, fullJsonEquality: true,
    boundary: "same-runtime captured-response replay: JSON.parse + upstream checked JS-to-Lean.Json conversion + existing FromJson Preview; no RPC, React, or DOM",
    numericContract: "producer must validate safe integer domain before JSON serialization; fixture checks original text outside timing",
    instrumentation: "coarse call timers and one Bool conversion marker; no per-node host timers" };
}
