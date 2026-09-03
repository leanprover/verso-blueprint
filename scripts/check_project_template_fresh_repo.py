from __future__ import annotations

import argparse
import json
from pathlib import Path
import secrets
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


def run_capture(command: list[str], *, cwd: Path) -> str:
    print(f"[project-template-smoke] $ {shlex.join(command)}", flush=True)
    result = subprocess.run(
        command,
        cwd=cwd,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    print(result.stdout, end="")
    return result.stdout


def parse_json_output(output: str) -> dict[str, object]:
    for line in reversed(output.splitlines()):
        if line.startswith("{"):
            return json.loads(line)
    raise SystemExit("[project-template-smoke] command produced no JSON object")


def generated_site_contains(site_root: Path, text: str) -> bool:
    normalized_text = " ".join(text.split())
    return any(
        normalized_text in " ".join(path.read_text(errors="replace").split())
        for path in site_root.rglob("*.html")
    )


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
        run(lean_low_priority_command(PACKAGE_ROOT, "lake", "exe", "vbp", "discover"), cwd=fresh_root)
        run(lean_low_priority_command(PACKAGE_ROOT, "bash", "./scripts/ci-pages.sh"), cwd=fresh_root)

        site_root = fresh_root / "_out" / "site" / "html-multi"
        if not site_root.exists():
            raise SystemExit(f"[project-template-smoke] expected generated site at {site_root}")

        node_output = run_capture(
            lean_low_priority_command(PACKAGE_ROOT, "lake", "exe", "vbp", "query", "node", "addition_spec"),
            cwd=fresh_root,
        )
        if "addition_spec" not in node_output:
            raise SystemExit("[project-template-smoke] expected addition_spec in generated manifest")
        code_node_output = run_capture(
            lean_low_priority_command(
                PACKAGE_ROOT,
                "lake",
                "exe",
                "vbp",
                "query",
                "node",
                "multiplication_one_right",
            ),
            cwd=fresh_root,
        )
        code_node = parse_json_output(code_node_output)
        expected_code_keys = ["Informal.LeanCodePreview.Inline.multiplication_one_right"]
        if code_node.get("leanCodePreviewKeys") != expected_code_keys:
            raise SystemExit(
                "[project-template-smoke] imported chapter lost its Lean code preview metadata",
            )
        uses_output = run_capture(
            lean_low_priority_command(PACKAGE_ROOT, "lake", "exe", "vbp", "query", "uses", "collatz_step"),
            cwd=fresh_root,
        )
        for dependency in ("addition_spec", "multiplication_spec"):
            if dependency not in uses_output:
                raise SystemExit(
                    f"[project-template-smoke] collatz_step is missing dependency {dependency}",
                )
        run(lean_low_priority_command(PACKAGE_ROOT, "lake", "exe", "vbp", "check"), cwd=fresh_root)

        addition_source = fresh_root / "ProjectTemplate" / "Chapters" / "Addition.lean"
        original_addition = addition_source.read_text()
        original_text = "This starter Blueprint begins with the most basic sanity checks around that\noperation."
        nonce = secrets.token_hex(8)
        incremental_text = (
            "This incremental module check rebuilt the edited chapter without rebuilding\n"
            f"unrelated chapters. Probe: {nonce}."
        )
        if original_text not in original_addition:
            raise SystemExit("[project-template-smoke] incremental-edit source marker is missing")

        addition_source.write_text(original_addition.replace(original_text, incremental_text, 1))
        incremental_output = run_capture(
            lean_low_priority_command(PACKAGE_ROOT, "bash", "./scripts/ci-pages.sh"),
            cwd=fresh_root,
        )
        if "ProjectTemplate.Chapters.Addition" not in incremental_output:
            raise SystemExit("[project-template-smoke] edited Addition chapter was not rebuilt")
        for untouched_module in (
            "ProjectTemplate.Chapters.Multiplication",
            "ProjectTemplate.Chapters.Collatz",
        ):
            if untouched_module in incremental_output:
                raise SystemExit(
                    f"[project-template-smoke] incremental edit rebuilt unrelated module {untouched_module}",
                )
        if not generated_site_contains(site_root, incremental_text):
            raise SystemExit("[project-template-smoke] incremental edit did not reach generated HTML")
        run(lean_low_priority_command(PACKAGE_ROOT, "lake", "exe", "vbp", "check"), cwd=fresh_root)

        addition_source.write_text(original_addition)
        run(lean_low_priority_command(PACKAGE_ROOT, "bash", "./scripts/ci-pages.sh"), cwd=fresh_root)
        if generated_site_contains(site_root, incremental_text):
            raise SystemExit("[project-template-smoke] restored source left incremental text in generated HTML")

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
