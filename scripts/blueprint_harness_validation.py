from __future__ import annotations

from pathlib import Path
import shutil
import sys


UV_CACHE_DIR = "/tmp/verso-blueprint-uv-cache"


def resolve_package_relative_path(package_root: Path, path_text: str) -> Path:
    path = Path(path_text)
    if path.is_absolute():
        return path
    return package_root / path


def panel_regression_command(package_root: Path, script_path: str, site_dir: Path) -> list[str]:
    return [
        sys.executable,
        str(resolve_package_relative_path(package_root, script_path)),
        "--site-dir",
        str(site_dir),
    ]


def browser_test_command(
    package_root: Path,
    tests_path_text: str,
    site_dir: Path,
    pytest_args: list[str],
) -> list[str]:
    tests_path = resolve_package_relative_path(package_root, tests_path_text)
    if shutil.which("uv") is not None:
        command = [
            "env",
            f"UV_CACHE_DIR={UV_CACHE_DIR}",
            "uv",
            "run",
            "--project",
            str(tests_path),
            "--extra",
            "test",
            "python",
            "-m",
            "pytest",
        ]
    else:
        command = [sys.executable, "-m", "pytest"]
    return [
        *command,
        str(tests_path),
        "-q",
        "--browser",
        "chromium",
        "--site-dir",
        str(site_dir),
        *pytest_args,
    ]
