#!/usr/bin/env python3
"""Verify the module refactor's incremental rebuild boundaries."""

from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import time


ROOT = Path(__file__).resolve().parents[1]
OWNER = ROOT / "tests/VersoBlueprintModuleTests/IncrementalOwner.lean"
RUNTIME = ROOT / "src/VersoBlueprint/Graft/Render.lean"
SHARED_DATA = ROOT / "src/VersoBlueprint/Commands/Graph/Data.lean"

OWNER_MODULE = "VersoBlueprintModuleTests.IncrementalOwner"
CONSUMER_MODULE = "VersoBlueprintModuleTests.IncrementalAuthoring"
RUNTIME_MODULE = "VersoBlueprint.Graft.Render"
SHARED_DATA_MODULE = "VersoBlueprint.Commands.Graph.Data"

BUILD_TARGETS = [
    f"+{OWNER_MODULE}:olean",
    f"+{RUNTIME_MODULE}:olean",
    f"+{SHARED_DATA_MODULE}:olean",
    f"+{CONSUMER_MODULE}:olean",
]

BUILT_RE = re.compile(r"\bBuilt ([^\s(]+)")


class CheckFailure(RuntimeError):
    pass


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command,
        cwd=ROOT,
        env=os.environ.copy(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if result.returncode != 0:
        raise CheckFailure(
            f"command failed ({result.returncode}): {' '.join(command)}\n{result.stdout}"
        )
    return result


def build(*targets: str) -> set[str]:
    result = run(
        [str(ROOT / "scripts/lean-low-priority"), "lake", "build", *targets]
    )
    return set(BUILT_RE.findall(result.stdout))


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise CheckFailure(
            f"expected one synthetic-edit marker in {path.relative_to(ROOT)}, found {count}"
        )
    path.write_text(text.replace(old, new, 1))


def require_built(label: str, built: set[str], module: str) -> None:
    if module not in built:
        raise CheckFailure(
            f"{label}: expected {module} to rebuild; observed {sorted(built)}"
        )


def require_not_built(label: str, built: set[str], module: str) -> None:
    if module in built:
        raise CheckFailure(
            f"{label}: expected {module} to remain cached; observed {sorted(built)}"
        )


def report(label: str, built: set[str]) -> None:
    project_jobs = sorted(
        module for module in built if module.startswith("VersoBlueprint")
    )
    print(f"{label}: built={','.join(project_jobs) if project_jobs else '(none)'}")


def git_status() -> str:
    return run(["git", "status", "--porcelain=v1"]).stdout


def main() -> int:
    originals = {
        path: path.read_text() for path in (OWNER, RUNTIME, SHARED_DATA)
    }
    initial_status = git_status()
    nonce = f"{os.getpid()}_{time.time_ns()}"
    failure: BaseException | None = None

    try:
        print("warm baseline")
        build(*BUILD_TARGETS)

        owner_old = """private theorem implementationProof : True := by
  trivial"""
        owner_new = f"""private theorem implementationProof : True := by
  have incrementalProofProbe_{nonce} : True := True.intro
  exact incrementalProofProbe_{nonce}"""
        replace_once(OWNER, owner_old, owner_new)
        private_built = build(
            f"+{OWNER_MODULE}:olean", f"+{CONSUMER_MODULE}:olean"
        )
        report("private implementation", private_built)
        require_built("private implementation", private_built, OWNER_MODULE)
        require_not_built("private implementation", private_built, CONSUMER_MODULE)
        OWNER.write_text(originals[OWNER])
        build(f"+{OWNER_MODULE}:olean", f"+{CONSUMER_MODULE}:olean")

        runtime_marker = "\nend Informal.Graft\n"
        runtime_probe = f"""

private theorem incrementalRuntimeProbe_{nonce} : True := by
  trivial

end Informal.Graft
"""
        replace_once(RUNTIME, runtime_marker, runtime_probe)
        runtime_built = build(
            f"+{RUNTIME_MODULE}:olean", f"+{CONSUMER_MODULE}:olean"
        )
        report("runtime renderer", runtime_built)
        require_built("runtime renderer", runtime_built, RUNTIME_MODULE)
        require_not_built("runtime renderer", runtime_built, CONSUMER_MODULE)
        RUNTIME.write_text(originals[RUNTIME])
        build(f"+{RUNTIME_MODULE}:olean", f"+{CONSUMER_MODULE}:olean")

        shared_marker = "\nend Informal.Commands\n"
        shared_probe = f"""

def incrementalPublicProbe_{nonce} : Nat := 0

end Informal.Commands
"""
        replace_once(SHARED_DATA, shared_marker, shared_probe)
        public_built = build(
            f"+{SHARED_DATA_MODULE}:olean", f"+{CONSUMER_MODULE}:olean"
        )
        report("public shared data", public_built)
        require_built("public shared data", public_built, SHARED_DATA_MODULE)
        require_built("public shared data", public_built, CONSUMER_MODULE)
    except BaseException as error:
        failure = error
    finally:
        for path, text in originals.items():
            path.write_text(text)
        try:
            build(*BUILD_TARGETS)
        except BaseException as restore_error:
            if failure is None:
                failure = restore_error
            else:
                failure = CheckFailure(
                    f"{failure}\nrestoring the warm baseline also failed:\n{restore_error}"
                )

    final_status = git_status()
    if final_status != initial_status:
        status_failure = CheckFailure(
            "synthetic edits did not restore the worktree status\n"
            f"before:\n{initial_status}after:\n{final_status}"
        )
        if failure is None:
            failure = status_failure
        else:
            failure = CheckFailure(f"{failure}\n{status_failure}")

    if failure is not None:
        raise failure

    print("restored baseline: build=green worktree=unchanged")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
