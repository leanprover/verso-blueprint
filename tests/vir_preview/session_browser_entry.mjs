/* Copyright (c) 2026 Lean FRO LLC. Released under Apache 2.0. */

import * as React from "react";
import { createRoot } from "react-dom/client";
import { createVirRuntime } from "lean-vir";
import { createBrowserHostBindings } from "lean-vir/host-bindings";
import { createBrowserReactHostBindings } from "lean-vir/react-host-bindings";
import { describeError, withCleanup } from "@vir-test-support";

const entry = "VersoBlueprintVirTests.NativeSession";
const check = (value, message) => { if (!value) throw new Error(message); };
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
globalThis.sessionAcceptance = run().then(
  value => ({ ok: true, value }), error => ({ ok: false, error: describeError(error) }));

async function run() {
  let runtime, root;
  let documentRenders = 0;
  let trackedDocument = null, trackedDocumentDecodes = 0;
  const warnings = [];
  const originalError = console.error, originalWarn = console.warn;
  console.error = (...args) => { warnings.push(args.map(String).join(" ")); originalError(...args); };
  console.warn = (...args) => { warnings.push(args.map(String).join(" ")); originalWarn(...args); };
  const unmount = () => {
    if (root) React.act(() => root.unmount());
    root = null;
  };
  return withCleanup(async () => {
    runtime = await createVirRuntime({
      wasmUrl: "/runtime.wasm", irPackageSet: "/widget.irpkg-set.json",
      hostBindings: { "previewDemo.now": () => performance.now() },
      defaultHostBindings: () => {
        const bindings = createBrowserHostBindings({
        reactHostBindings: lifecycle => {
          const bindings = createBrowserReactHostBindings(lifecycle);
          const createElement = bindings["react.node.createElement"];
          bindings["react.node.createElement"] = (type, props, children) => {
            if (props?.id === "vir-verso-document") documentRenders++;
            return createElement(type, props, children);
          };
          return bindings;
        },
        });
        const stringValue = bindings["js.string.value"];
        bindings["js.string.value"] = value => {
          if (value === trackedDocument) trackedDocumentDecodes++;
          return stringValue(value);
        };
        return bindings;
      },
    });
    for (let scenario = 0; scenario < 16; scenario++) {
      check(runtime.call(`${entry}.timingChecks`, scenario) === true,
        `timing partition/correlation scenario ${scenario} failed`);
    }
    const component = runtime.call(`${entry}.createComponent`);
    root = createRoot(document.getElementById("app"));
    const render = scenario => React.act(() => root.render(
      React.createElement(React.StrictMode, null,
        runtime.call(`${entry}.render`, component, scenario))));
    const byId = id => document.getElementById(`vir-verso-${id}`);
    const click = id => React.act(() => byId(id).click());
    const status = () => byId("preview")?.dataset.versoPreviewStatus;
    const panel = () => byId("debug-panel");
    const sequence = () => Number(panel()?.dataset.versoDebugSnapshotEffects);
    const setScale = value => React.act(() => {
      byId("timing-scale").value = value;
      byId("timing-scale").dispatchEvent(new Event("change", { bubbles: true }));
    });

    render(0);
    check(status() === "ready" && byId("preview").textContent.includes("Before edit"),
      "full document did not render");
    check(byId("preview").textContent.includes("Retained informal proof"),
      "Blueprint adapter did not render the informal block");
    check(byId("follow-cursor").checked && !byId("highlight-changes").checked && !panel(),
      "incorrect default options");
    check(!byId("server-timings") && !byId("timing-scale"),
      "timing metrics and scale control must be hidden outside debug mode");
    render(0);
    check(!panel() && byId("preview").dataset.versoChangedBlockCount === "0",
      "unchanged normal input enabled diagnostics or highlighting");
    const checkbox = byId("follow-cursor");
    click("follow-cursor");
    check(byId("preview").dataset.versoFocusBlock === "", "follow-cursor toggle ignored");
    click("highlight-changes");
    render(1);
    check(checkbox === byId("follow-cursor") && !checkbox.checked,
      "document edit lost checkbox identity or state");
    check(byId("preview").dataset.versoChangedBlockCount !== "0", "edit was not highlighted");
    const paragraph = [...document.querySelectorAll("p")].find(p => p.textContent === "After edit");
    const beforeDebug = documentRenders;
    click("debug");
    check(documentRenders - beforeDebug === 2,
      `debug rendered document ${documentRenders - beforeDebug} times; expected only Strict Mode's two calls`);
    check(panel() && paragraph.isConnected, "debug insertion remounted document content");
    check(!byId("debug-disclosure") && document.querySelectorAll("#vir-verso-server-bar").length === 1,
      "debug controls must not hide or duplicate the timing bar");
    check(panel().dataset.versoDebugBrowserTiming === "unavailable" &&
      !panel().hasAttribute("data-verso-debug-browser-ms") && !byId("processing"),
    "pending browser timing was presented as a measurement");
    check(byId("server-timings").textContent.includes("RPC server only 6.0 ms") &&
      panel().dataset.versoDebugNewInput === "false", "option toggle misreported server sample");
    check(byId("timing-boundary").textContent.includes("not total elaboration time"),
      "server-only display did not explain the measurement boundary");
    const bar = byId("server-bar");
    const segments = [...bar.querySelectorAll("[data-verso-phase]")];
    check(bar.getAttribute("role") === "img" &&
      bar.getAttribute("aria-label").includes("Snapshot wait 1.0 ms"), "timing bar lacks a text alternative");
    check(segments.length === 3 && segments.map(s => Number(s.dataset.versoNanos)).join() ===
      "1000000,2000000,3000000", "timing phases differ from the server sample");
    check(new Set(segments.map(s => getComputedStyle(s).backgroundColor)).size === 3,
      "timing phases lack distinct colors");
    const width = bar.getBoundingClientRect().width;
    check(byId("timing-scale").value === "0" &&
      bar.dataset.versoRangeNanos === "10000000" &&
      Math.abs(width / byId("server-scale").clientWidth - 0.6) < 0.01,
      "auto scale must make 6 ms occupy 60% of the available 10 ms ruler");
    segments.forEach((segment, index) => check(
      Math.abs(segment.getBoundingClientRect().width - width * (index + 1) / 6) < 0.05,
      "timing segment width is not proportional to duration"));
    const beforeScale = sequence();
    const beforeScaleRenders = documentRenders;
    for (const [value, expected] of [["10", 24], ["1000", 0.24], ["100", 2.4]]) {
      setScale(value);
      check(byId("timing-scale").value === value &&
        Math.abs(byId("server-bar").getBoundingClientRect().width - expected) < 0.05,
        `scale ${value} did not change the bar width`);
      check(sequence() === beforeScale && paragraph.isConnected,
        "scale change repeated diagnostic effects or replaced document DOM");
      check(documentRenders === beforeScaleRenders, "scale change rebuilt the document");
    }
    const unchangedSequence = sequence();
    render(1);
    check(sequence() === unchangedSequence, "unchanged input repeated the diagnostic effect");
    check(documentRenders === beforeScaleRenders, "unchanged input rebuilt the document");
    check(paragraph.isConnected, "unchanged input replaced paragraph DOM");

    const shell = byId("shell"), content = byId("content");
    check(shell.contains(panel()) && !content.contains(panel()) &&
      content.contains(byId("document")), "debug shell is not outside the document");
    check(getComputedStyle(shell).position === "sticky", "shell is not sticky");
    content.style.minHeight = "2000px";
    window.scrollTo(0, 500);
    check(window.scrollY > 0 && Math.abs(shell.getBoundingClientRect().top) < 1 &&
      content.getBoundingClientRect().top < 0, "shell did not stay on top while content scrolled");
    window.scrollTo(0, 0);
    content.style.minHeight = "";

    for (const [scenario, expected] of [[2, "loading"], [3, "unavailable"], [4, "error"], [5, "ready"]]) {
      render(scenario);
      check(status() === expected, `missing ${expected} transition`);
      check(checkbox === byId("follow-cursor") && !checkbox.checked &&
        byId("highlight-changes").checked && byId("debug").checked,
      `${expected} transition reset options`);
      check(panel().dataset.versoDebugStatus === expected &&
        panel().dataset.versoDebugNewInput === "true", `${expected} diagnostic observation is stale`);
      check(byId("timing-scale").value === "100", `${expected} transition reset the time scale`);
    }
    check(byId("preview").textContent.includes("Recovered preview"), "recovery lost document");
    render(6);
    check(byId("measurement").dataset.versoMeasurementVersion === "3" &&
      panel().dataset.versoDebugVersion === "4",
      "missing timing must keep the explicitly versioned last completed measurement");
    render(7);
    check(byId("server-bar").dataset.versoTotalNanos === "0" &&
      [...byId("server-bar").children].every(s => s.getBoundingClientRect().width === 0),
      "zero timing should have an empty, finite bar");
    click("debug");
    check(!panel() && !byId("server-timings") && !byId("timing-scale"),
      "debug off must hide all timing metrics and controls");
    render(8);
    check(!byId("server-timings"), "an edit restored timing while debug was off");
    click("debug");
    check(byId("timing-scale").value === "100", "debug off/on reset the selected scale");
    const firstWidth = byId("server-bar").getBoundingClientRect().width;
    check(Math.abs(firstWidth - 240) < 0.05, "600 ms must occupy 240 CSS pixels");
    const app = document.getElementById("app");
    app.style.width = "220px";
    render(9);
    check(Math.abs(byId("server-bar").getBoundingClientRect().width - 2 * firstWidth) < 0.05,
      "doubling the time must double the width, including in a narrow panel");
    const scale = byId("server-scale");
    check(scale.scrollWidth > scale.clientWidth && scale.clientWidth <= 220,
      "long timings must overflow the ruler, not widen the panel or rescale");
    scale.scrollLeft = 100;
    check(scale.scrollLeft > 0, "long timings must be horizontally scrollable");
    app.style.width = "";
    setScale("0");
    for (const pixels of [220, 800]) {
      app.style.width = `${pixels}px`;
      const autoBar = byId("server-bar");
      check(autoBar.dataset.versoRangeNanos === "2000000000" &&
        Math.abs(autoBar.getBoundingClientRect().width / byId("server-scale").clientWidth - 0.6) < 0.01,
        "auto scale did not adapt to the available width");
      check(byId("server-scale").scrollWidth <= byId("server-scale").clientWidth + 1,
        "auto ruler overflowed");
    }
    app.style.width = "";
    click("highlight-changes");
    check(panel().dataset.versoDebugBlockCount === "skipped" &&
      !document.querySelector(".vir-verso-block-changed"), "highlighting did not switch off");
    unmount();
    root = createRoot(document.getElementById("app"));
    render(0);
    check(byId("follow-cursor").checked && !byId("highlight-changes").checked && !panel(),
      "intentional remount did not reset session state");
    click("debug");
    check(byId("timing-scale").value === "0", "intentional remount did not reset the scale");
    unmount();

    // Observe every commit, not just the final DOM: a new accepted response must
    // not temporarily pair its server data with an old browser sample or drop
    // to the server-only scale. This also exercises timing-only invalidation.
    const timedComponent = runtime.call(`${entry}.createTimedComponent`);
    root = createRoot(document.getElementById("app"));
    const commits = [];
    const renderTimed = refresh => React.act(() => root.render(
      React.createElement(React.StrictMode, null,
        React.createElement(React.Profiler, { id: "timing", onRender: () => {
          const bar = byId("server-bar");
          if (bar) commits.push({ total: Number(bar.dataset.versoTotalNanos),
            timing: panel().dataset.versoDebugBrowserTiming });
        } }, runtime.call(`${entry}.renderTimed`, timedComponent, refresh)))));
    renderTimed(0);
    click("debug");
    renderTimed(1);
    check(panel().dataset.versoDebugBrowserTiming === "demo-clock" &&
      byId("server-bar").dataset.versoTotalNanos === "80000000", "timed sample did not settle");
    commits.length = 0;
    const beforeRefresh = documentRenders;
    renderTimed(2);
    check(documentRenders - beforeRefresh === 2, "timing-only response rebuilt content more than once per Strict Mode pass");
    check(byId("server-bar").dataset.versoTotalNanos === "80000000", "refresh replaced the completed edit measurement");
    check(commits.length >= 2 && commits.every(c => c.timing === "demo-clock" &&
      c.total === 80000000), "debug bar displayed an incomplete sample during refresh");
    const beforeTimedScale = documentRenders;
    setScale("10");
    check(documentRenders === beforeTimedScale &&
      byId("server-bar").dataset.versoTotalNanos === "80000000", "scale change rebuilt or remeasured content");
    click("highlight-changes");
    check(byId("server-bar").dataset.versoTotalNanos === "80000000", "highlight control discarded the completed measurement");
    unmount();
    const encodedComponent = runtime.call(`${entry}.createEncodedDocumentComponent`);
    root = createRoot(document.getElementById("app"));
    const renderEncoded = scenario => React.act(() => root.render(
      React.createElement(React.StrictMode, null, React.createElement(encodedComponent,
        { document: runtime.call(`${entry}.encodedDocument`, scenario) }))));
    renderEncoded(0);
    click("highlight-changes");
    click("follow-cursor");
    const encodedArticle = document.getElementById("vir-verso-document");
    const encodedRenders = documentRenders;
    renderEncoded(0);
    check(documentRenders === encodedRenders, "unchanged document String rebuilt content");
    renderEncoded(1);
    check(document.getElementById("vir-verso-document") === encodedArticle &&
      byId("highlight-changes").checked && !byId("follow-cursor").checked,
      "native String update lost document/options identity");
    check(document.querySelector('.vir-verso-block-changed') &&
      !document.querySelector('.vir-verso-block-focused'),
      "native String options did not reach the renderer");
    renderEncoded(2);
    check(document.querySelector('[data-verso-preview-status="error"]'),
      "malformed document String did not display an error");
    renderEncoded(1);
    check(byId("highlight-changes").checked && !byId("follow-cursor").checked,
      "decode error recovery lost options");
    unmount();
    const timedEncoded = runtime.call(`${entry}.createTimedEncodedDocumentComponent`);
    const timedDocument = runtime.call(`${entry}.encodedDocument`, 0);
    trackedDocument = timedDocument;
    root = createRoot(document.getElementById("app"));
    const renderTimedEncoded = (requestedMs, receivedMs) => React.act(() => root.render(
      React.createElement(React.StrictMode, null, React.createElement(timedEncoded,
        { document: timedDocument, requestedMs, receivedMs }))));
    renderTimedEncoded(10, 20);
    const initialNativeDecodes = trackedDocumentDecodes;
    check(initialNativeDecodes > 0, "native decode guard did not observe its String");
    click("debug");
    // Diagnostics start with the next accepted response, not a retroactive
    // observation of the mount that ran with debug disabled.
    renderTimedEncoded(10, 25);
    check(byId("server-bar").dataset.versoTotalNanos === "90000000",
      "encoded document boundary did not connect native RPC/browser timings");
    const nativeTimedArticle = byId("document");
    const beforeNativeSame = documentRenders;
    renderTimedEncoded(10, 25);
    check(documentRenders === beforeNativeSame,
      "unchanged native timing props rebuilt content");
    renderTimedEncoded(15, 30);
    check(byId("server-bar").dataset.versoTotalNanos === "90000000" &&
      byId("document") === nativeTimedArticle && byId("debug").checked,
      "timing-only native props lost coherent sample, DOM or controls");
    const beforeNativeScale = documentRenders;
    setScale("10");
    check(documentRenders === beforeNativeScale &&
      byId("server-bar").dataset.versoTotalNanos === "90000000",
      "native scale update rebuilt content or changed its timestamp");
    renderTimedEncoded(undefined, undefined);
    check(panel().dataset.versoDebugBrowserTiming === "demo-clock" &&
      byId("server-bar").dataset.versoTotalNanos === "90000000",
      "absent timing props discarded the explicitly retained measurement");
    check(trackedDocumentDecodes === initialNativeDecodes,
      "timing/control-only native updates decoded the unchanged document again");
    unmount();
    runtime.dispose();
    let rejected = false;
    try { runtime.call(`${entry}.createComponent`); } catch { rejected = true; }
    check(rejected, "runtime accepted a call after disposal");
    runtime = null;
    check(warnings.length === 0, `React/browser warnings: ${warnings.join("\n")}`);
    return { strictMode: true, fullManualInput: true, blueprintAdapter: true,
      retainedOptions: true, debugInsertionKeepsDocument: true,
      unchangedInputNoEffect: true, statusTransitions: 4, intentionalRemountResets: true,
      postDisposalRejected: true, serverTimingDisplay: true, proportionalTimingBar: true,
      debugOnlyTiming: true, selectableTimeScale: true, retainedScale: true,
      fixedTimeScale: true, scrollableLongTiming: true,
      missingAndZeroTiming: true, retainedMeasurementVersion: true, timingAccountingCases: 16,
      documentRenderCounts: true, shellOnlyUpdatesSkipDocument: true,
      stickyShellOutsideDocument: true, responsiveAutoScale: true,
      coherentCompletedSamples: true, timingOnlyResponseRefresh: true,
      nativeDocumentStringOptions: true, nativeDocumentStringErrorRecovery: true,
      nativeDocumentStringTiming: true, nativeTimingOnlyUpdate: true,
      nativeTimingUpdatesSkipDecode: true,
      noReactWarnings: true, scope: "explicit Lean fixture inputs, not editor/RPC integration" };
  }, [["React root", unmount], ["VIR runtime", () => runtime?.dispose()],
    ["console", () => { console.error = originalError; console.warn = originalWarn; }]]);
}
