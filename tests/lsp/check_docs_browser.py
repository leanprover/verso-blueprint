"""Browser acceptance for saved LSP results in plain Verso and Blueprint.

Run with the existing tests/browser Playwright environment. No language server
is started by this check or needed by either generated document.
"""

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import shutil
import threading

from playwright.sync_api import expect, sync_playwright


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("documents", type=Path)
    args = parser.parse_args()
    root = args.documents.resolve()
    plan = json.loads((root / "plan.json").read_text())
    code = [request for request in plan if request["kind"] == "code"]
    server = ThreadingHTTPServer(("127.0.0.1", 0), partial(QuietHandler, directory=str(root)))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    results = []
    try:
        with sync_playwright() as playwright:
            executable = shutil.which("google-chrome") or shutil.which("chromium")
            browser = playwright.chromium.launch(executable_path=executable, args=["--no-sandbox"])
            for kind in ("plain", "blueprint"):
                page = browser.new_page(viewport={"width": 1280, "height": 960})
                errors = []
                dialogs = []
                page.on("pageerror", lambda error: errors.append(str(error)))
                page.on("dialog", lambda dialog: (dialogs.append(dialog.message), dialog.dismiss()))
                page.goto(f"http://127.0.0.1:{server.server_port}/{kind}/html-single/index.html")
                panels = page.locator(".lsp-panel code")
                expect(panels).to_have_count(3)
                for index, request in enumerate(code):
                    assert panels.nth(index).text_content() == request["text"]
                expect(page.locator(".lsp-reference")).to_have_count(2)
                expect(page.locator(".lsp-contexts details")).to_have_count(3)
                expect(page.locator(".lsp-contexts")).to_contain_text("compiler checks disabled")
                expect(page.locator(".lsp-diagnostics")).to_contain_text("missing_name")
                expect(page.locator(".lsp-diagnostics")).to_contain_text(
                    f"source line {code[2]['origins'][0]['line'] + 1}")
                assert page.locator("a[href^='file:']").count() == 0
                assert panels.nth(0).locator(".lsp-function").count() > 0
                reference = page.locator(".lsp-reference").nth(0)
                trigger = reference.locator("[data-verso-hover]").first
                page.wait_for_function("el => !!el._tippy", arg=trigger.element_handle())
                trigger.hover()
                tooltip = page.locator("[role=tooltip]:visible")
                expect(tooltip).to_contain_text("pub fn step")
                assert tooltip.locator("img").count() == 0
                target = reference.locator("a").get_attribute("href")
                assert target and target.startswith("#")
                expect(page.locator(target)).to_have_count(1)
                reference.locator("a").click()
                assert page.evaluate("window.location.hash") == target
                rocq = page.locator(".lsp-reference").nth(1).locator("[data-verso-hover]").first
                rocq.focus()
                expect(page.locator("[role=tooltip]:visible").filter(has_text="nat -> nat")).to_have_count(1)
                page.mouse.move(0, 0)
                rocq.evaluate("el => { el.blur(); el._tippy.hide(); }")
                page.evaluate("window.scrollTo(0, 0)")
                page.screenshot(path=str(root / f"{kind}-desktop.png"), full_page=True)
                page.set_viewport_size({"width": 390, "height": 844})
                assert page.evaluate("document.documentElement.scrollWidth <= window.innerWidth + 1")
                page.screenshot(path=str(root / f"{kind}-mobile.png"), full_page=True)
                assert not errors, errors
                assert not dialogs, dialogs
                results.append({"kind": kind, "sourcePreserved": True, "hovers": True,
                                "localNavigation": True, "diagnostics": True, "mobileOverflow": False})
                page.close()
            browser.close()
    finally:
        server.shutdown()
        server.server_close()
    (root / "browser-check.json").write_text(json.dumps(results, indent=2) + "\n")
    print("Plain Verso and Blueprint: offline source, hovers, navigation, diagnostics and mobile layout passed")


if __name__ == "__main__":
    main()
