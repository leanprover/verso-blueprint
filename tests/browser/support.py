from __future__ import annotations

import socket
import subprocess
import time
import urllib.request
from pathlib import Path

from playwright.sync_api import Page


PACKAGE_ROOT = Path(__file__).resolve().parents[2]


def find_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def wait_for_server(url: str, proc: subprocess.Popen[bytes], timeout_s: float = 10.0) -> None:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        if proc.poll() is not None:
            raise RuntimeError(f"local test server exited early with code {proc.returncode}")
        try:
            with urllib.request.urlopen(url):
                return
        except OSError:
            time.sleep(0.1)
    raise RuntimeError(f"timed out waiting for local test server at {url}")


def record_runtime_errors(page: Page) -> list[str]:
    errors: list[str] = []

    page.on("pageerror", lambda exc: errors.append(str(exc)))

    def on_console(msg) -> None:
        if msg.type == "error":
            errors.append(msg.text)

    page.on("console", on_console)
    return errors


def assert_no_runtime_errors(errors: list[str]) -> None:
    relevant = [
        err
        for err in errors
        if "cancelChildHide" in err or "ReferenceError" in err or "Uncaught" in err
    ]
    assert not relevant, "\n".join(relevant)


def blueprint_render_api_script(body: str) -> str:
    return f"""
    async () => {{
        async function loadBlueprintRenderApi() {{
            const moduleUrl = new URL(
                "-verso-data/blueprint-page-runtime.mjs",
                document.baseURI
            ).href;
            const runtime = await import(moduleUrl);
            if (runtime && runtime.blueprintPageRuntime) {{
                return runtime.blueprintPageRuntime;
            }}
            throw new Error("Blueprint page runtime did not expose a render API");
        }}
        const api = await loadBlueprintRenderApi();
        {body}
    }}
    """


def wait_for_blueprint_render_api(page: Page) -> None:
    page.evaluate(blueprint_render_api_script("return true;"))
