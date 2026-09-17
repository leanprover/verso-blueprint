import assert from "node:assert/strict";
import test from "node:test";
import { configureDemoShell, configureNativeComponentShell } from "./demo_shell.mjs";

const shell = `
async function openService() {
  const runtimeOptions = {};
  runtimeOptions.defaultHostBindings = () => ({});
  return {
    runtime: await createBundledVirRuntime(runtimeOptions),
  };
}
function disposeService(service) {
    service.runtime.dispose?.();
}
function renderStyle(loaded, configurationKey) {
  return [
    loaded?.configurationKey === configurationKey
  ];
}
`;
const assets = { bridge: "/bridge.mjs", math: "/math.mjs", katex: "/katex.mjs", mathCss: "font-css" };
const configured = fir => configureDemoShell(shell, fir, assets);
const executable = (source, names, values) => new Function(...names,
  source.replace(/^import .*;\n/gm, "") + "\nreturn { openService, disposeService };")(...values);

test("matched native view uses one provider and disposes after the shell", async () => {
  const order = [], Component = () => {};
  const native = { Component, dispose() { order.push("view"); } };
  let options;
  const source = configureNativeComponentShell(shell, {
    module: "@matched-demo", open: "openMatchedDemo", binding: "previewDemo.matchedComponent",
  });
  const service = executable(source, ["openNativePreview", "createBundledVirRuntime"], [
    async () => native, async value => { options = value; return { dispose() { order.push("shell"); } }; },
  ]);
  const opened = await service.openService();
  assert.equal(options.hostBindings["previewDemo.matchedComponent"](), Component);
  service.disposeService(opened);
  assert.deepEqual(order, ["shell", "view"]);
});

test("FIR exposes one native component without VIR document codecs/math/clock", async () => {
  let opens = 0, options;
  const Component = () => {};
  const fir = { Component, dispose() {} };
  const source = configured(true);
  for (const absent of ["JSON.parse", "performance.now", "createMathComponent", "data-verso-math-styles"])
    assert.ok(!source.includes(absent), absent);
  const service = executable(source, ["openNativePreview", "createBundledVirRuntime"], [
    async () => { opens++; return fir; },
    async value => { options = value; return {}; },
  ]);
  assert.equal((await service.openService()).nativePreview, fir);
  assert.equal(opens, 1);
  assert.deepEqual(Object.keys(options.hostBindings), ["previewDemo.componentFir"]);
  assert.equal(options.hostBindings["previewDemo.componentFir"](), Component);
});

test("FIR is released when opening the shell runtime fails", async () => {
  let disposed = 0;
  const error = new Error("runtime failed");
  const service = executable(configured(true), ["openNativePreview", "createBundledVirRuntime"], [
    async () => ({ dispose() { disposed++; } }),
    async () => { throw error; },
  ]);
  await assert.rejects(service.openService(), value => value === error);
  assert.equal(disposed, 1);
});

for (const throws of [false, true]) test(`dispose shell before FIR, including shell failure=${throws}`, () => {
  const order = [], error = new Error("dispose failed");
  const service = executable(configured(true), ["openNativePreview", "createBundledVirRuntime"], []);
  const resource = {
    runtime: { dispose() { order.push("shell"); if (throws) throw error; } },
    nativePreview: { dispose() { order.push("FIR"); } },
  };
  if (throws) assert.throws(() => service.disposeService(resource), value => value === error);
  else service.disposeService(resource);
  assert.deepEqual(order, ["shell", "FIR"]);
});

test("VIR preserves explicit codecs, native clock/math, and one stylesheet", async () => {
  let options;
  const Formula = () => {};
  const service = executable(configured(false), [
    "createJsonValueHostBindings", "createMathComponent", "katex", "performance", "createBundledVirRuntime",
  ], [() => ({ codec: true }), () => Formula, {}, { now: () => 42 },
    async value => { options = value; return {}; }]);
  await service.openService();
  assert.equal(options.hostBindings.codec, true);
  assert.equal(options.hostBindings["previewDemo.now"](), 42);
  assert.equal(options.hostBindings["previewDemo.mathComponent"](), Formula);
  assert.deepEqual(options.hostBindings["previewDemo.parse"]('{"value":7}'), { value: 7 });
  assert.throws(() => options.hostBindings["previewDemo.parse"]({}), TypeError);
  assert.throws(() => options.hostBindings["previewDemo.parse"]("{"), SyntaxError);
  assert.equal(configured(false).split('"data-verso-math-styles"').length, 2);
  assert.ok(!configured(false).includes("openFirDemo"));
});

test("missing or repeated upstream seams fail closed", () => {
  for (const [fir, sites] of [
    [true, ["  runtimeOptions.defaultHostBindings = () =>",
      "    runtime: await createBundledVirRuntime(runtimeOptions),", "    service.runtime.dispose?.();"]],
    [false, ["  runtimeOptions.defaultHostBindings = () =>", "    loaded?.configurationKey === configurationKey"]],
  ]) for (const site of sites) {
    assert.throws(() => configureDemoShell(shell.replace(site, "changed"), fir, assets), /upstream shell drift/);
    assert.throws(() => configureDemoShell(shell + site, fir, assets), /upstream shell drift/);
  }
});
