// Exercise the persistent demo using the existing VIR Chromium driver.
// Usage: node fir_demo_smoke.mjs URL PREPARED_VBP OUTPUT
import assert from "node:assert/strict";
import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

assert.equal(process.argv.length, 5, "expected URL PREPARED_VBP OUTPUT");
const [url, prepared, output] = process.argv.slice(2);
const vir = resolve(prepared, ".lake/packages/lean_vir");
const { launchChromium, openChromiumPage, navigate, evaluate } = await import(pathToFileURL(resolve(vir, "tests/browser/harness.mjs")));
const { withCleanup } = await import(pathToFileURL(resolve(vir, "tests/infoview/rpc-test-support.js")));
await mkdir(output, { recursive: false });
let chrome, cdp;
await withCleanup(async () => {
  chrome = await launchChromium();
  cdp = await openChromiumPage(chrome);
  await navigate(cdp, url);
  const ready = await evaluate(cdp, `(async () => {
    for (let i = 0; i < 100; i++) {
      const article = document.querySelector("#fir-demo-preview article");
      if (article) { globalThis.demoArticle = article; return true; }
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    return document.body.textContent;
  })()`);
  assert.equal(ready, true);
  const changed = await evaluate(cdp, `(async () => {
    const input = document.getElementById("fir-demo-title");
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set.call(input, "Live FIR λ — edited");
    input.dispatchEvent(new Event("input", { bubbles: true }));
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    document.getElementById("fir-demo-callback").click();
    await new Promise(resolve => requestAnimationFrame(resolve));
    return {
      retained: globalThis.demoArticle === document.querySelector("#fir-demo-preview article"),
      title: document.querySelector("#fir-demo-preview h1").textContent,
      status: document.getElementById("fir-demo-state").textContent
    };
  })()`);
  assert.equal(changed.retained, true);
  assert.equal(changed.title, "Live FIR λ — edited");
  assert.match(changed.status, /Updates in this session: 1\..*retained Lean callback is alive/);
  const screenshot = await cdp.send("Page.captureScreenshot", { format: "png" });
  await writeFile(resolve(output, "demo.png"), Buffer.from(screenshot.data, "base64"));
  const closed = await evaluate(cdp, `(async () => {
    document.getElementById("fir-demo-close").click();
    await new Promise(resolve => requestAnimationFrame(resolve));
    return { children: document.getElementById("app").childNodes.length,
      status: document.getElementById("status").textContent };
  })()`);
  assert.equal(closed.children, 0);
  assert.match(closed.status, /unmounted; FIR session disposed/);
  await writeFile(resolve(output, "result.json"), JSON.stringify({ url, changed, closed }, null, 2));
  console.log("FIR demo edit, retained DOM, callback and close checks passed");
}, [["CDP", () => cdp?.close()], ["Chromium", () => chrome?.close()]]);
