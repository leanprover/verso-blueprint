#!/usr/bin/env python3
"""Check imported semantic invalidation through ordinary Lake builds.

Only Runtime.lean receives reversible body and type byte edits; source/consumer
bytes stay fixed. No mtimes/cache deletion, foreign artifacts or FIR changes
are involved. Saved MOCK review bindings are temporary test controls, not a
production API.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=root / ".lake/build/realization-semantics-test")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    fixtures = root / "tests/VersoBlueprintTests/BlueprintRealizationSemantics"
    runtime = fixtures / "Runtime.lean"
    owner = fixtures / "Owner.lean"
    consumer = fixtures.with_suffix(".lean")
    original = runtime.read_bytes()
    marker = b"def runtimeMode : Nat := 0"
    if original.count(marker) != 1:
        raise RuntimeError("Runtime fixture is not at its exact baseline")
    body_change = original.replace(marker, b"def runtimeMode : Nat := 1")
    type_change = original.replace(marker, b"def runtimeMode : Int := 0")
    proof_marker = b"theorem runtimeFact : True := True.intro"
    if original.count(proof_marker) != 1:
        raise RuntimeError("Expected the exact imported proof control")
    proof_change = original.replace(proof_marker, b"theorem runtimeFact : True := (fun h : True => h) True.intro")
    proof_hole = original.replace(proof_marker, b"theorem runtimeFact : True := by sorry")
    unchanged = {path: path.read_bytes() for path in (owner, consumer)}
    commands = []

    def run(step: str, arguments: list[str], environment=None) -> None:
        command = [str(root / "scripts/lean-low-priority"), "lake", *arguments]
        with (output / f"{step}.log").open("w") as log:
            result = subprocess.run(command, cwd=root, env=environment, stdout=log, stderr=subprocess.STDOUT)
        commands.append({"step": step, "arguments": arguments, "exit": result.returncode})
        print(f"{step}: exit {result.returncode}", flush=True)
        if result.returncode:
            raise RuntimeError(f"{step} failed; see {output / (step + '.log')}")
        for path, data in unchanged.items():
            if path.read_bytes() != data:
                raise RuntimeError(f"Local source changed during the control: {path}")

    def build(step: str, environment=None) -> None:
        run(step, ["build", "+VersoBlueprintTests.BlueprintRealizationSemantics:olean"], environment)

    def query(step: str, mode: str, control: Path) -> None:
        environment = dict(os.environ)
        environment["VBP_SEMANTIC_REVIEW_MODE"] = mode
        environment["VBP_SEMANTIC_REVIEW_CONTROL"] = str(control)
        run(step, ["lean", str(consumer.relative_to(root))], environment)

    restored_build = False
    try:
        with tempfile.TemporaryDirectory(prefix="semantic-review-") as temporary:
            control = Path(temporary) / "mock-review-bindings.json"
            build("01-baseline-build")
            query("02-capture-current", "capture", control)
            for step, content, mode in [
                ("proof-edit", proof_change, "current"),
                ("proof-hole", proof_hole, "proof-hole"),
                ("comment-edit", original + b"\n-- unrelated source comment\n", "current"),
            ]:
                restored_build = False
                runtime.write_bytes(content)
                environment = dict(os.environ)
                if mode == "proof-hole":
                    environment["VBP_SEMANTIC_REVIEW_MODE"] = mode
                    environment["VBP_SEMANTIC_REVIEW_CONTROL"] = str(control)
                build(step + "-build", environment)
                query(step + "-reviews", mode, control)
            restored_build = False
            runtime.write_bytes(body_change)
            build("03-import-changed-build")
            query("04-saved-reviews-stale", "stale", control)
            restored_build = False
            runtime.write_bytes(type_change)
            build("05-import-type-changed-build")
            query("06-saved-reviews-stale-after-type-change", "stale", control)
            restored_build = False
            runtime.write_bytes(original)
            build("07-restored-build")
            restored_build = True
            query("08-exact-inputs-current", "current", control)
    finally:
        if runtime.read_bytes() != original:
            runtime.write_bytes(original)
        if not restored_build:
            # Restore both bytes and the normal owning build even on failure.
            build("recovery-restored-build")
            restored_build = True
        receipt = {
            "runtime_restored": runtime.read_bytes() == original,
            "local_source_unchanged": all(path.read_bytes() == data for path, data in unchanged.items()),
            "source_sha256": {str(path.relative_to(root)): hashlib.sha256(data).hexdigest()
                              for path, data in unchanged.items()},
            "commands": commands,
        }
        (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")


if __name__ == "__main__":
    main()
