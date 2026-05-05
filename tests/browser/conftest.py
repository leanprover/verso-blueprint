import json
import pytest
import random
import shutil
import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path
from playwright.sync_api import sync_playwright

PACKAGE_ROOT = Path(__file__).resolve().parents[2]
if str(PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(PACKAGE_ROOT))

from scripts.blueprint_harness_paths import (
    canonical_test_blueprint_output_dir,
    default_test_blueprint_site_dir,
)


DEFAULT_TEST_BLUEPRINT = "preview_runtime_showcase"

def default_site_dir() -> Path:
    return default_test_blueprint_site_dir(DEFAULT_TEST_BLUEPRINT, Path(__file__))


DEFAULT_SITE_DIR = default_site_dir()


def find_free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def browser_executable(browser_type: str) -> str | None:
    candidates = {
        "chromium": ["chromium", "chromium-browser", "google-chrome"],
        "firefox": ["firefox"],
    }.get(browser_type, [])
    for candidate in candidates:
        path = shutil.which(candidate)
        if path:
            return path
    return None


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


def load_redirects(site_dir: str | Path):
    json_path = Path(site_dir)
    if not json_path.is_absolute():
        json_path = (Path(__file__).parent / json_path).resolve()
    json_path = json_path / "xref.json"
    with open(json_path) as f:
        data = json.load(f)

    sections = data["Verso.Genre.Manual.section"]["contents"]
    return [(s, sections[s][0]["address"] + "#" + sections[s][0]["id"]) for s in sections]


def build_test_blueprint_site(name: str) -> Path:
    output_dir = canonical_test_blueprint_output_dir(name, Path(__file__))
    output_dir.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            sys.executable,
            "-m",
            "scripts.blueprint_test_blueprints",
            "generate",
            name,
            str(output_dir),
        ],
        cwd=PACKAGE_ROOT,
        check=True,
    )
    return output_dir / "html-multi"


def pytest_addoption(parser):
    parser.addoption(
        "--test-blueprint",
        action="store",
        default=DEFAULT_TEST_BLUEPRINT,
        help="Named in-repo test blueprint to build and serve by default",
    )
    parser.addoption(
        "--port",
        action="store",
        default=None,
        help="Port for the local test server (default: auto-select)",
    )
    parser.addoption(
        "--site-dir",
        action="store",
        default=None,
        help="Path to the built site directory (overrides --test-blueprint)",
    )
    parser.addoption(
        "--server-url",
        action="store",
        default=None,
        help="Use an existing server instead of starting one (e.g., http://localhost:3000)",
    )
    parser.addoption(
        "--seed",
        action="store",
        default=None,
        type=int,
        help="Random seed for reproducible redirect selection",
    )


def pytest_configure(config):
    seed = config.getoption("--seed")
    if seed is not None:
        random.seed(seed)


@pytest.fixture(scope="session")
def server(request):
    external_url = request.config.getoption("--server-url")

    if external_url:
        yield external_url
        return

    site_dir = request.config.getoption("--site-dir")
    if site_dir is None:
        site_dir = build_test_blueprint_site(request.config.getoption("--test-blueprint"))
    else:
        site_dir = Path(site_dir)
        if not site_dir.is_absolute():
            site_dir = (Path(__file__).parent / site_dir).resolve()
    port = request.config.getoption("--port")

    if port is None:
        port = find_free_port()
    else:
        port = int(port)

    proc = subprocess.Popen(
        [sys.executable, "-m", "http.server", str(port), "--bind", "127.0.0.1"],
        cwd=site_dir,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    server_url = f"http://127.0.0.1:{port}"
    wait_for_server(server_url, proc)
    yield server_url
    proc.terminate()
    proc.wait()


@pytest.fixture(scope="session")
def playwright_instance():
    with sync_playwright() as p:
        yield p


@pytest.fixture(scope="session", params=["chromium", "firefox"])
def browser(request, playwright_instance):
    browser_type = request.param
    selected = request.config.getoption("browser")
    if isinstance(selected, (list, tuple, set)):
        selected_browsers = set(selected)
    elif selected in (None, ""):
        selected_browsers = {"chromium"}
    else:
        selected_browsers = {selected}
    if browser_type not in selected_browsers:
        pytest.skip(f"browser {browser_type} not selected")
    launcher = getattr(playwright_instance, browser_type)
    try:
        browser = launcher.launch()
    except Exception as err:
        executable = browser_executable(browser_type)
        if executable is None:
            pytest.skip(f"no Playwright-managed or system browser available for {browser_type}: {err}")
        browser = launcher.launch(executable_path=executable)
    yield browser
    browser.close()


@pytest.fixture
def page(browser):
    page = browser.new_page()
    yield page
    page.close()
