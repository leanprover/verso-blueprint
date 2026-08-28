from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path


PACKAGE_ROOT = Path(__file__).resolve().parents[2]
LEAN_TOOLCHAIN = (PACKAGE_ROOT / "lean-toolchain").read_text(encoding="utf-8")
LEAN_LOW_PRIORITY = PACKAGE_ROOT / "scripts" / "lean-low-priority"
VBP = PACKAGE_ROOT / ".lake" / "build" / "bin" / "vbp"

LAKEFILE = """import Lake
open Lake DSL

package BrokenBlueprint
"""

GENERATOR = """import MissingBlueprintDependency

-- PreviewManifest marks this file as the Blueprint generator fixture.
def main : IO Unit := pure ()
"""


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="verso-blueprint-vbp-failure-") as tmp:
        project = Path(tmp)
        (project / "lean-toolchain").write_text(LEAN_TOOLCHAIN, encoding="utf-8")
        (project / "lakefile.lean").write_text(LAKEFILE, encoding="utf-8")
        (project / "BrokenBlueprintMain.lean").write_text(GENERATOR, encoding="utf-8")

        result = subprocess.run(
            [str(LEAN_LOW_PRIORITY), "lake", "env", str(VBP), "build"],
            cwd=project,
            check=False,
            text=True,
            capture_output=True,
        )
        if result.returncode == 0:
            raise SystemExit("vbp unexpectedly accepted a generator with a missing import")
        if "vbp build: generator run failed" not in result.stderr:
            raise SystemExit(
                "vbp did not preserve its documented build-failure protocol\n"
                f"stdout:\n{result.stdout}\n"
                f"stderr:\n{result.stderr}"
            )
        if "MissingBlueprintDependency" not in result.stdout + result.stderr:
            raise SystemExit(
                "vbp did not preserve the generator failure diagnostic\n"
                f"stdout:\n{result.stdout}\n"
                f"stderr:\n{result.stderr}"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
