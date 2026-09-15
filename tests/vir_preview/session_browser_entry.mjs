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
      defaultHostBindings: () => createBrowserHostBindings({
        reactHostBindings: createBrowserReactHostBindings,
      }),
    });
    for (let scenario = 0; scenario < 13; scenario++) {
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
    click("debug");
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
    check(byId("timing-scale").value === "0" && Math.abs(width - 240) < 0.05,
      "default 1 ms/tick scale must make 6 ms occupy 240 CSS pixels");
    segments.forEach((segment, index) => check(
      Math.abs(segment.getBoundingClientRect().width - width * (index + 1) / 6) < 0.05,
      "timing segment width is not proportional to duration"));
    const beforeScale = sequence();
    for (const [value, expected] of [["10", 24], ["1000", 0.24], ["100", 2.4]]) {
      setScale(value);
      check(byId("timing-scale").value === value &&
        Math.abs(byId("server-bar").getBoundingClientRect().width - expected) < 0.05,
        `scale ${value} did not change the bar width`);
      check(sequence() === beforeScale && paragraph.isConnected,
        "scale change repeated diagnostic effects or replaced document DOM");
    }
    const unchangedSequence = sequence();
    render(1);
    check(sequence() === unchangedSequence, "unchanged input repeated the diagnostic effect");
    check(paragraph.isConnected, "unchanged input replaced paragraph DOM");

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
    check(!byId("server-bar") && byId("server-timings").textContent.includes("unavailable"),
      "missing timing was displayed as zero or retained from an old response");
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
      missingAndZeroTiming: true, absentClockNotMeasured: true, timingAccountingCases: 13,
      noReactWarnings: true, scope: "explicit Lean fixture inputs, not editor/RPC integration" };
  }, [["React root", unmount], ["VIR runtime", () => runtime?.dispose()],
    ["console", () => { console.error = originalError; console.warn = originalWarn; }]]);
}
