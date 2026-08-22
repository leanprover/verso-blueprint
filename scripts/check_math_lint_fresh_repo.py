from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import shlex
import re
import subprocess
import sys
import tempfile

PACKAGE_ROOT = Path(__file__).resolve().parents[1]

if str(PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(PACKAGE_ROOT))

from scripts.blueprint_harness_utils import lean_low_priority_command

SMOKE_SOURCE = """import Verso
import VersoManual
import VersoBlueprint

open Verso.Genre
open Verso.Genre.Manual
open Informal

__CASE_IDENTITY__

#eval show IO Unit from do
  let result ← Informal.MathLint.lint? {
    mode := .inline
    source := r#"\\undefinedmacro"#
  }
  match result with
  | some failure =>
      IO.println s!"FAILURE: {failure.reason}"
  | none =>
      IO.println "NO_FAILURE"

#doc (Manual) "Introduction" =>

:::theorem "bad_math"
This has invalid math $`\\definitelynotacommand` inside the statement.
:::
"""


@dataclass(frozen=True)
class Case:
    name: str
    packages_dir: str | None = None


CASES = (
    Case(name="default"),
    Case(name="alt-packages-dir", packages_dir="vendor/packages"),
)


def run(command: list[str], *, cwd: Path, expect: int | None = 0) -> subprocess.CompletedProcess[str]:
    print(f"[math-lint-smoke] $ {shlex.join(command)}", flush=True)
    result = subprocess.run(
        command,
        cwd=cwd,
        check=False,
        text=True,
        capture_output=True,
    )
    if expect is not None and result.returncode != expect:
        raise SystemExit(
            f"[math-lint-smoke] expected exit code {expect}, got {result.returncode}\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )
    return result


def combined_output(result: subprocess.CompletedProcess[str]) -> str:
    return result.stdout + result.stderr


def require_substring(result: subprocess.CompletedProcess[str], needle: str, *, context: str) -> None:
    haystack = combined_output(result)
    if needle not in haystack:
        raise SystemExit(
            f"[math-lint-smoke] missing expected text for {context}: {needle!r}\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )


def ensure_node_available() -> None:
    result = run(["node", "--version"], cwd=PACKAGE_ROOT)
    if result.returncode != 0:
        raise SystemExit("[math-lint-smoke] expected a working `node` command")


def current_repo_head() -> str:
    result = run(["git", "rev-parse", "HEAD"], cwd=PACKAGE_ROOT)
    return result.stdout.strip()


def current_lean_toolchain() -> str:
    return (PACKAGE_ROOT / "lean-toolchain").read_text(encoding="utf-8")


def current_verso_require_line() -> str:
    text = (PACKAGE_ROOT / "lakefile.lean").read_text(encoding="utf-8")
    match = re.search(r"^\s*require\s+verso\s+from\s+.+$", text, flags=re.MULTILINE)
    if match is None:
        raise SystemExit("[math-lint-smoke] could not find a `require verso ...` line in the current lakefile")
    return match.group(0)


def package_lakefile_text(
    *,
    verso_require_line: str,
    blueprint_repo_url: str,
    blueprint_ref: str,
    packages_dir: str | None,
) -> str:
    config_lines = [
        "package Smoke where",
        "  precompileModules := false",
        "  leanOptions := #[⟨`experimental.module, true⟩]",
    ]
    if packages_dir is not None:
        config_lines.append(f'  packagesDir := "{packages_dir}"')
    return "\n".join(
        [
            "import Lake",
            "open Lake DSL",
            "",
            verso_require_line,
            f'require VersoBlueprint from git "{blueprint_repo_url}"@"{blueprint_ref}"',
            "",
            *config_lines,
            "",
            "@[default_target]",
            "lean_lib Smoke where",
            "",
        ]
    )


def materialize_case(
    workspace: Path,
    case: Case,
    *,
    lean_toolchain: str,
    verso_require_line: str,
    blueprint_repo_url: str,
    blueprint_ref: str,
) -> Path:
    project_dir = workspace / case.name
    project_dir.mkdir(parents=True, exist_ok=True)
    (project_dir / "lean-toolchain").write_text(lean_toolchain, encoding="utf-8")
    (project_dir / "lakefile.lean").write_text(
        package_lakefile_text(
            verso_require_line=verso_require_line,
            blueprint_repo_url=blueprint_repo_url,
            blueprint_ref=blueprint_ref,
            packages_dir=case.packages_dir,
        ),
        encoding="utf-8",
    )
    # Keep each source distinct so the shared artifact cache cannot replay the
    # consumer module from an earlier layout instead of exercising elaboration.
    case_identity = f"{project_dir.parent.name}-{case.name}"
    smoke_source = SMOKE_SOURCE.replace(
        "__CASE_IDENTITY__",
        f'def smokeCaseIdentity : String := "{case_identity}"',
    )
    (project_dir / "Smoke.lean").write_text(smoke_source, encoding="utf-8")
    return project_dir


def expected_packages_root(project_dir: Path, case: Case) -> Path:
    if case.packages_dir is None:
        return project_dir / ".lake" / "packages"
    return project_dir / Path(case.packages_dir)


def run_case(project_dir: Path, case: Case) -> None:
    update = run(
        lean_low_priority_command(PACKAGE_ROOT, "lake", "update", "VersoBlueprint"),
        cwd=project_dir,
    )
    require_substring(update, "VersoBlueprint", context=f"{case.name} lake update")

    packages_root = expected_packages_root(project_dir, case)
    blueprint_dep = packages_root / "VersoBlueprint"
    if not blueprint_dep.exists():
        raise SystemExit(f"[math-lint-smoke] expected dependency checkout at {blueprint_dep}")
    default_blueprint_dep = project_dir / ".lake" / "packages" / "VersoBlueprint"
    if case.packages_dir is not None and default_blueprint_dep.exists():
        raise SystemExit("[math-lint-smoke] alternate packagesDir case still populated `.lake/packages`")

    build = run(lean_low_priority_command(PACKAGE_ROOT, "lake", "build", "Smoke"), cwd=project_dir)
    require_substring(build, "KaTeX rejected blueprint math", context=f"{case.name} plain build")
    require_substring(
        build,
        "Undefined control sequence: \\definitelynotacommand",
        context=f"{case.name} plain build",
    )
    require_substring(
        build,
        "FAILURE: Undefined control sequence: \\undefinedmacro",
        context=f"{case.name} Lake-built probe",
    )

    wfail = run(
        lean_low_priority_command(PACKAGE_ROOT, "lake", "--wfail", "build", "Smoke"),
        cwd=project_dir,
        expect=1,
    )
    require_substring(wfail, "KaTeX rejected blueprint math", context=f"{case.name} wfail build")
    require_substring(wfail, "error: build failed", context=f"{case.name} wfail build")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Materialize fresh consumer Blueprint projects and verify KaTeX math lint "
            "warnings and --wfail behavior."
        ),
    )
    args = parser.parse_args()
    _ = args

    ensure_node_available()
    blueprint_repo_url = PACKAGE_ROOT.resolve().as_uri()
    blueprint_ref = current_repo_head()
    lean_toolchain = current_lean_toolchain()
    verso_require_line = current_verso_require_line()

    with tempfile.TemporaryDirectory(prefix="verso-blueprint-math-lint-smoke-") as tmp:
        workspace = Path(tmp)
        for case in CASES:
            print(f"[math-lint-smoke] case={case.name}", flush=True)
            project_dir = materialize_case(
                workspace,
                case,
                lean_toolchain=lean_toolchain,
                verso_require_line=verso_require_line,
                blueprint_repo_url=blueprint_repo_url,
                blueprint_ref=blueprint_ref,
            )
            run_case(project_dir, case)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
