from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path


PACKAGE_ROOT = Path(__file__).resolve().parents[2]
LEAN_TOOLCHAIN = (PACKAGE_ROOT / "lean-toolchain").read_text(encoding="utf-8")
LEAN_LOW_PRIORITY = PACKAGE_ROOT / "scripts" / "lean-low-priority"
VBP = PACKAGE_ROOT / ".lake" / "build" / "bin" / "vbp"

MISSING_IMPORT_LAKEFILE = """import Lake
open Lake DSL

package MissingImportBlueprint
"""

MISSING_IMPORT_GENERATOR = """import MissingBlueprintDependency

def blueprintMain : IO Unit := pure ()
def main : IO Unit := blueprintMain
"""

MISSING_NEED_LAKEFILE = """import Lake
open Lake DSL

package MissingInputBlueprint

input_file missingGeneratorInput where
  path := "missing-generator-input.txt"
  text := true

lean_lib MissingInputBlueprint where
  roots := #[`MissingInputBlueprint]
  needs := #[missingGeneratorInput]
"""

MISSING_NEED_MODULE = """def witness : Nat := 1
"""

MISSING_NEED_GENERATOR = """import MissingInputBlueprint

def blueprintMain : IO Unit := pure ()
def main : IO Unit := blueprintMain
"""


def write_project(
    root: Path,
    name: str,
    lakefile: str,
    files: dict[str, str],
) -> Path:
    project = root / name
    project.mkdir()
    (project / "lean-toolchain").write_text(LEAN_TOOLCHAIN, encoding="utf-8")
    (project / "lakefile.lean").write_text(lakefile, encoding="utf-8")
    for path, contents in files.items():
        (project / path).write_text(contents, encoding="utf-8")
    return project


def assert_build_failure(
    project: Path,
    *,
    expected_protocol: str,
    expected_diagnostic: str,
) -> None:
    result = subprocess.run(
        [str(LEAN_LOW_PRIORITY), "lake", "env", str(VBP), "build"],
        cwd=project,
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode == 0:
        raise SystemExit(f"vbp unexpectedly accepted invalid project {project.name}")
    if expected_protocol not in result.stderr:
        raise SystemExit(
            f"vbp did not preserve its build-failure protocol for {project.name}; "
            f"expected {expected_protocol!r}\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )
    if expected_diagnostic not in result.stdout + result.stderr:
        raise SystemExit(
            f"vbp did not preserve the underlying diagnostic for {project.name}; "
            f"expected {expected_diagnostic!r}\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="verso-blueprint-vbp-failure-") as tmp:
        root = Path(tmp)
        # An invalid import reaches Lean, which returns a nonzero process exit code.
        missing_import = write_project(
            root,
            "missing-import",
            MISSING_IMPORT_LAKEFILE,
            {"MissingImportBlueprintMain.lean": MISSING_IMPORT_GENERATOR},
        )
        assert_build_failure(
            missing_import,
            expected_protocol="vbp build: generator run failed with exit code 1",
            expected_diagnostic="MissingBlueprintDependency",
        )

        # A missing Lake input fails dependency preparation, so evalLeanFile throws.
        missing_need = write_project(
            root,
            "missing-need",
            MISSING_NEED_LAKEFILE,
            {
                "MissingInputBlueprint.lean": MISSING_NEED_MODULE,
                "MissingInputBlueprintMain.lean": MISSING_NEED_GENERATOR,
            },
        )
        assert_build_failure(
            missing_need,
            expected_protocol="vbp build: generator run failed:",
            expected_diagnostic="missing-generator-input.txt",
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
