from __future__ import annotations

import argparse
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile

PACKAGE_ROOT = Path(__file__).resolve().parents[1]
TEMPLATE_ROOT = PACKAGE_ROOT / "project_template"

if str(PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(PACKAGE_ROOT))

from scripts.blueprint_harness_project_commands import rewrite_local_blueprint_dependency
from scripts.blueprint_harness_utils import lean_low_priority_command


def run(command: list[str], *, cwd: Path) -> None:
    print(f"[project-template-smoke] $ {shlex.join(command)}", flush=True)
    subprocess.run(command, cwd=cwd, check=True)


def resolve_output_path(path_text: str) -> Path:
    path = Path(path_text)
    if path.is_absolute():
        return path
    return (PACKAGE_ROOT / path).resolve()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Materialize project_template as a fresh standalone repository and run its local CI script.",
    )
    parser.add_argument(
        "--site-output",
        default=None,
        help="Optional path where the generated html-multi site should be copied after a successful run.",
    )
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="verso-blueprint-template-smoke-") as tmp:
        fresh_root = Path(tmp) / "project-template"
        shutil.copytree(TEMPLATE_ROOT, fresh_root)
        rewrite_local_blueprint_dependency(fresh_root, PACKAGE_ROOT)
        run(lean_low_priority_command(PACKAGE_ROOT, "lake", "update", "VersoBlueprint"), cwd=fresh_root)
        run(lean_low_priority_command(PACKAGE_ROOT, "bash", "./scripts/ci-pages.sh"), cwd=fresh_root)

        site_root = fresh_root / "_out" / "site" / "html-multi"
        if not site_root.exists():
            raise SystemExit(f"[project-template-smoke] expected generated site at {site_root}")

        if args.site_output is not None:
            destination = resolve_output_path(args.site_output)
            if destination.exists():
                shutil.rmtree(destination)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(site_root, destination)
            print(f"[project-template-smoke] copied site artifact: {destination}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
