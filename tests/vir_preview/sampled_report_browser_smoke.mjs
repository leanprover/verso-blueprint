/* Verify the generated report with the existing disposable Chromium harness. */
import assert from "node:assert/strict";
import { writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { launchChromium, openChromiumPage, navigate, evaluate } from
  "../../.lake/packages/lean_vir/tests/browser/harness.mjs";

const [url, capture] = process.argv.slice(2);
assert.ok(url && capture, "usage: sampled_report_browser_smoke.mjs URL CAPTURE");
const chrome = await launchChromium();
let cdp;
try {
  cdp = await openChromiumPage(chrome);
  await cdp.send("Emulation.setDeviceMetricsOverride", {
    width: 1600, height: 1200, deviceScaleFactor: 1, mobile: false,
  });
  await navigate(cdp, url);
  const initial = await evaluate(cdp, `({ title: document.title,
    frames: document.querySelector('#server object').contentDocument?.querySelectorAll('#frames > g').length,
    overflow: document.documentElement.scrollWidth > innerWidth })`);
  assert.ok(initial.frames > 0, JSON.stringify(initial));
  assert.equal(initial.overflow, false);
  const browser = await evaluate(cdp, `(async () => {
    const select = document.getElementById('profile');
    select.value = 'browser-active'; select.dispatchEvent(new Event('change'));
    const object = document.querySelector('#browser-active object');
    if (object.contentDocument?.documentElement?.localName !== 'svg') {
      await new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(Error('SVG load timeout')), 10000);
        object.addEventListener('load', () => { clearTimeout(timer); resolve(); }, {once:true});
      });
    }
    const doc = object.contentDocument;
    const frame = [...doc.querySelectorAll('#frames > g')].find(g =>
      g.querySelector('title')?.textContent.includes('renderWithHooks '));
    if (!frame) throw Error('React stack missing');
    frame.querySelector('rect').dispatchEvent(new MouseEvent('click', {bubbles:true}));
    const zoomed = !doc.getElementById('unzoom').classList.contains('hide');
    doc.getElementById('unzoom').dispatchEvent(new MouseEvent('click', {bubbles:true}));
    // Exercise the renderer's search operation without an interactive prompt.
    object.contentWindow.search('renderWithHooks');
    return { visible: [...document.querySelectorAll('.graph')].filter(g => !g.hidden).map(g => g.id),
      frames: doc.querySelectorAll('#frames > g').length, zoomed,
      namedWasm: [...doc.querySelectorAll('#frames > g > title')].some(t => t.textContent.includes('interpreter::call(')),
      unnamedWasm: [...doc.querySelectorAll('#frames > g > title')].some(t => t.textContent.includes('wasm-function[')),
      search: doc.getElementById('matched').textContent };
  })()`);
  assert.deepEqual(browser.visible, ["browser-active"]);
  assert.equal(browser.zoomed, true);
  assert.equal(browser.namedWasm, true);
  assert.equal(browser.unnamedWasm, false);
  assert.match(browser.search, /Matched:/);
  const sliced = await evaluate(cdp, `(async () => {
    const select = document.getElementById('profile');
    const counts = {};
    for (const id of ['server-until-reply', 'server-until-dom', 'server-after-dom']) {
      select.value = id; select.dispatchEvent(new Event('change'));
      const object = document.querySelector('#' + id + ' object');
      if (object.contentDocument?.documentElement?.localName !== 'svg') {
        await new Promise((resolve, reject) => {
          const timer = setTimeout(() => reject(Error('slice load timeout')), 10000);
          object.addEventListener('load', () => { clearTimeout(timer); resolve(); }, {once:true});
        });
      }
      if (document.querySelectorAll('.graph:not([hidden])').length !== 1) throw Error('slice visibility');
      counts[id] = object.contentDocument.querySelectorAll('#frames > g').length;
    }
    select.value = 'browser-active'; select.dispatchEvent(new Event('change'));
    return counts;
  })()`);
  for (const count of Object.values(sliced)) assert.ok(count > 0);
  const timeline = await evaluate(cdp, `(async () => {
    const data = await (await fetch('timeline-data.json')).json();
    const end = data.milestones.diagnosticsMs;
    const expected = [...data.nativePoints, ...data.browserPoints].filter(p => p.timeMs >= 0 && p.timeMs <= end).length;
    const actual = document.querySelectorAll('#ownership-timeline .cpu-sample').length;
    const titled = document.querySelectorAll('#ownership-timeline .cpu-sample title').length;
    return { expected, actual, titled, phaseTable: document.querySelector('#timeline table').rows.length };
  })()`);
  assert.equal(timeline.actual, timeline.expected);
  assert.equal(timeline.titled, timeline.actual);
  assert.equal(timeline.phaseTable, 10);
  const screenshot = await cdp.send("Page.captureScreenshot", { format: "png" });
  await writeFile(resolve(capture, "viewer.png"), Buffer.from(screenshot.data, "base64"));
  await evaluate(cdp, "document.getElementById('timeline').scrollIntoView()");
  const timelineScreenshot = await cdp.send("Page.captureScreenshot", { format: "png" });
  await writeFile(resolve(capture, "timeline.png"), Buffer.from(timelineScreenshot.data, "base64"));
  await writeFile(resolve(capture, "viewer-check.json"), JSON.stringify({ initial, browser, sliced, timeline }, null, 2));
  console.log(JSON.stringify({ initial, browser, sliced, timeline }, null, 2));
} finally {
  cdp?.close();
  await chrome.close();
}
